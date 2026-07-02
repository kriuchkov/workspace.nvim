-- Central colour palettes for the claudespace theme.
--
-- Two semantic palettes — `dark` (VS Code Dark Modern inspired) and `light`
-- (Light Modern) — share the same keys so every consumer can be written once and
-- follow `&background`. Nothing here touches highlight groups; see theme/init.lua
-- for the applier and `require('claudespace.theme').colors()` for the accessor.
local M = {}

M.dark = {
  bg          = '#1f1f1f',   -- editor background
  bg_dark     = '#181818',   -- sidebars / panels / tabline
  bg_float    = '#252526',   -- popups / floats
  bg_sel      = '#264f78',   -- visual selection
  bg_hl       = '#2a2d2e',   -- current line / hover
  bg_alt      = '#2d2d2d',   -- subtle contrast blocks (code bg)
  border      = '#3c3c3c',
  border_dim  = '#2b2b2b',

  fg          = '#d4d4d4',
  fg_dim      = '#858585',   -- line numbers / inactive
  fg_faint    = '#5a5a5a',   -- whitespace / very subtle
  fg_bright   = '#ffffff',

  comment     = '#6a9955',
  keyword     = '#c586c0',   -- control-flow keywords
  keyword_alt = '#569cd6',   -- declaration keywords (fn, let, use)
  string      = '#ce9178',
  number      = '#b5cea8',
  func        = '#dcdcaa',
  type        = '#4ec9b0',
  variable    = '#9cdcfe',
  constant    = '#4fc1ff',
  property    = '#9cdcfe',
  operator    = '#d4d4d4',

  blue        = '#569cd6',
  cyan        = '#4ec9b0',
  green       = '#6a9955',
  orange      = '#ce9178',
  yellow      = '#dcdcaa',
  red         = '#f14c4c',
  purple      = '#c586c0',
  accent      = '#0a7aca',   -- primary UI accent (active tab / selection)

  error       = '#f14c4c',
  warn        = '#cca700',
  info        = '#3794ff',
  hint        = '#4ec9b0',

  git_add     = '#487e02',
  git_add_fg  = '#89d185',
  git_change  = '#e2c08d',
  git_delete  = '#f14c4c',
}

M.light = {
  bg          = '#ffffff',
  bg_dark     = '#f3f3f3',
  bg_float    = '#f8f8f8',
  bg_sel      = '#add6ff',
  bg_hl       = '#e8e8e8',
  bg_alt      = '#f0f0f0',
  border      = '#d0d0d0',
  border_dim  = '#e0e0e0',

  fg          = '#3b3b3b',
  fg_dim      = '#6e7781',
  fg_faint    = '#b0b0b0',
  fg_bright   = '#000000',

  comment     = '#008000',
  keyword     = '#af00db',
  keyword_alt = '#0000ff',
  string      = '#a31515',
  number      = '#098658',
  func        = '#795e26',
  type        = '#267f99',
  variable    = '#001080',
  constant    = '#0070c1',
  property    = '#001080',
  operator    = '#3b3b3b',

  blue        = '#0451a5',
  cyan        = '#267f99',
  green       = '#008000',
  orange      = '#a31515',
  yellow      = '#795e26',
  red         = '#e51400',
  purple      = '#af00db',
  accent      = '#0060c0',

  error       = '#e51400',
  warn        = '#bf8803',
  info        = '#1a85ff',
  hint        = '#267f99',

  git_add     = '#587c0c',
  git_add_fg  = '#587c0c',
  git_change  = '#895503',
  git_delete  = '#ad0707',
}

-- The palette matching the current &background.
function M.active()
  return vim.o.background == 'light' and M.light or M.dark
end

return M
