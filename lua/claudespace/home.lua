-- Home screen: workspace list + recent files, shown on bare nvim startup.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_home')

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function git_branch(cwd)
  if fn.isdirectory(cwd) == 0 then return '' end
  local b = fn.trim(fn.system(
    'git -C ' .. fn.shellescape(cwd) .. ' branch --show-current 2>/dev/null'))
  return vim.v.shell_error == 0 and b or ''
end

-- ── Build ─────────────────────────────────────────────────────────────────────

local function build()
  local ws      = require('claudespace.workspace')
  local lines   = {}
  local hls     = {}
  local actions = {}
  local SEP     = '  ' .. string.rep('─', 54)

  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end
  local function act(fn_) actions[#lines] = fn_ end

  add('')
  add('  claudespace.nvim', 'CSTreeDir')
  add('')

  -- ── Workspaces ──────────────────────────────────────────────────────────
  local workspaces = ws.list()
  if #workspaces > 0 then
    add('  Workspaces', 'CSWinbarDir')
    add(SEP)
    for _, w in ipairs(workspaces) do
      local marker = (w.name == ws._current) and ' ✓' or '  '
      local branch = git_branch(w.cwd)
      local bstr   = branch ~= '' and ('  [' .. branch .. ']') or ''
      local col2   = string.rep(' ', math.max(1, 22 - #w.name))
      local line   = '  ' .. marker .. '  ' .. w.name .. col2
                  .. fn.fnamemodify(w.cwd, ':~') .. bstr
      add(line, w.name == ws._current and 'CSGit' or nil)
      local captured = w.name
      act(function() ws.load(captured) end)
    end
    add('')
  end

  -- ── Recent files ────────────────────────────────────────────────────────
  local oldfiles = vim.v.oldfiles or {}
  local shown    = 0
  if #oldfiles > 0 then
    add('  Recent files', 'CSWinbarDir')
    add(SEP)
    for _, path in ipairs(oldfiles) do
      if fn.filereadable(path) == 1 and shown < 8 then
        add('    ' .. fn.fnamemodify(path, ':~:.'))
        local captured = path
        act(function() pcall(vim.cmd, 'edit ' .. fn.fnameescape(captured)) end)
        shown = shown + 1
      end
    end
    add('')
  end

  add('  <Enter> open  ·  n new workspace  ·  r refresh  ·  q quit', 'CSInfo')

  return lines, hls, actions
end

-- ── Open ──────────────────────────────────────────────────────────────────────

function M.open()
  local lines, hls, actions = build()

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].bufhidden  = 'wipe'
  vim.bo[buf].filetype   = 'cs_home'
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  api.nvim_set_current_buf(buf)
  local wo = vim.wo[0]
  wo.number = false; wo.relativenumber = false
  wo.signcolumn = 'no'; wo.cursorline = true; wo.winbar = ''

  local o = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set('n', '<CR>', function()
    local row = api.nvim_win_get_cursor(0)[1]
    local fn_ = actions[row]
    if fn_ then fn_() end
  end, o)

  vim.keymap.set('n', 'n', function()
    vim.ui.input({ prompt = 'Workspace name: ',
                   default = fn.fnamemodify(fn.getcwd(), ':t') }, function(name)
      if name and name ~= '' then require('claudespace.workspace').save(name) end
    end)
  end, o)

  vim.keymap.set('n', 'r', function()
    local nl, nh, na = build()
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, nl)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(nh) do api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3]) end
    actions = na
  end, o)

  vim.keymap.set('n', 'q', function() vim.cmd('bd') end, o)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      -- `nvim .` (единственный аргумент — директория) трактуем как открытие
      -- проекта и восстанавливаем его воркспейс. С файловыми аргументами
      -- (`nvim foo.go`) restore не делаем — открываем то, что попросили.
      local dir
      if fn.argc() == 1 then
        local p = fn.fnamemodify(fn.argv(0), ':p')
        if fn.isdirectory(p) == 1 then dir = (p:gsub('/$', '')) end
      end
      if fn.argc() ~= 0 and not dir then return end

      vim.schedule(function()
        local ws = require('claudespace.workspace')
        if dir then
          local name
          for _, w in ipairs(ws.list()) do
            if w.cwd and (w.cwd:gsub('/$', '')) == dir then name = w.name break end
          end
          -- Нет сохранённого воркспейса для этой папки → пусть dirdash покажет дашборд.
          if name and fn.filereadable(ws._get_ws_file(name)) == 1 then
            ws.load(name)
          end
          return
        end
        local last = ws._read_last()
        if last and fn.filereadable(ws._get_ws_file(last)) == 1 then
          ws.load(last)
        elseif #ws.list() > 0 then
          M.open()
        end
      end)
    end,
  })
end

return M
