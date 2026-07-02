-- Workspace manager: named snapshots of (cwd + open files + buffer groups).
-- Switch between projects without losing context; state persists across restarts.
local M = {}

local api = vim.api
local fn  = vim.fn

M._current = nil   -- name of the active workspace

local WDIR = fn.stdpath('data') .. '/claudespace_workspaces'

local function ws_file(name)
  return WDIR .. '/ws_' .. name:gsub('[^%w%-_]', '_') .. '.json'
end
local function index_file() return WDIR .. '/_index.json' end
local function last_file()  return WDIR .. '/_last.txt'  end

function M._set_wdir(dir) WDIR = dir end       -- test helper only
function M._get_ws_file(name) return ws_file(name) end  -- home.lua needs this

M._terminals = {}  -- { [ws_name] = { [slot] = bufnr } }

-- ── Persistence helpers ───────────────────────────────────────────────────────

function M._read_index()
  if fn.filereadable(index_file()) == 0 then return {} end
  local lines = fn.readfile(index_file())
  local ok, data = pcall(fn.json_decode, table.concat(lines, ''))
  return (ok and type(data) == 'table') and data or {}
end

function M._update_index(name, cwd)
  fn.mkdir(WDIR, 'p')
  local idx = {}
  for _, ws in ipairs(M._read_index()) do
    if ws.name ~= name then table.insert(idx, ws) end
  end
  table.insert(idx, { name = name, cwd = cwd })
  local ok, json = pcall(fn.json_encode, idx)
  if ok then pcall(fn.writefile, { json }, index_file()) end
end

function M._write_last(name)
  fn.mkdir(WDIR, 'p')
  pcall(fn.writefile, { name }, last_file())
end

function M._read_last()
  if fn.filereadable(last_file()) == 0 then return nil end
  local lines = fn.readfile(last_file())
  return lines and lines[1] ~= '' and lines[1] or nil
end

-- ── Core API ──────────────────────────────────────────────────────────────────

function M.list()
  return M._read_index()
end

function M.current_name()
  return M._current or fn.fnamemodify(fn.getcwd(), ':t')
end

---Save current state as a named workspace.
---@param name? string defaults to current workspace name
---@param silent? boolean suppress notification
function M.save(name, silent)
  name = name or M.current_name()
  fn.mkdir(WDIR, 'p')

  local files, active = {}, api.nvim_buf_get_name(api.nvim_get_current_buf())
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      local path = api.nvim_buf_get_name(buf)
      if path ~= '' and fn.filereadable(path) == 1 then
        table.insert(files, path)
      end
    end
  end

  -- Save window layout
  local layout
  local ok_lay, lay = pcall(require, 'claudespace.layout')
  if ok_lay then layout = lay.save() end

  -- Save Claude sessions for persistence across restarts
  local claude_sessions, claude_id
  local ok_cs, cs = pcall(require, 'claudespace.claude.sessions')
  if ok_cs then
    claude_id      = cs.active_id_()
    claude_sessions = cs.get_persistence_data()
  end

  -- Multi-repo workspace: record the workspace root and the active repo so the
  -- context can be restored even before a file is focused.
  local ws_root, active_repo
  local ok_repos, repos = pcall(require, 'claudespace.repos')
  if ok_repos then
    ws_root = repos.root()
    local ar = repos.active()
    active_repo = ar and ar.path or nil
  end

  local state = {
    name = name, cwd = fn.getcwd(), files = files, active = active,
    layout = layout, claude_session_id = claude_id,
    claude_sessions = claude_sessions,
    root = ws_root, active_repo = active_repo,
  }
  local ok, json = pcall(fn.json_encode, state)
  if ok then
    pcall(fn.writefile, { json }, ws_file(name))
    M._update_index(name, state.cwd)
    M._current = name
    M._write_last(name)
    if not silent then vim.notify('Workspace saved: ' .. name, vim.log.levels.INFO) end
  end
end

---Load a workspace by name, saving the current one first.
---@param name string
function M.load(name)
  if fn.filereadable(ws_file(name)) == 0 then
    vim.notify('Workspace not found: ' .. name, vim.log.levels.ERROR)
    return
  end

  local lines = fn.readfile(ws_file(name))
  local ok, state = pcall(fn.json_decode, table.concat(lines, ''))
  if not ok or type(state) ~= 'table' then
    vim.notify('Workspace corrupt: ' .. name, vim.log.levels.ERROR)
    return
  end

  -- Save current workspace before switching
  if M._current then M.save(M._current) end

  -- Close unmodified listed buffers
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted
      and not vim.bo[buf].modified and vim.bo[buf].buftype == '' then
      pcall(api.nvim_buf_delete, buf, {})
    end
  end

  -- Switch directory (triggers tabline DirChanged → loads that dir's groups)
  vim.cmd('cd ' .. fn.fnameescape(state.cwd))

  -- Re-scan the workspace repos. DirChanged usually triggers this, but won't
  -- fire when loading a workspace whose cwd equals the current one.
  pcall(function() require('claudespace.repos').load() end)

  -- Restore files as background buffers
  for _, path in ipairs(state.files or {}) do
    if fn.filereadable(path) == 1 then
      pcall(vim.cmd, 'badd ' .. fn.fnameescape(path))
    end
  end

  -- Focus the previously active file
  if state.active ~= '' and fn.filereadable(state.active) == 1 then
    pcall(vim.cmd, 'edit ' .. fn.fnameescape(state.active))
  end

  -- Restore layout (splits)
  if state.layout then
    local ok_lay, lay = pcall(require, 'claudespace.layout')
    if ok_lay then lay.restore(state.layout) end
  end

  -- Restore Claude sessions in background (deferred so layout is settled first)
  if state.claude_sessions and #state.claude_sessions > 0 then
    vim.schedule(function()
      local ok_cs2, cs2 = pcall(require, 'claudespace.claude.sessions')
      if ok_cs2 then cs2.restore(state.claude_sessions) end
    end)
  end

  M._current = name
  M._write_last(name)

  -- Re-apply tabline groups after all files are open.
  -- DirChanged already called load_session(), but buffers from badd/edit may
  -- have been added after that scan — reapply_groups() catches stragglers.
  vim.schedule(function()
    pcall(function()
      require('claudespace.tabline').reapply_groups()
    end)
  end)

  vim.notify('Workspace: ' .. name .. '  (' .. fn.fnamemodify(state.cwd, ':~') .. ')', vim.log.levels.INFO)
end

---Delete a workspace by name.
---@param name string
function M.delete(name)
  local choice = fn.confirm('Delete workspace "' .. name .. '"?', '&Yes\n&No', 2)
  if choice ~= 1 then return end
  pcall(fn.delete, ws_file(name))
  local idx = {}
  for _, ws in ipairs(M._read_index()) do
    if ws.name ~= name then table.insert(idx, ws) end
  end
  local ok, json = pcall(fn.json_encode, idx)
  if ok then pcall(fn.writefile, { json }, index_file()) end
  if M._current == name then M._current = nil end
  vim.notify('Workspace deleted: ' .. name, vim.log.levels.INFO)
end

---Interactive picker — switch or create a workspace.
function M.switch()
  local workspaces = M.list()
  local items = {}
  for _, ws in ipairs(workspaces) do
    table.insert(items, ws)
  end
  table.insert(items, { name = '+ New workspace…', cwd = '' })

  vim.ui.select(items, {
    prompt = 'Workspaces',
    format_item = function(ws)
      if ws.cwd == '' then return ws.name end
      local marker = ws.name == M._current and ' ✓' or ''
      return ws.name .. marker .. '  ' .. fn.fnamemodify(ws.cwd, ':~')
    end,
  }, function(ws)
    if not ws then return end
    if ws.cwd == '' then
      vim.ui.input({ prompt = 'Workspace name: ',
                     default = fn.fnamemodify(fn.getcwd(), ':t') }, function(name)
        if name and name ~= '' then M.save(name) end
      end)
    else
      M.load(ws.name)
    end
  end)
end

---Show all workspaces in a floating window.
function M.show_list()
  local workspaces = M.list()
  if #workspaces == 0 then
    vim.notify('No saved workspaces. Use <leader>ww to save one.', vim.log.levels.WARN)
    return
  end

  local lines = { '', '  Saved workspaces', '  ' .. string.rep('─', 44), '' }
  local hls   = { { 1, 0, -1, 'CSTreeDir' }, { 2, 0, -1, 'CSWinbarDir' } }
  for _, ws in ipairs(workspaces) do
    local marker = ws.name == M._current and ' ✓' or '  '
    local line   = '  ' .. marker .. '  ' .. ws.name
                .. string.rep(' ', math.max(1, 22 - #ws.name))
                .. fn.fnamemodify(ws.cwd, ':~')
    table.insert(lines, line)
    if ws.name == M._current then
      table.insert(hls, { #lines - 1, 0, -1, 'CSGit' })
    end
  end
  table.insert(lines, '')

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = false
  api.nvim_set_option_value('modifiable', true, { buf = buf })
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = buf })
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, 0, h[4], h[1], h[2], h[3])
  end

  local width = 56
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' Workspaces ', title_pos = 'center',
    width = width, height = #lines,
    row = math.floor((vim.o.lines   - #lines) / 2),
    col = math.floor((vim.o.columns - width)  / 2),
  })
  local close = function() api.nvim_win_close(win, true) end
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, close, { buffer = buf, nowait = true, silent = true })
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  -- Auto-save on exit (always, using cwd name as fallback)
  api.nvim_create_autocmd('VimLeave', {
    callback = function() M.save(nil, true) end,
  })

  -- VimEnter restore is handled by home.lua

  -- User commands
  vim.api.nvim_create_user_command('WorkspaceSave',
    function(a) M.save(a.args ~= '' and a.args or nil) end,
    { nargs = '?', desc = 'Save current workspace' })
  vim.api.nvim_create_user_command('WorkspaceSwitch',
    function() M.switch() end, { desc = 'Switch workspace' })
  vim.api.nvim_create_user_command('WorkspaceDelete',
    function(a) M.delete(a.args) end,
    { nargs = 1, desc = 'Delete a workspace' })
  vim.api.nvim_create_user_command('WorkspaceList',
    function() M.show_list() end, { desc = 'List workspaces' })

  -- Keymaps
  local map = vim.keymap.set
  map('n', '<leader>ws', M.switch,                 { desc = 'Workspace: switch', silent = true })
  map('n', '<leader>wS', function() M.save() end, { desc = 'Workspace: save',   silent = true })
  map('n', '<leader>wl', M.show_list,             { desc = 'Workspace: list',   silent = true })
  map('n', '<leader>wh', function()
    require('claudespace.home').open()
  end, { desc = 'Workspace: home screen' })
  map('n', '<leader>wd', function()
    vim.ui.input({ prompt = 'Delete workspace: ', default = M.current_name() }, function(name)
      if name and name ~= '' then M.delete(name) end
    end)
  end, { desc = 'Workspace: delete' })

  -- Per-workspace terminals: <leader>ww1 / ww2 / ww3.
  -- All three share a single bottom window — switching slots swaps the buffer
  -- in place instead of stacking new splits.
  for slot = 1, 3 do
    map('n', '<leader>ww' .. slot, function()
      local ws_name = M._current or M.current_name()
      M._terminals[ws_name] = M._terminals[ws_name] or {}
      local buf      = M._terminals[ws_name][slot]
      local have_buf = buf and api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal'

      -- Ensure the single shared terminal window exists and is focused.
      if M._term_win and api.nvim_win_is_valid(M._term_win) then
        api.nvim_set_current_win(M._term_win)
      else
        vim.cmd 'botright split'
        M._term_win = api.nvim_get_current_win()
        api.nvim_win_set_height(M._term_win, math.floor(vim.o.lines * 0.28))
      end

      if have_buf then
        api.nvim_win_set_buf(M._term_win, buf)
      else
        -- Create the terminal for this slot inside the shared window.
        local newbuf = api.nvim_create_buf(true, false)
        api.nvim_win_set_buf(M._term_win, newbuf)
        fn.termopen(vim.o.shell, { cwd = fn.getcwd() })
        M._terminals[ws_name][slot] = newbuf
      end
      vim.cmd 'startinsert'
    end, { desc = 'Workspace: terminal ' .. slot })
  end
end

return M
