local M = {}

local constants = require("claude-multi.constants")

---Create a new session with optional name and source
---@param name? string
---@param source? string "recall" or "new" (default: "new")
---@param cwd? string working directory path
---@return table session
function M.create(name, source, cwd)
  local state = require("claude-multi.state")
  local id = state.generate_next_id()

  -- Look up branch name if cwd is provided
  local branch = nil
  if cwd then
    local git = require("claude-multi.git")
    branch = git.get_branch(cwd)
  end

  local session = {
    id = id,
    name = name or M.get_default_name(),
    source = source or constants.Source.NEW,  -- RECALL or NEW
    created_at = os.time(),
    cwd = cwd,      -- working directory path
    branch = branch, -- git branch name (looked up from cwd)
  }

  state.add_session(session)
  return session
end

---Rename a session by ID
---@param id number
---@param new_name string
---@return boolean success
---@return string? error
function M.rename(id, new_name)
  if not new_name or new_name == "" then
    return false, "Name cannot be empty"
  end

  local state = require("claude-multi.state")
  return state.update_session(id, { name = new_name })
end

---Get default session name based on count
---@return string
function M.get_default_name()
  local state = require("claude-multi.state")
  local sessions = state.get_sessions()
  return "Chat " .. (#sessions + 1)
end

return M
