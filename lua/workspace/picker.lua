-- Native fuzzy picker: a prompt + results + preview trio of floats. Fuzzy
-- ranking uses Neovim's built-in matchfuzzypos (C, fast); async sources (grep,
-- file listing) run through vim.system. Replaces the common telescope pickers
-- and backs vim.ui.select. No plugin.
--
--   static source:  opts.items = { {text=, ...}, ... }   (or opts.load(cb))
--   dynamic source: opts.dynamic = function(query, cb) -> cancel   (per keystroke)
--   preview:        opts.preview = function(item) -> { lines=, ft=, lnum= }
--   accept:         opts.on_select(item)      cancel: opts.on_cancel()
local M = {}

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop

local P = nil                      -- the one live picker's state
local NS = api.nvim_create_namespace 'cs_picker'

-- ── Windows ───────────────────────────────────────────────────────────────────

local function scratch()
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  return b
end

-- Prompt (top) and results (bottom) share one frame: the prompt's tee'd bottom
-- border acts as the divider, and the results box omits its own top edge.
local B_PROMPT  = { '╭', '─', '╮', '│', '┤', '─', '├', '│' }
local B_RESULTS = { '', '', '', '│', '╯', '─', '╰', '│' }
local BORDER_HL = 'FloatBorder:CSPickerBorder,FloatTitle:CSPickerTitle'

local PNS = api.nvim_create_namespace 'cs_picker_prompt'

local function open_windows(has_preview)
  local W   = math.floor(vim.o.columns * 0.82)
  local H   = math.floor(vim.o.lines * 0.78)
  local row = math.floor((vim.o.lines - H) / 2)
  local col = math.floor((vim.o.columns - W) / 2)

  local list_w = has_preview and math.floor(W * 0.42) or W
  local prev_w = W - list_w - 3

  local function mk(buf, cfg, border, wh)
    cfg.style, cfg.relative, cfg.zindex, cfg.noautocmd, cfg.border = 'minimal', 'editor', 100, true, border
    local w = api.nvim_open_win(buf, false, cfg)
    vim.wo[w].fillchars   = 'eob: '
    vim.wo[w].winhighlight = wh
    return w
  end

  P.prompt_win = mk(P.prompt_buf,
    { row = row, col = col, width = list_w, height = 1, title = ' ' .. P.title .. ' ', title_pos = 'left' },
    B_PROMPT, 'Normal:CSPickerPrompt,' .. BORDER_HL)
  P.list_win = mk(P.list_buf,
    { row = row + 2, col = col, width = list_w, height = math.max(1, H - 2),
      footer = P.hints, footer_pos = 'right' },
    B_RESULTS, 'Normal:CSPickerList,CursorLine:CSPickerSel,' .. BORDER_HL .. ',FloatFooter:CSPickerBorder')
  vim.wo[P.list_win].cursorline = true

  if has_preview then
    P.prev_win = mk(P.prev_buf,
      { row = row, col = col + list_w + 3, width = prev_w, height = H, title = ' Preview ', title_pos = 'left' },
      'rounded', 'Normal:CSPickerPrev,' .. BORDER_HL)
    vim.wo[P.prev_win].wrap = false
  end
end

local function close()
  local p = P
  if not p then return end
  P = nil                    -- first, so a re-entrant WinClosed callback no-ops
  if p.timer then pcall(function() p.timer:stop(); p.timer:close() end) end
  if p.prev_timer then pcall(function() p.prev_timer:stop(); p.prev_timer:close() end) end
  if p.cancel then pcall(p.cancel) end
  for _, w in ipairs { p.prompt_win, p.list_win, p.prev_win } do
    if w and api.nvim_win_is_valid(w) then pcall(api.nvim_win_close, w, true) end
  end
  if api.nvim_get_mode().mode:sub(1, 1) == 'i' then vim.cmd 'stopinsert' end
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

-- The picker name + live match count live in the prompt's top border.
local function set_title()
  if not (P and P.prompt_win and api.nvim_win_is_valid(P.prompt_win)) then return end
  local n = #P.matches
  local shown = n == 0 and 0 or math.min(P.sel, n)
  pcall(api.nvim_win_set_config, P.prompt_win,
    { title = string.format(' %s   %d/%d ', P.title, shown, n), title_pos = 'left' })
end

local function render()
  if not P then return end
  local empty = #P.matches == 0
  local lines = {}
  if empty then
    local hint = (P.dynamic and P.query == '') and 'Type to search…' or 'No matches'
    lines = { '   ' .. hint }
  else
    for i, it in ipairs(P.matches) do
      if i > 500 then break end
      lines[i] = (it.icon and (it.icon .. ' ') or '') .. it.text
    end
  end
  vim.bo[P.list_buf].modifiable = true
  api.nvim_buf_set_lines(P.list_buf, 0, -1, false, lines)
  vim.bo[P.list_buf].modifiable = false

  api.nvim_buf_clear_namespace(P.list_buf, NS, 0, -1)
  if empty then
    pcall(api.nvim_buf_add_highlight, P.list_buf, NS, 'CSPickerHint', 0, 0, -1)
  else
    for i, it in ipairs(P.matches) do
      if i > 500 then break end
      -- Match positions from matchfuzzypos index into it.text; shift past the icon.
      local off = it.icon and (#it.icon + 1) or 0
      if it.icon and it.icon_hl then
        pcall(api.nvim_buf_add_highlight, P.list_buf, NS, it.icon_hl, i - 1, 0, #it.icon)
      end
      if it.pos then
        for _, cpos in ipairs(it.pos) do
          pcall(api.nvim_buf_add_highlight, P.list_buf, NS, 'CSPickerMatch', i - 1, cpos + off, cpos + off + 1)
        end
      end
    end
  end

  if api.nvim_win_is_valid(P.list_win) then
    -- No full-width selection bar on an empty list.
    vim.wo[P.list_win].cursorline = not empty
    P.sel = math.min(math.max(P.sel or 1, 1), math.max(#P.matches, 1))
    pcall(api.nvim_win_set_cursor, P.list_win, { P.sel, 0 })
  end
  set_title()
  M._schedule_preview()
end

function M._schedule_preview()
  if not (P and P.prev_win) then return end
  if not P.prev_timer then P.prev_timer = uv.new_timer() end
  P.prev_timer:stop()
  P.prev_timer:start(50, 0, vim.schedule_wrap(function()
    if not (P and P.prev_win and api.nvim_win_is_valid(P.prev_win)) then return end
    local it = P.matches[P.sel]
    local pv = (it and P.preview) and P.preview(it) or { lines = {} }
    vim.bo[P.prev_buf].modifiable = true
    api.nvim_buf_set_lines(P.prev_buf, 0, -1, false, pv.lines or {})
    vim.bo[P.prev_buf].modifiable = false
    api.nvim_buf_clear_namespace(P.prev_buf, NS, 0, -1)
    pcall(function() vim.bo[P.prev_buf].filetype = pv.ft or '' end)
    local ttl = (it and it.path) and (' ' .. fn.fnamemodify(it.path, ':t') .. ' ') or ' Preview '
    pcall(api.nvim_win_set_config, P.prev_win, { title = ttl, title_pos = 'left' })
    if pv.lnum and pv.lnum > 0 then
      local n = api.nvim_buf_line_count(P.prev_buf)
      local l = math.min(pv.lnum, n)
      pcall(api.nvim_win_set_cursor, P.prev_win, { l, 0 })
      api.nvim_win_call(P.prev_win, function() vim.cmd 'normal! zz' end)
      pcall(api.nvim_buf_add_highlight, P.prev_buf, NS, 'CSPickerPrevLine', l - 1, 0, -1)
    end
  end))
end

-- ── Filtering ─────────────────────────────────────────────────────────────────

local function refilter_static()
  local q = P.query
  if q == '' then
    for _, it in ipairs(P.items) do it.pos = nil end   -- clear stale match highlights
    P.matches = P.items
  else
    -- matchfuzzypos returns a single Vim list: [matched, positions, scores].
    local ok, ret = pcall(fn.matchfuzzypos, P.items, q, { key = 'text' })
    if ok and ret and ret[1] then
      P.matches = ret[1]
      local pos = ret[2] or {}
      for i, it in ipairs(P.matches) do it.pos = pos[i] end
    else
      P.matches = {}
    end
  end
  P.sel = 1
  render()
end

local function run_dynamic()
  local q = P.query
  if P.cancel then pcall(P.cancel); P.cancel = nil end
  P.cancel = P.dynamic(q, vim.schedule_wrap(function(items)
    if not P then return end
    P.matches = items or {}
    P.sel = 1
    render()
  end))
end

local function on_query_change()
  if not P then return end
  local first = api.nvim_buf_get_lines(P.prompt_buf, 0, 1, false)[1] or ''
  P.query = first
  if P.dynamic then
    if not P.timer then P.timer = uv.new_timer() end
    P.timer:stop()
    P.timer:start(120, 0, vim.schedule_wrap(function()
      if P then run_dynamic() end
    end))
  elseif #P.items > 5000 then
    -- Debounce fuzzy ranking over very large lists so fast typing doesn't
    -- re-rank on every keystroke; small lists stay instant.
    if not P.timer then P.timer = uv.new_timer() end
    P.timer:stop()
    P.timer:start(60, 0, vim.schedule_wrap(function()
      if P then refilter_static() end
    end))
  else
    refilter_static()
  end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function move(delta)
  if not P or #P.matches == 0 then return end
  local n = #P.matches
  P.sel = ((P.sel - 1 + delta) % n) + 1   -- wrap around top/bottom
  pcall(api.nvim_win_set_cursor, P.list_win, { P.sel, 0 })
  set_title()
  M._schedule_preview()
end

local function cancel()
  local cb = P and P.on_cancel
  close()
  if cb then vim.schedule(cb) end
end

local function accept()
  local it = P and P.matches[P.sel]
  if not it then return cancel() end   -- <CR> on empty results = cancel
  local cb = P.on_select
  close()
  if cb then vim.schedule(function() cb(it) end) end
end

local function scroll_preview(delta)
  if P and P.prev_win and api.nvim_win_is_valid(P.prev_win) then
    api.nvim_win_call(P.prev_win, function()
      local n = api.nvim_buf_line_count(P.prev_buf)
      local cur = api.nvim_win_get_cursor(P.prev_win)[1]
      pcall(api.nvim_win_set_cursor, P.prev_win, { math.min(math.max(cur + delta, 1), n), 0 })
    end)
  end
end

-- ── Open ──────────────────────────────────────────────────────────────────────

local function wrap_items(list)
  local out = {}
  for i, it in ipairs(list) do
    out[i] = type(it) == 'table' and it or { text = tostring(it) }
  end
  return out
end

function M.open(opts)
  close()
  P = {
    query = '', sel = 1, matches = {}, items = {}, title = opts.title or 'Pick',
    hints = opts.hints or (opts.preview and ' ↵ open · ^n/^p · ^u/^d preview · esc ' or ' ↵ open · ^n/^p · esc '),
    preview = opts.preview, on_select = opts.on_select, on_cancel = opts.on_cancel,
    dynamic = opts.dynamic,
    prompt_buf = scratch(), list_buf = scratch(),
  }
  local has_preview = opts.preview ~= nil
  if has_preview then P.prev_buf = scratch() end
  vim.bo[P.list_buf].modifiable = false

  open_windows(has_preview)

  local o = { buffer = P.prompt_buf, nowait = true, silent = true }
  local map = vim.keymap.set
  map({ 'i', 'n' }, '<CR>',   accept, o)
  map({ 'i', 'n' }, '<Esc>',  cancel, o)
  map({ 'i', 'n' }, '<C-c>',  cancel, o)
  map({ 'i', 'n' }, '<Down>', function() move(1)  end, o)
  map({ 'i', 'n' }, '<Up>',   function() move(-1) end, o)
  map({ 'i', 'n' }, '<C-n>',  function() move(1)  end, o)
  map({ 'i', 'n' }, '<C-p>',  function() move(-1) end, o)
  map({ 'i', 'n' }, '<C-j>',  function() move(1)  end, o)
  map({ 'i', 'n' }, '<C-k>',  function() move(-1) end, o)
  map({ 'i', 'n' }, '<C-d>',  function() scroll_preview(10)  end, o)
  map({ 'i', 'n' }, '<C-u>',  function() scroll_preview(-10) end, o)

  -- Extra per-key actions: run fn(item) after closing the picker.
  for key, fn2 in pairs(opts.actions or {}) do
    map({ 'i', 'n' }, key, function()
      local it = P and P.matches[P.sel]
      close()
      if it then vim.schedule(function() fn2(it) end) end
    end, o)
  end

  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    buffer = P.prompt_buf, callback = on_query_change,
  })
  -- Closing the prompt window (click away, :q) tears the whole picker down.
  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(P.prompt_win), once = true,
    callback = function() if P then cancel() end end,
  })

  api.nvim_set_current_win(P.prompt_win)
  vim.cmd 'startinsert'

  if opts.default_text and opts.default_text ~= '' then
    api.nvim_buf_set_lines(P.prompt_buf, 0, 1, false, { opts.default_text })
    api.nvim_win_set_cursor(P.prompt_win, { 1, #opts.default_text })
  end

  -- Prompt indicator (inline virt text, so it isn't part of the query).
  pcall(api.nvim_buf_set_extmark, P.prompt_buf, PNS, 0, 0,
    { virt_text = { { '❯ ', 'CSPickerPromptIcon' } }, virt_text_pos = 'inline' })

  if opts.items then
    P.items = wrap_items(opts.items)
    refilter_static()
  elseif opts.load then
    opts.load(vim.schedule_wrap(function(list)
      if not P then return end
      P.items = wrap_items(list)
      refilter_static()
    end))
  elseif opts.dynamic then
    on_query_change()
  end
end

-- ── Previews / open helpers ───────────────────────────────────────────────────

local function editor_win()
  local ok, shell = pcall(require, 'workspace.shell')
  if ok and shell.center then return shell.center() end
  return api.nvim_get_current_win()
end

local function edit_file(path, lnum, col)
  if not path then return end
  api.nvim_set_current_win(editor_win())
  vim.cmd('edit ' .. fn.fnameescape(path))
  if lnum then
    pcall(api.nvim_win_set_cursor, 0, { lnum, math.max((col or 1) - 1, 0) })
    vim.cmd 'normal! zz'
  end
end

local function preview_file(item)
  local path = item.path
  if not path or fn.filereadable(path) == 0 then return { lines = { '— no preview —' } } end
  local ok, lines = pcall(fn.readfile, path, '', 500)
  if not ok then return { lines = { '— unreadable —' } } end
  return { lines = lines, ft = vim.filetype.match { filename = path } or '', lnum = item.lnum }
end

-- ── Built-in pickers ──────────────────────────────────────────────────────────

-- File-type glyph via mini.icons (nil if unavailable), for the file pickers.
local mini_icons
local function file_icon(path)
  if mini_icons == nil then
    local ok, m = pcall(require, 'mini.icons')
    mini_icons = ok and m or false
  end
  if not mini_icons then return nil, nil end
  local ok, ic, hl = pcall(mini_icons.get, 'file', fn.fnamemodify(path, ':t'))
  if ok then return ic, hl end
  return nil, nil
end

local function file_cmd()
  if fn.executable 'rg' == 1 then
    return { 'rg', '--files', '--hidden', '--glob', '!.git' }
  elseif fn.executable 'fd' == 1 then
    return { 'fd', '--type', 'f', '--hidden', '--exclude', '.git' }
  end
  return nil
end

function M.files(opts)
  opts = opts or {}
  local cwd = opts.cwd or fn.getcwd()
  local cmd = file_cmd()
  M.open {
    title = opts.title or ('Files · ' .. fn.fnamemodify(cwd, ':t')),
    preview = preview_file,
    on_select = function(it) edit_file(it.path) end,
    load = function(cb)
      if not cmd then
        local list = fn.globpath(cwd, '**/*', false, true)
        local items = {}
        for _, p in ipairs(list) do
          if fn.isdirectory(p) == 0 then items[#items + 1] = { text = fn.fnamemodify(p, ':.'), path = p } end
        end
        cb(items); return
      end
      vim.system(cmd, { text = true, cwd = cwd }, function(res)
        local items = {}
        for line in (res.stdout or ''):gmatch '[^\n]+' do
          local ic, hl = file_icon(line)
          items[#items + 1] = { text = line, path = cwd .. '/' .. line, icon = ic, icon_hl = hl }
        end
        cb(items)
      end)
    end,
  }
end

function M.grep(opts)
  opts = opts or {}
  local cwd = opts.cwd or fn.getcwd()
  M.open {
    title = opts.title or 'Live Grep',
    default_text = opts.default_text,
    preview = preview_file,
    on_select = function(it) edit_file(it.path, it.lnum, it.col) end,
    dynamic = function(query, cb)
      if query == '' then cb {}; return function() end end
      local cmd = { 'rg', '--vimgrep', '--smart-case', '--color=never' }
      vim.list_extend(cmd, opts.rg_args or {})
      cmd[#cmd + 1] = '--'; cmd[#cmd + 1] = query
      local obj = vim.system(cmd, { text = true, cwd = cwd }, function(res)
        local items = {}
        for line in (res.stdout or ''):gmatch '[^\n]+' do
          local f, l, c, t = line:match '^(.-):(%d+):(%d+):(.*)$'
          if f then
            local ic, hl = file_icon(f)
            items[#items + 1] = {
              text = string.format('%s:%s: %s', f, l, t),
              path = cwd .. '/' .. f, lnum = tonumber(l), col = tonumber(c),
              icon = ic, icon_hl = hl,
            }
          end
        end
        cb(items)
      end)
      return function() pcall(function() obj:kill(9) end) end
    end,
  }
end

function M.buffers()
  local items = {}
  for _, b in ipairs(fn.getbufinfo { buflisted = 1 }) do
    if b.name ~= '' then
      local ic, hl = file_icon(b.name)
      items[#items + 1] = { text = fn.fnamemodify(b.name, ':~:.'), path = b.name,
        lnum = b.lnum > 0 and b.lnum or nil, icon = ic, icon_hl = hl }
    end
  end
  M.open { title = 'Buffers', items = items, preview = preview_file,
    on_select = function(it) edit_file(it.path, it.lnum) end }
end

function M.oldfiles()
  local items = {}
  for _, p in ipairs(vim.v.oldfiles or {}) do
    if fn.filereadable(p) == 1 then items[#items + 1] = { text = fn.fnamemodify(p, ':~:.'), path = p } end
  end
  M.open { title = 'Recent Files', items = items, preview = preview_file,
    on_select = function(it) edit_file(it.path) end }
end

function M.help()
  local items = {}
  for _, tag in ipairs(fn.getcompletion('', 'help')) do items[#items + 1] = { text = tag } end
  M.open { title = 'Help', items = items,
    on_select = function(it) vim.cmd('help ' .. it.text) end }
end

-- ── vim.ui.select backend ─────────────────────────────────────────────────────

function M.select(items, opts, on_choice)
  opts = opts or {}
  local fmt = opts.format_item or tostring
  local wrapped = {}
  for i, it in ipairs(items) do wrapped[i] = { text = fmt(it), idx = i } end
  M.open {
    title = opts.prompt or 'Select',
    items = wrapped,
    on_select = function(w) on_choice(items[w.idx], w.idx) end,
    on_cancel = function() on_choice(nil, nil) end,
  }
end

-- ── Highlights ────────────────────────────────────────────────────────────────

local function setup_highlights()
  local ok, theme = pcall(require, 'workspace.theme')
  if not ok then return end
  local c, hi = theme.colors(), api.nvim_set_hl
  hi(0, 'CSPickerPrompt',     { fg = c.fg,     bg = c.bg_dark })
  hi(0, 'CSPickerList',       { fg = c.fg,     bg = c.bg_dark })
  hi(0, 'CSPickerPrev',       { fg = c.fg,     bg = c.bg })
  hi(0, 'CSPickerSel',        { bg = c.bg_sel })
  hi(0, 'CSPickerMatch',      { fg = c.cyan,   bold = true })
  hi(0, 'CSPickerPrevLine',   { bg = c.bg_sel })
  hi(0, 'CSPickerBorder',     { fg = c.fg_dim, bg = c.bg_dark })
  hi(0, 'CSPickerTitle',      { fg = c.cyan,   bg = c.bg_dark, bold = true })
  hi(0, 'CSPickerPromptIcon', { fg = c.green,  bg = c.bg_dark, bold = true })
  hi(0, 'CSPickerHint',       { fg = c.fg_dim, bg = c.bg_dark, italic = true })
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = setup_highlights })
  vim.ui.select = M.select
end

-- Reusable helpers for callers porting their own pickers.
M.file_preview = preview_file
M.open_file    = edit_file

-- test seam
M._picker = function() return P end

return M
