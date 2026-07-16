local map = vim.keymap.set

-- ── gitsigns ──────────────────────────────────────────────────────────────────
-- Inline hunks, blame, stage/reset without leaving the buffer.

vim.pack.add { 'https://github.com/lewis6991/gitsigns.nvim' }
if pcall(require, 'gitsigns') then
  require('gitsigns').setup {
    signs = {
      add          = { text = '▎' },
      change       = { text = '▎' },
      delete       = { text = '▁' },
      topdelete    = { text = '▔' },
      changedelete = { text = '▎' },
      untracked    = { text = '▎' },
    },
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 600,
      virt_text_pos = 'eol',
    },
    current_line_blame_formatter = ' <author>, <author_time:%d %b %Y> · <summary>',
    on_attach = function(bufnr)
      local gs = require 'gitsigns'
      local o  = { buffer = bufnr, silent = true }

      -- Hunk navigation
      map('n', ']h', function()
        if vim.wo.diff then vim.cmd.normal { ']c', bang = true }
        else gs.nav_hunk 'next' end
      end, vim.tbl_extend('force', o, { desc = 'Next hunk' }))
      map('n', '[h', function()
        if vim.wo.diff then vim.cmd.normal { '[c', bang = true }
        else gs.nav_hunk 'prev' end
      end, vim.tbl_extend('force', o, { desc = 'Prev hunk' }))

      -- Stage / reset
      map({ 'n', 'v' }, '<leader>gs', gs.stage_hunk,   vim.tbl_extend('force', o, { desc = 'Stage hunk' }))
      map({ 'n', 'v' }, '<leader>gr', gs.reset_hunk,   vim.tbl_extend('force', o, { desc = 'Reset hunk' }))
      map('n', '<leader>gS', gs.stage_buffer,           vim.tbl_extend('force', o, { desc = 'Stage buffer' }))
      map('n', '<leader>gR', gs.reset_buffer,           vim.tbl_extend('force', o, { desc = 'Reset buffer' }))
      map('n', '<leader>gu', gs.undo_stage_hunk,        vim.tbl_extend('force', o, { desc = 'Undo stage' }))

      -- Preview / blame
      map('n', '<leader>gp', gs.preview_hunk,           vim.tbl_extend('force', o, { desc = 'Preview hunk' }))
      map('n', '<leader>gb', function() gs.blame_line { full = true } end,
        vim.tbl_extend('force', o, { desc = 'Blame line' }))
      map('n', '<leader>gB', gs.blame,                  vim.tbl_extend('force', o, { desc = 'Blame file' }))

      -- Diff
      map('n', '<leader>gi', gs.diffthis,               vim.tbl_extend('force', o, { desc = 'Diff index' }))
      map('n', '<leader>gI', function() gs.diffthis '~' end,
        vim.tbl_extend('force', o, { desc = 'Diff HEAD~' }))

      -- Toggle
      map('n', '<leader>gtb', gs.toggle_current_line_blame,
        vim.tbl_extend('force', o, { desc = 'Toggle blame' }))
      map('n', '<leader>gtd', gs.toggle_deleted,
        vim.tbl_extend('force', o, { desc = 'Toggle deleted' }))

      -- Text object: ih = inner hunk
      map({ 'o', 'x' }, 'ih', gs.select_hunk, o)
    end,
  }
end

-- ── diff / history ──────────────────────────────────────────────────────────────
-- Native, workspace-integrated diff & log viewer (replaces diffview.nvim). Renders
-- in the center window using Neovim's own diff mode; registers <leader>gd/gh/gl/gD
-- and :WSDiff / :WSFileHistory / :WSLog / :WSDiffClose.

require('workspace.gitdiff').setup()

-- ── lazygit ───────────────────────────────────────────────────────────────────
-- Floating terminal wrapper around the lazygit CLI.

require('workspace.lazygit').setup()
map('n', '<leader>gg', '<cmd>LazyGit<cr>', { desc = 'Git: lazygit', silent = true })
