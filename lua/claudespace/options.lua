local o = vim.opt

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
o.updatetime = 250
o.timeoutlen = 300
o.undofile = true
o.swapfile = false  -- no swap files; undofile already handles crash recovery
o.mouse = 'a'
o.clipboard = 'unnamedplus'

-- Completion
o.completeopt = 'menuone,noselect'
o.pumheight = 10

-- Terminal: prevent scrolloff drift and resize artifacts in TUI apps
vim.api.nvim_create_autocmd({ 'TermOpen', 'TermEnter', 'BufEnter' }, {
  callback = function()
    if vim.bo.buftype ~= 'terminal' then return end
    vim.wo.scrolloff = 0
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = 'no'
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
