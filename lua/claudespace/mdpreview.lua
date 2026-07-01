-- In-buffer Markdown preview: concealed markers + coloured decorations via
-- extmarks. No plugins, no browser — the buffer stays editable (markers reveal
-- in insert mode). Toggle with <leader>mp; auto-on for markdown filetypes.
local M = {}

local api = vim.api
local ns  = api.nvim_create_namespace('cs_mdpreview')

local HEAD_ICON = { '󰉫 ', '󰉬 ', '󰉭 ', '󰉮 ', '󰉯 ', '󰉰 ' }

-- Fold level per line for <details> bodies (v:lua.CSMdFold foldexpr reads it).
local fold_levels = {}   -- bufnr -> { [lnum] = level string }
local has_details  = {}  -- bufnr -> bool

function _G.CSMdFold()
  local t = fold_levels[api.nvim_get_current_buf()]
  return (t and t[vim.v.lnum]) or '0'
end

local function setup_highlights()
  local hi = api.nvim_set_hl
  hi(0, 'CSMdH1', { fg = '#7aa2f7', bold = true })
  hi(0, 'CSMdH2', { fg = '#7dcfff', bold = true })
  hi(0, 'CSMdH3', { fg = '#9ece6a', bold = true })
  hi(0, 'CSMdH4', { fg = '#e0af68', bold = true })
  hi(0, 'CSMdH5', { fg = '#bb9af7', bold = true })
  hi(0, 'CSMdH6', { fg = '#f7768e', bold = true })
  hi(0, 'CSMdCodeBg',     { bg = '#1b1d2b' })
  hi(0, 'CSMdCodeFence',  { fg = '#414868' })
  hi(0, 'CSMdInlineCode', { fg = '#bb9af7', bg = '#1f2233' })
  hi(0, 'CSMdBold',       { bold = true, fg = '#c0caf5' })
  hi(0, 'CSMdItalic',     { italic = true })
  hi(0, 'CSMdBullet',     { fg = '#7dcfff' })
  hi(0, 'CSMdRule',       { fg = '#414868' })
  hi(0, 'CSMdQuote',      { fg = '#565f89', italic = true })
  hi(0, 'CSMdCheckOn',    { fg = '#9ece6a' })
  hi(0, 'CSMdCheckOff',   { fg = '#565f89' })
  hi(0, 'CSMdLink',       { fg = '#7dcfff', underline = true })
  hi(0, 'CSMdNote',    { fg = '#7aa2f7', bold = true })
  hi(0, 'CSMdTip',     { fg = '#9ece6a', bold = true })
  hi(0, 'CSMdWarn',    { fg = '#e0af68', bold = true })
  hi(0, 'CSMdCaution', { fg = '#f7768e', bold = true })
  hi(0, 'CSMdTablePipe', { fg = '#3d59a1' })
end

-- GitHub callouts: > [!NOTE] etc.
local CALLOUT = {
  NOTE      = { hl = 'CSMdNote',    icon = '󰋽 ' },
  TIP       = { hl = 'CSMdTip',     icon = '󰌶 ' },
  IMPORTANT = { hl = 'CSMdNote',    icon = '󰅾 ' },
  WARNING   = { hl = 'CSMdWarn',    icon = ' ' },
  CAUTION   = { hl = 'CSMdCaution', icon = '󰳦 ' },
}
local BULLETS = { '•', '◦', '▪', '‣' }

-- ── Inline decorations (bold / italic / inline code) ──────────────────────────

-- Conceal a byte range [s,e) on `row` and optionally colour it.
local function mark(buf, row, s, e, opts)
  pcall(api.nvim_buf_set_extmark, buf, ns, row, s,
    vim.tbl_extend('force', { end_col = e }, opts or {}))
end

local function inline(buf, row, line)
  -- inline code `code`
  local init = 1
  while true do
    local s, e = line:find('`([^`\n]+)`', init)
    if not s then break end
    mark(buf, row, s - 1, s, { conceal = '' })
    mark(buf, row, e - 1, e, { conceal = '' })
    mark(buf, row, s, e - 1, { hl_group = 'CSMdInlineCode' })
    init = e + 1
  end
  -- bold **text**
  init = 1
  while true do
    local s, e = line:find('%*%*([^%*\n]+)%*%*', init)
    if not s then break end
    mark(buf, row, s - 1, s + 1, { conceal = '' })
    mark(buf, row, e - 2, e, { conceal = '' })
    mark(buf, row, s + 1, e - 2, { hl_group = 'CSMdBold' })
    init = e + 1
  end
  -- HTML bold <b>text</b>
  init = 1
  while true do
    local s, e = line:find('<b>(.-)</b>', init)
    if not s then break end
    mark(buf, row, s - 1, s - 1 + 3, { conceal = '' })   -- <b>
    mark(buf, row, e - 4, e, { conceal = '' })           -- </b>
    mark(buf, row, s - 1 + 3, e - 4, { hl_group = 'CSMdBold' })
    init = e + 1
  end
  -- italic *text* or _text_
  for _, pat in ipairs { '%f[%*]%*([^%*\n]+)%*%f[^%*]', '%f[_]_([^_\n]+)_%f[^_]' } do
    init = 1
    while true do
      local s, e = line:find(pat, init)
      if not s then break end
      mark(buf, row, s - 1, s, { conceal = '' })
      mark(buf, row, e - 1, e, { conceal = '' })
      mark(buf, row, s, e - 1, { hl_group = 'CSMdItalic' })
      init = e + 1
    end
  end
  -- links [text](url): keep text, hide the URL
  init = 1
  while true do
    local s, e = line:find('%[([^%]\n]+)%]%(([^%)\n]+)%)', init)
    if not s then break end
    local mid = line:find(']%(', s)   -- index of ']'
    mark(buf, row, s - 1, s, { conceal = '' })            -- [
    mark(buf, row, s, mid - 1, { hl_group = 'CSMdLink' }) -- text
    mark(buf, row, mid - 1, e, { conceal = '' })          -- ](url)
    init = e + 1
  end
end

-- ── Full-buffer render ────────────────────────────────────────────────────────

local function render(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local in_code = false
  local in_details = false
  local hdepth = 0        -- current heading nesting depth (for fold levels)
  local levels = {}       -- lnum -> fold level string
  has_details[buf] = false

  for i, line in ipairs(lines) do
    local row = i - 1
    -- default: section depth, one deeper inside a <details> body
    levels[i] = tostring(in_details and (hdepth + 1) or hdepth)

    -- fenced code block boundaries + body
    if line:match('^%s*```') then
      in_code = not in_code
      mark(buf, row, 0, #line, { conceal = '', hl_group = 'CSMdCodeFence' })
      api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = 'CSMdCodeBg' })
      goto cont
    end
    if in_code then
      api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = 'CSMdCodeBg' })
      goto cont
    end

    -- <details> / </details>: hide the tag; the body between summary and
    -- </details> becomes a fold (collapsible like on GitHub).
    if line:match('^%s*<details>%s*$') then
      has_details[buf] = true
      levels[i] = tostring(hdepth)
      mark(buf, row, 0, #line, { conceal = '' })
      goto cont
    end
    if line:match('^%s*</details>%s*$') then
      levels[i] = tostring(in_details and (hdepth + 1) or hdepth)
      in_details = false
      mark(buf, row, 0, #line, { conceal = '' })
      goto cont
    end
    -- <summary>...</summary>: disclosure marker, hidden tags, bold inner
    local sinner = line:match('^%s*<summary>(.-)</summary>%s*$')
    if sinner then
      in_details = true
      levels[i] = tostring(hdepth)   -- summary stays visible above the fold
      local lead = #(line:match('^%s*'))
      local so = line:find('<summary>', 1, true)
      local eo = line:find('</summary>', 1, true)
      mark(buf, row, so - 1, so - 1 + #'<summary>', { conceal = '' })
      mark(buf, row, eo - 1, eo - 1 + #'</summary>', { conceal = '' })
      api.nvim_buf_set_extmark(buf, ns, row, lead, {
        virt_text = { { '▸ ', 'CSMdBullet' } }, virt_text_pos = 'inline',
      })
      inline(buf, row, line)   -- render <b>..</b> inside
      goto cont
    end

    -- headings: hide "### ", colour the text, add a level icon + breathing room
    local hashes, htext = line:match('^(#+)%s+(.*)')
    if hashes and htext then
      local lvl = math.min(#hashes, 6)
      local grp = 'CSMdH' .. lvl
      levels[i] = '>' .. lvl        -- heading starts a fold at its level
      hdepth = lvl
      has_details[buf] = true       -- enable foldexpr for heading folds
      mark(buf, row, 0, #hashes + 1, { conceal = '' })
      api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { HEAD_ICON[lvl], grp } }, virt_text_pos = 'inline',
      })
      if row > 0 then   -- breathing room: a blank virtual line above the heading
        api.nvim_buf_set_extmark(buf, ns, row, 0,
          { virt_lines = { { { '', grp } } }, virt_lines_above = true })
      end
      mark(buf, row, #hashes + 1, #line, { hl_group = grp })
      goto cont
    end

    -- horizontal rule: --- / *** / ___
    if line:match('^%s*[%-%*_][%s%-%*_]*$') and #line:gsub('%s', '') >= 3
       and line:match('^%s*([%-%*_])%1%1') then
      api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { string.rep('─', 60), 'CSMdRule' } },
        virt_text_pos = 'overlay',
      })
      goto cont
    end

    -- callout: > [!NOTE] / [!TIP] / [!WARNING] / [!IMPORTANT] / [!CAUTION]
    local ckind = line:match('^%s*>%s*%[!(%u+)%]')
    if ckind and CALLOUT[ckind] then
      local c = CALLOUT[ckind]
      local q = line:find('>', 1, true)
      mark(buf, row, q - 1, #line, { conceal = '' })   -- hide "> [!NOTE]"
      api.nvim_buf_set_extmark(buf, ns, row, q - 1, {
        virt_text = { { c.icon .. ckind, c.hl } }, virt_text_pos = 'inline',
        line_hl_group = c.hl,
      })
      goto cont
    end

    -- table rows: | a | b |  → box pipes, header bold, separator as a border
    if line:match('^%s*|.*|%s*$') then
      if line:match('^%s*|[%s%-:|]+|%s*$') then
        local bord = (line:gsub('[^|]', '─'):gsub('|', '┼'))
        mark(buf, row, 0, #line, { conceal = '' })
        api.nvim_buf_set_extmark(buf, ns, row, 0, {
          virt_text = { { bord, 'CSMdTablePipe' } }, virt_text_pos = 'overlay',
        })
        goto cont
      end
      local is_header = lines[i + 1] and lines[i + 1]:match('^%s*|[%s%-:|]+|%s*$')
      if is_header then mark(buf, row, 0, #line, { hl_group = 'CSMdBold' }) end
      local col = 1
      while true do
        local p = line:find('|', col, true)
        if not p then break end
        mark(buf, row, p - 1, p, { conceal = '' })
        api.nvim_buf_set_extmark(buf, ns, row, p - 1, {
          virt_text = { { '│', 'CSMdTablePipe' } }, virt_text_pos = 'inline',
        })
        col = p + 1
      end
      inline(buf, row, line)
      goto cont
    end

    -- blockquote
    if line:match('^%s*>%s') then
      api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = 'CSMdQuote' })
      goto cont
    end

    -- checkbox: - [ ] / - [x]
    local cb_ind, cb_mark = line:match('^(%s*)[%-%*%+]%s%[([ xX])%]%s')
    if cb_ind then
      local col = #cb_ind
      local endc = line:find('%]', col) + 1   -- through "] "
      mark(buf, row, col, endc, { conceal = '' })
      local on = cb_mark:lower() == 'x'
      api.nvim_buf_set_extmark(buf, ns, row, col, {
        virt_text = { { on and '󰄲 ' or '󰄱 ', on and 'CSMdCheckOn' or 'CSMdCheckOff' } },
        virt_text_pos = 'inline',
      })
      inline(buf, row, line)
      goto cont
    end

    -- bullet list: nested bullet by indent depth (•/◦/▪/‣)
    local indent, bullet = line:match('^(%s*)([%-%*%+])%s')
    if indent then
      local col   = #indent
      local depth = math.floor(col / 2) % #BULLETS + 1
      mark(buf, row, col, col + #bullet, { conceal = '' })
      api.nvim_buf_set_extmark(buf, ns, row, col, {
        virt_text = { { BULLETS[depth], 'CSMdBullet' } }, virt_text_pos = 'inline',
      })
    end

    inline(buf, row, line)
    ::cont::
  end

  fold_levels[buf] = levels
end

-- ── Enable / disable / toggle ─────────────────────────────────────────────────

local enabled = {}   -- bufnr -> true
local saved   = {}   -- bufnr -> { fm, fe } saved fold settings

-- Turn <details> bodies into folds via a scoped foldexpr (restored on disable).
local function apply_folds(buf)
  if has_details[buf] then
    if not saved[buf] then   -- set once; fold_levels updates keep it fresh
      saved[buf] = { fm = vim.wo.foldmethod, fe = vim.wo.foldexpr }
      vim.wo.foldmethod = 'expr'
      vim.wo.foldexpr   = 'v:lua.CSMdFold()'
    end
  elseif saved[buf] then
    vim.wo.foldmethod = saved[buf].fm
    vim.wo.foldexpr   = saved[buf].fe
    saved[buf] = nil
  end
end

local function set_conceal(on)
  if on then
    vim.wo.conceallevel = 2
    vim.wo.concealcursor = 'nc'   -- reveal markers only while editing the line
  else
    vim.wo.conceallevel = 0
  end
end

function M.enable(buf)
  buf = buf or api.nvim_get_current_buf()
  enabled[buf] = true
  set_conceal(true)
  render(buf)
  apply_folds(buf)
end

function M.disable(buf)
  buf = buf or api.nvim_get_current_buf()
  enabled[buf] = nil
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  set_conceal(false)
  has_details[buf] = false
  apply_folds(buf)   -- restores foldmethod
end

function M.toggle(buf)
  buf = buf or api.nvim_get_current_buf()
  if enabled[buf] then M.disable(buf) else M.enable(buf) end
end

-- ── Heading navigation & TOC ──────────────────────────────────────────────────

local function headings(buf)
  local out = {}
  for i, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local h, t = l:match('^(#+)%s+(.*)')
    if h then out[#out + 1] = { lnum = i, level = #h, text = t } end
  end
  return out
end

function M.goto_heading(dir)
  local cur = api.nvim_win_get_cursor(0)[1]
  local hs  = headings(api.nvim_get_current_buf())
  local target
  if dir > 0 then
    for _, h in ipairs(hs) do if h.lnum > cur then target = h.lnum; break end end
  else
    for i = #hs, 1, -1 do if hs[i].lnum < cur then target = hs[i].lnum; break end end
  end
  if target then api.nvim_win_set_cursor(0, { target, 0 }); vim.cmd 'normal! zz' end
end

function M.toc()
  local hs = headings(api.nvim_get_current_buf())
  if #hs == 0 then vim.notify('No headings in this file', vim.log.levels.INFO); return end
  local function label(h) return ('  '):rep(h.level - 1) .. h.text end
  local function jump(h) api.nvim_win_set_cursor(0, { h.lnum, 0 }); vim.cmd 'normal! zz' end

  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(hs, { prompt = 'TOC', format_item = label },
      function(h) if h then jump(h) end end)
    return
  end
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local astate       = require('telescope.actions.state')
  pickers.new({}, {
    prompt_title = 'Table of contents',
    finder = finders.new_table {
      results = hs,
      entry_maker = function(h)
        return { value = h, display = label(h), ordinal = h.text, lnum = h.lnum }
      end,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(pb)
      actions.select_default:replace(function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then jump(e.value) end
      end)
      return true
    end,
  }):find()
end

-- ── Yank the fenced code block under the cursor ───────────────────────────────

function M.yank_code()
  local buf   = api.nvim_get_current_buf()
  local cur   = api.nvim_win_get_cursor(0)[1]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local top
  for i = cur, 1, -1 do if lines[i]:match('^%s*```') then top = i; break end end
  if not top then vim.notify('Not inside a code block', vim.log.levels.INFO); return end
  local bot
  for i = top + 1, #lines do if lines[i]:match('^%s*```') then bot = i; break end end
  if not bot then return end
  local body = {}
  for i = top + 1, bot - 1 do body[#body + 1] = lines[i] end
  vim.fn.setreg('+', table.concat(body, '\n'))
  vim.notify(('Yanked %d line(s) of code'):format(#body), vim.log.levels.INFO)
end

-- ── Focus mode: dim everything but the current section ────────────────────────

local focus_ns = api.nvim_create_namespace('cs_mdfocus')
local focus_on = {}   -- bufnr -> true

local function apply_focus(buf)
  api.nvim_buf_clear_namespace(buf, focus_ns, 0, -1)
  if not focus_on[buf] then return end
  local cur   = api.nvim_win_get_cursor(0)[1]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local top, bot = 1, #lines
  for i = cur, 1, -1 do if lines[i]:match('^#+%s') then top = i; break end end
  for i = cur + 1, #lines do if lines[i]:match('^#+%s') then bot = i - 1; break end end
  for i = 1, #lines do
    if (i < top or i > bot) and #lines[i] > 0 then
      pcall(api.nvim_buf_set_extmark, buf, focus_ns, i - 1, 0, {
        end_col = #lines[i], hl_group = 'CSMdDim', priority = 200, hl_eol = true,
      })
    end
  end
end

function M.focus_toggle(buf)
  buf = buf or api.nvim_get_current_buf()
  focus_on[buf] = not focus_on[buf] or nil
  apply_focus(buf)
  vim.notify('Focus mode ' .. (focus_on[buf] and 'on' or 'off'), vim.log.levels.INFO)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  setup_highlights()
  api.nvim_set_hl(0, 'CSMdDim', { fg = '#3b4261' })
  api.nvim_create_autocmd('ColorScheme', { callback = function()
    setup_highlights(); api.nvim_set_hl(0, 'CSMdDim', { fg = '#3b4261' })
  end })

  api.nvim_create_autocmd('CursorMoved', {
    callback = function(a) if focus_on[a.buf] then apply_focus(a.buf) end end,
  })

  vim.keymap.set('n', '<leader>mp', function() M.toggle() end,
    { silent = true, desc = 'Markdown preview (toggle)' })

  -- Auto-enable for markdown; wire buffer-local heading nav + TOC.
  local timer
  api.nvim_create_autocmd('FileType', {
    pattern = { 'markdown', 'md' },
    callback = function(a)
      M.enable(a.buf)
      local o = { buffer = a.buf, silent = true }
      vim.keymap.set('n', ']]', function() M.goto_heading(1) end,
        vim.tbl_extend('force', o, { desc = 'Next heading' }))
      vim.keymap.set('n', '[[', function() M.goto_heading(-1) end,
        vim.tbl_extend('force', o, { desc = 'Prev heading' }))
      vim.keymap.set('n', '<leader>mf', function() M.focus_toggle(a.buf) end,
        vim.tbl_extend('force', o, { desc = 'Markdown: focus current section' }))
      vim.keymap.set('n', 'yc', M.yank_code,
        vim.tbl_extend('force', o, { desc = 'Yank code block' }))
    end,
  })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    callback = function(a)
      if not enabled[a.buf] then return end
      if timer then timer:stop() end
      timer = vim.defer_fn(function()
        if enabled[a.buf] then render(a.buf); apply_folds(a.buf) end
      end, 150)
    end,
  })
  -- Restore conceal when returning to an enabled buffer's window.
  api.nvim_create_autocmd('BufWinEnter', {
    callback = function(a) if enabled[a.buf] then set_conceal(true) end end,
  })
end

return M
