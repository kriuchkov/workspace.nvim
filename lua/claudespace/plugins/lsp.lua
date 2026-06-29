local map = vim.keymap.set

-- Readable hover/signature popups: rounded border + capped width so long doc
-- lines wrap at ~90 cols instead of stretching across the whole editor.
local FLOAT = { border = 'rounded', max_width = 90, max_height = 25, wrap = true }
local function hover()     vim.lsp.buf.hover(FLOAT) end
local function signature() vim.lsp.buf.signature_help(FLOAT) end

-- Match border for diagnostic float popups too.
pcall(vim.diagnostic.config, { float = { border = 'rounded', max_width = 90 } })

-- ── LSP servers ───────────────────────────────────────────────────────────────

vim.pack.add {
  'https://github.com/neovim/nvim-lspconfig',
  'https://github.com/williamboman/mason.nvim',
  'https://github.com/williamboman/mason-lspconfig.nvim',
}
pcall(function() require('mason').setup() end)
pcall(function()
  require('mason-lspconfig').setup {
    ensure_installed = { 'lua_ls', 'gopls', 'ts_ls', 'pyright', 'vimls' },
    handlers = {
      function(server_name)
        pcall(function() require('lspconfig')[server_name].setup {} end)
      end,
    },
  }
end)

-- ── navic: breadcrumb in winbar ───────────────────────────────────────────────

require('claudespace.navic').setup {
  lsp       = { auto_attach = false },
  highlight = true,
  separator = '  ',
  depth_limit = 5,
  icons = {
    File          = ' ', Module      = ' ', Namespace   = ' ',
    Package       = ' ', Class       = ' ', Method      = ' ',
    Property      = ' ', Field       = ' ', Constructor = ' ',
    Enum          = ' ', Interface   = ' ', Function    = ' ',
    Variable      = ' ', Constant    = ' ', String      = ' ',
    Number        = ' ', Boolean     = '◩ ', Array      = ' ',
    Object        = ' ', Key         = ' ', Null        = '○ ',
    EnumMember    = ' ', Struct      = ' ', Event       = ' ',
    Operator      = ' ', TypeParameter = ' ',
  },
}

-- ── LSP keymaps + per-buffer features ────────────────────────────────────────
-- Applied once when an LSP client attaches to a buffer.

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local o = { buffer = ev.buf, silent = true }
    local b = function(desc) return vim.tbl_extend('force', o, { desc = desc }) end

    -- Goto
    map('n', 'gd', vim.lsp.buf.definition,     b 'LSP: definition')
    map('n', 'gD', vim.lsp.buf.declaration,    b 'LSP: declaration')
    map('n', 'gi', vim.lsp.buf.implementation, b 'LSP: implementation')
    map('n', 'gr', vim.lsp.buf.references,     b 'LSP: references')
    map('n', '<leader>lr', require('claudespace.lsp_reflens').open_references, b 'LSP: usages')
    map('n', 'K',  hover,     b 'LSP: hover docs')
    map('i', '<C-k>', signature, b 'LSP: signature help')

    -- Actions
    map('n', '<leader>ln', vim.lsp.buf.rename,    b 'LSP: rename')
    map({ 'n', 'v' }, '<leader>la', vim.lsp.buf.code_action, b 'LSP: code action')
    map('n', '<leader>lf', function() vim.lsp.buf.format { async = true } end, b 'LSP: format')
    map('n', '<leader>ls', signature,  b 'LSP: signature')
    map('n', '<leader>lt', vim.lsp.buf.type_definition, b 'LSP: type definition')
    map('n', '<leader>lw', function()
      vim.lsp.buf.workspace_symbol(vim.fn.input 'Symbol: ')
    end, b 'LSP: workspace symbol')
    map('n', '<leader>li', function()
      if vim.lsp.inlay_hint then
        local enabled = vim.lsp.inlay_hint.is_enabled {}
        vim.lsp.inlay_hint.enable(not enabled)
        vim.notify('Inlay hints ' .. (enabled and 'off' or 'on'), vim.log.levels.INFO)
      end
    end, b 'LSP: toggle inlay hints')

    local client = vim.lsp.get_client_by_id(ev.data and ev.data.client_id)

    -- Inlay hints
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    end

    -- navic breadcrumb
    if client and client.server_capabilities.documentSymbolProvider then
      require('claudespace.navic').attach(client, ev.buf)
    end

    -- Document highlight (LSP-aware, not just text match) — skip on huge files
    if client and client.server_capabilities.documentHighlightProvider
      and vim.api.nvim_buf_line_count(ev.buf) <= 6000 then
      local grp = vim.api.nvim_create_augroup('cs_lsp_hi_' .. ev.buf, { clear = true })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buffer = ev.buf, group = grp, callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = ev.buf, group = grp, callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})

-- Reference lens: «N usages» virtual text above symbol
require('claudespace.lsp_reflens').setup()

-- ── Completion ────────────────────────────────────────────────────────────────

vim.pack.add {
  'https://github.com/hrsh7th/nvim-cmp',
  'https://github.com/L3MON4D3/LuaSnip',
}

pcall(function()
  local cmp = require 'cmp'

  require('claudespace.sources.nvim_lsp').setup()
  cmp.register_source('buffer', require('claudespace.sources.buffer').new())
  cmp.register_source('path',   require('claudespace.sources.path').new())

  local cs_luasnip = require 'claudespace.sources.luasnip'
  cmp.register_source('luasnip', cs_luasnip.new())
  local grp = vim.api.nvim_create_augroup('cs_cmp_luasnip', {})
  vim.api.nvim_create_autocmd('User', {
    pattern = 'LuasnipCleanup',       group = grp,
    callback = function() cs_luasnip.clear_cache() end,
  })
  vim.api.nvim_create_autocmd('User', {
    pattern = 'LuasnipSnippetsAdded', group = grp,
    callback = function() cs_luasnip.refresh() end,
  })

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
    formatting = {
      format = require('claudespace.sources.format').cmp_format {
        mode = 'symbol_text', maxwidth = 40, ellipsis_char = '…',
      },
    },
    window = {
      completion    = cmp.config.window.bordered(),
      documentation = cmp.config.window.bordered(),
    },
    performance = { debounce = 120 },
  }
end)

-- ── Autopairs ─────────────────────────────────────────────────────────────────

vim.pack.add { 'https://github.com/windwp/nvim-autopairs' }
pcall(function() require('nvim-autopairs').setup() end)
