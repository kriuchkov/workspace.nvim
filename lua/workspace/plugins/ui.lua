local map = vim.keymap.set

-- Own theme: dark (VS Code Dark Modern) + light, following the terminal's
-- background. See lua/workspace/theme/. Toggle with <leader>ub.
require('workspace.theme').setup()
map('n', '<leader>ub', '<cmd>CSThemeToggle<cr>',
  { silent = true, desc = 'Toggle dark/light background' })

-- Icons (used by neo-tree, lualine, etc.)
vim.pack.add { 'https://github.com/echasnovski/mini.icons' }
if pcall(require, 'mini.icons') then
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()
end

-- Which-key: native leader-hints popup (no plugin). Pausing on <leader> pops up
-- the possible continuations, read live from the registered maps. Group labels
-- live in workspace.whichkey's GROUPS table; the per-key descriptions come from
-- each map's own `desc`, so nothing has to be mirrored here.
require('workspace.whichkey').setup()
