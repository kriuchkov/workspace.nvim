-- claude-multi: bundled at lua/claude-multi/ — behaviour patched in source, not here
require('claude-multi').setup {
  layout = 'sidebar',
  sidebar_width = 0.45,
  keymaps = {
    toggle          = false,  -- we register our own below
    new_session     = false,
    prev_session    = false,
    next_session    = false,
    recall          = false,  -- <leader>cr reserved for code review
    recall_worktree = false,
  },
}

local cm_terminal = require('claude-multi.terminal')

-- Keymaps
local map = vim.keymap.set
map({ 'n', 't' }, '<leader>cc', function()
  local sessions = require('claude-multi.state').get_sessions()
  if #sessions == 0 then
    require('claude-multi').new_session_here()
  else
    local active = require('claude-multi').get_active_session() or sessions[1]
    if active then cm_terminal.open_in_current_window(active) end
  end
end, { desc = 'Claude: open', silent = true })

map({ 'n', 't' }, '<leader>cn', function()
  require('claude-multi').new_session_here()
end, { desc = 'Claude: new session', silent = true })

map({ 'n', 't' }, '<leader>ch', function()
  local state = require('claude-multi.state')
  local sessions = state.get_sessions()
  if #sessions == 0 then return end
  local active_id = state.get_active_session_id()
  local idx = 1
  for i, s in ipairs(sessions) do if s.id == active_id then idx = i; break end end
  local prev = sessions[idx <= 1 and #sessions or idx - 1]
  if prev then state.set_active_session_id(prev.id); cm_terminal.open_in_current_window(prev) end
end, { desc = 'Claude: prev session', silent = true })

map({ 'n', 't' }, '<leader>cl', function()
  local state = require('claude-multi.state')
  local sessions = state.get_sessions()
  if #sessions == 0 then return end
  local active_id = state.get_active_session_id()
  local idx = 1
  for i, s in ipairs(sessions) do if s.id == active_id then idx = i; break end end
  local next_s = sessions[idx >= #sessions and 1 or idx + 1]
  if next_s then state.set_active_session_id(next_s.id); cm_terminal.open_in_current_window(next_s) end
end, { desc = 'Claude: next session', silent = true })

-- Claude terminal buffers: fix scrolloff, name them, list them in tabline
vim.api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= 'terminal' then return end
    local session_id = vim.b[buf].cm_session_id
    if not session_id then return end
    vim.wo.scrolloff = 0
    vim.wo.winbar = ''
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local ok, st = pcall(require, 'claude-multi.state')
      if not ok then return end
      for _, s in ipairs(st.get_sessions()) do
        if s.id == session_id then
          pcall(vim.api.nvim_buf_set_name, buf, (s.name or 'Chat') .. ' [claude]')
          break
        end
      end
    end)

    -- :q on a terminal window — delegate close to our tabline module
    if not vim.b[buf]._cs_quitpre_registered then
      vim.b[buf]._cs_quitpre_registered = true
      vim.api.nvim_create_autocmd('QuitPre', {
        buffer = buf,
        once = true,
        callback = function()
          require('claudespace.tabline').close_terminal(buf)
        end,
      })
    end
  end,
})

-- Auto-scroll background Claude terminals
local timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd('VimLeave', { callback = function() timer:stop() end })
timer:start(500, 200, vim.schedule_wrap(function()
  local cur = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not vim.api.nvim_win_is_valid(win) or win == cur then goto continue end
    local buf = vim.api.nvim_win_get_buf(win)
    if not vim.api.nvim_buf_is_valid(buf) then goto continue end
    if vim.bo[buf].buftype ~= 'terminal' or not vim.b[buf].cm_session_id then goto continue end
    local lc = vim.api.nvim_buf_line_count(buf)
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if ok and cursor[1] >= lc - 15 then pcall(vim.api.nvim_win_set_cursor, win, { lc, 0 }) end
    ::continue::
  end
end))

-- claudecode.nvim: official Anthropic plugin
-- Starts a local WebSocket server; Claude Code CLI connects to it and gains
-- awareness of cursor position, visual selection, LSP diagnostics, open files.
vim.pack.add { 'https://github.com/coder/claudecode.nvim' }
if pcall(require, 'claudecode') then
  require('claudecode').setup {
    log_level = 'warn',
    track_selection = true,   -- Claude sees your cursor/selection in real time
    focus_after_send = false, -- stay in editor after @-mentioning a file
    terminal = {
      provider = 'native',
    },
    diff_opts = {
      layout = 'vertical',
      open_in_new_tab = false,
      auto_resize_terminal = true,
    },
  }

  -- Send current file / visual selection to Claude as an @ mention
  local map = vim.keymap.set
  map('n', '<leader>cS', '<cmd>ClaudeCodeSend<cr>',
    { desc = 'Claude: send file as @mention', silent = true })
  map('v', '<leader>cS', '<cmd>ClaudeCodeSend<cr>',
    { desc = 'Claude: send selection as @mention', silent = true })

  -- Add file under cursor in neo-tree to Claude context
  map('n', '<leader>cA', '<cmd>ClaudeCodeTreeAdd<cr>',
    { desc = 'Claude: add tree file to context', silent = true })
end

