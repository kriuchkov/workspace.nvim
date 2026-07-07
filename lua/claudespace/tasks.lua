-- Task runner: reads tasks.json or .tasks.lua from project root.
-- Runs commands in a bottom terminal split.
local M = {}

local fn  = vim.fn
local api = vim.api

-- ── Config loading ────────────────────────────────────────────────────────────

-- Where to look for a task file. In a multi-repo workspace tasks.json lives in
-- each member repo, not the workspace root, so prefer the active repo's dir,
-- then the current file's dir, then the cwd.
local function task_dirs()
  local dirs, seen = {}, {}
  local function add(d)
    if d and d ~= '' and not seen[d] then seen[d] = true; dirs[#dirs + 1] = d end
  end
  local ok, repos = pcall(require, 'claudespace.repos')
  if ok then
    -- the active repo wins; then the current file's repo/dir; then, as a
    -- fallback (e.g. focus on the tree), every workspace member repo.
    pcall(function() add(repos.active_cwd()) end)
  end
  if vim.bo.buftype == '' then
    local bufdir = fn.expand('%:p:h')
    if bufdir ~= '' then add(bufdir) end
  end
  if ok and repos.list then
    pcall(function() for _, m in ipairs(repos.list() or {}) do add(m.abspath) end end)
  end
  add(fn.getcwd())
  return dirs
end

-- Returns (tasks_table, dir) for the first dir that has a task file, else nil.
local function load_config()
  for _, dir in ipairs(task_dirs()) do
    -- tasks.json: { "build": "cargo build", "test": "cargo test" }
    local json = dir .. '/tasks.json'
    if fn.filereadable(json) == 1 then
      local ok, data = pcall(fn.json_decode, table.concat(fn.readfile(json), ''))
      if ok and type(data) == 'table' then return data, dir end
    end
    -- .tasks.lua: return { build = 'cargo build', test = 'cargo test' }
    local lua = dir .. '/.tasks.lua'
    if fn.filereadable(lua) == 1 then
      local ok, data = pcall(dofile, lua)
      if ok and type(data) == 'table' then return data, dir end
    end
  end
  return nil
end

-- ── Execution ─────────────────────────────────────────────────────────────────

local _term_buf = nil  -- reuse the task terminal window

local function set_winbar(win, text, hl)
  if win and api.nvim_win_is_valid(win) then
    -- Escape % so a task name like "100% coverage" isn't read as a statusline item.
    vim.wo[win].winbar = '%#' .. hl .. '# ' .. text:gsub('%%', '%%%%') .. ' '
  end
end

-- Show how the task ran: a winbar banner (running → passed/failed by exit code)
-- and green/red matches on the usual test/build keywords, plus a notification.
local function decorate(buf, win, name)
  set_winbar(win, '▶ ' .. name .. ' · running…', 'DiagnosticWarn')
  api.nvim_win_call(win, function()
    fn.clearmatches()
    fn.matchadd('DiagnosticOk',    [[\c\<\(ok\|pass\|passed\)\>\|✓]])
    fn.matchadd('DiagnosticError', [[\cFAIL\|\<error\|panic\|--- FAIL\|✗]])
  end)
  api.nvim_create_autocmd('TermClose', {
    buffer = buf, once = true,
    callback = function()
      -- A restart kills the old job; ignore its late TermClose if the window has
      -- already moved on to a newer task buffer.
      if not (api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf) then return end
      local code = vim.v.event.status or 0
      local ok   = code == 0
      set_winbar(win,
        (ok and '✓ ' .. name .. ' · passed') or ('✗ ' .. name .. ' · failed (exit ' .. code .. ')'),
        ok and 'DiagnosticOk' or 'DiagnosticError')
      vim.notify(('Task %s: %s'):format(name, ok and 'passed ✓' or ('failed ✗ (exit ' .. code .. ')')),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end,
  })
end

-- Run `cmd` from `dir` (so a member repo's task runs in that repo, not the
-- workspace root).
local function open_terminal(cmd, dir, name)
  local full = (dir and dir ~= '')
    and ('cd ' .. fn.shellescape(dir) .. ' && ' .. cmd) or cmd
  -- Reuse existing task terminal if still alive
  if _term_buf and api.nvim_buf_is_valid(_term_buf) then
    -- Find its window or open a new split
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == _term_buf then
        api.nvim_set_current_win(win)
        break
      end
    end
    if api.nvim_get_current_buf() ~= _term_buf then
      vim.cmd 'botright split'
      api.nvim_set_current_buf(_term_buf)
    end
    -- Kill old job and restart
    local job = vim.b[_term_buf] and vim.b[_term_buf].terminal_job_id
    if job then pcall(fn.jobstop, job) end
    vim.cmd('terminal ' .. full)
  else
    vim.cmd 'botright split'
    api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.28))
    vim.cmd('terminal ' .. full)
  end
  _term_buf = api.nvim_get_current_buf()
  decorate(_term_buf, api.nvim_get_current_win(), name or 'task')
  vim.cmd 'startinsert'
end

function M.run(name)
  local tasks, dir = load_config()
  if not tasks then
    vim.notify('Tasks: no tasks.json / .tasks.lua found (active repo, file dir, cwd)',
               vim.log.levels.WARN)
    return
  end
  local cmd = tasks[name]
  if not cmd then
    vim.notify('Tasks: unknown task "' .. name .. '"', vim.log.levels.ERROR)
    return
  end
  open_terminal(cmd, dir, name)
end

function M.pick()
  local tasks, dir = load_config()
  if not tasks then
    vim.notify('Tasks: no tasks.json / .tasks.lua found (active repo, file dir, cwd)',
               vim.log.levels.WARN)
    return
  end
  local items = {}
  for name, cmd in pairs(tasks) do
    table.insert(items, { name = name, cmd = cmd })
  end
  if #items == 0 then
    vim.notify('Tasks: tasks file is empty', vim.log.levels.WARN)
    return
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  vim.ui.select(items, {
    prompt      = 'Run task',
    format_item = function(item) return item.name .. '   ' .. item.cmd end,
  }, function(item)
    if item then M.run(item.name) end
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  local map = vim.keymap.set
  -- <leader>R (not <leader>rr — that's neotest "run nearest test").
  map('n', '<leader>R', M.pick,
    { silent = true, desc = 'Tasks: pick and run' })
  map('n', '<leader>rb', function() M.run('build') end,
    { silent = true, desc = 'Tasks: build' })
  map('n', '<leader>rt', function() M.run('test') end,
    { silent = true, desc = 'Tasks: test' })
  map('n', '<leader>rl', function() M.run('lint') end,
    { silent = true, desc = 'Tasks: lint' })
  map('n', '<leader>rx', function() M.run('run') end,
    { silent = true, desc = 'Tasks: run' })

  vim.schedule(function()
    local ok, wk = pcall(require, 'which-key')
    if ok and wk.add then
      wk.add({ { '<leader>r', group = 'Run/Tasks' } })
    end
  end)
end

return M
