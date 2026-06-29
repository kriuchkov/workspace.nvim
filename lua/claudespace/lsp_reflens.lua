-- Reference lens: показывает «interface · 5 usages» / «function · 3 usages» над
-- объявлением под курсором (CodeLens-стиль, как в GoLand). Срабатывает только когда
-- курсор на имени объявления (func/method/type/interface/struct/trait/enum/class/…) —
-- вид определяется по treesitter-узлу (Go/Rust/Lua/TS/JS). Запрос references по CursorHold.
-- <leader>lr открывает список использований с превью.
local M = {}

-- Resource controls:
--   auto      — show the lens automatically on CursorHold (false = only via <leader>lu)
--   max_lines — skip the auto lens on buffers larger than this (on-demand bypasses it)
M.config = { auto = true, max_lines = 4000 }

local ns = vim.api.nvim_create_namespace 'cs_reflens'

local function reflens_hl()
  vim.api.nvim_set_hl(0, 'CsRefLens', { link = 'Comment', italic = true, default = true })
end

local function clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

-- Токены-имена, на которых вообще имеет смысл искать объявление.
local NAME_NODES = {
  identifier = true, type_identifier = true, field_identifier = true,
  property_identifier = true,
}

-- Узел-объявление → вид (строка) либо функция-резолвер(decl)->вид, по языку.
-- Резолвер нужен там, где вид зависит от содержимого (Go type_spec, Rust impl, TS const).
local DECL = {
  go = {
    function_declaration = 'function',
    method_declaration   = 'method',
    const_spec           = 'constant',
    var_spec             = 'variable',
    type_spec = function(d)
      local ty = d:field('type')[1]
      local t  = ty and ty:type()
      if t == 'interface_type' then return 'interface' end
      if t == 'struct_type'    then return 'struct'    end
      return 'type'
    end,
  },
  rust = {
    struct_item = 'struct', enum_item = 'enum', trait_item = 'trait',
    type_item = 'type', const_item = 'constant', static_item = 'static',
    union_item = 'union', mod_item = 'module',
    function_item = function(d)
      local p = d:parent()
      while p do
        local t = p:type()
        if t == 'impl_item' or t == 'trait_item' then return 'method' end
        if t == 'source_file' then break end
        p = p:parent()
      end
      return 'function'
    end,
  },
  lua = {
    function_declaration = function(d)
      local nm = d:field('name')[1]
      if nm and nm:type() == 'method_index_expression' then return 'method' end
      return 'function'
    end,
  },
  -- TS и JS делят почти все типы узлов; interface/enum/type_alias безвредны для JS.
  ts = {
    function_declaration   = 'function',
    generator_function_declaration = 'function',
    method_definition      = 'method',
    class_declaration      = 'class',
    abstract_class_declaration = 'class',
    interface_declaration  = 'interface',
    enum_declaration       = 'enum',
    type_alias_declaration = 'type',
    public_field_definition = 'property',
    variable_declarator = function(d)
      local val = d:field('value')[1]
      local t   = val and val:type()
      if t == 'arrow_function' or t == 'function_expression' or t == 'function' then
        return 'function'
      end
      return 'variable'
    end,
  },
}

local FT_DECL = {
  go = DECL.go, rust = DECL.rust, lua = DECL.lua,
  typescript = DECL.ts, typescriptreact = DECL.ts,
  javascript = DECL.ts, javascriptreact = DECL.ts,
}

local function pos_le(ar, ac, br, bc) return ar < br or (ar == br and ac <= bc) end

-- node целиком внутри outer? (диапазоны treesitter: 0-инд, конец эксклюзивный)
local function within(node, outer)
  local nsr, nsc, ner, nec = node:range()
  local osr, osc, oer, oec = outer:range()
  return pos_le(osr, osc, nsr, nsc) and pos_le(ner, nec, oer, oec)
end

-- Курсор на ИМЕНИ объявления decl? (а не в его теле)
local function on_name(decl, node)
  for _, f in ipairs(decl:field 'name') do
    if within(node, f) then return true end
  end
  return false
end

-- Если курсор стоит на имени объявления — вернуть его вид, иначе nil.
local function decl_kind()
  local ok, node = pcall(vim.treesitter.get_node)
  if not ok or not node or not NAME_NODES[node:type()] then return nil end
  local set = FT_DECL[vim.bo.filetype]
  if not set then return nil end
  -- ближайший предок-объявление известного типа
  local decl, kind = node:parent(), nil
  while decl do
    kind = set[decl:type()]
    if kind then break end
    decl = decl:parent()
  end
  if not decl or not on_name(decl, node) then return nil end
  if type(kind) == 'function' then return kind(decl) end
  return kind
end

-- Go methods of a type: scan the package dir (.go files) for `func (r *Type) M(`.
-- Cached per dir+name; cleared on BufWritePost.
local _methods_cache = {}
local function go_methods(name, dir)
  local key = dir .. '\0' .. name
  if _methods_cache[key] then return _methods_cache[key] end
  local list = {}
  for _, file in ipairs(vim.fn.globpath(dir, '*.go', false, true)) do
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then
      for i, line in ipairs(lines) do
        local recv, method = line:match '^func%s*(%b())%s*([%w_]+)'
        if recv and method and recv:match('%*?([%w_]+)%s*%)$') == name then
          list[#list + 1] = { filename = file, lnum = i, col = 1, text = vim.trim(line) }
        end
      end
    end
  end
  _methods_cache[key] = list
  return list
end
M._clear_methods_cache = function() _methods_cache = {} end

-- Rust/TS methods live inside the type body (impl block / class body) — find them
-- via treesitter in the current buffer.
local TS_METHOD_LANG = {
  rust = 'rust',
  typescript = 'typescript', typescriptreact = 'tsx',
  javascript = 'javascript', javascriptreact = 'jsx',
}
-- container node → { field that holds the type name, method node type inside body }
local CONTAINER = {
  impl_item                  = { field = 'type', method = 'function_item' },
  class_declaration          = { field = 'name', method = 'method_definition' },
  abstract_class_declaration = { field = 'name', method = 'method_definition' },
  interface_declaration      = { field = 'name', method = 'method_signature' },
}
local BODY_TYPES = { declaration_list = true, class_body = true, object_type = true }

local function body_of(node)
  local b = node:field('body')[1]
  if b then return b end
  for c in node:iter_children() do
    if BODY_TYPES[c:type()] then return c end
  end
end

local function ts_methods(name, bufnr, ft)
  local lang = TS_METHOD_LANG[ft]
  if not lang then return {} end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then return {} end
  local tree = (parser:parse() or {})[1]
  if not tree then return {} end
  local fname, list = vim.api.nvim_buf_get_name(bufnr), {}
  local function walk(node)
    for child in node:iter_children() do
      local spec = CONTAINER[child:type()]
      if spec then
        local f = child:field(spec.field)[1]
        if f and vim.treesitter.get_node_text(f, bufnr) == name then
          local body = body_of(child)
          if body then
            for m in body:iter_children() do
              if m:type() == spec.method then
                local sr = (m:field('name')[1] or m):start()
                local line = vim.api.nvim_buf_get_lines(bufnr, sr, sr + 1, false)[1] or ''
                list[#list + 1] = { filename = fname, lnum = sr + 1, col = 1, text = vim.trim(line) }
              end
            end
          end
        end
      end
      walk(child)
    end
  end
  walk(tree:root())
  return list
end

-- Methods of the named type for the current buffer's language.
local function methods_for(name, bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == 'go' then
    return go_methods(name, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':h'))
  end
  return ts_methods(name, bufnr, ft)
end

-- Declaration kinds that can own methods.
local METHOD_KINDS = { struct = true, class = true, enum = true, trait = true, interface = true }

-- force=true bypasses the auto/size gates (on-demand via <leader>lu).
local function do_show(force)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = 'textDocument/references' }
  if vim.tbl_isempty(clients) then return end
  -- Size gate: huge files make `references` expensive — skip the passive lens.
  if not force and vim.api.nvim_buf_line_count(bufnr) > M.config.max_lines then
    clear(bufnr)
    return
  end
  local kind = decl_kind()
  if not kind then
    clear(bufnr)
    return
  end
  -- For a type that can own methods, also count them (Go: package scan, cached;
  -- Rust/TS: treesitter in the current buffer).
  local methods
  if METHOD_KINDS[kind] then
    methods = #methods_for(vim.fn.expand '<cword>', bufnr)
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
  params.context = { includeDeclaration = false }

  vim.lsp.buf_request(bufnr, 'textDocument/references', params, function(err, result)
    if err or not result then return end
    -- Курсор мог уйти, пока ждали ответ — рисуем только если всё ещё на той же строке.
    if vim.api.nvim_get_current_buf() ~= bufnr then return end
    if vim.api.nvim_win_get_cursor(0)[1] ~= lnum then return end

    clear(bufnr)
    local n = #result
    if n == 0 then return end
    local usages = n == 1 and '1 usage' or (n .. ' usages')
    local label  = kind .. ' · ' .. usages
    if methods and methods > 0 then
      label = label .. ' · ' .. methods .. (methods == 1 and ' method' or ' methods')
    end
    local indent = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]:match '^%s*' or ''
    vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
      virt_lines_above = true,
      virt_lines = { { { indent .. '┊ ' .. label, 'CsRefLens' } } },
    })
  end)
end

local function auto_show()
  if M.config.auto then do_show(false) end
end

-- Show the lens for the declaration under the cursor on demand (ignores gates).
function M.refresh() do_show(true) end

-- Toggle the passive (CursorHold) lens — useful in large workspaces.
function M.toggle_auto()
  M.config.auto = not M.config.auto
  vim.notify('Reference lens auto: ' .. (M.config.auto and 'on' or 'off'), vim.log.levels.INFO)
  if M.config.auto then do_show(false) else clear(vim.api.nvim_get_current_buf()) end
end

-- Список всех использований символа под курсором с превью кода.
-- Telescope даёт панель предпросмотра (контекст вокруг каждой ссылки) + fuzzy-фильтр;
-- Enter — переход. Без telescope откатываемся на quickfix.
function M.open_references()
  local ok, tb = pcall(require, 'telescope.builtin')
  if ok then
    tb.lsp_references {
      include_declaration = false,
      jump_type = 'default',
      fname_width = 60,
    }
    return
  end

  vim.lsp.buf.references({ includeDeclaration = false }, {
    on_list = function(opts)
      vim.fn.setqflist({}, ' ', opts)
      vim.cmd 'botright copen'
      local qf = vim.api.nvim_get_current_buf()
      vim.keymap.set('n', '<CR>', function()
        local idx = vim.fn.line '.'
        vim.cmd 'cclose'
        vim.cmd(idx .. 'cc')
      end, { buffer = qf, nowait = true, silent = true, desc = 'Jump & close' })
      vim.keymap.set('n', 'q', '<cmd>cclose<cr>', { buffer = qf, nowait = true, silent = true })
    end,
  })
end

-- Pick a method of the type under the cursor and jump to it (with preview).
-- Go: scans the package; Rust/TS: scans the current buffer (impl/class body).
function M.struct_methods()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.fn.expand '<cword>'
  if name == '' then return end
  local list = methods_for(name, bufnr)
  if #list == 0 then
    vim.notify('No methods found for ' .. name, vim.log.levels.INFO)
    return
  end
  local title = name .. ' methods (' .. #list .. ')'
  vim.fn.setqflist({}, ' ', { title = title, items = list })
  local ok, tb = pcall(require, 'telescope.builtin')
  if ok then
    tb.quickfix { prompt_title = title }
  else
    vim.cmd 'botright copen'
    local qf = vim.api.nvim_get_current_buf()
    vim.keymap.set('n', '<CR>', function()
      local idx = vim.fn.line '.'
      vim.cmd 'cclose'
      vim.cmd(idx .. 'cc')
    end, { buffer = qf, nowait = true, silent = true, desc = 'Jump & close' })
    vim.keymap.set('n', 'q', '<cmd>cclose<cr>', { buffer = qf, nowait = true, silent = true })
  end
end

M._decl_kind    = decl_kind     -- test seam
M._go_methods   = go_methods    -- test seam
M._methods_for  = methods_for   -- test seam

function M.setup()
  reflens_hl()
  local grp = vim.api.nvim_create_augroup('cs_reflens', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = grp, callback = reflens_hl })
  vim.api.nvim_create_autocmd('CursorHold', { group = grp, callback = auto_show })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = grp,
    callback = function() clear(vim.api.nvim_get_current_buf()) end,
  })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = grp, callback = M._clear_methods_cache,
  })

  vim.keymap.set('n', '<leader>lu', M.refresh,
    { silent = true, desc = 'LSP: usages lens here' })
  vim.keymap.set('n', '<leader>lm', M.struct_methods,
    { silent = true, desc = 'LSP: struct methods (jump)' })
  vim.api.nvim_create_user_command('ReflensToggle', M.toggle_auto,
    { desc = 'Toggle reference-lens auto mode' })
end

return M
