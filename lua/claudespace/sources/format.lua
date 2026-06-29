-- nvim-cmp formatting with LSP kind icons.
local M = {}

local ICONS = {
  Text          = '󰉿', Method      = '󰆧', Function    = '󰊕',
  Constructor   = '',  Field       = '󰜢', Variable    = '󰀫',
  Class         = '󰠱', Interface   = '',  Module      = '',
  Property      = '󰜢', Unit        = '󰑭', Value       = '󰎠',
  Enum          = '',  Keyword     = '󰌋', Snippet     = '',
  Color         = '󰏘', File        = '󰈙', Reference   = '󰈇',
  Folder        = '󰉋', EnumMember  = '',  Constant    = '󰏿',
  Struct        = '󰙅', Event       = '',  Operator    = '󰆕',
  TypeParameter = '',
}

local function abbrev(str, max, ellipsis)
  if vim.fn.strchars(str) > max then
    return vim.fn.strcharpart(str, 0, max) .. ellipsis
  end
  return str
end

---Returns a nvim-cmp `formatting.format` function.
---@param opts {mode?:string, maxwidth?:integer, ellipsis_char?:string, before?:function}
function M.cmp_format(opts)
  opts = opts or {}
  local mode      = opts.mode or 'symbol'
  local maxwidth  = opts.maxwidth or 40
  local ellipsis  = opts.ellipsis_char or '…'

  return function(entry, item)
    if opts.before then item = opts.before(entry, item) end

    local icon = ICONS[item.kind] or ''
    if mode == 'symbol' then
      item.kind = icon
    elseif mode == 'symbol_text' then
      item.kind = icon .. ' ' .. (item.kind or '')
    elseif mode == 'text_symbol' then
      item.kind = (item.kind or '') .. ' ' .. icon
    end

    if item.abbr then item.abbr = abbrev(item.abbr, maxwidth, ellipsis) end
    if item.menu and #item.menu > 20 then
      item.menu = item.menu:sub(1, 20) .. ellipsis
    end

    return item
  end
end

return M
