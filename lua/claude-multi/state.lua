local M = {}

-- Internal state
local _state = {
  visible = false,
  active_session_id = nil,
  sessions = {},
  pick_mode = false,
  next_id = 1,
}

---Initialize state with defaults or provided values
---@param initial_state? table Initial state to merge
function M.init(initial_state)
  if initial_state then
    _state = vim.tbl_extend("force", _state, initial_state)
  end
end

---Get all sessions
---@return table[] sessions
function M.get_sessions()
  return vim.deepcopy(_state.sessions)
end

---Get active session object
---@return table? session
function M.get_active_session()
  if not _state.active_session_id then return nil end
  return M.get_session_by_id(_state.active_session_id)
end

---Get session by ID
---@param id number
---@return table? session
function M.get_session_by_id(id)
  for _, session in ipairs(_state.sessions) do
    if session.id == id then
      return vim.deepcopy(session)
    end
  end
  return nil
end

---Get active session ID
---@return number?
function M.get_active_session_id()
  return _state.active_session_id
end

---Get pick mode state
---@return boolean
function M.get_pick_mode()
  return _state.pick_mode
end

---Set pick mode state
---@param pick_mode boolean
function M.set_pick_mode(pick_mode)
  _state.pick_mode = pick_mode
end

---Get visibility state
---@return boolean
function M.get_visible()
  return _state.visible
end

---Set visibility state
---@param visible boolean
function M.set_visible(visible)
  _state.visible = visible
end

---Set active session ID
---@param id number?
function M.set_active_session_id(id)
  if id and not M.get_session_by_id(id) then
    return false
  end
  _state.active_session_id = id
  return true
end

---Add a session
---@param session table
---@return boolean success
function M.add_session(session)
  if not session or not session.id then
    return false
  end
  table.insert(_state.sessions, vim.deepcopy(session))
  return true
end

---Remove a session by ID
---@param id number
---@return boolean success
function M.remove_session(id)
  local found = false
  local new_sessions = {}
  for _, s in ipairs(_state.sessions) do
    if s.id ~= id then
      table.insert(new_sessions, s)
    else
      found = true
    end
  end
  if found then
    _state.sessions = new_sessions
  end
  return found
end

---Renumber session names from left to right (Chat 1, Chat 2, etc.)
function M.renumber_sessions()
  for i, s in ipairs(_state.sessions) do
    s.name = "Chat " .. i
  end
end

---Update a session (partial update)
---@param id number
---@param updates table
---@return boolean success
function M.update_session(id, updates)
  for _, session in ipairs(_state.sessions) do
    if session.id == id then
      -- Modify the table in-place (don't reassign the loop variable!)
      for k, v in pairs(updates) do
        session[k] = v
      end
      return true
    end
  end
  return false
end

---Generate and return next ID
---@return number
function M.generate_next_id()
  local id = _state.next_id
  _state.next_id = _state.next_id + 1
  return id
end

return M
