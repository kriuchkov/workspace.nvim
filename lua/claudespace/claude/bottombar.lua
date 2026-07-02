-- Bottom bar listing Claude sessions (they no longer live in the top tabline).
-- A thin full-width float just above the global statusline; auto-shown while any
-- session exists. Switch sessions with the usual <leader>cc/ch/cl/cs keys.
local M = {}

local api = vim.api
local ns  = api.nvim_create_namespace('cs_claudebar')
local SUP = { '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹' }

local S = { win = nil, buf = nil, ranges = {} }  -- ranges: { {s, e, session_id} }

local function set_hl()
  local hl = api.nvim_set_hl
  local c  = require('claudespace.theme').colors()
  hl(0, 'CSBarBg',       { bg = c.bg_dark })
  hl(0, 'CSBarActive',   { bg = c.bg_sel, fg = c.cyan, bold = true })
  hl(0, 'CSBarInactive', { bg = c.bg_dark, fg = c.fg_dim })
  hl(0, 'CSBarDim',      { bg = c.bg_dark, fg = c.fg_faint })
end

local function sessions() return require('claudespace.claude.sessions') end

-- Open the session whose segment sits under the given column.
local function click_at(col)
  for _, r in ipairs(S.ranges) do
    if col >= r[1] and col < r[2] then
      pcall(function() sessions().open(r[3]) end)
      return
    end
  end
end

local function ensure_win()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then
    S.buf = api.nvim_create_buf(false, true)
    vim.bo[S.buf].bufhidden = 'hide'
    vim.bo[S.buf].filetype  = 'cs_claudebar'
    local o = { buffer = S.buf, nowait = true, silent = true }
    vim.keymap.set('n', '<LeftRelease>', function()
      click_at(api.nvim_win_get_cursor(0)[2])
    end, o)
    vim.keymap.set('n', '<CR>', function()
      click_at(api.nvim_win_get_cursor(0)[2])
    end, o)
  end
  local cfg = {
    relative = 'editor', row = vim.o.lines - 2 - vim.o.cmdheight, col = 0,
    width = vim.o.columns, height = 1,
    style = 'minimal', focusable = true, zindex = 30, noautocmd = true,
  }
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_set_config(S.win, cfg)
  else
    S.win = api.nvim_open_win(S.buf, false, cfg)
    vim.wo[S.win].winhighlight = 'Normal:CSBarBg,EndOfBuffer:CSBarBg'
  end
end

function M.hide()
  if S.win and api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  S.win = nil
end

function M.refresh()
  local ok, sess = pcall(sessions)
  local list = ok and sess.list() or {}
  if #list == 0 then M.hide(); return end
  ensure_win()
  local active = ok and sess.active() or nil

  local parts, hls, col = {}, {}, 0
  S.ranges = {}
  local function add(text, hl)
    hls[#hls + 1] = { col, col + #text, hl }
    parts[#parts + 1] = text
    col = col + #text
  end
  add(' 󰚩 Claude ', 'CSBarDim')
  for i, s in ipairs(list) do
    local grp = (active and s.id == active.id) and 'CSBarActive' or 'CSBarInactive'
    local num = (i <= #SUP) and (SUP[i] .. ' ') or ''
    local start = col
    add(' ' .. num .. (s.name or 'Chat') .. ' ', grp)
    S.ranges[#S.ranges + 1] = { start, col, s.id }   -- clickable segment
    add('│', 'CSBarDim')
  end

  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, { table.concat(parts) })
  vim.bo[S.buf].modifiable = false
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(api.nvim_buf_add_highlight, S.buf, ns, h[3], 0, h[1], h[2])
  end
end

function M.setup()
  set_hl()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = set_hl })
  -- Rebuild when sessions or focus change, or the UI resizes.
  api.nvim_create_autocmd(
    { 'BufEnter', 'BufWinEnter', 'TermClose', 'BufDelete', 'VimResized' },
    { callback = function() vim.schedule(M.refresh) end })
  vim.api.nvim_create_autocmd('VimLeavePre', { callback = M.hide })
  vim.schedule(M.refresh)
end

return M
