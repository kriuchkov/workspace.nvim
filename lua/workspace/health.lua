local M = {}

M.check = function()
  vim.health.start 'workspace.nvim'

  -- Neovim version
  if vim.fn.has 'nvim-0.12' == 1 then
    vim.health.ok 'Neovim >= 0.12'
  else
    vim.health.error 'Neovim >= 0.12 required (vim.pack not available)'
  end

  -- claude CLI
  if vim.fn.executable 'claude' == 1 then
    local version = vim.trim(vim.fn.system 'claude --version 2>/dev/null')
    vim.health.ok('claude CLI found: ' .. (version ~= '' and version or 'unknown version'))
  else
    vim.health.error('claude CLI not found', {
      'Install from: https://docs.anthropic.com/en/docs/claude-code',
    })
  end

  -- git
  if vim.fn.executable 'git' == 1 then
    vim.health.ok 'git found'
  else
    vim.health.warn 'git not found (commit/PR features disabled)'
  end

  -- Fuzzy finder (native picker)
  if vim.fn.executable 'rg' == 1 or vim.fn.executable 'fd' == 1 then
    vim.health.ok 'ripgrep/fd found (file & grep pickers)'
  else
    vim.health.warn 'neither rg nor fd found — file/grep pickers fall back to vimglob/off'
  end

  -- CLAUDE.md
  local project_md = vim.fn.getcwd() .. '/CLAUDE.md'
  if vim.fn.filereadable(project_md) == 1 then
    vim.health.ok 'CLAUDE.md found in project root'
  else
    vim.health.warn('no CLAUDE.md in project root', {
      'Create one with <leader>cm for better Claude context',
    })
  end
end

return M
