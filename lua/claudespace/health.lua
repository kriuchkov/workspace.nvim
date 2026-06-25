local M = {}

M.check = function()
  vim.health.start 'claudespace.nvim'

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

  -- Telescope
  if pcall(require, 'telescope') then
    vim.health.ok 'telescope.nvim loaded'
  else
    vim.health.warn 'telescope.nvim not loaded (session picker disabled)'
  end

  -- claude-multi
  if pcall(require, 'claude-multi') then
    vim.health.ok 'claude-multi loaded'
    local ok, state = pcall(require, 'claude-multi.state')
    if ok then
      local sessions = state.get_sessions()
      if #sessions > 0 then
        vim.health.ok('claude-multi: ' .. #sessions .. ' active session(s)')
      else
        vim.health.ok 'claude-multi: no active sessions'
      end
    end
  else
    vim.health.error 'claude-multi failed to load'
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
