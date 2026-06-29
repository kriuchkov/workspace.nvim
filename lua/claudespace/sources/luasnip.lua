-- nvim-cmp source for LuaSnip.
local cmp  = require 'cmp'
local util = require 'vim.lsp.util'

local source   = {}
local snip_cache = {}
local doc_cache  = {}

local DEFAULTS = { use_show_condition = true, show_autosnippets = false }

local function init_opts(params)
  params.option = vim.tbl_deep_extend('keep', params.option, DEFAULTS)
end

local function get_documentation(snip, data)
  local header  = (snip.name or '') .. ' _ `[' .. data.filetype .. ']`\n'
  local docstr  = { '', '```' .. vim.bo.filetype, snip:get_docstring(), '```' }
  local lines   = util.convert_input_to_markdown_lines { header .. '---', (snip.dscr or ''), docstr }
  local doc     = table.concat(lines, '\n')
  doc_cache[data.filetype] = doc_cache[data.filetype] or {}
  doc_cache[data.filetype][data.snip_id] = doc
  return doc
end

source.new = function()
  return setmetatable({}, { __index = source })
end

source.clear_cache = function() snip_cache = {}; doc_cache = {} end

source.refresh = function()
  local ft = require('luasnip.session').latest_load_ft
  snip_cache[ft] = nil
  doc_cache[ft]  = nil
end

function source:is_available()
  return pcall(require, 'luasnip')
end

function source:get_debug_name() return 'luasnip' end

function source:get_keyword_pattern()
  return '\\%([^[:alnum:][:blank:]]\\|\\w\\+\\)'
end

function source:complete(params, callback)
  init_opts(params)
  local ls = require 'luasnip'
  local filetypes = require('luasnip.util.util').get_snippet_filetypes()
  local items = {}

  for _, ft in ipairs(filetypes) do
    if not snip_cache[ft] then
      local ft_items = {}
      local snip_tab = ls.get_snippets(ft, { type = 'snippets' })
      local iter = params.option.show_autosnippets
        and { { snip_tab, false }, { ls.get_snippets(ft, { type = 'autosnippets' }), true } }
        or  { { snip_tab, false } }

      for _, pair in ipairs(iter) do
        local tab, auto = pair[1], pair[2]
        for _, snip in pairs(tab) do
          if not snip.hidden then
            ft_items[#ft_items + 1] = {
              word  = snip.trigger,
              label = snip.trigger,
              kind  = cmp.lsp.CompletionItemKind.Snippet,
              data  = {
                priority       = snip.effective_priority or 1000,
                filetype       = ft,
                snip_id        = snip.id,
                show_condition = snip.show_condition,
                auto           = auto,
              },
            }
          end
        end
      end
      table.sort(ft_items, function(a, b) return a.data.priority > b.data.priority end)
      snip_cache[ft] = ft_items
    end
    vim.list_extend(items, snip_cache[ft])
  end

  if params.option.use_show_condition then
    local line = params.context.cursor_before_line
    items = vim.tbl_filter(function(i)
      return not i.data.show_condition or i.data.show_condition(line)
    end, items)
  end

  callback(items)
end

function source:resolve(item, callback)
  local snip = require('luasnip').get_id_snippet(item.data.snip_id)
  local cached = (doc_cache[item.data.filetype] or {})[item.data.snip_id]
  item.documentation = {
    kind  = cmp.lsp.MarkupKind.Markdown,
    value = cached or get_documentation(snip, item.data),
  }
  callback(item)
end

function source:execute(item, callback)
  local ls   = require 'luasnip'
  local snip = ls.get_id_snippet(item.data.snip_id)
  if snip.regTrig then snip = snip:get_pattern_expand_helper() end

  local cursor = vim.api.nvim_win_get_cursor(0)
  cursor[1] = cursor[1] - 1
  local line   = require('luasnip.util.util').get_current_line_to_cursor()
  local ep     = snip:matches(line)

  local region = { from = { cursor[1], cursor[2] - #item.word }, to = cursor }
  if ep then
    if ep.clear_region then
      region = ep.clear_region
    elseif ep.trigger then
      region = { from = { cursor[1], cursor[2] - #ep.trigger }, to = cursor }
    end
  end

  ls.snip_expand(snip, { clear_region = region, expand_params = ep })
  callback(item)
end

return source
