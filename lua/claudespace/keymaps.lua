local map = vim.keymap.set

-- File / buffer navigation
map({ 'n', 'i', 'v' }, '<C-s>', '<cmd>w<CR><Esc>', { desc = 'Save' })
map('n', '<leader>q', '<cmd>q<CR>', { desc = 'Quit' })
map('n', '<leader>Q', '<cmd>qa<CR>', { desc = 'Quit all' })
map('n', '<leader>?', function() require('claudespace.cheatsheet').show() end, { desc = 'Keymap cheatsheet' })

-- Window navigation
map('n', '<C-h>', '<C-w>h', { desc = 'Window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Window down' })
map('n', '<C-k>', '<C-w>k', { desc = 'Window up' })
map('n', '<C-l>', '<C-w>l', { desc = 'Window right' })

-- Diagnostics
map('n', '[d', vim.diagnostic.goto_prev, { desc = 'Prev diagnostic' })
map('n', ']d', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
map('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Diagnostic float' })

-- LSP reference highlights: прыжок между подсвеченными вхождениями символа
map('n', ']r', function()
  vim.lsp.buf.document_highlight()
  vim.cmd "normal! ]\'"
end, { desc = 'Next LSP reference' })
map('n', '[r', function()
  vim.lsp.buf.document_highlight()
  vim.cmd "normal! [\'"
end, { desc = 'Prev LSP reference' })

-- Terminal: exit with double Esc
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Toggle word wrap (word-boundary breaks + kept indent) for the current window
map('n', '<leader>uw', function()
  local on = not vim.wo.wrap
  vim.wo.wrap        = on
  vim.wo.linebreak   = on
  vim.wo.breakindent = on
  vim.notify('Word wrap ' .. (on and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle word wrap' })

-- Clear search highlight
map('n', '<Esc>', '<cmd>nohlsearch<CR>')
