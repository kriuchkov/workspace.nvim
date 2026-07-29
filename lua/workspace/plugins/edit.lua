local map = vim.keymap.set

-- ── Diagnostics & panels (native) ─────────────────────────────────────────────
-- No external plugin: the structured diagnostics/symbols lists are our own
-- sidebar panels (diag_panel / outline), and quickfix / location lists are
-- Neovim built-ins. Replaces trouble.nvim.

local sidebar = require 'workspace.sidebar'

-- Workspace-wide diagnostics list in the sidebar panel (toggles on repeat).
map('n', '<leader>xx', function() sidebar.select 'diagnostics' end,
  { desc = 'Diagnostics: panel',         silent = true })
-- Current-buffer diagnostics into the location list.
map('n', '<leader>xb', function() vim.diagnostic.setloclist() end,
  { desc = 'Diagnostics: buffer (loclist)', silent = true })
-- Document symbols in the sidebar outline panel (toggles on repeat).
map('n', '<leader>xs', function() sidebar.select 'outline' end,
  { desc = 'Symbols panel',              silent = true })
-- LSP references for the symbol under the cursor.
map('n', '<leader>xl', function() require('workspace.lsp_reflens').open_references() end,
  { desc = 'LSP: references',            silent = true })
-- Quickfix / location list windows (native).
map('n', '<leader>xq', '<cmd>botright copen<cr>', { desc = 'Quickfix list',  silent = true })
map('n', '<leader>xL', '<cmd>lopen<cr>',          { desc = 'Location list', silent = true })

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

