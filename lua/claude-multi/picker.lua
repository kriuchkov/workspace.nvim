local M = {}

M.letters = "abcdefghijklmnopqrstuvwxyz"

---Start pick mode: display letters and wait for key press
---@param config table Plugin configuration
function M.start_pick(config)
  local state = require("claude-multi.state")
  local ui = require("claude-multi.ui")
  local terminal = require("claude-multi.terminal")
  local navigation = require("claude-multi.navigation")

  -- Only operate when our terminal window is actually visible
  if not terminal.is_window_visible() then
    state.set_visible(false)
    return
  end

  local sessions = state.get_sessions()
  if #sessions <= 1 then
    return
  end

  -- Enter pick mode and render the letter labels
  state.set_pick_mode(true)
  ui.update_winbar()
  vim.cmd("redraw")

  -- Wait for a single key press
  local ok, char = pcall(vim.fn.getcharstr)

  state.set_pick_mode(false)
  ui.update_winbar()

  if ok and char then
    -- Convert letter to session index and switch the visible terminal
    local idx = M.letters:find(char, 1, true)
    if idx and idx <= #sessions then
      navigation.switch_session(sessions[idx].id, false, config)
    end
  end
end

return M
