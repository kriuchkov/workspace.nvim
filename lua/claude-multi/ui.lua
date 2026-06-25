local M = {}

local constants = require("claude-multi.constants")

---Setup custom highlight groups (links to user's theme)
function M.setup_highlights()
  -- Active session - link to TabLineSel (selected tab)
  vim.api.nvim_set_hl(0, "ClaudeMultiActive", { link = "TabLineSel", default = true })

  -- Inactive session - link to TabLine (inactive tabs)
  vim.api.nvim_set_hl(0, "ClaudeMultiInactive", { link = "TabLine", default = true })

  -- Pick mode letter label - link to WarningMsg (stands out)
  vim.api.nvim_set_hl(0, "ClaudeMultiPickLabel", { link = "WarningMsg", default = true })
end

---Get the letter for a given index (a, b, c, ...)
---@param index number (1-based)
---@return string letter
function M.get_pick_label(index)
  local letters = "abcdefghijklmnopqrstuvwxyz"
  if index >= 1 and index <= #letters then
    return letters:sub(index, index)
  end
  return "?"
end

---Format a single session tab for the winbar
---@param session table
---@param index number
---@param is_active boolean
---@param pick_mode boolean
---@return string formatted_tab
function M.format_session_tab(session, index, is_active, pick_mode)
  local name = session.name or "Unnamed"

  -- Add branch indicator if available
  if session.branch then
    name = name .. " [" .. session.branch .. "]"
  end

  local text
  if pick_mode then
    -- Show letter labels in pick mode
    local letter = M.get_pick_label(index)
    text = letter .. ":" .. name
  else
    -- Normal mode
    text = name
  end

  -- Apply highlight to active session
  if is_active then
    text = "%#ClaudeMultiActive#" .. text .. "%*"
  end

  return text
end

---Get the complete winbar string
---@return string
function M.get_winbar()
  local state = require("claude-multi.state")
  local sessions = state.get_sessions()
  local active_id = state.get_active_session_id()
  local pick_mode = state.get_pick_mode()

  if #sessions == 0 then
    return "No sessions"
  end

  local parts = {}

  for i, session in ipairs(sessions) do
    local is_active = session.id == active_id
    local tab = M.format_session_tab(session, i, is_active, pick_mode)
    table.insert(parts, tab)
  end

  local sep = " | "
  return table.concat(parts, sep)
end

---Update winbar — no-op in claudespace (tabline owns session display)
function M.update_winbar() end

return M
