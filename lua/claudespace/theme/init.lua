-- claudespace theme engine.
--
-- Applies a full set of highlight groups from a semantic palette (theme/palette)
-- for both dark and light `&background`, then broadcasts `User CSThemeApplied`
-- so the custom UI modules (tabline, statusline, mdpreview, …) can re-tint
-- themselves against the active palette.
--
-- Background follows the terminal: Neovim queries the terminal background at
-- startup (OSC 11) to set `&background`, and modern terminals notify Neovim on a
-- light/dark switch — both surface as `OptionSet background`, which we re-apply.
local M = {}

local palette = require('claudespace.theme.palette')

-- Public accessor for the active palette (used by custom-highlight modules).
function M.colors()
  return palette.active()
end

local function apply()
  local c   = palette.active()
  local set = vim.api.nvim_set_hl

  -- Reset any previous colorscheme so stale links don't leak through.
  vim.cmd 'highlight clear'
  if vim.fn.exists 'syntax_on' == 1 then vim.cmd 'syntax reset' end
  vim.g.colors_name = 'claudespace'

  local hl = {
    -- ── Editor UI ──────────────────────────────────────────────────────────
    Normal        = { fg = c.fg, bg = c.bg },
    NormalNC      = { fg = c.fg, bg = c.bg },
    NormalFloat   = { fg = c.fg, bg = c.bg_float },
    FloatBorder   = { fg = c.border, bg = c.bg_float },
    FloatTitle    = { fg = c.accent, bg = c.bg_float, bold = true },
    ColorColumn   = { bg = c.bg_alt },
    Cursor        = { fg = c.bg, bg = c.fg },
    CursorLine    = { bg = c.bg_hl },
    CursorColumn  = { bg = c.bg_hl },
    CursorLineNr  = { fg = c.fg, bold = true },
    LineNr        = { fg = c.fg_dim },
    SignColumn    = { bg = c.bg },
    FoldColumn    = { fg = c.fg_dim, bg = c.bg },
    Folded        = { fg = c.fg_dim, bg = c.bg_alt },
    WinSeparator  = { fg = c.border_dim, bg = c.bg },
    VertSplit     = { fg = c.border_dim, bg = c.bg },
    Visual        = { bg = c.bg_sel },
    VisualNOS     = { bg = c.bg_sel },
    MatchParen    = { fg = c.yellow, bold = true, underline = true },
    Whitespace    = { fg = c.fg_faint },
    NonText       = { fg = c.fg_faint },
    SpecialKey    = { fg = c.fg_faint },
    EndOfBuffer   = { fg = c.bg },
    Conceal       = { fg = c.fg_dim },
    Directory     = { fg = c.blue },
    Title         = { fg = c.accent, bold = true },
    ErrorMsg      = { fg = c.error },
    WarningMsg    = { fg = c.warn },
    MoreMsg       = { fg = c.green },
    ModeMsg       = { fg = c.fg, bold = true },
    Question      = { fg = c.blue },
    QuickFixLine  = { bg = c.bg_hl, bold = true },
    Search        = { fg = c.bg, bg = c.yellow },
    IncSearch     = { fg = c.bg, bg = c.orange },
    CurSearch     = { fg = c.bg, bg = c.orange },
    WildMenu      = { fg = c.bg, bg = c.accent },
    StatusLine    = { fg = c.fg, bg = c.bg_dark },
    StatusLineNC  = { fg = c.fg_dim, bg = c.bg_dark },
    TabLine       = { fg = c.fg_dim, bg = c.bg_dark },
    TabLineFill   = { bg = c.bg_dark },
    TabLineSel    = { fg = c.fg, bg = c.bg },
    WinBar        = { fg = c.fg_dim, bg = c.bg },
    WinBarNC      = { fg = c.fg_faint, bg = c.bg },

    -- ── Popup menu / completion ────────────────────────────────────────────
    Pmenu         = { fg = c.fg, bg = c.bg_float },
    PmenuSel      = { fg = c.fg_bright, bg = c.bg_sel },
    PmenuSbar     = { bg = c.bg_alt },
    PmenuThumb    = { bg = c.fg_dim },
    PmenuKind     = { fg = c.type, bg = c.bg_float },
    PmenuExtra    = { fg = c.fg_dim, bg = c.bg_float },

    -- ── Syntax (legacy vim groups) ─────────────────────────────────────────
    Comment       = { fg = c.comment, italic = true },
    Constant      = { fg = c.constant },
    String        = { fg = c.string },
    Character     = { fg = c.string },
    Number        = { fg = c.number },
    Boolean       = { fg = c.keyword_alt },
    Float         = { fg = c.number },
    Identifier    = { fg = c.variable },
    Function      = { fg = c.func },
    Statement     = { fg = c.keyword },
    Conditional   = { fg = c.keyword },
    Repeat        = { fg = c.keyword },
    Label         = { fg = c.keyword },
    Operator      = { fg = c.operator },
    Keyword       = { fg = c.keyword_alt },
    Exception     = { fg = c.keyword },
    PreProc       = { fg = c.keyword },
    Include       = { fg = c.keyword },
    Define        = { fg = c.keyword },
    Macro         = { fg = c.keyword_alt },
    Type          = { fg = c.type },
    StorageClass  = { fg = c.keyword_alt },
    Structure     = { fg = c.type },
    Typedef       = { fg = c.type },
    Special       = { fg = c.yellow },
    SpecialChar   = { fg = c.yellow },
    Delimiter     = { fg = c.fg },
    Todo          = { fg = c.bg, bg = c.yellow, bold = true },
    Error         = { fg = c.error },

    -- ── Treesitter ─────────────────────────────────────────────────────────
    ['@comment']              = { link = 'Comment' },
    ['@keyword']              = { fg = c.keyword_alt },
    ['@keyword.function']     = { fg = c.keyword_alt },
    ['@keyword.return']       = { fg = c.keyword },
    ['@keyword.conditional']  = { fg = c.keyword },
    ['@keyword.repeat']       = { fg = c.keyword },
    ['@keyword.import']       = { fg = c.keyword },
    ['@keyword.operator']     = { fg = c.keyword },
    ['@keyword.exception']    = { fg = c.keyword },
    ['@function']             = { fg = c.func },
    ['@function.call']        = { fg = c.func },
    ['@function.method']      = { fg = c.func },
    ['@function.method.call'] = { fg = c.func },
    ['@function.builtin']     = { fg = c.func },
    ['@constructor']          = { fg = c.type },
    ['@type']                 = { fg = c.type },
    ['@type.builtin']         = { fg = c.type },
    ['@type.definition']      = { fg = c.type },
    ['@variable']             = { fg = c.variable },
    ['@variable.builtin']     = { fg = c.keyword_alt },
    ['@variable.parameter']   = { fg = c.variable },
    ['@variable.member']      = { fg = c.property },
    ['@property']             = { fg = c.property },
    ['@field']                = { fg = c.property },
    ['@constant']             = { fg = c.constant },
    ['@constant.builtin']     = { fg = c.keyword_alt },
    ['@constant.macro']       = { fg = c.constant },
    ['@string']               = { fg = c.string },
    ['@string.escape']        = { fg = c.yellow },
    ['@string.special']       = { fg = c.yellow },
    ['@number']               = { fg = c.number },
    ['@boolean']              = { fg = c.keyword_alt },
    ['@operator']             = { fg = c.operator },
    ['@punctuation']          = { fg = c.fg },
    ['@punctuation.bracket']  = { fg = c.fg },
    ['@punctuation.delimiter']= { fg = c.fg },
    ['@punctuation.special']  = { fg = c.yellow },
    ['@tag']                  = { fg = c.keyword_alt },
    ['@tag.attribute']        = { fg = c.func },
    ['@tag.delimiter']        = { fg = c.fg_dim },
    ['@module']               = { fg = c.type },
    ['@namespace']            = { fg = c.type },
    ['@attribute']            = { fg = c.func },

    -- ── LSP semantic tokens ────────────────────────────────────────────────
    ['@lsp.type.class']       = { fg = c.type },
    ['@lsp.type.enum']        = { fg = c.type },
    ['@lsp.type.interface']   = { fg = c.type },
    ['@lsp.type.struct']      = { fg = c.type },
    ['@lsp.type.namespace']   = { fg = c.type },
    ['@lsp.type.parameter']   = { fg = c.variable },
    ['@lsp.type.property']    = { fg = c.property },
    ['@lsp.type.function']    = { fg = c.func },
    ['@lsp.type.method']      = { fg = c.func },
    ['@lsp.type.variable']    = { fg = c.variable },
    ['@lsp.type.keyword']     = { fg = c.keyword_alt },
    LspReferenceText          = { bg = c.bg_sel, underline = true },
    LspReferenceRead          = { bg = c.bg_sel, underline = true },
    LspReferenceWrite         = { bg = c.bg_sel, underline = true, bold = true },
    LspInlayHint              = { fg = c.fg_faint, bg = c.bg_alt },
    LspCodeLens               = { fg = c.fg_dim, italic = true },

    -- ── Diagnostics ────────────────────────────────────────────────────────
    DiagnosticError            = { fg = c.error },
    DiagnosticWarn             = { fg = c.warn },
    DiagnosticInfo             = { fg = c.info },
    DiagnosticHint             = { fg = c.hint },
    DiagnosticUnderlineError   = { undercurl = true, sp = c.error },
    DiagnosticUnderlineWarn    = { undercurl = true, sp = c.warn },
    DiagnosticUnderlineInfo    = { undercurl = true, sp = c.info },
    DiagnosticUnderlineHint    = { undercurl = true, sp = c.hint },
    DiagnosticVirtualTextError = { fg = c.error, bg = c.bg_alt },
    DiagnosticVirtualTextWarn  = { fg = c.warn, bg = c.bg_alt },
    DiagnosticVirtualTextInfo  = { fg = c.info, bg = c.bg_alt },
    DiagnosticVirtualTextHint  = { fg = c.hint, bg = c.bg_alt },

    -- ── Diff / git ─────────────────────────────────────────────────────────
    DiffAdd       = { bg = c.git_add,    fg = c.fg_bright },
    DiffChange    = { fg = c.git_change },
    DiffDelete    = { bg = c.git_delete, fg = c.fg_bright },
    DiffText      = { bg = c.accent,     fg = c.fg_bright },
    diffAdded     = { fg = c.git_add_fg },
    diffRemoved   = { fg = c.git_delete },
    diffChanged   = { fg = c.git_change },
    Added         = { fg = c.git_add_fg },
    Removed       = { fg = c.git_delete },
    Changed       = { fg = c.git_change },
    GitSignsAdd    = { fg = c.git_add_fg },
    GitSignsChange = { fg = c.git_change },
    GitSignsDelete = { fg = c.git_delete },

    -- ── Markdown (base groups; mdpreview adds its own CSMd* on top) ─────────
    ['@markup.heading']       = { fg = c.accent, bold = true },
    ['@markup.link']          = { fg = c.blue, underline = true },
    ['@markup.link.url']      = { fg = c.fg_dim, underline = true },
    ['@markup.raw']           = { fg = c.string },
    ['@markup.list']          = { fg = c.accent },
    ['@markup.quote']         = { fg = c.fg_dim, italic = true },
  }

  for group, opts in pairs(hl) do set(0, group, opts) end

  -- Terminal ANSI palette.
  vim.g.terminal_color_0  = c.bg_dark
  vim.g.terminal_color_8  = c.fg_dim
  vim.g.terminal_color_1  = c.red
  vim.g.terminal_color_9  = c.red
  vim.g.terminal_color_2  = c.green
  vim.g.terminal_color_10 = c.green
  vim.g.terminal_color_3  = c.yellow
  vim.g.terminal_color_11 = c.yellow
  vim.g.terminal_color_4  = c.blue
  vim.g.terminal_color_12 = c.blue
  vim.g.terminal_color_5  = c.purple
  vim.g.terminal_color_13 = c.purple
  vim.g.terminal_color_6  = c.cyan
  vim.g.terminal_color_14 = c.cyan
  vim.g.terminal_color_7  = c.fg
  vim.g.terminal_color_15 = c.fg_bright

  -- `highlight clear` above wiped every group, so let plugins that hook
  -- ColorScheme (telescope, gitsigns, which-key, …) re-apply their palette, then
  -- let our own UI modules re-tint via the dedicated event.
  vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'claudespace' })
  vim.api.nvim_exec_autocmds('User', { pattern = 'CSThemeApplied' })
end

M.apply = apply

-- Switch background explicitly ('dark'|'light'); nil toggles.
function M.set(bg)
  if not bg then bg = vim.o.background == 'dark' and 'light' or 'dark' end
  vim.o.background = bg   -- fires OptionSet → apply()
end

function M.setup()
  apply()
  -- Re-apply whenever the background changes (terminal light/dark switch, or a
  -- manual `:set background=…` / M.set()).
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern  = 'background',
    callback = apply,
  })
  vim.api.nvim_create_user_command('CSThemeToggle', function() M.set() end, {})
end

return M
