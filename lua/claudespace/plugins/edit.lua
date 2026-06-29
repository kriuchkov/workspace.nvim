local map = vim.keymap.set

-- ── trouble ───────────────────────────────────────────────────────────────────
-- Structured panel for diagnostics, references, quickfix.

vim.pack.add { 'https://github.com/folke/trouble.nvim' }
if pcall(require, 'trouble') then
  require('trouble').setup {
    modes = {
      symbols = {
        win = { position = 'right', size = 0.25 },
      },
    },
  }
end

map('n', '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>',
  { desc = 'Diagnostics: all',    silent = true })
map('n', '<leader>xb', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
  { desc = 'Diagnostics: buffer', silent = true })
map('n', '<leader>xs', '<cmd>Trouble symbols toggle focus=false<cr>',
  { desc = 'Symbols panel',       silent = true })
map('n', '<leader>xl', '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
  { desc = 'LSP panel',           silent = true })
map('n', '<leader>xq', '<cmd>Trouble qflist toggle<cr>',
  { desc = 'Quickfix',            silent = true })
map('n', '<leader>xL', '<cmd>Trouble loclist toggle<cr>',
  { desc = 'Location list',       silent = true })

-- ── grug-far ──────────────────────────────────────────────────────────────────
-- Search & replace across the project with live preview before applying.

vim.pack.add { 'https://github.com/MagicDuck/grug-far.nvim' }
if pcall(require, 'grug-far') then
  require('grug-far').setup {
    headerMaxWidth = 80,
    resultsSeparatorLineChar = '─',
    spinnerStates = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' },
  }
end

-- Open with current word pre-filled
map('n', '<leader>sr', function()
  require('grug-far').open { prefills = { search = vim.fn.expand '<cword>' } }
end, { desc = 'Search/replace (word)', silent = true })

-- Open empty
map('n', '<leader>sR', function()
  require('grug-far').open()
end, { desc = 'Search/replace', silent = true })

-- Search for visual selection
map('v', '<leader>sr', function()
  require('grug-far').with_visual_selection()
end, { desc = 'Search/replace (selection)', silent = true })

