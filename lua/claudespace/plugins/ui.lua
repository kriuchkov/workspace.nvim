local map = vim.keymap.set

-- Own theme: dark (VS Code Dark Modern) + light, following the terminal's
-- background. See lua/claudespace/theme/. Toggle with <leader>ub.
require('claudespace.theme').setup()
map('n', '<leader>ub', '<cmd>CSThemeToggle<cr>',
  { silent = true, desc = 'Toggle dark/light background' })

-- Icons (used by neo-tree, lualine, etc.)
vim.pack.add { 'https://github.com/echasnovski/mini.icons' }
if pcall(require, 'mini.icons') then
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()
end

-- Which-key
vim.pack.add { 'https://github.com/folke/which-key.nvim' }
local ok_wk, wk = pcall(require, 'which-key')
if ok_wk then
  wk.setup()
  if wk.add then
    wk.add({
      { '<leader>f',  group = 'Find/Files' },
      { '<leader>t',  group = 'Tabs' },
      { '<leader>c',  group = 'Claude' },
      { '<leader>g',  group = 'Git' },
      { '<leader>gt', group = 'Git: toggle' },
      { '<leader>l',  group = 'LSP' },
      { '<leader>x',  group = 'Diagnostics/Panels' },
      { '<leader>s',  group = 'Search/Replace' },
      { '<leader>w',  group = 'Workspace' },
      { '<leader>ww', group = 'Terminals' },
      { '<leader>d',  group = 'Debug' },
      { '<leader>r',  group = 'Run/Test' },
      { '<leader>m',  group = 'Marks' },
      { '<leader>?',  desc = 'Keymap cheatsheet' },
      -- Claude sub-groups for discoverability
      { '<leader>cf', desc = 'Claude: fix diagnostic' },
      { '<leader>ck', desc = 'Claude: explain code' },
      { '<leader>ci', desc = 'Claude: inject workspace context' },
      { '<leader>cd', desc = 'Claude: send diagnostics' },
      { '<leader>cT', desc = 'Claude: send terminal output' },
      { '<leader>c!', desc = 'Claude: shell command' },
      { '<leader>co', desc = 'Claude: generate docs' },
      { '<leader>cE', desc = 'Claude: multi-file compose' },
      { '<leader>cx', desc = 'Claude: cancel running jobs' },
      { '<leader>cH', desc = 'Claude: past session history' },
    })
  end
end
