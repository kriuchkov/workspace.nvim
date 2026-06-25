local map = vim.keymap.set

-- Diff viewer
vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }
if pcall(require, 'diffview') then
  require('diffview').setup()
end
map('n', '<leader>gd', '<cmd>DiffviewOpen<cr>', { desc = 'Git diff' })
map('n', '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', { desc = 'File history' })
map('n', '<leader>gD', '<cmd>DiffviewClose<cr>', { desc = 'Close diff' })

-- Lazygit
vim.pack.add { 'https://github.com/kdheepak/lazygit.nvim' }
map('n', '<leader>lg', '<cmd>LazyGit<cr>', { desc = 'LazyGit' })

-- Git signs
vim.pack.add { 'https://github.com/lewis6991/gitsigns.nvim' }
if pcall(require, 'gitsigns') then
  require('gitsigns').setup {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
    },
  }
end
