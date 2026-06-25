local M = {}

local constants = require("claude-multi.constants")
local state = require("claude-multi.state")
local session = require("claude-multi.session")
local ui = require("claude-multi.ui")
local terminal = require("claude-multi.terminal")
local window = require("claude-multi.window")
local health = require("claude-multi.health")

---Open recall TUI for session selection
---@param config table Plugin configuration
---@param cwd? string Working directory to open recall in
function M.open(config, cwd)
  if not health.has_recall() then
    vim.notify("claude-multi: 'recall' CLI not found. Install from https://github.com/hrishioa/recall", vim.log.levels.ERROR)
    return
  end

  if not health.has_claude() then
    vim.notify("claude-multi: 'claude' CLI not found. Install from https://docs.anthropic.com/en/docs/claude-code", vim.log.levels.ERROR)
    return
  end

  terminal.setup_close_handler()

  -- Use provided cwd or current directory
  cwd = cwd or vim.fn.getcwd()
  local new_session = session.create(nil, constants.Source.RECALL, cwd)
  state.set_active_session_id(new_session.id)

  -- Open recall in terminal
  terminal.show(new_session, window.get_win_opts(config))

  state.set_visible(true)
  ui.update_winbar()
end

return M
