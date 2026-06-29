-- Lualine component: active sessions count + claudecode.nvim connection status
local M = {}

function M.component()
  local parts = {}

  local n = #require('claudespace.claude.sessions').list()
  if n > 0 then table.insert(parts, '⚡' .. n) end

  -- claudecode.nvim WebSocket connection indicator
  local ok_cc, cc = pcall(require, 'claudecode')
  if ok_cc and cc.is_claude_connected and cc.is_claude_connected() then
    table.insert(parts, '◉')
  end

  return table.concat(parts, ' ')
end

return M
