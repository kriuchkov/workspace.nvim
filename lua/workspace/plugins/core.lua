local map = vim.keymap.set

-- ── Fuzzy finder ──────────────────────────────────────────────────────────────
-- Native picker (prompt + results + preview, fuzzy via matchfuzzypos, async via
-- vim.system). Backs vim.ui.select and every workspace picker; no telescope.
-- plenary stays for neotest and the todo search job.

vim.pack.add { 'https://github.com/nvim-lua/plenary.nvim' }

local picker = require 'workspace.picker'
picker.setup()

map('n', '<leader>ff', function() picker.files() end,    { desc = 'Find files' })
map('n', '<leader>fg', function() picker.grep() end,     { desc = 'Live grep' })
map('n', '<leader>fb', function() picker.buffers() end,  { desc = 'Buffers' })
map('n', '<leader>fh', function() picker.help() end,     { desc = 'Help' })
map('n', '<leader>fr', function() picker.oldfiles() end, { desc = 'Recent files' })

-- ── Treesitter ────────────────────────────────────────────────────────────────
-- Per-buffer activation via FileType autocmd — avoids nvim-treesitter.configs API
-- that doesn't exist on the main branch.

vim.pack.add { 'https://github.com/nvim-treesitter/nvim-treesitter' }
pcall(function()
  local ts    = require 'nvim-treesitter'
  local langs = {
    'lua', 'rust', 'go', 'python', 'typescript',
    'javascript', 'json', 'yaml', 'toml', 'markdown',
  }
  pcall(function() ts.install(langs) end)
  vim.api.nvim_create_autocmd('FileType', {
    pattern  = langs,
    callback = function(ev)
      -- Skip treesitter on very large files — parsing/highlighting gets costly.
      if vim.api.nvim_buf_line_count(ev.buf) > 6000 then return end
      pcall(vim.treesitter.start, ev.buf)
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
end)

-- ── Folding ───────────────────────────────────────────────────────────────────

map('n', 'zR', '<cmd>set foldlevel=99<cr>', { desc = 'Unfold all', silent = true })
map('n', 'zM', '<cmd>set foldlevel=0<cr>',  { desc = 'Fold all',   silent = true })
