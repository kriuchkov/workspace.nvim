-- Claude integration — sessions managed by claudespace.claude.sessions
local sessions = require('claudespace.claude.sessions')
sessions.setup()

-- Label Claude terminal buffers for tabline ("Chat N [claude]" is set in
-- sessions.lua already; this autocmd handles the winbar suppression and
-- :q delegation that must happen for EVERY Claude terminal window open).
vim.api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= 'terminal' then return end
    if not vim.b[buf].cs_session_id then return end

    -- :q on a Claude window → clean close via sessions module
    if not vim.b[buf]._cs_quitpre_registered then
      vim.b[buf]._cs_quitpre_registered = true
      vim.api.nvim_create_autocmd('QuitPre', {
        buffer = buf,
        once   = true,
        callback = function()
          require('claudespace.tabline').close_terminal(buf)
        end,
      })
    end
  end,
})

-- claudecode.nvim: official Anthropic plugin — gives Claude Code awareness of
-- cursor position, visual selection, LSP diagnostics, and open files via a
-- local WebSocket server.
vim.pack.add { 'https://github.com/coder/claudecode.nvim' }
if pcall(require, 'claudecode') then
  require('claudecode').setup {
    log_level    = 'warn',
    track_selection = true,
    focus_after_send = false,
    terminal = { provider = 'native' },
    diff_opts = {
      layout              = 'vertical',
      open_in_new_tab     = false,
      auto_resize_terminal = true,
    },
  }

  local map = vim.keymap.set
  -- @mention / tree-add are reachable from the <leader>cA context picker;
  -- keep a visual-mode @mention for sending a selection.
  map('v', '<leader>cA', '<cmd>ClaudeCodeSend<cr>',
    { desc = 'Claude: send selection as @mention', silent = true })
  -- Accept / reject inline diff proposed by Claude Code
  map('n', '<leader>cy', '<cmd>ClaudeCodeDiffAccept<cr>',
    { desc = 'Claude: accept diff',                silent = true })
  map('n', '<leader>cY', '<cmd>ClaudeCodeDiffDeny<cr>',
    { desc = 'Claude: reject diff',                silent = true })
end
