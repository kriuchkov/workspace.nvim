-- Shared helpers for Claude modules.
local M = {}

-- ── Window helpers ────────────────────────────────────────────────────────────

local function special(win)
  if not vim.api.nvim_win_is_valid(win) then return true end
  local b = vim.api.nvim_win_get_buf(win)
  return vim.wo[win].winfixbuf
      or vim.bo[b].buftype ~= ''
      or vim.bo[b].filetype:match('^cs_') ~= nil
end

-- Move focus to a real editor window (creating one if needed) so the caller can
-- safely replace its buffer. Never lands on a sidebar / terminal / winfixbuf win.
function M.ensure_editor_win()
  if not special(vim.api.nvim_get_current_win()) then return end

  vim.cmd 'wincmd p'
  if not special(vim.api.nvim_get_current_win()) then return end

  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if not special(w) then vim.api.nvim_set_current_win(w); return end
  end

  -- No editor window exists. Split from a non-winfixbuf window if possible
  -- (splitting a winfixbuf window copies the flag), then clear it so the
  -- caller's nvim_win_set_buf can't fail with E1513.
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and not vim.wo[w].winfixbuf then
      vim.api.nvim_set_current_win(w); break
    end
  end
  vim.cmd 'vsplit'
  vim.wo[vim.api.nvim_get_current_win()].winfixbuf = false
end

-- ── Spinner ───────────────────────────────────────────────────────────────────

local FRAMES = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }

local function start_spinner(label)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = #label + 4
  local win = vim.api.nvim_open_win(buf, false, {
    relative  = 'editor',
    width     = width,
    height    = 1,
    row       = vim.o.lines - 3,
    col       = vim.o.columns - width - 2,
    style     = 'minimal',
    border    = 'rounded',
    focusable = false,
    zindex    = 150,
  })
  vim.wo[win].winblend = 15

  local idx   = 1
  local timer = vim.uv.new_timer()

  local function tick()
    if not vim.api.nvim_buf_is_valid(buf) then timer:stop(); return end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ' ' .. FRAMES[idx] .. ' ' .. label })
    idx = (idx % #FRAMES) + 1
  end
  tick()
  timer:start(0, 80, vim.schedule_wrap(tick))

  return function()
    timer:stop()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

-- ── Core async runner ─────────────────────────────────────────────────────────

-- opts.model: optional model ID string passed as --model flag
function M.run(prompt, label, callback, opts)
  local stop = start_spinner(label or 'thinking…')

  local tmp       = vim.fn.tempname()
  local model_arg = (opts and opts.model) and (' --model ' .. vim.fn.shellescape(opts.model)) or ''
  vim.fn.writefile(vim.split(prompt, '\n'), tmp)

  vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print' .. model_arg, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.fn.delete(tmp)
      stop()
      if not data then return end
      local result = vim.trim(table.concat(data, '\n'))
      if result ~= '' then callback(result) end
    end,
    on_stderr = function(_, data)
      if data and data[1] ~= '' then
        stop()
        vim.notify('claudespace: ' .. table.concat(data, '\n'), vim.log.levels.ERROR)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then stop() end
    end,
  })
end

-- ── Shared floats ─────────────────────────────────────────────────────────────

-- Float with y=apply / n/q/Esc=cancel.
function M.preview_float(lines, title, on_apply)
  local display = vim.list_extend(vim.deepcopy(lines), { '', '  y  apply    n/q  cancel' })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
  vim.bo[buf].modifiable = false

  local width  = math.min(math.floor(vim.o.columns * 0.72), 110)
  local height = math.min(#display + 2, math.floor(vim.o.lines * 0.6))
  local win    = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines  - height) / 2),
    title = title, title_pos = 'center',
  })
  vim.wo[win].wrap = false

  local function close() pcall(vim.api.nvim_win_close, win, true) end
  vim.keymap.set('n', 'y', function() close(); vim.schedule(on_apply) end,
    { buffer = buf, nowait = true })
  for _, k in ipairs { 'n', 'q', '<Esc>' } do
    vim.keymap.set('n', k, close, { buffer = buf, nowait = true })
  end
end

-- Read-only float; q/Esc/Enter to close.
function M.read_float(lines, title, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if ft then vim.bo[buf].filetype = ft end

  local width  = math.min(math.floor(vim.o.columns * 0.72), 110)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
  local win    = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines  - height) / 2),
    title = title, title_pos = 'center',
  })
  vim.wo[win].wrap = true

  local function close() pcall(vim.api.nvim_win_close, win, true) end
  for _, k in ipairs { 'q', '<Esc>', '<CR>' } do
    vim.keymap.set('n', k, close, { buffer = buf, nowait = true })
  end
end

return M
