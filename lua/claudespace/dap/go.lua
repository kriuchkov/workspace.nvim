-- Go DAP adapter (delve) + treesitter test finder.
local M = {
  last_testname = '',
  last_testpath = '',
  test_buildflags = '',
  test_verbose    = false,
}

-- ── Treesitter test finder ────────────────────────────────────────────────────

local TESTS_QUERY = [[
(function_declaration
  name: (identifier) @testname
  parameters: (parameter_list
    . (parameter_declaration
      type: (pointer_type) @type) .)
  (#match? @type "*testing.(T|M)")
  (#match? @testname "^Test.+$")) @parent
]]

local SUBTESTS_QUERY = [[
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @run)
  arguments: (argument_list
    (interpreted_string_literal) @testname
    [(func_literal)(identifier)])
  (#eq? @run "Run")) @parent
]]

local function is_parent(dest, source)
  if not (dest and source) or dest == source then return false end
  local cur = source
  while cur do
    if cur == dest then return true end
    cur = cur:parent()
  end
  return false
end

local function format_subtest(tc, tree)
  if tc.parent then
    for _, c in pairs(tree) do
      if c.name == tc.parent then
        return format_subtest(c, tree) .. '/' .. tc.name
      end
    end
  end
  return tc.name
end

local function get_closest_above_cursor(tree)
  local result
  for _, cur in pairs(tree) do
    if not result then
      result = cur
    else
      local r1 = cur.node:range()
      local r2 = result.node:range()
      if r1 > r2 then result = cur end
    end
  end
  return result and format_subtest(result, tree) or nil
end

local function closest_test()
  local stop = vim.api.nvim_win_get_cursor(0)[1]
  local ft   = vim.bo.filetype
  assert(ft == 'go', 'dap_go: not a Go file')
  local parser = vim.treesitter.get_parser(0)
  local root   = (parser:parse()[1]):root()
  local tree   = {}

  local function collect(query_str)
    local q = vim.treesitter.query.parse(ft, query_str)
    for _, match in q:iter_matches(root, 0, 0, stop, { all = true }) do
      local m = {}
      for id, nodes in pairs(match) do
        for _, node in ipairs(nodes) do
          local cap = q.captures[id]
          if cap == 'testname' then
            m.name = vim.treesitter.get_node_text(node, 0)
            if cap == 'testname' and query_str == SUBTESTS_QUERY then
              m.name = m.name:gsub(' ', '_'):gsub('"', '')
            end
          end
          if cap == 'parent' then m.node = node end
        end
      end
      table.insert(tree, m)
    end
  end

  collect(TESTS_QUERY)
  collect(SUBTESTS_QUERY)
  table.sort(tree, function(a, b) return is_parent(a.node, b.node) end)
  for _, p in ipairs(tree) do
    for _, ch in ipairs(tree) do
      if is_parent(p.node, ch.node) then ch.parent = p.name end
    end
  end

  local pkg  = './' .. vim.fn.fnamemodify(vim.fn.expand '%:.:h', ':r')
  local name = get_closest_above_cursor(tree)
  return { package = pkg, name = name, scope = name and 'testcase' or 'package' }
end

-- ── Adapter + configurations ──────────────────────────────────────────────────

local CFG = {
  delve = {
    path = 'dlv', port = '${port}', args = {}, build_flags = '',
    initialize_timeout_sec = 20, detached = vim.fn.has 'win32' == 0,
    output_mode = 'remote',
  },
  tests = { verbose = false },
}

local function ask_args()
  return coroutine.create(function(co)
    vim.ui.input({ prompt = 'Args: ' }, function(input)
      coroutine.resume(co, vim.split(input or '', ' '))
    end)
  end)
end

local function ask_flags(cfg)
  return coroutine.create(function(co)
    vim.ui.input({ prompt = 'Build flags: ' }, function(input)
      coroutine.resume(co, vim.split(input or '', ' '))
    end)
  end)
end

local function pick_process()
  local filter = ''
  vim.ui.input({ prompt = 'Filter process name (or Enter for list): ' },
    function(i) filter = i or '' end)
  return require('dap.utils').pick_process { filter = filter }
end

local function setup_adapter(dap, cfg)
  local base = {
    type = 'server', port = cfg.delve.port,
    executable = {
      command = cfg.delve.path,
      args    = vim.list_extend({ 'dap', '-l', '127.0.0.1:' .. cfg.delve.port }, cfg.delve.args),
      detached = cfg.delve.detached,
    },
    options = { initialize_timeout_sec = cfg.delve.initialize_timeout_sec },
  }
  dap.adapters.go = function(cb, client_cfg)
    if client_cfg.port then
      local host = client_cfg.host or '127.0.0.1'
      base.port = client_cfg.port
      base.executable.args = { 'dap', '-l', host .. ':' .. client_cfg.port }
    end
    cb(base)
  end
end

local function setup_configurations(dap, cfg)
  dap.configurations.go = dap.configurations.go or {}
  local bf = cfg.delve.build_flags
  local om = cfg.delve.output_mode
  for _, c in ipairs {
    { name = 'Debug',                            program = '${file}',            buildFlags = bf, outputMode = om },
    { name = 'Debug (with args)',                program = '${file}',            args = ask_args, buildFlags = bf, outputMode = om },
    { name = 'Debug (args + flags)',             program = '${file}',            args = ask_args, buildFlags = ask_flags, outputMode = om },
    { name = 'Debug package',                   program = '${fileDirname}',     buildFlags = bf, outputMode = om },
    { name = 'Attach',                           mode = 'local', request = 'attach', processId = pick_process, buildFlags = bf },
    { name = 'Debug test',                       mode = 'test', program = '${file}',         buildFlags = bf, outputMode = om },
    { name = 'Debug test (go.mod)',              mode = 'test', program = './${relativeFileDirname}', buildFlags = bf, outputMode = om },
  } do
    c.type = 'go'; c.request = c.request or 'launch'
    table.insert(dap.configurations.go, c)
  end
end

function M.setup(opts)
  CFG = vim.tbl_deep_extend('force', CFG, opts or {})
  M.test_buildflags = CFG.delve.build_flags
  M.test_verbose    = CFG.tests.verbose
  local dap = require 'dap'
  setup_adapter(dap, CFG)
  setup_configurations(dap, CFG)
end

local function run_test(name, path, flags, extra, custom)
  local cfg = vim.tbl_deep_extend('force', {
    type = 'go', name = name, request = 'launch', mode = 'test',
    program = path, args = vim.list_extend({ '-test.run', '^' .. name .. '$' }, extra or {}),
    buildFlags = flags, outputMode = 'remote',
  }, custom or {})
  require('dap').run(cfg)
end

function M.debug_test(custom)
  local t = closest_test()
  if not t.name or t.name == '' then
    vim.notify('dap-go: no test found'); return false
  end
  M.last_testname = t.name; M.last_testpath = t.package
  vim.notify(('dap-go: debugging %s : %s'):format(t.package, t.name))
  run_test(t.name, t.package, M.test_buildflags, M.test_verbose and { '-test.v' } or {}, custom)
  return true
end

function M.debug_last_test()
  if M.last_testname == '' then
    vim.notify('dap-go: no previous test'); return false
  end
  vim.notify(('dap-go: re-running %s : %s'):format(M.last_testpath, M.last_testname))
  run_test(M.last_testname, M.last_testpath, M.test_buildflags, M.test_verbose and { '-test.v' } or {})
  return true
end

return M
