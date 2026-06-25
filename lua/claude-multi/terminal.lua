local M = {}

local state = require("claude-multi.state")
local session = require("claude-multi.session")
local ui = require("claude-multi.ui")
local constants = require("claude-multi.constants")

local _handling_close = false
local _config = nil

function M.set_config(config)
  _config = config
end

---@param sess table Session object
---@return string
function M.get_cmd(sess)
  local cmd = sess.source == constants.Source.RECALL and "recall" or "claude"
  return "zsh -i -c '" .. cmd .. "'"
end

---Find the terminal buffer for a session via our own buffer variable.
---@param session_id number
---@return number?
function M.find_session_buf(session_id)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == constants.BufferType.TERMINAL
      and vim.b[buf].cm_session_id == session_id
    then
      return buf
    end
  end
  return nil
end

---Open or focus a session's terminal in the current window.
---No float, no sidebar split, no snacks dependency.
---@param sess table Session object
function M.open_in_current_window(sess)
  local buf = M.find_session_buf(sess.id)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_win_set_buf(0, buf)
  else
    -- Create a listed, non-scratch buffer, mark it before termopen so that
    -- TermOpen autocmds (e.g. in plugins/claude.lua) can read cm_session_id.
    buf = vim.api.nvim_create_buf(true, false)
    vim.b[buf].cm_session_id = sess.id
    vim.api.nvim_win_set_buf(0, buf)
    vim.fn.termopen(M.get_cmd(sess), { cwd = sess.cwd })
    -- Clean up buffer and session state when the process exits
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = buf,
      once = true,
      callback = function() M.on_terminal_close(buf) end,
    })
  end
  vim.wo.winbar = ""
  vim.wo.scrolloff = 0
end

---Show a session — always opens in current window in claudespace.
---@param sess table
---@param _win_opts table (ignored)
function M.show(sess, _win_opts)
  M.open_in_current_window(sess)
end

---Hide a session — no-op in claudespace (switching sessions swaps buffers).
function M.hide(_sess, _config) end

---Return true when any Claude terminal buffer is visible in any window.
---@return boolean
function M.is_window_visible()
  local sessions = state.get_sessions()
  if #sessions == 0 then return false end
  local ids = {}
  for _, sess in ipairs(sessions) do ids[sess.id] = true end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if ids[vim.b[buf].cm_session_id] then return true end
  end
  return false
end

---Handle terminal process exit: update session state, switch to neighbour,
---then delete the closed buffer.
---@param buf number
function M.on_terminal_close(buf)
  if _handling_close then return end
  _handling_close = true

  if not vim.api.nvim_buf_is_valid(buf) then
    _handling_close = false
    return
  end

  local session_id = vim.b[buf].cm_session_id
  if not session_id then
    _handling_close = false
    return
  end

  local sessions = state.get_sessions()
  local closed_idx = nil
  for i, sess in ipairs(sessions) do
    if sess.id == session_id then closed_idx = i; break end
  end

  if not closed_idx then
    _handling_close = false
    return
  end

  local active_id = state.get_active_session_id()

  vim.schedule(function()
    state.remove_session(session_id)
    state.renumber_sessions()
    local remaining = state.get_sessions()

    pcall(function()
      require("neo-tree.sources.manager").refresh("claude")
    end)

    local function delete_buf()
      vim.defer_fn(function()
        if vim.v.dying > 0 then return end
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end, 150)
    end

    if #remaining == 0 then
      state.set_visible(false)
      state.set_active_session_id(nil)
      delete_buf()
    elseif active_id == session_id then
      local new_idx = math.min(math.max(1, closed_idx - 1), #remaining)
      local next_sess = remaining[new_idx]
      if next_sess then
        state.set_active_session_id(next_sess.id)
        M.open_in_current_window(next_sess)
        ui.update_winbar()
      end
      delete_buf()
    else
      delete_buf()
    end

    _handling_close = false
  end)
end

---No-op: TermClose is now registered per-buffer in open_in_current_window.
function M.setup_close_handler() end

return M
