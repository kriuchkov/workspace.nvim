local map = vim.keymap.set

-- Fuzzy finder
vim.pack.add {
  'https://github.com/nvim-telescope/telescope.nvim',
  'https://github.com/nvim-lua/plenary.nvim',
}
if pcall(require, 'telescope') then
  require('telescope').setup()
end
map('n', '<leader>ff', '<cmd>Telescope find_files<cr>', { desc = 'Find files' })
map('n', '<leader>fg', '<cmd>Telescope live_grep<cr>', { desc = 'Live grep' })
map('n', '<leader>fb', '<cmd>Telescope buffers<cr>', { desc = 'Buffers' })
map('n', '<leader>fh', '<cmd>Telescope help_tags<cr>', { desc = 'Help' })
map('n', '<leader>fr', '<cmd>Telescope oldfiles<cr>', { desc = 'Recent files' })

-- Treesitter
vim.pack.add { 'https://github.com/nvim-treesitter/nvim-treesitter' }
if pcall(require, 'nvim-treesitter.configs') then
  require('nvim-treesitter.configs').setup {
    ensure_installed = { 'lua', 'rust', 'go', 'python', 'typescript', 'javascript', 'json', 'yaml', 'toml', 'markdown' },
    highlight = { enable = true },
    indent = { enable = true },
  }
end

-- LSP
vim.pack.add {
  'https://github.com/neovim/nvim-lspconfig',
  'https://github.com/williamboman/mason.nvim',
  'https://github.com/williamboman/mason-lspconfig.nvim',
}
if pcall(require, 'mason') then
  require('mason').setup()
end
if pcall(require, 'mason-lspconfig') then
  require('mason-lspconfig').setup {
    ensure_installed = { 'lua_ls', 'gopls', 'ts_ls', 'pyright', 'vimls' },
    handlers = {
      function(server_name)
        pcall(function() require('lspconfig')[server_name].setup {} end)
      end,
    },
  }
end

-- Completion
vim.pack.add {
  'https://github.com/hrsh7th/nvim-cmp',
  'https://github.com/hrsh7th/cmp-nvim-lsp',
  'https://github.com/hrsh7th/cmp-buffer',
  'https://github.com/hrsh7th/cmp-path',
  'https://github.com/L3MON4D3/LuaSnip',
  'https://github.com/saadparwaiz1/cmp_luasnip',
}
if pcall(require, 'cmp') then
  local cmp = require 'cmp'
  cmp.setup {
    snippet = { expand = function(args) require('luasnip').lsp_expand(args.body) end },
    mapping = cmp.mapping.preset.insert {
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<CR>']      = cmp.mapping.confirm { select = true },
      ['<Tab>']     = cmp.mapping.select_next_item(),
      ['<S-Tab>']   = cmp.mapping.select_prev_item(),
      ['<C-e>']     = cmp.mapping.abort(),
      ['<C-d>']     = cmp.mapping.scroll_docs(4),
      ['<C-u>']     = cmp.mapping.scroll_docs(-4),
    },
    sources = cmp.config.sources {
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
      { name = 'buffer' },
      { name = 'path' },
    },
    experimental = {
      ghost_text = true,  -- inline preview of first suggestion
    },
    performance = {
      debounce = 80,
    },
  }
end

-- Autopairs
vim.pack.add { 'https://github.com/windwp/nvim-autopairs' }
if pcall(require, 'nvim-autopairs') then
  require('nvim-autopairs').setup()
end

