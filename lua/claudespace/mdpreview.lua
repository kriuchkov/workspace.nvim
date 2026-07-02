-- In-buffer Markdown preview: concealed markers + coloured decorations via
-- extmarks. No plugins, no browser — the buffer stays editable (markers reveal
-- in insert mode). Toggle with <leader>mp; auto-on for markdown filetypes.
local M = {}

local api = vim.api
local fn  = vim.fn
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
  local c  = require('claudespace.theme').colors()
  hi(0, 'CSMdH1', { fg = c.blue, bold = true })
  hi(0, 'CSMdH2', { fg = c.cyan, bold = true })
  hi(0, 'CSMdH3', { fg = c.green, bold = true })
  hi(0, 'CSMdH4', { fg = c.yellow, bold = true })
  hi(0, 'CSMdH5', { fg = c.purple, bold = true })
  hi(0, 'CSMdH6', { fg = c.red, bold = true })
  hi(0, 'CSMdCodeBg',     { bg = c.bg_alt })
  hi(0, 'CSMdCodeFence',  { fg = c.fg_dim })
  hi(0, 'CSMdInlineCode', { fg = c.purple, bg = c.bg_alt })
  hi(0, 'CSMdBold',       { bold = true, fg = c.fg })
  hi(0, 'CSMdItalic',     { italic = true })
  hi(0, 'CSMdBullet',     { fg = c.cyan })
  hi(0, 'CSMdRule',       { fg = c.fg_dim })
  hi(0, 'CSMdQuote',      { fg = c.fg_dim, italic = true })
  hi(0, 'CSMdCheckOn',    { fg = c.green })
  hi(0, 'CSMdCheckOff',   { fg = c.fg_dim })
  hi(0, 'CSMdLink',       { fg = c.cyan, underline = true })
  hi(0, 'CSMdNote',    { fg = c.blue, bold = true })
  hi(0, 'CSMdTip',     { fg = c.green, bold = true })
  hi(0, 'CSMdWarn',    { fg = c.warn, bold = true })
  hi(0, 'CSMdCaution', { fg = c.red, bold = true })
  hi(0, 'CSMdTablePipe', { fg = c.blue })
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

-- ── Tables: align columns to their widest cell ────────────────────────────────

local function is_table_row(l) return l ~= nil and l:match('^%s*|.*|%s*$') ~= nil end
local function is_sep_row(l)   return l ~= nil and l:match('^%s*|[%s%-:|]+|%s*$') ~= nil end

local function pipe_pos(line)
  local pos, c = {}, 1
  while true do local p = line:find('|', c, true); if not p then break end; pos[#pos + 1] = p; c = p + 1 end
  return pos
end

-- Displayed width of a cell after inline() hides link URLs and **/`` markers
-- (padding must match what is actually shown, or the columns drift).
local function cell_width(s)
  s = s:gsub('%[([^%]\n]+)%]%([^%)\n]+%)', '%1')  -- [text](url) → text
  s = s:gsub('%*%*([^%*\n]+)%*%*', '%1')            -- **bold** → bold
  s = s:gsub('`([^`\n]+)`', '%1')                    -- `code` → code
  return vim.fn.strdisplaywidth(s)
end

-- Render contiguous table blocks with padded columns; mark their rows handled.
local function render_tables(buf, lines, handled)
  local i, in_code = 1, false
  while i <= #lines do
    if lines[i]:match('^%s*```') then in_code = not in_code; i = i + 1; goto next end
    if in_code or not is_table_row(lines[i]) or is_sep_row(lines[i]) then i = i + 1; goto next end

    local a = i
    local b = i
    while b + 1 <= #lines and is_table_row(lines[b + 1]) do b = b + 1 end

    -- widest raw cell per column
    local widths = {}
    for r = a, b do
      if not is_sep_row(lines[r]) then
        local p = pipe_pos(lines[r])
        for k = 1, #p - 1 do
          local w = cell_width(lines[r]:sub(p[k] + 1, p[k + 1] - 1))
          widths[k] = math.max(widths[k] or 0, w)
        end
      end
    end

    for r = a, b do
      handled[r] = true
      local row, ln = r - 1, lines[r]
      if is_sep_row(ln) then
        local bord = '┼'
        for k = 1, #widths do bord = bord .. string.rep('─', widths[k]) .. '┼' end
        mark(buf, row, 0, #ln, { conceal = '' })
        api.nvim_buf_set_extmark(buf, ns, row, 0,
          { virt_text = { { bord, 'CSMdTablePipe' } }, virt_text_pos = 'inline' })
      else
        if r == a then mark(buf, row, 0, #ln, { hl_group = 'CSMdBold' }) end
        local p = pipe_pos(ln)
        for k = 1, #p do
          local pad = ''
          if k >= 2 then
            local w = cell_width(ln:sub(p[k - 1] + 1, p[k] - 1))
            pad = string.rep(' ', math.max(0, (widths[k - 1] or 0) - w))
          end
          mark(buf, row, p[k] - 1, p[k], { conceal = '' })
          api.nvim_buf_set_extmark(buf, ns, row, p[k] - 1,
            { virt_text = { { pad .. '│', 'CSMdTablePipe' } }, virt_text_pos = 'inline' })
        end
        inline(buf, row, ln)
      end
    end
    i = b + 1
    ::next::
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

  local handled = {}      -- rows already decorated (tables)
  render_tables(buf, lines, handled)

  for i, line in ipairs(lines) do
    local row = i - 1
    -- default: section depth, one deeper inside a <details> body
    levels[i] = tostring(in_details and (hdepth + 1) or hdepth)
    if handled[i] then goto cont end

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

-- ── Link navigation ───────────────────────────────────────────────────────────

-- Every [text](target) link in the buffer, in document order. s/e are 1-based
-- byte columns of '[' and ')'.
local function links(buf)
  local out = {}
  for i, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local init = 1
    while true do
      local s, e, text, target = l:find('%[([^%]\n]+)%]%(([^%)\n]+)%)', init)
      if not s then break end
      out[#out + 1] = { lnum = i, s = s, e = e, text = text, target = target }
      init = e + 1
    end
  end
  return out
end

local function slugify(text)
  return text:lower():gsub('[^%w%s-]', ''):gsub('%s+', '-')
end

-- Jump the cursor to the next/prev link (wraps around).
function M.goto_link(dir)
  local buf = api.nvim_get_current_buf()
  local ls  = links(buf)
  if #ls == 0 then vim.notify('No links in this file', vim.log.levels.INFO); return end
  local pos = api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2] + 1
  local target
  if dir > 0 then
    for _, lk in ipairs(ls) do
      if lk.lnum > row or (lk.lnum == row and lk.s > col) then target = lk; break end
    end
    target = target or ls[1]
  else
    for i = #ls, 1, -1 do
      local lk = ls[i]
      if lk.lnum < row or (lk.lnum == row and lk.s < col) then target = lk; break end
    end
    target = target or ls[#ls]
  end
  api.nvim_win_set_cursor(0, { target.lnum, target.s })   -- land on the visible text
  vim.cmd 'normal! zz'
end

-- Resolve a link target: #anchor → heading jump, URL → browser, else a file path
-- (relative to the buffer's dir) opened in the center window (reused if loaded).
function M.open_target(target, buf)
  if target:match('^#') then
    local slug = slugify(target:gsub('^#', ''))
    for _, h in ipairs(headings(buf)) do
      if slugify(h.text) == slug then
        api.nvim_win_set_cursor(0, { h.lnum, 0 }); vim.cmd 'normal! zz'; return
      end
    end
    vim.notify('No heading: ' .. target, vim.log.levels.WARN); return
  end

  -- External link. Only hand safe schemes to the OS opener: a markdown file may
  -- come from an untrusted source (AI output, a cloned repo) and arbitrary URL
  -- schemes can launch apps / handlers on macOS. http(s), mailto and bare www.
  -- cover real docs; anything else is surfaced instead of opened.
  if target:match('^https?://') or target:match('^mailto:') or target:match('^www%.') then
    local url = target:match('^www%.') and ('https://' .. target) or target
    local ok = pcall(vim.ui.open, url)   -- argv-based, no shell interpolation
    if not ok then fn.jobstart({ 'open', url }) end
    return
  end
  if target:match('^%a[%w+.-]*:') then
    vim.notify('Refusing to open scheme: ' .. target, vim.log.levels.WARN)
    return
  end

  local path, anchor = target:match('^([^#]*)#?(.*)$')
  if not path or path == '' then return end
  path = path:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
  if not path:match('^/') then
    path = fn.fnamemodify(api.nvim_buf_get_name(buf), ':h') .. '/' .. path
  end
  path = fn.fnamemodify(path, ':p')
  if fn.filereadable(path) == 0 and fn.isdirectory(path) == 0
     and fn.filereadable(path .. '.md') == 1 then
    path = path .. '.md'
  end
  if fn.filereadable(path) == 0 and fn.isdirectory(path) == 0 then
    vim.notify('Not found: ' .. path, vim.log.levels.WARN); return
  end

  local ok, shell = pcall(require, 'claudespace.shell')
  if ok then pcall(api.nvim_set_current_win, shell.center()) end
  vim.cmd('edit ' .. fn.fnameescape(path))
  if anchor and anchor ~= '' then
    M.open_target('#' .. anchor, api.nvim_get_current_buf())
  end
end

-- Follow the link under the cursor (or the next one on the line).
function M.follow_link()
  local buf = api.nvim_get_current_buf()
  local pos = api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2] + 1
  local best
  for _, lk in ipairs(links(buf)) do
    if lk.lnum == row then
      if col >= lk.s and col <= lk.e then best = lk; break end
      if not best and lk.s >= col then best = lk end
    end
  end
  if not best then vim.notify('No link under cursor', vim.log.levels.INFO); return end
  M.open_target(best.target, buf)
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

local function apply_hls()
  setup_highlights()
  api.nvim_set_hl(0, 'CSMdDim', { fg = require('claudespace.theme').colors().fg_faint })
end

function M.setup()
  apply_hls()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = apply_hls })

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
      vim.keymap.set('n', ']l', function() M.goto_link(1) end,
        vim.tbl_extend('force', o, { desc = 'Next link' }))
      vim.keymap.set('n', '[l', function() M.goto_link(-1) end,
        vim.tbl_extend('force', o, { desc = 'Prev link' }))
      vim.keymap.set('n', '<CR>', M.follow_link,
        vim.tbl_extend('force', o, { desc = 'Follow link' }))
      vim.keymap.set('n', 'gx', M.follow_link,
        vim.tbl_extend('force', o, { desc = 'Follow link (url/file)' }))
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
