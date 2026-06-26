-- Test runner UI: detect framework, run tests, parse output, show summary.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_testui')

-- ── Framework detection ───────────────────────────────────────────────────────

local function detect_framework()
  local cwd = fn.getcwd()
  if fn.filereadable(cwd .. '/go.mod') == 1 then
    return 'go', 'go test ./... 2>&1'
  elseif fn.filereadable(cwd .. '/Cargo.toml') == 1 then
    return 'cargo', 'cargo test 2>&1'
  elseif fn.filereadable(cwd .. '/package.json') == 1 then
    local pkg = table.concat(fn.readfile(cwd .. '/package.json'), '')
    if pkg:match('"vitest"') then
      return 'vitest', 'npx vitest run 2>&1'
    else
      return 'jest', 'npx jest --no-coverage 2>&1'
    end
  elseif fn.filereadable(cwd .. '/pyproject.toml') == 1
      or fn.filereadable(cwd .. '/pytest.ini') == 1
      or fn.filereadable(cwd .. '/setup.py') == 1 then
    return 'pytest', 'python -m pytest -v 2>&1'
  end
  return 'unknown', nil
end

-- ── Output parsers ────────────────────────────────────────────────────────────

local PARSERS = {
  go = function(lines)
    local pass, fail, skip = {}, {}, {}
    for _, l in ipairs(lines) do
      local name = l:match('^%s*%-%-%- PASS: (%S+)')
      if name then table.insert(pass, name) end
      name = l:match('^%s*%-%-%- FAIL: (%S+)')
      if name then table.insert(fail, name) end
      name = l:match('^%s*%-%-%- SKIP: (%S+)')
      if name then table.insert(skip, name) end
    end
    return pass, fail, skip
  end,
  cargo = function(lines)
    local pass, fail, skip = {}, {}, {}
    for _, l in ipairs(lines) do
      local name, result = l:match('^test (%S+) %.%.%. (%a+)')
      if name then
        if result == 'ok'      then table.insert(pass, name)
        elseif result == 'FAILED' then table.insert(fail, name)
        elseif result == 'ignored' then table.insert(skip, name)
        end
      end
    end
    return pass, fail, skip
  end,
  pytest = function(lines)
    local pass, fail, skip = {}, {}, {}
    for _, l in ipairs(lines) do
      if l:match('PASSED') then
        local name = l:match('^(%S+) PASSED')
        if name then table.insert(pass, name) end
      elseif l:match('FAILED') then
        local name = l:match('^(%S+) FAILED')
        if name then table.insert(fail, name) end
      elseif l:match('SKIPPED') then
        local name = l:match('^(%S+) SKIPPED')
        if name then table.insert(skip, name) end
      end
    end
    return pass, fail, skip
  end,
}
PARSERS.jest   = PARSERS.pytest
PARSERS.vitest = PARSERS.pytest

local function parse(framework, output_lines)
  local parser = PARSERS[framework]
  if parser then return parser(output_lines) end
  return {}, {}, {}
end

-- ── Result panel ─────────────────────────────────────────────────────────────

local function show_results(framework, pass, fail, skip, raw_lines)
  local lines, hls = {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end

  local total = #pass + #fail + #skip
  local status_hl = #fail > 0 and 'DiagnosticError' or 'DiagnosticOk'
  local status    = #fail > 0 and '✗ FAILED' or '✓ PASSED'

  add('')
  add('  Test Results  [' .. framework .. ']  ' .. status, status_hl)
  add(('  %d passed  %d failed  %d skipped  (%d total)'):format(
    #pass, #fail, #skip, total), 'CSInfo')
  add('')

  if #fail > 0 then
    add('  ─ Failed ──────────────────────────────────────', 'DiagnosticError')
    for _, name in ipairs(fail) do
      add('  ✗  ' .. name, 'DiagnosticError')
    end
    add('')
  end

  if #pass > 0 then
    add('  ─ Passed ──────────────────────────────────────', 'DiagnosticOk')
    for _, name in ipairs(pass) do
      add('  ✓  ' .. name, 'DiagnosticOk')
    end
    add('')
  end

  add('  o full output  ·  q close', 'CSInfo')

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'; vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  local W = math.min(64, vim.o.columns - 4)
  local H = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' Tests ', title_pos = 'center',
    width = W, height = H,
    row = math.floor((vim.o.lines - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  vim.wo[win].number = false; vim.wo[win].cursorline = true

  local o = { buffer = buf, nowait = true, silent = true }
  local close = function() pcall(api.nvim_win_close, win, true) end
  vim.keymap.set('n', 'q',     close, o)
  vim.keymap.set('n', '<Esc>', close, o)
  vim.keymap.set('n', 'o', function()
    close()
    local rbuf = api.nvim_create_buf(false, true)
    vim.bo[rbuf].buftype = 'nofile'; vim.bo[rbuf].bufhidden = 'wipe'
    vim.bo[rbuf].filetype = 'text'; vim.bo[rbuf].modifiable = true
    api.nvim_buf_set_lines(rbuf, 0, -1, false, raw_lines)
    vim.bo[rbuf].modifiable = false
    vim.cmd 'botright split'
    api.nvim_set_current_buf(rbuf)
    api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.35))
    vim.keymap.set('n', 'q', function() vim.cmd 'bd' end, { buffer = rbuf, silent = true })
  end, o)
end

-- ── Runner ────────────────────────────────────────────────────────────────────

function M.run()
  local framework, cmd = detect_framework()
  if not cmd then
    vim.notify('Unknown test framework (no go.mod, Cargo.toml, package.json, pyproject.toml)', vim.log.levels.WARN)
    return
  end

  vim.notify('Running ' .. framework .. ' tests…', vim.log.levels.INFO)

  local output = {}
  vim.fn.jobstart(cmd, {
    cwd = fn.getcwd(),
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) if data then vim.list_extend(output, data) end end,
    on_stderr = function(_, data) if data then vim.list_extend(output, data) end end,
    on_exit = function(_, code)
      vim.schedule(function()
        local pass, fail, skip = parse(framework, output)
        show_results(framework, pass, fail, skip, output)
        if code ~= 0 and #fail == 0 then
          vim.notify('Tests exited with code ' .. code, vim.log.levels.WARN)
        end
      end)
    end,
  })
end

function M.setup()
  vim.keymap.set('n', '<leader>ru', M.run, { desc = 'Test: run + show results' })
end

return M
