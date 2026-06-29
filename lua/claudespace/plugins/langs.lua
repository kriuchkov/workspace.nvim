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

