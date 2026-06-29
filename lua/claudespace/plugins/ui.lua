local map = vim.keymap.set

-- Colorscheme
vim.pack.add { 'https://github.com/folke/tokyonight.nvim' }
pcall(vim.cmd.colorscheme, 'tokyonight-night')

-- LSP document-highlight: tokyonight рисует эти группы почти невидимо.
-- Делаем вхождения символа под курсором заметными (фон + подчёркивание),
-- с различием read/write. Переустанавливаем при каждой смене темы.
local function lsp_reference_hl()
  local set = vim.api.nvim_set_hl
  set(0, 'LspReferenceText',  { bg = '#3b4261', underline = true })
  set(0, 'LspReferenceRead',  { bg = '#3b4261', underline = true })
  set(0, 'LspReferenceWrite', { bg = '#54405a', underline = true, bold = true })
end
lsp_reference_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = lsp_reference_hl })

-- Go syntax palette: ключевые слова — розово-красные, функции — оранжевые,
-- типы — голубые, true/false/nil — синие, поля — лавандовые. Через capture-группы
-- с суффиксом `.go` правки касаются только Go (treesitter highlight).
local function go_syntax_hl()
  local set = vim.api.nvim_set_hl
  local red, orange = '#f7768e', '#ff9e64'
  local cyan, blue  = '#7dcfff', '#7aa2f7'
  local green, lav  = '#9ece6a', '#bb9af7'
  for _, g in ipairs {
    '@keyword.go', '@keyword.function.go', '@keyword.return.go',
    '@keyword.repeat.go', '@keyword.conditional.go', '@keyword.operator.go',
    '@keyword.import.go', '@keyword.coroutine.go',
  } do set(0, g, { fg = red }) end
  for _, g in ipairs {
    '@function.go', '@function.call.go', '@function.method.go', '@function.method.call.go',
  } do set(0, g, { fg = orange }) end
  set(0, '@type.go',            { fg = cyan })
  set(0, '@type.builtin.go',    { fg = cyan })
  set(0, '@boolean.go',         { fg = blue })
  set(0, '@constant.builtin.go',{ fg = blue })   -- nil, iota
  set(0, '@string.go',          { fg = green })
  set(0, '@variable.member.go', { fg = lav })    -- struct fields: activity.StartTime
end
go_syntax_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = go_syntax_hl })

-- Icons (used by neo-tree, lualine, etc.)
vim.pack.add { 'https://github.com/echasnovski/mini.icons' }
if pcall(require, 'mini.icons') then
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()
end

-- Which-key
vim.pack.add { 'https://github.com/folke/which-key.nvim' }
local ok_wk, wk = pcall(require, 'which-key')
if ok_wk then
  wk.setup()
  if wk.add then
    wk.add({
      { '<leader>f',  group = 'Find/Files' },
      { '<leader>t',  group = 'Tabs' },
      { '<leader>c',  group = 'Claude' },
      { '<leader>g',  group = 'Git' },
      { '<leader>gt', group = 'Git: toggle' },
      { '<leader>l',  group = 'LSP' },
      { '<leader>x',  group = 'Diagnostics/Panels' },
      { '<leader>s',  group = 'Search/Replace' },
      { '<leader>w',  group = 'Workspace' },
      { '<leader>ww', group = 'Terminals' },
      { '<leader>d',  group = 'Debug' },
      { '<leader>r',  group = 'Run/Test' },
      { '<leader>m',  group = 'Marks' },
      -- Claude sub-groups for discoverability
      { '<leader>cf', desc = 'Claude: fix diagnostic' },
      { '<leader>ck', desc = 'Claude: explain code' },
      { '<leader>ci', desc = 'Claude: inject workspace context' },
      { '<leader>cd', desc = 'Claude: send diagnostics' },
      { '<leader>cT', desc = 'Claude: send terminal output' },
      { '<leader>c!', desc = 'Claude: shell command' },
      { '<leader>co', desc = 'Claude: generate docs' },
      { '<leader>cE', desc = 'Claude: multi-file compose' },
    })
  end
end
