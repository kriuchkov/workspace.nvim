-- Workspace shell: fixed regions around a single content area.
--
--   top bar     : tabline
--   left bar    : activity bar + its panel (tree/git/outline/diag) — winfixwidth
--   center      : THE content window — every buffer tab & Claude session opens here
--   right bar   : outline / TOC panels — winfixwidth
--   bottom bar  : Claude session bar (float)
--
-- This module owns the "center" window so nothing ever splits the editor by
-- accident: content is always routed into the one center window.
local M = {}

local api = vim.api

-- A window is "center" when it is a real content window: not a float (the bars),
-- not a winfixwidth side panel, and not one of our cs_* panels. A Claude terminal
-- window counts as center so switching sessions reuses it.
function M.is_center(win)
  if not (win and api.nvim_win_is_valid(win)) then return false end
  if api.nvim_win_get_config(win).relative ~= '' then return false end  -- float / bar
  if vim.wo[win].winfixwidth then return false end                       -- left/right bar
  return vim.bo[api.nvim_win_get_buf(win)].filetype:match('^cs_') == nil
end

-- Return the center window, creating one if the layout has none (only bars open).
function M.center()
  local cur = api.nvim_get_current_win()
  if M.is_center(cur) then return cur end
  for _, w in ipairs(api.nvim_list_wins()) do
    if M.is_center(w) then return w end
  end
  -- No content window: split one off a non-fixed, non-float window.
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative == ''
       and not vim.wo[w].winfixbuf then
      pcall(api.nvim_set_current_win, w); break
    end
  end
  pcall(vim.cmd, 'vsplit')
  local w = api.nvim_get_current_win()
  vim.wo[w].winfixbuf = false
  return w
end

-- Open `buf` in the center window and focus it. Returns the window.
function M.open(buf)
  local w = M.center()
  pcall(api.nvim_set_current_win, w)
  if buf and api.nvim_buf_is_valid(buf) then pcall(api.nvim_win_set_buf, w, buf) end
  return w
end

-- Close extra content windows (keeping `keep`) that satisfy `pred(win)` — used to
-- collapse duplicate Claude panes into the single center slot.
function M.consolidate(keep, pred)
  for _, w in ipairs(api.nvim_list_wins()) do
    if w ~= keep and api.nvim_win_is_valid(w) and #api.nvim_list_wins() > 1
       and pred(w) then
      pcall(api.nvim_win_close, w, false)
    end
  end
end

return M
