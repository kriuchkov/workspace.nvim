-- Neo-tree "claude" source.
--
-- Registers Claude as a neo-tree source so it appears in neo-tree's source
-- selector (the clickable tabs at the top of the tree panel, like VS Code's
-- activity bar). Selecting this source replaces the file tree with a list of
-- Claude sessions; pressing <cr> on a session opens its terminal in the main
-- editor window while the tree panel stays in place.
--
-- Register it from your neo-tree config (renderers/mappings ship with this
-- module via `default_config`, so you only need to list the source):
--
--   require("neo-tree").setup({
--     sources = { "filesystem", "buffers", "git_status", "claude-multi.neotree" },
--     source_selector = {
--       winbar = true,
--       sources = {
--         { source = "filesystem" },
--         { source = "buffers" },
--         { source = "git_status" },
--         { source = "claude" },
--       },
--     },
--   })
--
-- Open it with `:Neotree claude` or by clicking the "Claude" tab.

local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local nt_utils = require("neo-tree.utils")

local M = {
  name = "claude",
  display_name = "  Claude ",
}

---Build the node list from the current claude-multi sessions.
---@param state table neo-tree state
M.navigate = function(state, _, _, callback)
  local cm_state = require("claude-multi.state")
  local sessions = cm_state.get_sessions()
  local active_id = cm_state.get_active_session_id()

  local nodes = {}
  for _, s in ipairs(sessions) do
    local label = s.name or ("Chat " .. tostring(s.id))
    if s.branch then
      label = label .. "  " .. s.branch
    end
    local marker = (s.id == active_id) and "● " or "○ "
    table.insert(nodes, {
      id = "claude-session-" .. tostring(s.id),
      name = marker .. label,
      type = "claude_session",
      extra = { session_id = s.id },
    })
  end

  table.insert(nodes, {
    id = "claude-new",
    name = "+ New chat",
    type = "claude_action",
    extra = { action = "new" },
  })

  renderer.show_nodes(nodes, state)

  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

M.setup = function(_, _) end

-- Move focus to a normal editor window (not the tree/sidebar) before opening
-- the chat there.
local function focus_main_window(state)
  local win = nt_utils.get_appropriate_window(state)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

-- Components: inherit the common ones (name, indent, icon, ...). Icons are baked
-- into the node name in navigate(), so no custom component is needed.
M.components = require("neo-tree.sources.common.components")

-- Commands: inherit the common ones, then add our two.
M.commands = vim.tbl_deep_extend("force", {}, require("neo-tree.sources.common.commands"), {
  ---Open (or focus) the session under the cursor in the main window, or create
  ---a new session for the "+ New chat" node.
  claude_open = function(state)
    local node = state.tree and state.tree:get_node()
    if not node or not node.extra then
      return
    end
    local cm = require("claude-multi")
    if node.extra.session_id then
      focus_main_window(state)
      cm.open_session_here(node.extra.session_id)
    elseif node.extra.action == "new" then
      focus_main_window(state)
      cm.new_session_here()
    end
  end,

  ---Close the session under the cursor.
  claude_close = function(state)
    local node = state.tree and state.tree:get_node()
    if not node or not node.extra or not node.extra.session_id then
      return
    end
    local cm = require("claude-multi")
    -- Make it active without touching the visible window, then close it; the
    -- TermClose handler refreshes this source.
    cm.switch_session(node.extra.session_id, true)
    cm.close_tab()
  end,

  ---Rebuild the session list.
  claude_refresh = function()
    manager.refresh("claude")
  end,
})

-- Shipped defaults for this source (merged with the user's neo-tree config).
M.default_config = {
  renderers = {
    claude_session = {
      { "indent" },
      { "name", zindex = 10 },
    },
    claude_action = {
      { "indent" },
      { "name", zindex = 10, highlight = "NeoTreeDimText" },
    },
  },
  window = {
    position = "left",
    mappings = {
      ["<cr>"] = "claude_open",
      ["<2-LeftMouse>"] = "claude_open",
      ["a"] = "claude_open", -- intended for the "+ New chat" line
      ["d"] = "claude_close",
      ["R"] = "claude_refresh",
    },
  },
}

return M
