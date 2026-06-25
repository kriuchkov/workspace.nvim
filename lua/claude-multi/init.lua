local M = {}

-- Module dependencies
local constants = require("claude-multi.constants")
local state = require("claude-multi.state")
local ui = require("claude-multi.ui")
local terminal = require("claude-multi.terminal")
local navigation = require("claude-multi.navigation")
local picker = require("claude-multi.picker")
local panel = require("claude-multi.panel")
local recall = require("claude-multi.recall")
local worktree = require("claude-multi.worktree")
local commands = require("claude-multi.commands")
local health = require("claude-multi.health")

-- Default configuration
M.defaults = {
  layout = constants.Layout.FLOAT,
  float_width = 0.85,
  float_height = 0.85,
  sidebar_width = 0.4,
  keymaps = {
    toggle = "<leader>cc",
    recall = "<leader>cr",
    recall_worktree = "<leader>cR",
    new_session = "<leader>cn",
    new_worktree = "<leader>cw",
    prev_session = "<leader>ch",
    next_session = "<leader>cl",
    close_tab = "<leader>cx",
    pick_session = "<leader>cp",
  },
}

-- Setup function (called from plugin spec)
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  ui.setup_highlights()
  state.init()
  terminal.set_config(M.config)
  terminal.setup_close_handler()
  commands.register(M)
end

-- Public API (thin wrappers)
function M.toggle() panel.toggle(M.config) end
function M.new_session(cwd) panel.new_session(M.config, cwd) end
function M.new_session_worktree() worktree.new_session(M.new_session) end
function M.open_recall(cwd) recall.open(M.config, cwd) end
function M.open_recall_worktree() worktree.open_recall(M.open_recall) end
function M.close_tab() panel.close_tab(M.config) end
function M.open_session_here(id) panel.open_session_here(M.config, id) end
function M.new_session_here(cwd) panel.new_session_here(M.config, cwd) end
function M.refresh_sidebar() panel.refresh_sidebar() end
function M.next_session() navigation.next_session(M.config) end
function M.prev_session() navigation.prev_session(M.config) end
function M.pick_session() picker.start_pick(M.config) end
function M.switch_session(id, skip) navigation.switch_session(id, skip, M.config) end
function M.update_winbar() ui.update_winbar() end
function M.get_active_session() return state.get_active_session() end
function M.has_claude() return health.has_claude() end
function M.has_recall() return health.has_recall() end

return M
