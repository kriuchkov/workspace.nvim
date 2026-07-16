local map = vim.keymap.set

-- ── indent-blankline ──────────────────────────────────────────────────────────
-- Vertical indent guides — shows code structure at a glance.

vim.pack.add { 'https://github.com/lukas-reineke/indent-blankline.nvim' }
if pcall(require, 'ibl') then
  require('ibl').setup {
    indent = {
      char      = '│',
      tab_char  = '│',
    },
    scope = {
      enabled   = true,
      char      = '│',
      -- Highlight the current scope's indent line
      show_start = false,
      show_end   = false,
    },
    exclude = {
      filetypes = {
        'help', 'dashboard', 'alpha', 'lazy', 'mason',
        'cs_home', 'cs_notify', 'cs_outline', 'cs_filetree',
        'cs_gitui', 'cs_tasks', 'cs_testui', 'terminal',
      },
      buftypes = { 'terminal', 'nofile', 'quickfix', 'prompt' },
    },
  }
end

-- ── todo-comments ─────────────────────────────────────────────────────────────
-- Highlights TODO/FIXME/HACK/NOTE/WARN/PERF in comments.
-- Integrates with Telescope and Trouble.

local tc = require 'workspace.todo_comments'
tc.setup {
  signs         = true,
  sign_priority = 8,
  keywords = {
    FIX  = { icon = ' ', color = 'error',   alt = { 'FIXME', 'BUG', 'FIXIT', 'ISSUE' } },
    TODO = { icon = ' ', color = 'info' },
    HACK = { icon = ' ', color = 'warning', alt = { 'TEMP', 'TEMPORARY' } },
    WARN = { icon = ' ', color = 'warning', alt = { 'WARNING', 'XXX' } },
    PERF = { icon = ' ', color = 'default', alt = { 'OPTIM', 'PERFORMANCE', 'OPTIMIZE' } },
    NOTE = { icon = ' ', color = 'hint',    alt = { 'INFO' } },
  },
  highlight = {
    before        = '',
    keyword       = 'wide',
    after         = 'fg',
    pattern       = [[.*<(KEYWORDS)\s*:]],
    comments_only = true,
  },
}

-- Jump between TODOs
map('n', ']t', tc.jump_next, { desc = 'Next TODO',  silent = true })
map('n', '[t', tc.jump_prev, { desc = 'Prev TODO',  silent = true })

-- List all TODOs (center-window list; the old Trouble mode needed the real
-- todo-comments plugin, which is vendored here)
map('n', '<leader>xt', tc.workspace,
  { desc = 'TODOs list', silent = true })
map('n', '<leader>ft', '<cmd>TodoTelescope<cr>',
  { desc = 'Find TODOs',  silent = true })

-- ── yanky: clipboard ring ─────────────────────────────────────────────────────
-- Keeps a history of yanked text; cycle through it after pasting.

local yanky = require 'workspace.yanky'
yanky.setup {
  ring = {
    history_length               = 20,
    storage                      = 'shada',
    sync_with_numbered_registers = true,
  },
  highlight = { on_put = true, on_yank = true, timer = 150 },
}
-- p/P track history; behaviour is identical to native p/P
map({ 'n', 'x' }, 'p',  function() yanky.put('p',  false) end, { desc = 'Put after',  silent = true })
map({ 'n', 'x' }, 'P',  function() yanky.put('P',  false) end, { desc = 'Put before', silent = true })
map({ 'n', 'x' }, 'gp', function() yanky.put('gp', false) end, { desc = 'GPut after', silent = true })
map({ 'n', 'x' }, 'gP', function() yanky.put('gP', false) end, { desc = 'GPut before',silent = true })
-- Cycle through clipboard ring after a paste
map('n', '[y', function() yanky.cycle(1)  end, { desc = 'Clipboard: older entry', silent = true })
map('n', ']y', function() yanky.cycle(-1) end, { desc = 'Clipboard: newer entry', silent = true })
-- Picker for clipboard history (uses vim.ui.select)
map('n', '<leader>fy', '<cmd>YankyRingHistory<cr>', { desc = 'Clipboard history', silent = true })
