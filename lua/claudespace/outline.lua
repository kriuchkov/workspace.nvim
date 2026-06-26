-- LSP outline panel: symbol tree for the current file, right-side split.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_outline')

local S = {
  win        = nil,
  buf        = nil,
  source_win = nil,
  symbols    = {},   -- flat: { depth, name, kind, lnum, col }
}

-- ── Symbol icons (VSCode-style) ───────────────────────────────────────────────

local ICONS = {
  [1]  = ' ',  -- File
  [2]  = ' ',  -- Module
  [3]  = ' ',  -- Namespace
  [4]  = ' ',  -- Package
  [5]  = ' ',  -- Class
  [6]  = ' ',  -- Method
  [7]  = ' ',  -- Property
  [8]  = ' ',  -- Field
  [9]  = ' ',  -- Constructor
  [10] = ' ',  -- Enum
  [11] = ' ',  -- Interface
  [12] = ' ',  -- Function
  [13] = ' ',  -- Variable
  [14] = ' ',  -- Constant
  [23] = ' ',  -- Struct
}
local ICON_HL = {
  [5]  = 'CSTreeDir',    -- Class  → blue
  [6]  = 'CSGit',        -- Method → yellow
  [9]  = 'CSGit',        -- Constructor
  [12] = 'CSGit',        -- Function
  [14] = 'CSTreeGitAdd', -- Constant → green
}

-- ── Flatten symbol tree ───────────────────────────────────────────────────────

local function flatten(symbols, depth, out)
  depth, out = depth or 0, out or {}
  for _, sym in ipairs(symbols or {}) do
    local range = sym.range or (sym.location and sym.location.range) or {}
    table.insert(out, {
      depth = depth,
      name  = sym.name or '?',
      kind  = sym.kind or 13,
      lnum  = range.start and (range.start.line + 1) or 0,
      col   = range.start and range.start.character or 0,
    })
    if sym.children then flatten(sym.children, depth + 1, out) end
  end
  return out
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  local lines, hls = {}, {}

  if #S.symbols == 0 then
    lines = { '', '  (no symbols)', '  attach LSP or save file' }
  else
    for _, sym in ipairs(S.symbols) do
      local icon = ICONS[sym.kind] or ' '
      local pad  = string.rep('  ', sym.depth)
      table.insert(lines, pad .. icon .. ' ' .. sym.name)
      local ihl = ICON_HL[sym.kind] or 'CSTreeFile'
      table.insert(hls, { #lines - 1, #pad, #pad + #icon + 1, ihl })
    end
  end

  api.nvim_set_option_value('modifiable', true,  { buf = S.buf })
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = S.buf })
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(S.buf, ns, h[4], h[1], h[2], h[3])
  end
end

-- ── LSP request ───────────────────────────────────────────────────────────────

local function request(win)
  if not (win and api.nvim_win_is_valid(win)) then return end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then return end

  local clients = vim.tbl_filter(function(c)
    return c.supports_method('textDocument/documentSymbol')
  end, vim.lsp.get_clients({ bufnr = buf }))

  if #clients == 0 then S.symbols = {}; render(); return end

  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  clients[1].request('textDocument/documentSymbol', params, function(err, result)
    if not (S.win and api.nvim_win_is_valid(S.win)) then return end
    S.symbols = (err or not result) and {} or flatten(result)
    render()
    M.sync_cursor(win)
  end, buf)
end

-- ── Cursor sync ───────────────────────────────────────────────────────────────

function M.sync_cursor(win)
  if not (S.win and api.nvim_win_is_valid(S.win)) then return end
  win = win or S.source_win
  if not (win and api.nvim_win_is_valid(win)) then return end
  local cur = api.nvim_win_get_cursor(win)[1]
  local best = 1
  for i, sym in ipairs(S.symbols) do
    if sym.lnum <= cur then best = i end
  end
  pcall(api.nvim_win_set_cursor, S.win, { best, 0 })
end

-- ── Buffer + window ───────────────────────────────────────────────────────────

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'cs_outline'

  local o = { buffer = buf, nowait = true, silent = true }
  local k = vim.keymap.set

  k('n', '<CR>', function()
    local row = api.nvim_win_get_cursor(S.win)[1]
    local sym = S.symbols[row]
    if not sym then return end
    if S.source_win and api.nvim_win_is_valid(S.source_win) then
      api.nvim_set_current_win(S.source_win)
      pcall(api.nvim_win_set_cursor, S.source_win, { sym.lnum, sym.col })
    end
  end, o)
  k('n', 'l',     function() vim.keymap.get('n', '<CR>', o) end, o)
  k('n', 'r',     function() request(S.source_win) end, o)
  k('n', 'q',     M.close, o)
  k('n', '<Esc>', M.close, o)
  return buf
end

function M.open()
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_set_current_win(S.win)
    return
  end
  S.source_win = api.nvim_get_current_win()
  S.buf        = create_buf()

  vim.cmd 'botright vsplit'
  S.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.win, S.buf)
  api.nvim_win_set_width(S.win, 34)

  local wo = vim.wo[S.win]
  wo.number = false; wo.relativenumber = false
  wo.signcolumn = 'no'; wo.wrap = false
  wo.cursorline = true; wo.winfixwidth = true; wo.winbar = ''

  api.nvim_create_autocmd('WinClosed', {
    pattern  = tostring(S.win),
    once     = true,
    callback = function() S.win = nil end,
  })

  request(S.source_win)
end

function M.close()
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_close(S.win, true)
  end
  S.win = nil
end

function M.toggle()
  if S.win and api.nvim_win_is_valid(S.win) then M.close() else M.open() end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  -- Refresh when entering a new file or saving
  api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
    callback = function()
      if not (S.win and api.nvim_win_is_valid(S.win)) then return end
      local cur = api.nvim_get_current_win()
      if cur ~= S.win then S.source_win = cur; vim.schedule(function() request(S.source_win) end) end
    end,
  })

  -- Cursor tracking
  api.nvim_create_autocmd('CursorMoved', {
    callback = function()
      if not (S.win and api.nvim_win_is_valid(S.win)) then return end
      if api.nvim_get_current_win() ~= S.win then M.sync_cursor() end
    end,
  })

  -- Refresh after LSP attaches
  api.nvim_create_autocmd('LspAttach', {
    callback = function()
      if S.win and api.nvim_win_is_valid(S.win) then
        vim.schedule(function() request(S.source_win) end)
      end
    end,
  })

  vim.keymap.set('n', '<leader>xo', M.toggle,
    { silent = true, desc = 'Outline: toggle' })
end

return M
