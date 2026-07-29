-- Enhanced live grep. ripgrep already treats the query as a regex; this adds
-- on-the-fly glob scoping so a search can be pinned to specific files or a single
-- service — e.g. `*.go`, `!*_test.go`, `services/vega/**`. Drives the native
-- workspace.picker grep source with extra `--glob` args; no plugins.
local M = {}

local fn = vim.fn

-- "*.go !*_test.go" → { '--glob', '*.go', '--glob', '!*_test.go' }.
local function glob_args(input)
  local args = {}
  for _, g in ipairs(vim.split(input, '%s+', { trimempty = true })) do
    args[#args + 1] = '--glob'
    args[#args + 1] = g
  end
  return args
end

local function picker() return require 'workspace.picker' end

---Open live grep immediately (regex is native to rg). Used by the activity-bar
---Search so a click opens results right away — no blocking prompt.
function M.live_grep(opts)
  opts = opts or {}
  picker().grep { cwd = opts.cwd, title = opts.title }
end

---Prompt for optional globs, then live grep the workspace scoped to them.
function M.live_grep_glob()
  vim.ui.input(
    { prompt = 'Grep globs (rg -g, space-sep · empty = all): ', completion = 'file' },
    function(input)
      if input == nil then return end
      local o = { title = 'Live Grep' }
      if input ~= '' then
        o.rg_args = glob_args(input)
        o.title   = 'Live Grep  [' .. input .. ']'
      end
      picker().grep(o)
    end)
end

---Live grep restricted to the active workspace repo, optionally + globs.
function M.live_grep_repo()
  local ok, repos = pcall(require, 'workspace.repos')
  local root = (ok and repos.active_cwd and repos.active_cwd()) or fn.getcwd()
  local name = fn.fnamemodify(root, ':t')
  vim.ui.input(
    { prompt = 'Grep globs in ' .. name .. ' (empty = all): ', completion = 'file' },
    function(input)
      if input == nil then return end
      local o = { cwd = root, title = 'Live Grep  @' .. name }
      if input ~= '' then o.rg_args = glob_args(input) end
      picker().grep(o)
    end)
end

function M.setup()
  vim.api.nvim_create_user_command('LiveGrepGlob', M.live_grep_glob,
    { desc = 'Live grep with glob scoping (regex + -g)' })
  vim.api.nvim_create_user_command('LiveGrepRepo', M.live_grep_repo,
    { desc = 'Live grep restricted to the active repo' })
  vim.keymap.set('n', '<leader>fG', M.live_grep_glob,
    { desc = 'Live grep (glob scoped)', silent = true })
  vim.keymap.set('n', '<leader>fR', M.live_grep_repo,
    { desc = 'Live grep (active repo)', silent = true })
end

return M
