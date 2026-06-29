-- Notifications center: captures vim.notify history, shows in a float.
local M = {}

local api = vim.api
local ns  = api.nvim_create_namespace('cs_notify')

local MAX     = 80
local history = {}  -- { msg, level, time }

local LEVEL = {
  [vim.log.levels.ERROR] = { icon = ' ', hl = 'DiagnosticError' },
  [vim.log.levels.WARN]  = { icon = ' ', hl = 'DiagnosticWarn' },
  [vim.log.levels.INFO]  = { icon = ' ', hl = 'DiagnosticInfo' },
  [vim.log.levels.DEBUG] = { icon = ' ', hl = 'Comment' },
}

local function build()
  local lines, hls = {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end

  add('')
  add('  Notifications  (' .. #history .. ')', 'CSTreeDir')
  add('  ' .. string.rep('─', 54))

  if #history == 0 then
    add('')
    add('  (no notifications yet)')
  else
    for _, n in ipairs(history) do
      local info = LEVEL[n.level] or LEVEL[vim.log.levels.INFO]
      local parts = vim.split(tostring(n.msg), '\n', { plain = true })
      for i, part in ipairs(parts) do
        if i == 1 then
          add('  ' .. info.icon .. ' ' .. n.time .. '  ' .. part, info.hl)
        else
          add('            ' .. part)
        end
      end
    end
  end

  add('')
  add('  d clear  ·  q close', 'CSInfo')
  return lines, hls
end

function M.open()
  local lines, hls = build()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].bufhidden  = 'wipe'
  vim.bo[buf].filetype   = 'cs_notify'
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  local W = math.min(72, vim.o.columns - 4)
  local H = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local win = api.nvim_open_win(buf, true, {
    relative  = 'editor', style = 'minimal', border = 'rounded',
    title = ' Notifications ', title_pos = 'center',
    width = W, height = H,
    row = math.floor((vim.o.lines - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  vim.wo[win].wrap = true
  vim.wo[win].number = false

  local o = { buffer = buf, nowait = true, silent = true }
  local close = function() pcall(api.nvim_win_close, win, true) end
  vim.keymap.set('n', 'q',     close, o)
  vim.keymap.set('n', '<Esc>', close, o)
  vim.keymap.set('n', 'd', function()
    history = {}
    close()
  end, o)
end

function M.setup()
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    level = level or vim.log.levels.INFO
    table.insert(history, 1, {
      msg   = tostring(msg or ''),
      level = level,
      time  = os.date('%H:%M:%S'),
    })
    if #history > MAX then history[MAX + 1] = nil end
    -- INFO goes to history only; WARN/ERROR still show in cmdline
    if level >= vim.log.levels.WARN then
      orig(msg, level, opts)
    end
  end

  vim.keymap.set('n', '<leader>N', M.open, { desc = 'Notifications: history' })
end

return M
