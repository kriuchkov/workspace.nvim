-- nvim-cmp filesystem path source.
local cmp = require 'cmp'

local NAME_PAT = '\\%([^/\\\\:\\*?<>\'"`\\|]\\)'
local PATH_RE  = vim.regex(
  ([[\%(\%(/PAT*[^/\\\\:\\*?<>\'"`\\| .~]\)\|\%(/\.\.\)\)*/\zePAT*$]]):gsub('PAT', NAME_PAT))

local defaults = {
  trailing_slash       = false,
  label_trailing_slash = true,
  get_cwd = function(params)
    return vim.fn.expand(('#%d:p:h'):format(params.context.bufnr))
  end,
}

local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_trigger_characters() return { '/', '.' } end
function source:get_keyword_pattern()    return NAME_PAT .. '*' end

function source:complete(params, callback)
  local opt     = self:_opts(params)
  local dirname = self:_dirname(params, opt)
  if not dirname then return callback() end
  local hidden = string.sub(params.context.cursor_before_line, params.offset, params.offset) == '.'
  self:_candidates(dirname, hidden, opt, function(err, items)
    callback(err and nil or items)
  end)
end

function source:resolve(item, callback)
  local data = item.data
  if data.stat and data.stat.type == 'file' then
    local ok, doc = pcall(self._get_documentation, self, data.path, 20)
    if ok then item.documentation = doc end
  end
  callback(item)
end

function source:_opts(params)
  return vim.tbl_deep_extend('keep', params.option, defaults)
end

function source:_dirname(params, opt)
  local s = PATH_RE:match_str(params.context.cursor_before_line)
  if not s then return nil end
  local dirname = string.gsub(string.sub(params.context.cursor_before_line, s + 2), '%a*$', '')
  local prefix  = string.sub(params.context.cursor_before_line, 1, s + 1)
  local base    = vim.api.nvim_get_mode().mode == 'c' and vim.fn.getcwd() or opt.get_cwd(params)

  if prefix:match('%.%./$')  then return vim.fn.resolve(base .. '/../' .. dirname) end
  if prefix:match('%./$') or prefix:match('"$') or prefix:match("'$") then
    return vim.fn.resolve(base .. '/' .. dirname)
  end
  if prefix:match('~/$') then return vim.fn.resolve(vim.fn.expand '~' .. '/' .. dirname) end
  local ev = prefix:match('%$([%a_]+)/$')
  if ev then
    local val = vim.fn.getenv(ev)
    if val ~= vim.NIL then return vim.fn.resolve(val .. '/' .. dirname) end
  end
  if prefix:match('/$') then
    local ok = true
    ok = ok and not prefix:match('%a/$')
    ok = ok and not prefix:match('%a+:/$') and not prefix:match('%a+://$')
    ok = ok and not prefix:match('</$')
    ok = ok and not prefix:match('[%d%)]%s*/$')
    ok = ok and (not prefix:match('^[%s/]*$') or not self:_is_slash_comment())
    if ok then return vim.fn.resolve('/' .. dirname) end
  end
  return nil
end

function source:_candidates(dirname, hidden, opt, callback)
  local fs, err = vim.loop.fs_scandir(dirname)
  if err then return callback(err, nil) end
  local items = {}
  while true do
    local name, ftype, e = vim.loop.fs_scandir_next(fs)
    if e then return callback(ftype, nil) end
    if not name then break end
    if hidden or name:sub(1, 1) ~= '.' then
      local path = dirname .. '/' .. name
      local stat  = vim.loop.fs_stat(path)
      local lstat
      if stat then
        ftype = stat.type
      elseif ftype == 'link' then
        lstat = vim.loop.fs_lstat(dirname)
        if not lstat then goto continue end
      else
        goto continue
      end
      local item = {
        label      = name,
        filterText = name,
        insertText = name,
        kind       = cmp.lsp.CompletionItemKind.File,
        data       = { path = path, type = ftype, stat = stat, lstat = lstat },
      }
      if ftype == 'directory' then
        item.kind       = cmp.lsp.CompletionItemKind.Folder
        item.label      = opt.label_trailing_slash and (name .. '/') or name
        item.insertText = name .. '/'
        if not opt.trailing_slash then item.word = name end
      end
      table.insert(items, item)
    end
    ::continue::
  end
  callback(nil, items)
end

function source:_is_slash_comment()
  local cs = vim.bo.commentstring or ''
  if vim.bo.filetype == '' then return false end
  return cs:match '/%*' or cs:match '//'
end

function source:_get_documentation(filename, count)
  local f = assert(io.open(filename, 'rb'))
  local chunk = f:read(1024); f:close()
  if chunk:find '\0' then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = 'binary file' }
  end
  local lines = {}
  for ln in chunk:gmatch '[^\r\n]+' do
    table.insert(lines, ln)
    if count and #lines >= count then break end
  end
  local ft = vim.filetype.match { filename = filename }
  if not ft then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = table.concat(lines, '\n') }
  end
  return {
    kind  = cmp.lsp.MarkupKind.Markdown,
    value = table.concat(vim.list_extend({ '```' .. ft }, vim.list_extend(lines, { '```' })), '\n'),
  }
end

return source
