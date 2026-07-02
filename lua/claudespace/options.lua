vim.g.mapleader      = ' '
vim.g.maplocalleader = ' '

local o = vim.opt

-- Russian ЙЦУКЕН → Latin QWERTY keyboard-position mapping.
-- Allows all Normal/Visual/Command keymaps to work with Russian locale active.
-- Does NOT affect Insert mode — see im-select.nvim in plugins/core.lua for that.
o.langmap = table.concat({
  'й;q','ц;w','у;e','к;r','е;t','н;y','г;u','ш;i','щ;o','з;p',
  'ф;a','ы;s','в;d','а;f','п;g','р;h','о;j','л;k','д;l',
  'я;z','ч;x','с;c','м;v','и;b','т;n','ь;m',
  'Й;Q','Ц;W','У;E','К;R','Е;T','Н;Y','Г;U','Ш;I','Щ;O','З;P',
  'Ф;A','Ы;S','В;D','А;F','П;G','Р;H','О;J','Л;K','Д;L',
  'Я;Z','Ч;X','С;C','М;V','И;B','Т;N','Ь;M',
}, ',')

-- Disable netrw before it loads (dirdash.lua replaces it)
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

-- Appearance
o.number = true
o.relativenumber = false
o.signcolumn = 'yes'
o.cursorline = true
o.termguicolors = true
o.showmode = false
o.laststatus = 3  -- single global statusline

-- Indentation
o.expandtab = true
o.tabstop = 2
o.shiftwidth = 2
o.smartindent = true

-- Search
o.ignorecase = true
o.smartcase = true
o.hlsearch = true
o.incsearch = true

-- Splits
o.splitright = true
o.splitbelow = true

-- Window borders (styled via WinSeparator in tabline.lua)
o.fillchars:append { vert = '│', vertleft = '│', vertright = '│', eob = ' ' }

-- Editor feel
o.scrolloff = 10
o.sidescrolloff = 8
o.wrap = false
o.updatetime  = 600   -- CursorHold delay (LSP doc-highlight + reference lens) — higher = fewer triggers
o.timeoutlen  = 150   -- fast leader key in normal mode
o.ttimeoutlen = 10    -- instant terminal escape codes (arrow keys, etc.)
o.undofile = true
o.swapfile = false  -- no swap files; undofile already handles crash recovery
o.mouse = 'a'
o.clipboard = 'unnamedplus'

-- Completion
o.completeopt = 'menuone,noselect'
o.pumheight = 10

-- Folding: native Neovim 0.12 treesitter-based
o.foldmethod    = 'expr'
o.foldexpr      = 'v:lua.vim.treesitter.foldexpr()'
o.foldcolumn    = '1'
o.foldlevel     = 99    -- open all folds by default
o.foldlevelstart = 99
o.foldenable    = true

-- Auto-save on focus loss or buffer leave (only real named files)
vim.api.nvim_create_autocmd({ 'FocusLost', 'BufLeave' }, {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].modified
      and vim.bo[buf].buftype == ''
      and vim.fn.bufname(buf) ~= '' then
      vim.cmd 'silent! write'
    end
  end,
})

-- Terminal: prevent scrolloff drift and resize artifacts in TUI apps.
-- Also raise timeoutlen while in terminal mode so <Esc><Esc> is comfortable
-- to press (timeoutlen=150 is fine for normal mode but too fast for double-Esc).
vim.api.nvim_create_autocmd({ 'TermOpen', 'TermEnter' }, {
  callback = function()
    vim.wo.scrolloff = 0
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = 'no'
    vim.opt.timeoutlen = 300
    -- Raise the key-code timeout so an Esc-prefixed Alt (iTerm2/Terminal.app
    -- send Alt+key as <Esc>key) assembles into <M-key> before Esc is forwarded
    -- to the terminal — lets <A-N> tab-switching work from inside Claude.
    vim.opt.ttimeoutlen = 50
  end,
})

vim.api.nvim_create_autocmd('TermLeave', {
  callback = function()
    vim.opt.timeoutlen = 150
    vim.opt.ttimeoutlen = 10
  end,
})

-- Restore number/signcolumn when switching back to a normal buffer
-- (window-local opts set for terminal persist when the window is reused)
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    if vim.bo.buftype == '' then
      vim.wo.number = true
      vim.wo.signcolumn = 'yes'
    end
  end,
})

-- Language-specific indentation
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'go', 'c', 'cpp', 'rust' },
  callback = function()
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
  end,
})
