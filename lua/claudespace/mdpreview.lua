-- In-buffer Markdown preview: concealed markers + coloured decorations via
-- extmarks. No plugins, no browser — the buffer stays editable (markers reveal
-- in insert mode). Toggle with <leader>mp; auto-on for markdown filetypes.
local M = {}

local api = vim.api
local ns  = api.nvim_create_namespace('cs_mdpreview')

local HEAD_ICON = { '󰉫 ', '󰉬 ', '󰉭 ', '󰉮 ', '󰉯 ', '󰉰 ' }

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
end

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
end

-- ── Full-buffer render ────────────────────────────────────────────────────────

local function render(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local in_code = false

  for i, line in ipairs(lines) do
    local row = i - 1

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

    -- headings: hide "### ", colour the text, add a level icon + line bg
    local hashes, htext = line:match('^(#+)%s+(.*)')
    if hashes and htext then
      local lvl = math.min(#hashes, 6)
      local grp = 'CSMdH' .. lvl
      mark(buf, row, 0, #hashes + 1, { conceal = '' })
      api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { HEAD_ICON[lvl], grp } }, virt_text_pos = 'inline',
      })
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

    -- blockquote
    if line:match('^%s*>%s') then
      api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = 'CSMdQuote' })
      goto cont
    end

    -- bullet list: turn "- " / "* " / "+ " into "• "
    local indent, bullet = line:match('^(%s*)([%-%*%+])%s')
    if indent then
      local col = #indent
      mark(buf, row, col, col + #bullet, { conceal = '' })
      api.nvim_buf_set_extmark(buf, ns, row, col, {
        virt_text = { { '•', 'CSMdBullet' } }, virt_text_pos = 'inline',
      })
    end

    inline(buf, row, line)
    ::cont::
  end
end

-- ── Enable / disable / toggle ─────────────────────────────────────────────────

local enabled = {}   -- bufnr -> true

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
end

function M.disable(buf)
  buf = buf or api.nvim_get_current_buf()
  enabled[buf] = nil
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  set_conceal(false)
end

function M.toggle(buf)
  buf = buf or api.nvim_get_current_buf()
  if enabled[buf] then M.disable(buf) else M.enable(buf) end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })

  vim.keymap.set('n', '<leader>mp', function() M.toggle() end,
    { silent = true, desc = 'Markdown preview (toggle)' })

  -- Auto-enable for markdown; re-render on edits (debounced).
  local timer
  api.nvim_create_autocmd('FileType', {
    pattern = { 'markdown', 'md' },
    callback = function(a) M.enable(a.buf) end,
  })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    callback = function(a)
      if not enabled[a.buf] then return end
      if timer then timer:stop() end
      timer = vim.defer_fn(function()
        if enabled[a.buf] then render(a.buf) end
      end, 150)
    end,
  })
  -- Restore conceal when returning to an enabled buffer's window.
  api.nvim_create_autocmd('BufWinEnter', {
    callback = function(a) if enabled[a.buf] then set_conceal(true) end end,
  })
end

return M
