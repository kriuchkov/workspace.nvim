require 'claudespace.claude.git_ops'
require 'claudespace.claude.codegen'
require 'claudespace.claude.fix'
require 'claudespace.claude.assist'
require 'claudespace.claude.agents'
require 'claudespace.claude.sessions'

-- CLAUDE.md management
vim.keymap.set('n', '<leader>cm', function()
  local repos = require('claudespace.repos')
  local project_md = repos.active_cwd() .. '/CLAUDE.md'
  -- In a multi-repo workspace, also offer the root CLAUDE.md as a fallback.
  local root_md   = repos.is_multi() and (repos.root() .. '/CLAUDE.md') or nil
  local global_md = vim.fn.expand '~/.claude/CLAUDE.md'
  if vim.fn.filereadable(project_md) == 1 then
    vim.cmd('edit ' .. project_md)
  elseif root_md and vim.fn.filereadable(root_md) == 1 then
    vim.cmd('edit ' .. root_md)
  elseif vim.fn.filereadable(global_md) == 1 then
    vim.cmd('edit ' .. global_md)
  else
    vim.cmd('edit ' .. project_md)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# Project Instructions for Claude',
      '',
      '## Project Overview',
      '',
      '## Code Style',
      '',
      '## Key Conventions',
      '',
    })
  end
end, { desc = 'Claude: open CLAUDE.md' })

-- Dashboard on startup (only when no file argument)
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    if vim.fn.argc() == 0 and vim.fn.line2byte '$' == -1 then
      -- defer so shada is read and vim.v.oldfiles is populated
      vim.schedule(function()
        require('claudespace.claude.dashboard').open()
      end)
    end
  end,
})
