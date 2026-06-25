-- claudespace.nvim
-- A Neovim distribution with deep Claude AI integration
-- https://github.com/kriuchkov/claudespace.nvim

require 'claudespace.options'
require 'claudespace.keymaps'
require 'claudespace.plugins'

-- Bootstrap: on first run plugins aren't installed yet — download them and ask to restart
vim.schedule(function()
  if not pcall(require, 'telescope') then
    vim.notify(
      'claudespace: installing plugins… restart Neovim when done.',
      vim.log.levels.WARN
    )
    vim.pack.update()
  end
end)

require 'claudespace.claude'

-- :checkhealth claudespace
vim.api.nvim_create_user_command('CheckhealthClaudespace', function()
  vim.cmd 'checkhealth claudespace'
end, { desc = 'Run claudespace health checks' })

-- Machine-local overrides (not tracked in git)
pcall(require, 'custom')
