-- Lualine component: active sessions count + claudecode.nvim connection status
local M = {}

function M.component()
  local parts = {}

  -- Session count from claude-multi
  local ok_state, state = pcall(require, 'claude-multi.state')
  if ok_state then
    local n = #state.get_sessions()
    if n > 0 then table.insert(parts, '⚡' .. n) end
  end

  -- claudecode.nvim WebSocket connection indicator
  local ok_cc, cc = pcall(require, 'claudecode')
  if ok_cc and cc.is_claude_connected and cc.is_claude_connected() then
    table.insert(parts, '◉')
  end

  return table.concat(parts, ' ')
end

return M
