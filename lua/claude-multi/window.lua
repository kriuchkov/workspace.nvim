local M = {}

-- Module dependencies
local ui = require("claude-multi.ui")
local constants = require("claude-multi.constants")

---Get window options based on layout mode
---@param config table Configuration object
---@return table opts Window options for snacks.terminal
function M.get_win_opts(config)
  local opts = {
    wo = {
      winbar = ui.get_winbar(),
    },
  }

  if config.layout == constants.Layout.TABPAGE then
    -- Each session lives in its own native Neovim tabpage; the terminal takes
    -- over the current window of that tab (see terminal.show).
    opts.position = "current"
  elseif config.layout == constants.Layout.SIDEBAR then
    opts.position = "right"
    opts.width = config.sidebar_width
    opts.height = 1.0
    opts.border = constants.Border.SINGLE
  else
    opts.position = "float"
    opts.width = config.float_width
    opts.height = config.float_height
    opts.border = constants.Border.ROUNDED
  end

  return opts
end

return M

