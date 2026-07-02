-- Task runner: reads tasks.json or .tasks.lua from project root.
-- Runs commands in a bottom terminal split.
local M = {}

local fn  = vim.fn
local api = vim.api

-- ── Config loading ────────────────────────────────────────────────────────────

local function load_config()
  -- tasks.json: { "build": "cargo build", "test": "cargo test" }
  local json = fn.getcwd() .. '/tasks.json'
  if fn.filereadable(json) == 1 then
    local ok, data = pcall(fn.json_decode, table.concat(fn.readfile(json), ''))
    if ok and type(data) == 'table' then return data end
  end
  -- .tasks.lua: return { build = 'cargo build', test = 'cargo test' }
  local lua = fn.getcwd() .. '/.tasks.lua'
  if fn.filereadable(lua) == 1 then
    local ok, data = pcall(dofile, lua)
    if ok and type(data) == 'table' then return data end
  end
  return nil
end

-- ── Execution ─────────────────────────────────────────────────────────────────

local _term_buf = nil  -- reuse the task terminal window

local function open_terminal(cmd)
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
    vim.cmd('terminal ' .. cmd)
  else
    vim.cmd 'botright split'
    api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.28))
    vim.cmd('terminal ' .. cmd)
    _term_buf = api.nvim_get_current_buf()
  end
  vim.cmd 'startinsert'
end

function M.run(name)
  local tasks = load_config()
  if not tasks then
    vim.notify('Tasks: no tasks.json or .tasks.lua found in ' .. fn.getcwd(),
               vim.log.levels.WARN)
    return
  end
  local cmd = tasks[name]
  if not cmd then
    vim.notify('Tasks: unknown task "' .. name .. '"', vim.log.levels.ERROR)
    return
  end
  open_terminal(cmd)
end

function M.pick()
  local tasks = load_config()
  if not tasks then
    vim.notify('Tasks: no tasks.json or .tasks.lua found in ' .. fn.getcwd(),
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
