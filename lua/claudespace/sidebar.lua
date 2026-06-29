-- Activity bar: a thin icon column (far left) that switches the sidebar panel,
-- VS Code style. Explorer/Outline are hosted panels (open to the right of the bar);
-- the rest are launchers. Click an icon, press its number, or <CR> on its line.
-- Badges show live counts (diagnostics errors, active Claude sessions).
local M = {}

local api = vim.api

local S = { ab_win = nil, ab_buf = nil, active = nil }

-- ── Badge sources ─────────────────────────────────────────────────────────────

local function diag_errors()
  local ok, c = pcall(vim.diagnostic.count, nil)
  if not ok then return nil end
  local e = c[vim.diagnostic.severity.ERROR] or 0
  return e > 0 and e or nil
end

local function session_count()
  local ok, s = pcall(require, 'claudespace.claude.sessions')
  if not ok or not s.list then return nil end
  local ok2, l = pcall(s.list)
  if not ok2 or not l or #l == 0 then return nil end
  return #l
end

-- ── Views ─────────────────────────────────────────────────────────────────────
-- kind 'panel'  = hosted to the right of the bar (mutually exclusive)
-- kind 'launch' = one-shot action (float / picker / toggle)
-- Icons by codepoint (FontAwesome, present in every Nerd Font). Built at runtime
-- via nr2char so the source stays ASCII. Swap a codepoint if your font lacks it;
-- the tooltip (label) names the view on hover regardless.
local function ic(cp) return vim.fn.nr2char(cp) end
local VIEWS = {
  { id = 'explorer', icon = ic(0xf07c), label = 'Explorer', kind = 'panel',
    open  = function() require('claudespace.filetree').open(nil, S.ab_win) end,
    close = function() require('claudespace.filetree').close() end },
  { id = 'search', icon = ic(0xf002), label = 'Search', kind = 'launch',
    run = function() pcall(vim.cmd, 'Telescope live_grep') end },
  { id = 'git', icon = ic(0xf126), label = 'Git', kind = 'panel',
    open  = function() require('claudespace.git_ui').open(S.ab_win) end,
    close = function() require('claudespace.git_ui').close() end },
  { id = 'outline', icon = ic(0xf0e8), label = 'Outline', kind = 'panel',
    open  = function() require('claudespace.outline').open(S.ab_win) end,
    close = function() require('claudespace.outline').close() end },
  { id = 'diagnostics', icon = ic(0xf188), label = 'Diagnostics', kind = 'panel',
    open  = function() require('claudespace.diag_panel').open(S.ab_win) end,
    close = function() require('claudespace.diag_panel').close() end,
    badge = diag_errors, badge_hl = 'CSAbBadgeErr' },
  { id = 'buffers', icon = ic(0xf0c5), label = 'Buffers', kind = 'launch',
    run = function() pcall(vim.cmd, 'Telescope buffers') end },
  { id = 'tests', icon = ic(0xf0c3), label = 'Tests', kind = 'launch',
    run = function() require('claudespace.test_ui').run() end },
  { id = 'todo', icon = ic(0xf046), label = 'TODO', kind = 'launch',
    run = function() pcall(vim.cmd, 'TodoTrouble') end },
  { id = 'marks', icon = ic(0xf02e), label = 'Marks', kind = 'launch',
    run = function() require('claudespace.marks').show() end },
  { id = 'claude', icon = ic(0xf075), label = 'Claude', kind = 'launch',
    run = function() require('claudespace.claude.dashboard').open() end,
    badge = session_count, badge_hl = 'CSAbBadgeInfo' },
}
local BY_ID, ORDER = {}, {}
for i, v in ipairs(VIEWS) do BY_ID[v.id] = v; ORDER[i] = v.id end

local SUP = { '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹' }
local function badge_str(n)
  if not n then return nil end
  return n > 9 and '⁹⁺' or SUP[n]
end

local NS = api.nvim_create_namespace 'cs_activitybar'

local function setup_highlights()
  local hi = api.nvim_set_hl
  hi(0, 'CSAbBg',       { bg = '#16161e' })
  hi(0, 'CSAbActive',   { bg = '#16161e', fg = '#7dcfff', bold = true })
  hi(0, 'CSAbInactive', { bg = '#16161e', fg = '#828bb8' })
  hi(0, 'CSAbBadgeErr',  { bg = '#16161e', fg = '#f7768e', bold = true })
  hi(0, 'CSAbBadgeInfo', { bg = '#16161e', fg = '#7dcfff', bold = true })
  hi(0, 'CSAbTip',       { bg = '#2d3149', fg = '#c0caf5', bold = true })
  hi(0, 'CSAbSel',       { bg = '#2d3149' })   -- cursor row when the bar is focused
end

local function render_bar()
  if not (S.ab_buf and api.nvim_buf_is_valid(S.ab_buf)) then return end
  local lines, badges = {}, {}
  for i, v in ipairs(VIEWS) do
    local b = v.badge and badge_str(v.badge())
    local prefix = (S.active == v.id) and '▎' or ' '
    lines[i] = prefix .. v.icon .. (b or '')
    badges[i] = b and { col = #(prefix .. v.icon), hl = v.badge_hl } or nil
  end
  vim.bo[S.ab_buf].modifiable = true
  api.nvim_buf_set_lines(S.ab_buf, 0, -1, false, lines)
  vim.bo[S.ab_buf].modifiable = false
  api.nvim_buf_clear_namespace(S.ab_buf, NS, 0, -1)
  for i, v in ipairs(VIEWS) do
    local grp = (S.active == v.id) and 'CSAbActive' or 'CSAbInactive'
    api.nvim_buf_add_highlight(S.ab_buf, NS, grp, i - 1, 0, -1)
    if badges[i] then
      api.nvim_buf_add_highlight(S.ab_buf, NS, badges[i].hl, i - 1, badges[i].col, -1)
    end
  end
end
M._render = render_bar

-- ── Tooltip ───────────────────────────────────────────────────────────────────
local tip = { win = nil, buf = nil }

local function hide_tip()
  if tip.win and api.nvim_win_is_valid(tip.win) then pcall(api.nvim_win_close, tip.win, true) end
  tip.win = nil
end

local function show_tip()
  if not (S.ab_win and api.nvim_win_is_valid(S.ab_win)) then return end
  if api.nvim_get_current_win() ~= S.ab_win then hide_tip(); return end
  local line = api.nvim_win_get_cursor(S.ab_win)[1]
  local v = VIEWS[line]
  if not v then hide_tip(); return end
  local text = ' ' .. v.label .. ' '
  if not (tip.buf and api.nvim_buf_is_valid(tip.buf)) then
    tip.buf = api.nvim_create_buf(false, true)
  end
  api.nvim_buf_set_lines(tip.buf, 0, -1, false, { text })
  local cfg = {
    relative = 'win', win = S.ab_win, row = line - 1, col = 5,
    width = #text, height = 1, style = 'minimal', focusable = false, zindex = 90, noautocmd = true,
  }
  if tip.win and api.nvim_win_is_valid(tip.win) then
    api.nvim_win_set_config(tip.win, cfg)
  else
    tip.win = api.nvim_open_win(tip.buf, false, cfg)
    vim.wo[tip.win].winhighlight = 'Normal:CSAbTip'
  end
end

local function ensure_bar()
  if S.ab_win and api.nvim_win_is_valid(S.ab_win) then return end
  S.ab_buf = api.nvim_create_buf(false, true)
  vim.bo[S.ab_buf].buftype   = 'nofile'
  vim.bo[S.ab_buf].bufhidden = 'hide'
  vim.bo[S.ab_buf].swapfile  = false
  vim.bo[S.ab_buf].filetype  = 'cs_activitybar'

  vim.cmd 'topleft vsplit'
  S.ab_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.ab_win, S.ab_buf)
  api.nvim_win_set_width(S.ab_win, 5)
  local wo = vim.wo[S.ab_win]
  wo.number = false; wo.relativenumber = false; wo.signcolumn = 'no'
  wo.wrap = false; wo.cursorline = true; wo.winfixwidth = true
  wo.winfixbuf = true; wo.foldcolumn = '0'; wo.statuscolumn = ''
  wo.winhighlight = 'Normal:CSAbBg,CursorLine:CSAbSel'
  wo.winbar = ''

  local o = { buffer = S.ab_buf, nowait = true, silent = true }
  local k = vim.keymap.set
  k('n', '<CR>', function() M.select(ORDER[api.nvim_win_get_cursor(0)[1]]) end, o)
  k('n', '<LeftRelease>', function() M.select(ORDER[api.nvim_win_get_cursor(0)[1]]) end, o)
  for i = 1, math.min(#ORDER, 9) do
    k('n', tostring(i), function() M.select(ORDER[i]) end, o)
  end
  k('n', 'q', M.close, o)

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(S.ab_win), once = true,
    callback = function() S.ab_win = nil; hide_tip() end,
  })
  -- Tooltip with the view name follows the cursor in the bar
  api.nvim_create_autocmd({ 'CursorMoved', 'WinEnter' }, {
    buffer = S.ab_buf, callback = show_tip,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    buffer = S.ab_buf, callback = hide_tip,
  })
  render_bar()
end

-- Select a view: panels toggle/switch in the slot; launchers just run.
function M.select(id)
  ensure_bar()
  local v = BY_ID[id]
  if not v then return end
  if v.kind == 'launch' then
    v.run()
    vim.schedule(render_bar)
    return
  end
  if S.active == id then
    BY_ID[id].close()
    S.active = nil
  else
    if S.active and BY_ID[S.active] then BY_ID[S.active].close() end
    v.open()
    S.active = id
  end
  render_bar()
end

function M.open()
  ensure_bar()
  if not S.active then M.select 'explorer' end
end

function M.close()
  if S.active and BY_ID[S.active] then pcall(BY_ID[S.active].close) end
  S.active = nil
  if S.ab_win and api.nvim_win_is_valid(S.ab_win) then
    pcall(api.nvim_win_close, S.ab_win, true)
  end
  S.ab_win = nil
end

function M.toggle()
  if S.ab_win and api.nvim_win_is_valid(S.ab_win) then M.close() else M.open() end
end

-- Open (if needed) and move focus into the bar, cursor on the active view.
function M.focus()
  if not (S.ab_win and api.nvim_win_is_valid(S.ab_win)) then M.open() end
  if not (S.ab_win and api.nvim_win_is_valid(S.ab_win)) then return end
  api.nvim_set_current_win(S.ab_win)
  for i, v in ipairs(VIEWS) do
    if v.id == S.active then pcall(api.nvim_win_set_cursor, S.ab_win, { i, 0 }); break end
  end
end

-- Re-render badges when their counts may have changed.
function M.refresh()
  if S.ab_win and api.nvim_win_is_valid(S.ab_win) then render_bar() end
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })
  api.nvim_create_autocmd({ 'DiagnosticChanged', 'BufEnter', 'TermClose' }, {
    callback = function() M.refresh() end,
  })
  vim.keymap.set('n', '<leader>e', M.toggle, { silent = true, desc = 'Toggle sidebar (activity bar)' })
  vim.keymap.set('n', '<leader>E', M.focus,  { silent = true, desc = 'Focus the activity bar' })
end

-- test seam
M._state = S
M._views = VIEWS

return M
