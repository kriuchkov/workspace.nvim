-- Markdown TOC: a right-side outline panel of the document's headings.
-- <CR>/click jumps to a heading; the panel tracks the cursor's section.
local M = {}

local api = vim.api
local ns  = api.nvim_create_namespace('cs_mdtoc')

local S = {
  win = nil, buf = nil,
  source_win = nil, source_buf = nil,
  items = {},      -- { lnum, level, text }
  line_map = {},   -- panel line -> item
}

local LEVEL_HL = { 'CSMdH1', 'CSMdH2', 'CSMdH3', 'CSMdH4', 'CSMdH5', 'CSMdH6' }

local function is_md(buf)
  local ft = vim.bo[buf].filetype
  return ft == 'markdown' or ft == 'md'
end

-- ── Collect headings (skipping fenced code) ───────────────────────────────────

local function collect(buf)
  local out, in_code = {}, false
  for i, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match('^%s*```') then
      in_code = not in_code
    elseif not in_code then
      local h, t = l:match('^(#+)%s+(.*)')
      if h then out[#out + 1] = { lnum = i, level = #h, text = t } end
    end
  end
  return out
end

-- ── Render ────────────────────────────────────────────────────────────────────

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  if not (S.source_buf and api.nvim_buf_is_valid(S.source_buf)) then return end
  S.items = collect(S.source_buf)

  local lines, hls, map = {}, {}, {}
  if #S.items == 0 then
    lines = { '', '  (no headings)' }
  else
    for _, it in ipairs(S.items) do
      lines[#lines + 1] = ' ' .. string.rep('  ', it.level - 1) .. it.text
      map[#lines] = it
      hls[#hls + 1] = { #lines - 1, 0, -1, LEVEL_HL[math.min(it.level, 6)] }
    end
  end
  S.line_map = map

  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do api.nvim_buf_add_highlight(S.buf, ns, h[4], h[1], h[2], h[3]) end
  M.sync_cursor()
end

-- Move the panel cursor onto the section that contains the source cursor.
function M.sync_cursor()
  if not (S.win and api.nvim_win_is_valid(S.win)) then return end
  if not (S.source_win and api.nvim_win_is_valid(S.source_win)) then return end
  local cur = api.nvim_win_get_cursor(S.source_win)[1]
  local best
  for line, it in pairs(S.line_map) do
    if it.lnum <= cur and (not best or it.lnum > S.line_map[best].lnum) then best = line end
  end
  if best then pcall(api.nvim_win_set_cursor, S.win, { best, 0 }) end
end

-- ── Jump ──────────────────────────────────────────────────────────────────────

-- Item under the panel cursor.
local function item_here()
  return S.line_map[api.nvim_win_get_cursor(S.win)[1]]
end

-- Scroll the source to the heading under the panel cursor, keeping focus in the
-- panel (live preview while moving with j/k).
local function preview()
  local it = item_here()
  if not (it and S.source_win and api.nvim_win_is_valid(S.source_win)) then return end
  pcall(api.nvim_win_set_cursor, S.source_win, { it.lnum, 0 })
  api.nvim_win_call(S.source_win, function() vim.cmd 'normal! zz' end)
end

-- <CR>: jump to the heading and move focus into the source window.
local function jump()
  local it = item_here()
  if not (it and S.source_win and api.nvim_win_is_valid(S.source_win)) then return end
  api.nvim_set_current_win(S.source_win)
  pcall(api.nvim_win_set_cursor, S.source_win, { it.lnum, 0 })
  vim.cmd 'normal! zz'
end

-- ── Window ────────────────────────────────────────────────────────────────────

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'cs_mdtoc'
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', jump, o)
  vim.keymap.set('n', '<LeftRelease>', jump, o)
  vim.keymap.set('n', 'q', M.close, o)
  vim.keymap.set('n', '<Esc>', M.close, o)
  return buf
end

function M.open(anchor_win)
  if not is_md(api.nvim_get_current_buf()) then
    vim.notify('Not a markdown buffer', vim.log.levels.WARN); return
  end
  S.source_win = api.nvim_get_current_win()
  S.source_buf = api.nvim_get_current_buf()

  if S.win and api.nvim_win_is_valid(S.win) then render(); return end
  S.buf = create_buf()
  if anchor_win and api.nvim_win_is_valid(anchor_win) then
    api.nvim_set_current_win(anchor_win); vim.cmd 'rightbelow vsplit'
  else
    vim.cmd 'botright vsplit'
  end
  S.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.win, S.buf)
  api.nvim_win_set_width(S.win, 36)
  local wo = vim.wo[S.win]
  wo.number = false; wo.relativenumber = false; wo.signcolumn = 'no'
  wo.wrap = false; wo.cursorline = true; wo.winfixwidth = true
  wo.winfixbuf = true; wo.winbar = ''
  api.nvim_win_set_var(S.win, 'cs_role', 'panel')

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(S.win), once = true, callback = function() S.win = nil end,
  })
  -- Live preview: moving with j/k in the panel scrolls the source (focus stays).
  api.nvim_create_autocmd('CursorMoved', {
    buffer = S.buf, callback = function() preview() end,
  })
  render()
  -- Focus stays in the panel so j/k navigate the TOC immediately.
end

function M.close()
  if S.win and api.nvim_win_is_valid(S.win) then api.nvim_win_close(S.win, true) end
  S.win = nil
end

function M.toggle()
  if S.win and api.nvim_win_is_valid(S.win) then M.close() else M.open() end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  vim.keymap.set('n', '<leader>mt', M.toggle, { silent = true, desc = 'Markdown: TOC panel (toggle)' })

  api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged' }, {
    callback = function(a)
      if not (S.win and api.nvim_win_is_valid(S.win)) then return end
      if a.buf == S.buf then return end
      if is_md(a.buf) then
        S.source_win = api.nvim_get_current_win()
        S.source_buf = a.buf
        vim.schedule(render)
      end
    end,
  })
  api.nvim_create_autocmd('CursorMoved', {
    callback = function(a)
      if S.win and api.nvim_win_is_valid(S.win) and a.buf == S.source_buf then
        M.sync_cursor()
      end
    end,
  })
end

return M
