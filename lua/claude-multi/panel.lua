local M = {}

local constants = require("claude-multi.constants")
local state = require("claude-multi.state")
local session = require("claude-multi.session")
local ui = require("claude-multi.ui")
local terminal = require("claude-multi.terminal")
local window = require("claude-multi.window")
local health = require("claude-multi.health")

---Toggle the Claude panel visibility
---@param config table Plugin configuration
function M.toggle(config)
  if not health.has_claude() then
    vim.notify("claude-multi: 'claude' CLI not found. Install from https://docs.anthropic.com/en/docs/claude-code", vim.log.levels.ERROR)
    return
  end

  terminal.setup_close_handler()

  -- Tabpage layout: there is no float/split to hide. "Toggle" means focus the
  -- active Claude tab (creating one if none exist). Leaving is done by switching
  -- tabs natively.
  if config.layout == constants.Layout.TABPAGE then
    local sessions = state.get_sessions()
    if #sessions == 0 then
      M.new_session(config)
    else
      local active_session = state.get_active_session()
      if active_session then
        terminal.show(active_session, window.get_win_opts(config))
        state.set_visible(true)
        ui.update_winbar()
      end
    end
    return
  end

  local actually_visible = terminal.is_window_visible()

  if actually_visible then
    -- Window is visible, hide it
    local active_session = state.get_active_session()
    if active_session then
      terminal.hide(active_session, config)
    end
    state.set_visible(false)
  else
    -- Window is hidden, show it
    local sessions = state.get_sessions()

    if #sessions == 0 then
      -- No tabs exist, open new session
      M.new_session(config)
    else
      -- Show existing active session
      local active_session = state.get_active_session()
      if active_session then
        terminal.show(active_session, window.get_win_opts(config))
        state.set_visible(true)
        ui.update_winbar()
      end
    end
  end
end

---Create a new Claude session
---@param config table Plugin configuration
---@param cwd? string Working directory path
function M.new_session(config, cwd)
  if not health.has_claude() then
    vim.notify("claude-multi: 'claude' CLI not found. Install from https://docs.anthropic.com/en/docs/claude-code", vim.log.levels.ERROR)
    return
  end

  -- Default to current working directory if no path provided
  if cwd then
    cwd = vim.fn.expand(cwd)
    if vim.fn.isdirectory(cwd) ~= 1 then
      vim.notify("claude-multi: Directory not found: " .. cwd, vim.log.levels.ERROR)
      return
    end
  else
    cwd = vim.fn.getcwd()
  end

  terminal.setup_close_handler()

  local win_opts = window.get_win_opts(config)
  local currently_visible = terminal.is_window_visible()

  -- Hide current session if visible
  if currently_visible then
    local current_session = state.get_active_session()
    if current_session then
      terminal.hide(current_session, config)
    end
  end

  -- Create and show new session
  local new_session = session.create(nil, constants.Source.NEW, cwd)
  terminal.show(new_session, win_opts)

  state.set_active_session_id(new_session.id)
  state.set_visible(true)
  ui.update_winbar()
end

---Open/focus an existing session in the current window (for the neo-tree source).
---@param config table Plugin configuration
---@param id number Session ID
function M.open_session_here(config, id)
  local sess = state.get_session_by_id(id)
  if not sess then return end
  terminal.setup_close_handler()
  state.set_active_session_id(id)
  state.set_visible(true)
  terminal.open_in_current_window(sess)
  -- No ui.update_winbar() here: the neo-tree "claude" source is the session UI.
  M.refresh_sidebar()
end

---Create a new session and open it in the current window (for the neo-tree source).
---@param config table Plugin configuration
---@param cwd? string Working directory path
function M.new_session_here(config, cwd)
  if not health.has_claude() then
    vim.notify("claude-multi: 'claude' CLI not found. Install from https://docs.anthropic.com/en/docs/claude-code", vim.log.levels.ERROR)
    return
  end
  cwd = cwd or vim.fn.getcwd()
  terminal.setup_close_handler()
  local new_session = session.create(nil, constants.Source.NEW, cwd)
  state.set_active_session_id(new_session.id)
  state.set_visible(true)
  terminal.open_in_current_window(new_session)
  -- No ui.update_winbar() here: the neo-tree "claude" source is the session UI.
  M.refresh_sidebar()
end

---Refresh the neo-tree "claude" source if it is loaded (no-op otherwise).
function M.refresh_sidebar()
  pcall(function()
    require("neo-tree.sources.manager").refresh("claude")
  end)
end

---Close the current tab
---@param config table Plugin configuration
function M.close_tab(config)
  local active_session = state.get_active_session()
  if not active_session then return end

  if config.layout == constants.Layout.TABPAGE then
    -- Deleting the terminal buffer kills the job, which fires TermClose ->
    -- on_terminal_close (removes the session and focuses a neighbor). Then drop
    -- the now-empty tabpage.
    local buf = terminal.find_session_buf(active_session.id)
    local tp = active_session.tabpage
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if tp and vim.api.nvim_tabpage_is_valid(tp) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    return
  end

  -- Close the terminal (this will trigger on_terminal_close)
  terminal.hide(active_session, config)
end

return M
