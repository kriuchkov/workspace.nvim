local map = vim.keymap.set

-- Colorscheme
vim.pack.add { 'https://github.com/folke/tokyonight.nvim' }
pcall(vim.cmd.colorscheme, 'tokyonight-night')

-- Icons (used by neo-tree, lualine, etc.)
vim.pack.add { 'https://github.com/echasnovski/mini.icons' }
if pcall(require, 'mini.icons') then
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()
end

-- Custom tabline (replaces barbar — we own the lifecycle)
require('claudespace.tabline').setup()

-- File tree (custom — no neo-tree/nui dependency)
require('claudespace.filetree').setup()

-- Statusline (custom — no lualine dependency)
require('claudespace.statusline').setup()

-- Winbar: relative path breadcrumb
require('claudespace.winbar').setup()

-- Directory dashboard (replaces netrw)
require('claudespace.dirdash').setup()

-- Workspace manager
require('claudespace.workspace').setup()

-- Home screen (replaces VimEnter logic from workspace)
require('claudespace.home').setup()

-- Task runner
require('claudespace.tasks').setup()

-- Outline panel
require('claudespace.outline').setup()

-- Notifications center
require('claudespace.notify').setup()

-- Quick marks
require('claudespace.marks').setup()

-- Command palette
require('claudespace.palette').setup()

-- Git staging UI
require('claudespace.git_ui').setup()

-- Claude context injection
require('claudespace.claude.context').setup()

-- Test runner UI
require('claudespace.test_ui').setup()

-- Workspace templates
require('claudespace.templates').setup()

-- Trouble (diagnostics panel)
vim.pack.add { 'https://github.com/folke/trouble.nvim' }
if pcall(require, 'trouble') then
  require('trouble').setup()
end
map('n', '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', { desc = 'Diagnostics' })
map('n', '<leader>xb', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', { desc = 'Buffer diagnostics' })
map('n', '<leader>xs', '<cmd>Trouble symbols toggle<cr>', { desc = 'Symbols' })
map('n', '<leader>xq', '<cmd>Trouble qflist toggle<cr>', { desc = 'Quickfix' })

-- Which-key
vim.pack.add { 'https://github.com/folke/which-key.nvim' }
local ok_wk, wk = pcall(require, 'which-key')
if ok_wk then
  wk.setup()
  if wk.add then
    wk.add({
      { '<leader>f', group = 'Find' },
      { '<leader>t', group = 'Tabs/Terminal' },
      { '<leader>c', group = 'Claude' },
      { '<leader>g', group = 'Git' },
      { '<leader>x', group = 'Diagnostics' },
      { '<leader>w', group = 'Workspace' },
      { '<leader>r', group = 'Run/Tasks' },
      { '<leader>m', group = 'Marks' },
      { '<leader>j', group = 'Jump' },
    })
  end
end
