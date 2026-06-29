-- neotest Go adapter.
local Path = require 'plenary.path'
local lib   = require 'neotest.lib'
local log   = require 'neotest.logging'
local async = require 'neotest.async'

-- ── patterns ─────────────────────────────────────────────────────────────────

local patterns = {
  testfile = '^%s%s%s%s(.*_test.go):(%d+): ',
  testlog  = '^%s%s%s%s%s%s%s%s',
  error    = { 'error' },
}

-- ── test_status ───────────────────────────────────────────────────────────────

local test_statuses = {
  run = false, pause = false, cont = false, bench = false, output = false,
  pass = 'passed', fail = 'failed', skip = 'skipped',
}

-- ── color ─────────────────────────────────────────────────────────────────────

local function highlight_output(s)
  if not s then return s end
  if s:find 'FAIL' then return s:gsub('^', '\27[31m'):gsub('$', '\27[0m') end
  if s:find 'PASS' then return s:gsub('^', '\27[32m'):gsub('$', '\27[0m') end
  if s:find 'SKIP' then return s:gsub('^', '\27[33m'):gsub('$', '\27[0m') end
  return s
end

-- ── utils ─────────────────────────────────────────────────────────────────────

local utils = {}

local function get_buf_line(buf, nr)
  nr = nr or 0
  return vim.trim(vim.api.nvim_buf_get_lines(buf, nr, nr + 1, false)[1])
end

function utils.transform_test_name(name)
  return name:gsub('[%s]', '_'):gsub('^"(.*)"$', '%1')
end

function utils.normalize_test_name(package, test)
  local parts = vim.split(test, '/')
  local is_sub = #parts > 1
  local parent = is_sub and (package .. '::' .. parts[1]) or nil
  return package .. '::' .. table.concat(parts, '::'), parent
end

function utils.normalize_id(id, go_root, go_module)
  local root = async.fn.substitute(id, go_root, go_module, '')
  return (root:gsub('/[%w_-]*_test.go', ''))
end

function utils.is_error(lines)
  for _, line in ipairs(lines) do
    line = line:lower()
    for _, p in ipairs(patterns.error) do
      if line:match(p:lower()) then return true end
    end
  end
  return false
end

function utils.is_test_logoutput(line)
  return line and line:match(patterns.testlog) ~= nil
end

function utils.get_build_tags()
  local line = get_buf_line(0)
  for _, prefix in ipairs { '// +build ', '//go:build ' } do
    if vim.startswith(line, prefix) then
      local tags = vim.split(line:gsub(prefix, ''), ' ')
      if #tags >= 1 then return ('-tags=%s'):format(table.concat(tags, ',')) end
    end
  end
  return ''
end

function utils.get_go_root(start_file)
  return lib.files.match_root_pattern('go.mod')(start_file)
end

function utils.get_go_module_name(go_root)
  local ok, lines = pcall(lib.files.read_lines, go_root .. '/go.mod')
  if not ok then log.error('neotest-go: could not read go.mod: ' .. lines); return end
  for _, line in pairs(lines) do
    local m = line:match('module (.+)')
    if m then return m end
  end
end

function utils.get_filename_from_id(id)
  return (id:match '/([%w_-]*_test.go)::')
end

function utils.get_test_file_info(line)
  if line then
    local file, num = line:match(patterns.testfile)
    return file, tonumber(num)
  end
  return nil, nil
end

function utils.get_errors_from_test(test, fname)
  if not test.file_output[fname] then return nil end
  local errors = {}
  for line, output in pairs(test.file_output[fname]) do
    if utils.is_error(output) then
      table.insert(errors, { line = line - 1, message = table.concat(output, '') })
    end
  end
  return errors
end

function utils.get_dap_config()
  return { type = 'go', name = 'Neotest Debugger', request = 'launch', mode = 'test', program = './${relativeFileDirname}' }
end

function utils.get_prefix(tree, name)
  local parent = tree:parent()
  if not parent or parent:data().type == 'file' then return name end
  return parent:data().name .. '/' .. name
end

-- ── output ────────────────────────────────────────────────────────────────────

local function sanitize_output(s)
  if not s then return nil end
  return s:gsub(patterns.testfile, ''):gsub(patterns.testlog, '')
end

local function marshal_gotest_output(lines)
  local tests, log_out = {}, {}
  local testfile, linenumber
  for _, line in ipairs(lines) do
    if line ~= '' and line:sub(1, 1) == '{' then
      local ok, parsed = pcall(vim.json.decode, line, { luanil = { object = true } })
      if not ok then
        return tests, vim.tbl_map(highlight_output, lines)
      end
      local output = highlight_output(parsed.Output)
      if output then table.insert(log_out, output) else testfile, linenumber = nil, nil end
      local action, pkg, test = parsed.Action, parsed.Package, parsed.Test
      if test then
        local status = test_statuses[action]
        local testname, parentname = utils.normalize_test_name(pkg, test)
        if not tests[testname] then
          tests[testname] = { output = {}, progress = {}, file_output = {} }
        end
        local nf, nl = utils.get_test_file_info(parsed.Output)
        testfile, linenumber = nf, nl
        if nf and nl then
          if not tests[testname].file_output[testfile] then
            tests[testname].file_output[testfile] = {}
          end
          local san = sanitize_output(parsed.Output)
          if san and not san:match '^%s*$' then
            tests[testname].file_output[testfile][linenumber] = { san }
          else
            tests[testname].file_output[testfile][linenumber] = {}
          end
        end
        if testfile and linenumber and utils.is_test_logoutput(parsed.Output) then
          table.insert(tests[testname].file_output[testfile][linenumber], sanitize_output(parsed.Output))
        end
        table.insert(tests[testname].progress, action)
        if status then tests[testname].status = status end
        if output then
          table.insert(tests[testname].output, output)
          if parentname and tests[parentname] then
            table.insert(tests[parentname].output, output)
          end
        end
      end
    end
  end
  return tests, log_out
end

-- ── adapter ───────────────────────────────────────────────────────────────────

local get_experimental_opts = function() return { test_table = false } end
local get_args              = function() return {} end
local recursive_run         = function() return false end

---@type neotest.Adapter
local adapter = { name = 'neotest-go' }

adapter.root = lib.files.match_root_pattern('go.mod', 'go.sum')

function adapter.is_test_file(file_path)
  if not vim.endswith(file_path, '.go') then return false end
  local elems = vim.split(file_path, Path.path.sep)
  return vim.endswith(elems[#elems], '_test.go')
end

function adapter._generate_position_id(position, namespaces)
  local prefix = {}
  for _, ns in ipairs(namespaces) do
    if ns.type ~= 'file' then table.insert(prefix, ns.name) end
  end
  local name = utils.transform_test_name(position.name)
  return table.concat(vim.tbl_flatten { position.path, prefix, name }, '::')
end

function adapter.discover_positions(path)
  local query = [[
    ;;query
    ((function_declaration
      name: (identifier) @test.name)
      (#match? @test.name "^(Test|Example)"))
      @test.definition

    (method_declaration
      name: (field_identifier) @test.name
      (#match? @test.name "^(Test|Example)")) @test.definition

    (call_expression
      function: (selector_expression
        field: (field_identifier) @test.method)
        (#match? @test.method "^Run$")
      arguments: (argument_list . (interpreted_string_literal) @test.name))
      @test.definition
  ]]

  if get_experimental_opts().test_table then
    query = query .. [[
;; list table tests
    (block
      (short_var_declaration
        left: (expression_list (identifier) @test.cases)
        right: (expression_list (composite_literal (literal_value
          (literal_element (literal_value (keyed_element
            (literal_element (identifier) @test.field.name)
            (literal_element (interpreted_string_literal) @test.name)))) @test.definition))))
      (for_statement (range_clause
          left: (expression_list (identifier) @test.case)
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1))
        body: (block (expression_statement (call_expression
            function: (selector_expression field: (field_identifier) @test.method
              (#match? @test.method "^Run$"))
            arguments: (argument_list (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)))))))))
;; map table tests
    (block
      (short_var_declaration
        left: (expression_list (identifier) @test.cases)
        right: (expression_list (composite_literal (literal_value
          (keyed_element
            (literal_element (interpreted_string_literal) @test.name)
            (literal_element (literal_value) @test.definition))))))
      (for_statement (range_clause
          left: (expression_list ((identifier) @test.key.name) ((identifier) @test.case))
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1))
        body: (block (expression_statement (call_expression
            function: (selector_expression field: (field_identifier) @test.method
              (#match? @test.method "^Run$"))
            arguments: (argument_list ((identifier) @test.key.name1 (#eq? @test.key.name @test.key.name1))))))))
    ]]
  end

  return lib.treesitter.parse_positions(path, query, {
    require_namespaces = false,
    nested_tests = true,
    position_id = "require('claudespace.neotest_go')._generate_position_id",
  })
end

function adapter.build_spec(args)
  local results_path = async.fn.tempname()
  local position = args.tree:data()
  local dir = recursive_run() and './...' or './'
  local location = position.path
  if vim.fn.isdirectory(location) ~= 1 then
    location = vim.fn.fnamemodify(location, ':h')
  end
  local command = vim.tbl_flatten {
    'cd', location, '&&', 'go', 'test', '-v', '-json',
    utils.get_build_tags(),
    vim.list_extend(get_args(location), args.extra_args or {}),
    dir,
  }
  local spec = {
    command = table.concat(command, ' '),
    context = { results_path = results_path, file = position.path },
  }
  if args.strategy == 'dap' then spec.strategy = utils.get_dap_config() end
  return spec
end

function adapter.results(spec, result, tree)
  local go_root = utils.get_go_root(spec.context.file)
  if not go_root then return {} end
  local go_module = utils.get_go_module_name(go_root)
  if not go_module then return {} end
  local ok, lines = pcall(lib.files.read_lines, result.output)
  if not ok then log.error('neotest-go: could not read output: ' .. lines); return {} end
  return adapter.prepare_results(tree, lines, go_root, go_module)
end

function adapter.prepare_results(tree, lines, go_root, go_module)
  local tests, lg = marshal_gotest_output(lines)
  local results = {}
  local no_results = vim.tbl_isempty(tests)
  local empty_fname = async.fn.tempname()
  vim.fn.writefile(lg, empty_fname)
  local file_id
  for _, node in tree:iter_nodes() do
    local v = node:data()
    if no_results then
      results[v.id] = { status = test_statuses.skip, output = empty_fname }
      break
    end
    if v.type == 'file' then
      results[v.id] = { status = test_statuses.pass, output = empty_fname }
      file_id = v.id
    else
      local vid = v.id:gsub('%"', ''):gsub(' ', '_')
      local nid = utils.normalize_id(vid, go_root, go_module)
      local tr  = tests[nid]
      if tr then
        local fname = async.fn.tempname()
        vim.fn.writefile(tr.output, fname)
        results[v.id] = { status = tr.status, short = table.concat(tr.output, ''), output = fname }
        local errs = utils.get_errors_from_test(tr, utils.get_filename_from_id(v.id))
        if errs then results[v.id].errors = errs end
        if tr.status == test_statuses.fail and file_id then
          results[file_id].status = test_statuses.fail
        end
      end
    end
  end
  return results
end

setmetatable(adapter, {
  __call = function(_, opts)
    local function callable(v) return type(v) == 'function' or (type(v) == 'table' and v.__call) end
    if callable(opts.experimental) then
      get_experimental_opts = opts.experimental
    elseif opts.experimental then
      get_experimental_opts = function() return opts.experimental end
    end
    if callable(opts.args) then
      get_args = opts.args
    elseif opts.args then
      get_args = function() return opts.args end
    end
    if callable(opts.recursive_run) then
      recursive_run = opts.recursive_run
    elseif opts.recursive_run then
      recursive_run = function() return opts.recursive_run end
    end
    return adapter
  end,
})

return adapter
