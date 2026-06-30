-- Jump between function/method declarations via treesitter.
-- ]f / [f (and aliases ]m / [m) move to the next/previous function or method.
local M = {}

-- Node types that count as a "function" per treesitter language.
local FUNC_NODES = {
  go     = { function_declaration = true, method_declaration = true },
  rust   = { function_item = true },
  lua    = { function_declaration = true },
  python = { function_definition = true },
  ts     = { function_declaration = true, method_definition = true,
             generator_function_declaration = true },
}

local FT = {
  go = 'go', rust = 'rust', lua = 'lua', python = 'python',
  typescript = 'ts', typescriptreact = 'ts',
  javascript = 'ts', javascriptreact = 'ts',
}

-- Collect start positions of function nodes (prefer the name's position).
local function collect(node, want, out)
  for child in node:iter_children() do
    if want[child:type()] then
      local nm = child:field('name')[1]
      local r, c = (nm or child):start()
      out[#out + 1] = { r, c }
    end
    collect(child, want, out)
  end
end

---Move the cursor to the next (dir>0) or previous (dir<0) function/method.
function M.goto_func(dir)
  local ok, parser = pcall(vim.treesitter.get_parser)
  if not ok or not parser then return end
  local want = FUNC_NODES[FT[vim.bo.filetype] or parser:lang()]
  if not want then return end
  local tree = parser:parse()[1]
  if not tree then return end

  local pos = {}
  collect(tree:root(), want, pos)
  if #pos == 0 then return end
  table.sort(pos, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)

  local cur = vim.api.nvim_win_get_cursor(0)
  local cr, cc = cur[1] - 1, cur[2]
  local target
  if dir > 0 then
    for _, p in ipairs(pos) do
      if p[1] > cr or (p[1] == cr and p[2] > cc) then target = p; break end
    end
  else
    for i = #pos, 1, -1 do
      local p = pos[i]
      if p[1] < cr or (p[1] == cr and p[2] < cc) then target = p; break end
    end
  end
  if target then
    vim.api.nvim_win_set_cursor(0, { target[1] + 1, target[2] })
    vim.cmd 'normal! zz'
  end
end

-- ── File symbols picker (functions & structures) ──────────────────────────────

-- LSP SymbolKinds we surface; covers Go (func/method/struct/interface/type),
-- Rust (fn/struct/enum/trait/impl) and TS (function/class/interface/type/enum).
local WANT_KIND = {
  [5] = true,  -- Class
  [6] = true,  -- Method
  [9] = true,  -- Constructor
  [10] = true, -- Enum
  [11] = true, -- Interface  (Go interface, Rust trait)
  [12] = true, -- Function
  [23] = true, -- Struct
}
local KIND_ICON = {
  [5] = '', [6] = '', [9] = '', [10] = '',
  [11] = '', [12] = '', [23] = '',
}
local KIND_NAME = {
  [5] = 'class', [6] = 'method', [9] = 'ctor', [10] = 'enum',
  [11] = 'interface', [12] = 'func', [23] = 'struct',
}

-- Treesitter struct/type nodes for the LSP-less fallback.
local TYPE_NODES = {
  go   = { type_declaration = true },
  rust = { struct_item = true, enum_item = true, trait_item = true },
  ts   = { class_declaration = true, interface_declaration = true,
           type_alias_declaration = true, enum_declaration = true },
}

local function jump(s)
  pcall(vim.api.nvim_win_set_cursor, 0, { s.lnum, s.col })
  vim.cmd 'normal! zz'
end

local function flatten_lsp(symbols, out)
  out = out or {}
  for _, s in ipairs(symbols or {}) do
    local r = s.range or (s.location and s.location.range)
    if r and WANT_KIND[s.kind or 0] then
      out[#out + 1] = { name = s.name, kind = s.kind,
                        lnum = r.start.line + 1, col = r.start.character }
    end
    if s.children then flatten_lsp(s.children, out) end
  end
  return out
end

local function show(syms)
  if #syms == 0 then
    vim.notify('No functions or structures found', vim.log.levels.INFO); return
  end
  local fmt = function(s)
    return (KIND_ICON[s.kind] or ' ') .. '  ' .. s.name
        .. '   ' .. (KIND_NAME[s.kind] or '') .. '  :' .. s.lnum
  end
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(syms, { prompt = 'Functions & structures', format_item = fmt },
      function(s) if s then jump(s) end end)
    return
  end
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local astate       = require('telescope.actions.state')
  local fname        = vim.api.nvim_buf_get_name(0)
  pickers.new({}, {
    prompt_title = 'Functions & structures',
    finder = finders.new_table {
      results = syms,
      entry_maker = function(s)
        return {
          value = s, display = fmt(s),
          ordinal = (KIND_NAME[s.kind] or '') .. ' ' .. s.name,
          filename = fname, lnum = s.lnum, col = s.col,
        }
      end,
    },
    sorter = conf.generic_sorter {},
    previewer = conf.grep_previewer {},
    attach_mappings = function(pb)
      actions.select_default:replace(function()
        local e = astate.get_selected_entry()
        actions.close(pb)
        if e then jump(e.value) end
      end)
      return true
    end,
  }):find()
end

local function pick_treesitter()
  local ok, parser = pcall(vim.treesitter.get_parser)
  if not ok or not parser then
    vim.notify('No LSP or treesitter for this file', vim.log.levels.WARN); return
  end
  local lang    = FT[vim.bo.filetype] or parser:lang()
  local want_fn = FUNC_NODES[lang] or {}
  local want_ty = TYPE_NODES[lang] or {}
  local tree = parser:parse()[1]; if not tree then return end
  local syms = {}
  local function walk(node)
    for child in node:iter_children() do
      local t = child:type()
      if want_fn[t] or want_ty[t] then
        local nm   = child:field('name')[1]
        local r, c = (nm or child):start()
        local name = nm and vim.treesitter.get_node_text(nm, 0) or t
        syms[#syms + 1] = { name = name, kind = want_fn[t] and 12 or 23,
                            lnum = r + 1, col = c }
      end
      walk(child)
    end
  end
  walk(tree:root())
  table.sort(syms, function(a, b) return a.lnum < b.lnum end)
  show(syms)
end

-- Pick a function/struct in the current file and jump to it. Uses LSP document
-- symbols (language-accurate), falling back to treesitter when no LSP attached.
function M.pick()
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.tbl_filter(function(c)
    return c.supports_method('textDocument/documentSymbol')
  end, vim.lsp.get_clients({ bufnr = buf }))
  if #clients == 0 then pick_treesitter(); return end
  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  clients[1].request('textDocument/documentSymbol', params, function(err, result)
    if err or not result then pick_treesitter(); return end
    show(flatten_lsp(result))
  end, buf)
end

function M.setup()
  local map = vim.keymap.set
  local o = { silent = true }
  map('n', ']f', function() M.goto_func(1) end,  vim.tbl_extend('force', o, { desc = 'Next function/method' }))
  map('n', '[f', function() M.goto_func(-1) end, vim.tbl_extend('force', o, { desc = 'Prev function/method' }))
  map('n', ']m', function() M.goto_func(1) end,  o)   -- aliases
  map('n', '[m', function() M.goto_func(-1) end, o)
  map('n', '<leader>fs', M.pick, { silent = true, desc = 'File symbols (functions & structs)' })

  -- Clickable winbar button next to the filename opens the picker.
  _G.CSSymbolsPick = function() M.pick() end
end

return M
