local M = {}

local health = require("claude-multi.health")

---Register all user commands and keymaps
---@param api table The plugin's public API (init.lua module)
function M.register(api)
  M.register_commands(api)
  M.register_keymaps(api.config, api)
end

---Register user commands
---@param api table The plugin's public API
function M.register_commands(api)
  local cmd = vim.api.nvim_create_user_command

  cmd("ClaudeToggle", api.toggle, { desc = "Toggle Claude panel" })
  cmd("ClaudeNew", function(opts)
    local path = opts.args ~= "" and opts.args or nil
    api.new_session(path)
  end, { desc = "New Claude session", nargs = "?" })
  cmd("ClaudeNewWorktree", api.new_session_worktree, { desc = "New session in worktree" })
  cmd("ClaudeNext", api.next_session, { desc = "Next session" })
  cmd("ClaudePrev", api.prev_session, { desc = "Previous session" })
  cmd("ClaudeClose", api.close_tab, { desc = "Close current tab" })
  cmd("ClaudePick", api.pick_session, { desc = "Pick session by letter" })

  -- Only register recall commands if recall is installed
  if health.has_recall() then
    cmd("ClaudeRecall", function() api.open_recall() end, { desc = "Open Recall TUI" })
    cmd("ClaudeRecallWorktree", api.open_recall_worktree, { desc = "Open Recall in worktree" })
  end
end

---Register keymaps
---@param config table Plugin configuration
---@param api table The plugin's public API
function M.register_keymaps(config, api)
  local function map(mode, lhs, rhs, desc)
    if lhs then
      vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
    end
  end

  local km = config.keymaps
  map({ "n", "t" }, km.toggle, "<cmd>ClaudeToggle<cr>", "Toggle Claude")
  map({ "n", "t" }, km.new_session, "<cmd>ClaudeNew<cr>", "New Session")
  map({ "n", "t" }, km.new_worktree, "<cmd>ClaudeNewWorktree<cr>", "New Worktree Session")
  map({ "n", "t" }, km.prev_session, "<cmd>ClaudePrev<cr>", "Previous Session")
  map({ "n", "t" }, km.next_session, "<cmd>ClaudeNext<cr>", "Next Session")
  map({ "n", "t" }, km.close_tab, "<cmd>ClaudeClose<cr>", "Close Tab")
  map({ "n", "t" }, km.pick_session, "<cmd>ClaudePick<cr>", "Pick Session")

  -- Only register recall keymaps if recall is installed
  if health.has_recall() then
    map({ "n", "t" }, km.recall, "<cmd>ClaudeRecall<cr>", "Open Recall")
    map({ "n", "t" }, km.recall_worktree, "<cmd>ClaudeRecallWorktree<cr>", "Recall in Worktree")
  end
end

return M
