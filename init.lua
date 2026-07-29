-- workspace.nvim
-- A Neovim distribution with deep Claude AI integration
-- https://github.com/kriuchkov/workspace.nvim

require 'workspace.options'
require 'workspace.keymaps'
require 'workspace.plugins'

-- Bootstrap: on first run plugins aren't installed yet — download them and ask to restart
vim.schedule(function()
  if not pcall(require, 'gitsigns') then
    vim.notify(
      'workspace: installing plugins… restart Neovim when done.',
      vim.log.levels.WARN
    )
    vim.pack.update()
  end
end)

require 'workspace.claude'

-- :checkhealth workspace
vim.api.nvim_create_user_command('CheckhealthClaudespace', function()
  vim.cmd 'checkhealth workspace'
end, { desc = 'Run workspace health checks' })

-- Machine-local overrides (not tracked in git)
pcall(require, 'custom')
