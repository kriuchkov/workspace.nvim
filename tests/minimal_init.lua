-- Minimal init for headless tests.
-- Adds lua/ to runtimepath so require('claude-multi') etc. resolve,
-- but does NOT load plugins or call vim.pack (no network in CI).

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.runtimepath:prepend(root)

-- Add plenary from the system nvim pack (needed for test runner)
local plenary_paths = {
  vim.fn.expand('~/.local/share/nvim/site/pack/core/opt/plenary.nvim'),
  vim.fn.expand('~/.local/share/nvim/site/pack/*/opt/plenary.nvim'),
  vim.fn.expand('~/.local/share/nvim/site/pack/*/start/plenary.nvim'),
}
for _, p in ipairs(plenary_paths) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:append(p)
    break
  end
end

-- Stub vim.pack.add so plugin files can be sourced without errors
vim.pack = vim.pack or {}
vim.pack.add = function() end
-- Stub snacks so claude-multi terminal module doesn't error
package.preload['snacks'] = function()
  return {
    setup = function() end,
    terminal = {
      get = function() end,
      toggle = function() end,
    },
  }
end
