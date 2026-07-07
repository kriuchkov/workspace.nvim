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

-- Move focus to the center content window (creating one if needed). Delegates to
-- the shell so every caller lands in the single center region.
function M.ensure_editor_win()
  local ok, shell = pcall(require, 'claudespace.shell')
  if ok then pcall(vim.api.nvim_set_current_win, shell.center()) end
end

-- ── Spinner ───────────────────────────────────────────────────────────────────

local FRAMES = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }

local function start_spinner(label)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = vim.fn.strdisplaywidth(label) + 4
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

  -- Replace the label and resize the float to fit (used to show live progress,
  -- e.g. the tool Claude is currently running).
  local function set_label(l)
    label = l
    if not vim.api.nvim_win_is_valid(win) then return end
    local w = vim.fn.strdisplaywidth(l) + 4
    pcall(vim.api.nvim_win_set_config, win, {
      relative = 'editor', width = w, height = 1,
      row = vim.o.lines - 3, col = vim.o.columns - w - 2,
    })
  end

  local function stop()
    timer:stop()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  return stop, set_label
end

-- Public spinner: returns stop(), set_label(text). Used by the command runners.
function M.spinner(label) return start_spinner(label) end

-- ── Core async runner ─────────────────────────────────────────────────────────

-- opts.model: optional model ID string passed as --model flag
-- Backed by claudespace.claude.runner (structured stream-json): no shell string,
-- no tempfile, real error/tool reporting. Preserves the (prompt,label,cb) contract:
-- callback receives the final answer text on success.
function M.run(prompt, label, callback, opts)
  opts = opts or {}
  local stop = start_spinner(label or 'thinking…')
  require('claudespace.claude.runner').run {
    prompt = prompt,
    model  = opts.model,
    cwd    = opts.cwd,
    label  = label,
    on_result = function(res)
      stop()
      if res.is_error then
        vim.notify('claudespace: ' .. (res.text or 'Claude error'), vim.log.levels.ERROR)
        return
      end
      local result = vim.trim(res.text or '')
      if result ~= '' then callback(result) end
    end,
    on_error = function(msg)
      stop()
      vim.notify('claudespace: ' .. msg, vim.log.levels.ERROR)
    end,
  }
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
function M.read_float(lines, title, ft, opts)
  opts = opts or {}
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
  vim.wo[win].linebreak = true   -- wrap at word boundaries, not mid-word
  vim.wo[win].breakindent = true

  -- Start at the end (last line at the bottom of the view) — used for transcripts
  -- where the latest message matters most.
  if opts.at_end then
    pcall(vim.api.nvim_win_set_cursor, win, { #lines, 0 })
    vim.api.nvim_win_call(win, function() vim.cmd 'normal! zb' end)
  end

  local function close() pcall(vim.api.nvim_win_close, win, true) end
  for _, k in ipairs { 'q', '<Esc>', '<CR>' } do
    vim.keymap.set('n', k, close, { buffer = buf, nowait = true })
  end
  return win
end

-- ── Streaming answer float ─────────────────────────────────────────────────────

-- Open a float that fills token-by-token as Claude answers. A 60ms repaint timer
-- decouples redraw rate from token rate (so a long answer isn't O(n²) rewrites).
-- q/Esc closes and stops the job if it's still running.
-- opts: { model?, cwd?, on_done?(res, text) }
function M.stream_float(prompt, title, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'markdown'

  local width  = math.min(math.floor(vim.o.columns * 0.72), 110)
  local height = math.floor(vim.o.lines * 0.6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines  - height) / 2),
    title = title or ' Claude ', title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true

  local acc, dirty = '', false
  local function repaint()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(acc, '\n'))
    vim.bo[buf].modifiable = false
    local line = vim.api.nvim_buf_line_count(buf)
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })  -- follow the tail
    end
  end

  local timer = vim.uv.new_timer()
  timer:start(0, 60, vim.schedule_wrap(function()
    if dirty then dirty = false; repaint() end
  end))
  local function stop_timer() pcall(function() timer:stop(); timer:close() end) end

  local runner = require('claudespace.claude.runner')
  local job
  job = runner.run {
    prompt = prompt, model = opts.model, cwd = opts.cwd, partial = true, label = title,
    on_delta  = function(d) acc = acc .. d; dirty = true end,
    on_result = function(res)
      stop_timer()
      if acc == '' then acc = res.text or '' end       -- fallback if no partials
      repaint()
      if opts.on_done then opts.on_done(res, acc) end
    end,
    on_error = function(msg)
      stop_timer()
      acc = acc .. '\n\n[error] ' .. msg
      repaint()
    end,
  }

  local function close()
    stop_timer()
    if job then pcall(vim.fn.jobstop, job) end
    pcall(vim.api.nvim_win_close, win, true)
  end
  for _, k in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', k, close, { buffer = buf, nowait = true })
  end
end

return M
