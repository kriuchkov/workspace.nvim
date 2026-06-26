-- Quick marks: per-workspace file bookmarks, jump instantly.
-- <leader>M = show panel | <leader>m1-5 = set mark | <leader>j1-5 = jump
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_marks')

local store = {}  -- { [ws_name] = { [slot] = { path, line, col } } }

local function ws_key()
  local ok, ws = pcall(require, 'claudespace.workspace')
  return ok and (ws._current or ws.current_name()) or 'global'
end

local function get_marks()
  local key = ws_key()
  if not store[key] then store[key] = {} end
  return store[key]
end

function M.set(slot)
  local path = api.nvim_buf_get_name(0)
  if path == '' or vim.bo.buftype ~= '' then
    vim.notify('Cannot mark this buffer', vim.log.levels.WARN)
    return
  end
  local cur = api.nvim_win_get_cursor(0)
  get_marks()[slot] = { path = path, line = cur[1], col = cur[2] }
  vim.notify(
    'Mark ' .. slot .. ' → ' .. fn.fnamemodify(path, ':~:.') .. ':' .. cur[1],
    vim.log.levels.INFO)
end

function M.jump(slot)
  local mark = get_marks()[slot]
  if not mark then
    vim.notify('Mark ' .. slot .. ' not set', vim.log.levels.WARN)
    return
  end
  if fn.filereadable(mark.path) == 1 then
    pcall(vim.cmd, 'edit ' .. fn.fnameescape(mark.path))
    pcall(api.nvim_win_set_cursor, 0, { mark.line, mark.col })
  else
    vim.notify('File missing: ' .. mark.path, vim.log.levels.WARN)
  end
end

-- Persist marks in workspace save/load
function M.get_state()  return store end
function M.set_state(s) store = s or {} end

function M.show()
  local marks = get_marks()
  local lines, hls = {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end

  add('')
  add('  Marks  [' .. ws_key() .. ']', 'CSTreeDir')
  add('  ' .. string.rep('─', 44))
  add('')

  for slot = 1, 5 do
    local m = marks[slot]
    if m then
      local rel = fn.fnamemodify(m.path, ':~:.')
      add('  ' .. slot .. '  ' .. rel .. '  :' .. m.line, 'CSFile')
    else
      add('  ' .. slot .. '  (empty)', 'Comment')
    end
  end

  add('')
  add('  1-5 jump  ·  s1-5 set  ·  x1-5 clear  ·  q close', 'CSInfo')

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].bufhidden  = 'wipe'
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  local W = 52
  local H = #lines
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' Marks ', title_pos = 'center',
    width = W, height = H,
    row = math.floor((vim.o.lines   - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  vim.wo[win].number = false

  local o = { buffer = buf, nowait = true, silent = true }
  local close = function() pcall(api.nvim_win_close, win, true) end
  vim.keymap.set('n', 'q',     close, o)
  vim.keymap.set('n', '<Esc>', close, o)

  for slot = 1, 5 do
    local s = slot
    vim.keymap.set('n', tostring(s), function() close(); M.jump(s) end, o)
    vim.keymap.set('n', 's' .. s, function()
      close()
      vim.schedule(function() M.set(s) end)
    end, o)
    vim.keymap.set('n', 'x' .. s, function()
      get_marks()[s] = nil
      close()
      M.show()
    end, o)
  end
end

function M.setup()
  local map = vim.keymap.set
  map('n', '<leader>M', M.show, { desc = 'Marks: show panel' })
  for slot = 1, 5 do
    local s = slot
    map('n', '<leader>m' .. s, function() M.set(s) end,  { desc = 'Mark: set '  .. s })
    map('n', '<leader>j' .. s, function() M.jump(s) end, { desc = 'Mark: jump ' .. s })
  end
end

return M
