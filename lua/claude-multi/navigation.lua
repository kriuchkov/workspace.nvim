local M = {}

-- Module dependencies
local state = require("claude-multi.state")
local ui = require("claude-multi.ui")
local terminal = require("claude-multi.terminal")
local window = require("claude-multi.window")
local constants = require("claude-multi.constants")

---Whether the panel is in native-tabpage layout
---@param config table
---@return boolean
local function is_tabpage(config)
  return config.layout == constants.Layout.TABPAGE
end

---Switch to specific session
---@param id number Session ID
---@param skip_hide_current? boolean Skip hiding current session
---@param config table Configuration object
function M.switch_session(id, skip_hide_current, config)
  -- Sync state with actual visibility (float/sidebar only; in tabpage mode the
  -- terminal lives in another tab, so this check does not apply).
  if not is_tabpage(config) and not terminal.is_window_visible() then
    state.set_visible(false)
    return
  end

  local active_id = state.get_active_session_id()
  if id == active_id then return end

  local win_opts = window.get_win_opts(config)

  -- Get session objects
  local target_session = state.get_session_by_id(id)
  local current_session = state.get_active_session()

  if not target_session then return end

  -- Hide current session
  if not skip_hide_current and current_session then
    terminal.hide(current_session, config)
  end

  -- Show new session (with startinsert)
  terminal.show(target_session, win_opts)

  state.set_active_session_id(id)
  ui.update_winbar()
end

---Navigate to next session (wrap around)
---@param config table Configuration object
function M.next_session(config)
  -- Sync state with actual visibility (float/sidebar only)
  if not is_tabpage(config) and not terminal.is_window_visible() then
    state.set_visible(false)
    return
  end

  local sessions = state.get_sessions()
  local active_id = state.get_active_session_id()

  if #sessions == 0 then return end

  local idx = 1
  for i, sess in ipairs(sessions) do
    if sess.id == active_id then
      idx = i
      break
    end
  end

  -- Navigate to next session (wrap around to first)
  if idx >= #sessions then
    M.switch_session(sessions[1].id, false, config)
  else
    M.switch_session(sessions[idx + 1].id, false, config)
  end
end

---Navigate to previous session (wrap around)
---@param config table Configuration object
function M.prev_session(config)
  -- Sync state with actual visibility (float/sidebar only)
  if not is_tabpage(config) and not terminal.is_window_visible() then
    state.set_visible(false)
    return
  end

  local sessions = state.get_sessions()
  local active_id = state.get_active_session_id()

  if #sessions == 0 then return end

  local idx = 1
  for i, sess in ipairs(sessions) do
    if sess.id == active_id then
      idx = i
      break
    end
  end

  -- Navigate to previous session (wrap around to last)
  if idx <= 1 then
    M.switch_session(sessions[#sessions].id, false, config)
  else
    M.switch_session(sessions[idx - 1].id, false, config)
  end
end

return M
