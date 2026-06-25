local map = vim.keymap.set

-- Rust
vim.g.rustaceanvim = {
  server = {
    default_settings = {
      ['rust-analyzer'] = {
        cargo = { allFeatures = true },
        checkOnSave = { command = 'clippy' },
      },
    },
  },
}
vim.pack.add {
  'https://github.com/mrcjkb/rustaceanvim',
  'https://github.com/saecki/crates.nvim',
}
if pcall(require, 'crates') then
  require('crates').setup { completion = { crates = { enabled = true } } }
end

-- Go
vim.pack.add {
  'https://github.com/ray-x/go.nvim',
  'https://github.com/ray-x/guihua.lua',
}
if pcall(require, 'go') then
  require('go').setup()
end

-- Toggle terminal
vim.pack.add { 'https://github.com/akinsho/toggleterm.nvim' }
if pcall(require, 'toggleterm') then
  require('toggleterm').setup {
    size = 20,
    open_mapping = [[<C-\>]],
    direction = 'horizontal',
  }
end
map('n', '<leader>tf', '<cmd>ToggleTerm direction=float<cr>', { desc = 'Terminal float' })
map('n', '<leader>tv', '<cmd>ToggleTerm direction=vertical size=60<cr>', { desc = 'Terminal vertical' })
