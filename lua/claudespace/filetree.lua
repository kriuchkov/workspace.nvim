-- Minimal file tree sidebar — replaces neo-tree.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace 'cs_filetree'

local ALWAYS_HIDE = { ['.git'] = true, ['.DS_Store'] = true }

local GIT_HL = {
  M = 'CSTreeGitMod', A = 'CSTreeGitAdd', D = 'CSTreeGitDel',
  R = 'CSTreeGitMod', C = 'CSTreeGitMod', U = 'CSTreeGitCon',
  ['?'] = 'CSTreeGitNew', ['!'] = 'CSTreeGitIgn',
}

-- Sidebar state
local S = {
  win          = nil,
  buf          = nil,
  root         = nil,
  expanded     = {},
  show_hidden  = true,
  entries      = {},   -- { depth, name, path, is_dir }
  git_map      = {},   -- abs_path → status char
  git_root     = nil,
  ignored_set  = {},   -- abs_path → true  (gitignored dirs/files, for subtree propagation)
}

-- ── Git ───────────────────────────────────────────────────────────────────────

local function refresh_git()
  S.git_map     = {}
  S.ignored_set = {}
  S.git_root    = fn.trim(fn.system(
    'git -C ' .. fn.shellescape(S.root) .. ' rev-parse --show-toplevel 2>/dev/null'))
  if vim.v.shell_error ~= 0 or S.git_root == '' then S.git_root = nil; return end

  -- --ignored shows !! entries so we can grey out gitignored paths
  local out = fn.system(
    'git -C ' .. fn.shellescape(S.root) .. ' status --porcelain --ignored 2>/dev/null')
  for line in out:gmatch('[^\n]+') do
    local xy  = line:sub(1, 2)
    local rel = line:sub(4):gsub('^"', ''):gsub('"$', '')
    rel = rel:match('^.+ %-> (.+)$') or rel
    rel = rel:gsub('/$', '')  -- ignored dirs arrive with trailing slash
    local abs = S.git_root .. '/' .. rel
    local ch  = (xy:sub(1,1) ~= ' ' and xy:sub(1,1)) or xy:sub(2,2)
    S.git_map[abs] = ch
    if ch == '!' then S.ignored_set[abs] = true end
  end
end

local function git_hl(path)
  if not S.git_root then return nil end
  if S.git_map[path] then return GIT_HL[S.git_map[path]] end
  -- Propagate: if any parent dir is in ignored_set, this path is also ignored
  for ignored_path in pairs(S.ignored_set) do
    if path:sub(1, #ignored_path + 1) == ignored_path .. '/' then
      return 'CSTreeGitIgn'
    end
  end
  return nil
end

-- ── Scanning ──────────────────────────────────────────────────────────────────

local function scan(dir, depth)
  local ok, items = pcall(fn.readdir, dir)
  if not ok or not items then return {} end

  table.sort(items, function(a, b)
    local ad = fn.isdirectory(dir .. '/' .. a) == 1
    local bd = fn.isdirectory(dir .. '/' .. b) == 1
    if ad ~= bd then return ad end
    return a:lower() < b:lower()
  end)

  local entries = {}
  for _, name in ipairs(items) do
    if ALWAYS_HIDE[name] then goto skip end
    if not S.show_hidden and name:sub(1,1) == '.' then goto skip end
    local path   = dir .. '/' .. name
    local is_dir = fn.isdirectory(path) == 1
    table.insert(entries, { depth = depth, name = name, path = path, is_dir = is_dir })
    if is_dir and S.expanded[path] then
      for _, child in ipairs(scan(path, depth + 1)) do
        table.insert(entries, child)
      end
    end
    ::skip::
  end
  return entries
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  S.entries = scan(S.root, 0)

  local hidden_hint = not S.show_hidden and '  (·hidden)' or ''
  local lines = { ' ' .. fn.fnamemodify(S.root, ':~') .. hidden_hint }
  local hls   = {}
  local function hi(ln, cs, ce, grp) table.insert(hls, { ln, cs, ce, grp }) end

  for _, e in ipairs(S.entries) do
    local pad      = string.rep('  ', e.depth + 1)
    local icon     = e.is_dir and (S.expanded[e.path] and '▼ ' or '▶ ') or '  '
    lines[#lines+1] = pad .. icon .. e.name

    local ln       = #lines - 1
    local name_col = #pad + #icon
    hi(ln, #pad, name_col, e.is_dir and 'CSTreeDir' or 'CSTreeFile')
    hi(ln, name_col, name_col + #e.name, git_hl(e.path) or (e.is_dir and 'CSTreeDir' or 'CSTreeFile'))
  end

  api.nvim_set_option_value('modifiable', true,  { buf = S.buf })
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  api.nvim_set_option_value('modifiable', false, { buf = S.buf })
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(S.buf, ns, h[4], h[1], h[2], h[3])
  end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function entry_at_cursor()
  if not (S.win and api.nvim_win_is_valid(S.win)) then return end
  local row = api.nvim_win_get_cursor(S.win)[1]
  return S.entries[row - 1]   -- line 1 = root header
end

local function open_or_expand()
  local e = entry_at_cursor()
  if not e then return end
  if e.is_dir then
    S.expanded[e.path] = not S.expanded[e.path] or nil
    render()
  else
    -- Open in the first non-tree window
    local wins = vim.tbl_filter(function(w)
      return w ~= S.win and api.nvim_win_is_valid(w)
        and vim.bo[api.nvim_win_get_buf(w)].buftype == ''
    end, api.nvim_list_wins())
    if wins[1] then
      api.nvim_set_current_win(wins[1])
    else
      vim.cmd 'wincmd p'
    end
    vim.cmd('noswapfile edit ' .. fn.fnameescape(e.path))
  end
end

local function collapse_or_parent()
  local e = entry_at_cursor()
  if not e then return end
  if e.is_dir and S.expanded[e.path] then
    S.expanded[e.path] = nil
    render()
    return
  end
  local parent = fn.fnamemodify(e.path, ':h')
  for i, other in ipairs(S.entries) do
    if other.path == parent then
      api.nvim_win_set_cursor(S.win, { i + 1, 0 })
      return
    end
  end
end

local function open_preview()
  local e = entry_at_cursor()
  if not e or e.is_dir then return end
  local wins = vim.tbl_filter(function(w)
    return w ~= S.win and api.nvim_win_is_valid(w)
      and vim.bo[api.nvim_win_get_buf(w)].buftype == ''
  end, api.nvim_list_wins())
  if wins[1] then
    local cur = api.nvim_get_current_win()
    api.nvim_set_current_win(wins[1])
    vim.cmd('noswapfile edit ' .. fn.fnameescape(e.path))
    api.nvim_set_current_win(cur)
  end
end

local function new_file()
  local e = entry_at_cursor()
  local dir
  if e then
    dir = e.is_dir and S.expanded[e.path] and e.path or fn.fnamemodify(e.path, ':h')
  else
    dir = S.root
  end
  vim.ui.input({ prompt = 'New file: ' }, function(name)
    if not name or name == '' then return end
    local path = dir .. '/' .. name
    fn.mkdir(fn.fnamemodify(path, ':h'), 'p')
    local f = io.open(path, 'w')
    if f then f:close() end
    refresh_git()
    render()
  end)
end

local function rename_entry()
  local e = entry_at_cursor()
  if not e then return end
  vim.ui.input({ prompt = 'Rename: ', default = e.name }, function(name)
    if not name or name == '' or name == e.name then return end
    local new_path = fn.fnamemodify(e.path, ':h') .. '/' .. name
    local ok, err = os.rename(e.path, new_path)
    if not ok then vim.notify('Rename failed: ' .. (err or ''), vim.log.levels.ERROR); return end
    refresh_git()
    render()
  end)
end

local function delete_entry()
  local e = entry_at_cursor()
  if not e then return end
  local label = e.is_dir and (e.name .. '/') or e.name
  local choice = vim.fn.confirm('Delete ' .. label .. '?', '&Yes\n&No', 2)
  if choice ~= 1 then return end
  fn.delete(e.path, e.is_dir and 'rf' or '')
  refresh_git()
  render()
end

local function yank_path()
  local e = entry_at_cursor()
  local path = e and e.path or S.root
  local rel = fn.fnamemodify(path, ':~:.')
  vim.fn.setreg('+', rel)
  vim.fn.setreg('"', rel)
  vim.notify('Copied: ' .. rel, vim.log.levels.INFO)
end

local function change_root()
  local e = entry_at_cursor()
  if not e or not e.is_dir then return end
  S.root    = e.path
  S.expanded = {}
  refresh_git()
  render()
end

local function root_up()
  local parent = fn.fnamemodify(S.root, ':h')
  if parent == S.root then return end
  S.root = parent
  refresh_git()
  render()
end

local HELP_LINES = {
  '  Filetree keybindings',
  '  ─────────────────────────────────',
  '  <CR> / l   open file / expand dir',
  '  o          open (keep tree focus)',
  '  h          collapse / go to parent',
  '  n          new file',
  '  r          rename',
  '  d          delete',
  '  y          yank path to clipboard',
  '  C          set dir as root',
  '  -          go up to parent root',
  '  H          toggle hidden files',
  '  R          refresh git status',
  '  q / <Esc>  close tree',
  '  ?          this help',
}

local function show_help()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, HELP_LINES)
  vim.bo[buf].modifiable = false
  local width  = 38
  local height = #HELP_LINES
  local win = api.nvim_open_win(buf, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    row       = math.floor((vim.o.lines   - height) / 2),
    col       = math.floor((vim.o.columns - width)  / 2),
    style     = 'minimal',
    border    = 'rounded',
    title     = ' Help ',
    title_pos = 'center',
  })
  local close = function() api.nvim_win_close(win, true) end
  for _, key in ipairs({ 'q', '<Esc>', '?' }) do
    vim.keymap.set('n', key, close, { buffer = buf, nowait = true, silent = true })
  end
end

-- ── Window ────────────────────────────────────────────────────────────────────

local function create_buf()
  local buf  = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile  = false
  vim.bo[buf].filetype  = 'cs_filetree'

  local o = { buffer = buf, nowait = true, silent = true }
  local k = vim.keymap.set
  k('n', '<CR>',  open_or_expand,    o)
  k('n', 'l',     open_or_expand,    o)
  k('n', 'o',     open_preview,      o)
  k('n', 'h',     collapse_or_parent,o)
  k('n', 'q',     M.close,           o)
  k('n', '<Esc>', M.close,           o)
  k('n', '\\',    M.close,           o)
  k('n', 'H',     function() S.show_hidden = not S.show_hidden; render() end, o)
  k('n', 'R',     function() refresh_git(); render() end, o)
  k('n', 'n',     new_file,          o)
  k('n', 'r',     rename_entry,      o)
  k('n', 'd',     delete_entry,      o)
  k('n', 'y',     yank_path,         o)
  k('n', 'C',     change_root,       o)
  k('n', '-',     root_up,           o)
  k('n', '?',     show_help,         o)
  return buf
end

function M.open(root)
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_set_current_win(S.win)
    return
  end
  S.root = root or fn.getcwd()
  S.buf  = create_buf()

  vim.cmd 'topleft vsplit'
  S.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.win, S.buf)
  api.nvim_win_set_width(S.win, 30)

  local wo = vim.wo[S.win]
  wo.number         = false
  wo.relativenumber = false
  wo.wrap           = false
  wo.signcolumn     = 'no'
  wo.cursorline     = true
  wo.winfixwidth    = true
  wo.scrolloff      = 0
  wo.winbar         = ''

  api.nvim_create_autocmd('WinClosed', {
    pattern  = tostring(S.win),
    once     = true,
    callback = function() S.win = nil end,
  })

  refresh_git()
  render()
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

function M.reveal()
  local file = api.nvim_buf_get_name(0)
  if not (S.win and api.nvim_win_is_valid(S.win)) then M.open() end

  if file == '' then return end

  -- Expand all ancestor directories between root and the file
  local path = fn.fnamemodify(file, ':h')
  while path ~= S.root and #path > #S.root do
    S.expanded[path] = true
    local up = fn.fnamemodify(path, ':h')
    if up == path then break end
    path = up
  end

  refresh_git()
  render()

  for i, e in ipairs(S.entries) do
    if e.path == file then
      api.nvim_win_set_cursor(S.win, { i + 1, 0 })
      break
    end
  end
end

-- ── Highlights ────────────────────────────────────────────────────────────────

local function setup_highlights()
  local hi = api.nvim_set_hl
  hi(0, 'CSTreeDir',    { fg = '#7aa2f7', bold = true })
  hi(0, 'CSTreeFile',   { fg = '#c0caf5' })
  hi(0, 'CSTreeGitMod', { fg = '#e0af68' })
  hi(0, 'CSTreeGitAdd', { fg = '#9ece6a' })
  hi(0, 'CSTreeGitDel', { fg = '#f7768e' })
  hi(0, 'CSTreeGitNew', { fg = '#73daca' })
  hi(0, 'CSTreeGitIgn', { fg = '#565f89' })
  hi(0, 'CSTreeGitCon', { fg = '#f7768e', bold = true })
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })
  api.nvim_create_autocmd('BufWritePost', {
    callback = function()
      if S.win and api.nvim_win_is_valid(S.win) then refresh_git(); render() end
    end,
  })
  vim.keymap.set('n', '\\', M.reveal, { silent = true, desc = 'File tree' })
end

return M
