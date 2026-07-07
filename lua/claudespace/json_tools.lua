-- JSON helpers: pretty-format a buffer in place, or open a read-only pretty view
-- (the file on disk stays as-is — handy for reading minified config like
-- .claudespace/workspace.json without reformatting it).
local M = {}

local api = vim.api
local fn  = vim.fn

-- Pretty-print `src` with jq; returns (lines, err). jq preserves key order.
local function jq_pretty(src)
  if fn.executable('jq') == 0 then return nil, 'jq not found' end
  local out = fn.system({ 'jq', '.' }, src)
  if vim.v.shell_error ~= 0 then
    return nil, (vim.trim(out) ~= '' and vim.trim(out) or 'invalid JSON')
  end
  return vim.split(vim.trim(out), '\n'), nil
end

local function buf_text(buf)
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

---Reformat the JSON buffer in place (modifies it; save to persist).
function M.pretty(buf)
  buf = (buf and buf ~= 0) and buf or api.nvim_get_current_buf()
  local lines, err = jq_pretty(buf_text(buf))
  if not lines then
    vim.notify('JSON pretty: ' .. err, vim.log.levels.ERROR)
    return
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.notify('JSON formatted', vim.log.levels.INFO)
end

---Show the JSON pretty-printed in a read-only float; the buffer/file is untouched.
function M.view(buf)
  buf = (buf and buf ~= 0) and buf or api.nvim_get_current_buf()
  local lines, err = jq_pretty(buf_text(buf))
  if not lines then
    vim.notify('JSON view: ' .. err, vim.log.levels.ERROR)
    return
  end
  require('claudespace.claude.util').read_float(lines, ' JSON ', 'json')
end

function M.setup()
  api.nvim_create_user_command('JsonPretty', function() M.pretty(0) end,
    { desc = 'JSON: pretty-format the buffer in place' })
  api.nvim_create_user_command('JsonView', function() M.view(0) end,
    { desc = 'JSON: read-only pretty view (file untouched)' })

  api.nvim_create_autocmd('FileType', {
    pattern = { 'json', 'jsonc', 'json5' },
    callback = function(ev)
      local function map(lhs, fnc, desc)
        vim.keymap.set('n', lhs, fnc, { buffer = ev.buf, silent = true, desc = desc })
      end
      map('<leader>=',  function() M.pretty(ev.buf) end, 'JSON: pretty format (in place)')
      map('<leader>uj', function() M.view(ev.buf) end,   'JSON: pretty view (read-only)')
    end,
  })
end

return M
