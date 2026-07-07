-- Enhanced live grep. ripgrep already treats the query as a regex; this adds
-- on-the-fly glob scoping so a search can be pinned to specific files or a single
-- service — e.g. `*.go`, `!*_test.go`, `services/vega/**`. No extra plugins:
-- it drives telescope's built-in live_grep with --glob / search_dirs.
local M = {}

local fn = vim.fn

local function builtin()
  local ok, b = pcall(require, 'telescope.builtin')
  if not ok then
    vim.notify('telescope not available', vim.log.levels.ERROR)
    return nil
  end
  return b
end

-- "*.go !*_test.go" → { '*.go', '!*_test.go' } (rg accepts repeated --glob).
local function split_globs(input)
  return vim.split(input, '%s+', { trimempty = true })
end

---Open telescope live grep immediately (regex is native to rg). Inside the picker,
---<C-g> refines the search by glob without losing the current query. Used by the
---activity-bar Search so a click opens results right away — no blocking prompt.
function M.live_grep(opts)
  local b = builtin()
  if not b then return end
  opts = opts or {}
  opts.attach_mappings = function(_, map)
    map({ 'i', 'n' }, '<C-g>', function(pb)
      local astate = require('telescope.actions.state')
      local query  = astate.get_current_line()
      require('telescope.actions').close(pb)
      vim.ui.input({ prompt = 'Scope to globs (space-sep · empty = all): ', completion = 'file' },
        function(input)
          if input == nil then return end
          local o = { default_text = query, prompt_title = 'Live Grep' }
          if input ~= '' then
            o.glob_pattern  = split_globs(input)
            o.prompt_title  = 'Live Grep  [' .. input .. ']'
          end
          M.live_grep(o)                 -- reopen scoped, keeping the typed query
        end)
    end)
    return true
  end
  b.live_grep(opts)
end

---Prompt for optional globs, then live grep the workspace scoped to them.
function M.live_grep_glob()
  local b = builtin()
  if not b then return end
  vim.ui.input(
    { prompt = 'Grep globs (rg -g, space-sep · empty = all): ', completion = 'file' },
    function(input)
      if input == nil then return end                 -- cancelled
      local opts = { prompt_title = 'Live Grep' }
      if input ~= '' then
        opts.glob_pattern = split_globs(input)
        opts.prompt_title = 'Live Grep  [' .. input .. ']'
      end
      b.live_grep(opts)
    end)
end

---Live grep restricted to the active workspace repo, optionally + globs.
function M.live_grep_repo()
  local b = builtin()
  if not b then return end
  local ok, repos = pcall(require, 'claudespace.repos')
  local root = (ok and repos.active_cwd and repos.active_cwd()) or fn.getcwd()
  local name = fn.fnamemodify(root, ':t')
  vim.ui.input(
    { prompt = 'Grep globs in ' .. name .. ' (empty = all): ', completion = 'file' },
    function(input)
      if input == nil then return end
      local opts = { search_dirs = { root }, prompt_title = 'Live Grep  @' .. name }
      if input ~= '' then opts.glob_pattern = split_globs(input) end
      b.live_grep(opts)
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
