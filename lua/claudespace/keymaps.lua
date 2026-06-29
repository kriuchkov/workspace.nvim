local map = vim.keymap.set

-- File / buffer navigation
map({ 'n', 'i', 'v' }, '<C-s>', '<cmd>w<CR><Esc>', { desc = 'Save' })
map('n', '<leader>q', '<cmd>q<CR>', { desc = 'Quit' })
map('n', '<leader>Q', '<cmd>qa<CR>', { desc = 'Quit all' })

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

-- Clear search highlight
map('n', '<Esc>', '<cmd>nohlsearch<CR>')
