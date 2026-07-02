-- Reading / Zen mode: centre the text with side padding, hide the chrome
-- (tree, tabline, statusline, numbers, signs) and turn on prose wrapping.
-- Toggle with <leader>z. No plugins.
local M = {}

local api = vim.api

local S = {
  active   = false,
  content  = nil,   -- content window
  pads     = {},    -- padding window ids
  sidebar  = false, -- was the activity bar open?
  saved    = nil,   -- saved global + window options
  wo       = nil,   -- saved content window-local options
}

local WO = { 'number', 'relativenumber', 'signcolumn', 'foldcolumn', 'cursorline',
             'wrap', 'linebreak', 'breakindent', 'scrolloff', 'winbar' }

-- Turn the current (just-split) window into an empty padding column.
local function make_pad(width)
  local win = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_set_width(win, width)
  local wo = vim.wo[win]
  wo.number = false; wo.relativenumber = false; wo.signcolumn = 'no'
  wo.foldcolumn = '0'; wo.cursorline = false; wo.winfixwidth = true
  wo.statuscolumn = ''; wo.winbar = ''
  wo.winhighlight = 'Normal:CSZenPad,EndOfBuffer:CSZenPad'
  return win
end

function M.enable()
  if S.active then return end
  api.nvim_set_hl(0, 'CSZenPad', { bg = 'NONE' })

  -- Close the activity bar so padding centres against the full width.
  local ok_sb, sidebar = pcall(require, 'claudespace.sidebar')
  if ok_sb and sidebar._state and sidebar._state.ab_win
     and api.nvim_win_is_valid(sidebar._state.ab_win) then
    S.sidebar = true
    pcall(sidebar.close)
  end

  S.content = api.nvim_get_current_win()
  S.saved = { showtabline = vim.o.showtabline, laststatus = vim.o.laststatus }
  S.wo = {}
  for _, o in ipairs(WO) do S.wo[o] = vim.wo[S.content][o] end

  local width = math.min((vim.o.textwidth > 0 and vim.o.textwidth + 8) or 88, vim.o.columns - 8)
  local pad   = math.max(0, math.floor((vim.o.columns - width) / 2))
  S.pads = {}
  if pad > 4 then
    api.nvim_set_current_win(S.content); vim.cmd 'topleft vsplit'
    S.pads[#S.pads + 1] = make_pad(pad)
    api.nvim_set_current_win(S.content); vim.cmd 'botright vsplit'
    S.pads[#S.pads + 1] = make_pad(pad)
  end

  api.nvim_set_current_win(S.content)
  local w = vim.wo[S.content]
  w.number = false; w.relativenumber = false; w.signcolumn = 'no'
  w.foldcolumn = '0'; w.cursorline = false
  w.wrap = true; w.linebreak = true; w.breakindent = true; w.scrolloff = 8
  vim.o.showtabline = 0
  vim.o.laststatus  = 0
  S.active = true
end

function M.disable()
  if not S.active then return end
  for _, p in ipairs(S.pads) do
    if api.nvim_win_is_valid(p) then pcall(api.nvim_win_close, p, true) end
  end
  S.pads = {}
  if S.content and api.nvim_win_is_valid(S.content) then
    for _, o in ipairs(WO) do
      if S.wo[o] ~= nil then pcall(function() vim.wo[S.content][o] = S.wo[o] end) end
    end
  end
  vim.o.showtabline = S.saved.showtabline
  vim.o.laststatus  = S.saved.laststatus
  if S.sidebar then pcall(function() require('claudespace.sidebar').open() end) end
  S.sidebar = false
  S.active = false
end

function M.toggle()
  if S.active then M.disable() else M.enable() end
end

function M.setup()
  vim.keymap.set('n', '<leader>z', M.toggle, { silent = true, desc = 'Zen / reading mode' })
end

return M
