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
  _sticky      = false, -- true = auto-reopen if window is force-closed
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

-- Pure: returns true when path is a descendant of any entry in ignored_set
local function is_ignored(path, ignored_set)
  for ignored_path in pairs(ignored_set) do
    if path:sub(1, #ignored_path + 1) == ignored_path .. '/' then
      return true
    end
  end
  return false
end

local function git_hl(path)
  if not S.git_root then return nil end
  if S.git_map[path] then return GIT_HL[S.git_map[path]] end
  if is_ignored(path, S.ignored_set) then return 'CSTreeGitIgn' end
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

-- ── Icons ─────────────────────────────────────────────────────────────────────

local FALLBACK_ICONS = {
  lua='', py='', go='', rs='', ts='󰛦', js='', sh='',
  md='', json='', yaml='', yml='', toml='', txt='',
  vim='', css='', html='', c='', cpp='', h='',
  png='', jpg='', svg='', gif='',
  zip='', gz='', tar='', lock='',
}

local function get_file_icon(name, is_dir, expanded)
  if is_dir then
    return expanded and '▾ ' or '▸ ', 'CSTreeDirIcon'
  end
  -- Use mini.icons for the glyph only — always apply CSTreeFileIcon (no rainbow bg/fg)
  local ok, icon = pcall(function()
    local i = MiniIcons.get('file', name)  ---@diagnostic disable-line
    return i
  end)
  if ok and icon then return icon .. ' ', 'CSTreeFileIcon' end
  local ext = name:match('%.([^.]+)$') or ''
  return (FALLBACK_ICONS[ext] or '') .. ' ', 'CSTreeFileIcon'
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

-- Pure: mark e.is_last on every entry so render() can draw indent guides.
-- An entry is "last" when it has no future sibling at the same depth —
-- scanning forward through deeper children until the depth returns to or above e.depth.
local function compute_is_last(entries)
  for i, e in ipairs(entries) do
    local has_sibling = false
    for j = i + 1, #entries do
      if entries[j].depth == e.depth then
        has_sibling = true; break
      elseif entries[j].depth < e.depth then
        break  -- returned to an ancestor level, no sibling possible
      end
    end
    e.is_last = not has_sibling
  end
end

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  S.entries = scan(S.root, 0)
  compute_is_last(S.entries)

  -- Header: icon + project name (bold), dimmer full path below
  local project  = fn.fnamemodify(S.root, ':t')
  local fullpath = fn.fnamemodify(S.root, ':~')
  local hint     = not S.show_hidden and '  ·hidden' or ''
  local lines = {
    ' 󰉋 ' .. project .. hint,
    '  ' .. fullpath,
  }
  local hls = {}
  local function hi(ln, cs, ce, grp) table.insert(hls, { ln, cs, ce, grp }) end

  hi(0, 0, -1, 'CSTreeRoot')
  hi(1, 0, -1, 'CSTreePath')

  for idx, e in ipairs(S.entries) do
    -- Build indent: guide chars for each ancestor level
    local indent = ' '
    for d = 0, e.depth - 1 do
      -- Find nearest ancestor at depth d (look backwards)
      local ancestor_is_last = true
      for j = idx - 1, 1, -1 do
        if S.entries[j].depth == d then
          ancestor_is_last = S.entries[j].is_last
          break
        end
      end
      indent = indent .. (ancestor_is_last and '  ' or '│ ')
    end

    -- Connector: ├ or └ (only for depth > 0)
    local connector = e.depth == 0 and '  '
                   or (e.is_last     and '└ ' or '├ ')

    local icon, icon_hl = get_file_icon(e.name, e.is_dir, S.expanded[e.path])
    local line = indent .. connector .. icon .. e.name
    lines[#lines + 1] = line

    local ln       = #lines - 1
    local icon_col = #indent + #connector
    local name_col = icon_col + #icon
    hi(ln, 0, icon_col, 'CSTreeGuide')   -- dim the entire structural prefix
    hi(ln, icon_col, name_col, icon_hl)
    hi(ln, name_col, name_col + #e.name,
       git_hl(e.path) or (e.is_dir and 'CSTreeDir' or 'CSTreeFile'))
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

local HEADER_LINES = 2  -- project name + full path

local function entry_at_cursor()
  if not (S.win and api.nvim_win_is_valid(S.win)) then return end
  local row = api.nvim_win_get_cursor(S.win)[1]
  return S.entries[row - HEADER_LINES]
end

-- Find a non-tree editor window, or create one to the right of the tree.
-- Dirdash/home windows count as valid targets — they get replaced by the file.
local REPLACEABLE_FT = { cs_dirdash = true, cs_home = true }

local function editor_win()
  -- Prefer a real editor window first
  for _, w in ipairs(api.nvim_list_wins()) do
    if w ~= S.win and api.nvim_win_is_valid(w)
      and vim.bo[api.nvim_win_get_buf(w)].buftype == '' then
      return w
    end
  end
  -- Fall back to a replaceable panel (dirdash / home screen)
  for _, w in ipairs(api.nvim_list_wins()) do
    if w ~= S.win and api.nvim_win_is_valid(w)
      and REPLACEABLE_FT[vim.bo[api.nvim_win_get_buf(w)].filetype] then
      return w
    end
  end
  -- No suitable window — create a vertical split to the right of the tree
  local cur = api.nvim_get_current_win()
  api.nvim_set_current_win(S.win)
  vim.cmd('rightbelow vsplit')
  local new_win = api.nvim_get_current_win()
  api.nvim_set_current_win(cur)
  return new_win
end

local function open_or_expand()
  local e = entry_at_cursor()
  if not e then return end
  if e.is_dir then
    S.expanded[e.path] = not S.expanded[e.path] or nil
    render()
  else
    api.nvim_set_current_win(editor_win())
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

-- anchor_win: when given, open to the RIGHT of it (used by the activity bar);
-- otherwise the tree is the leftmost split.
function M.open(root, anchor_win)
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_set_current_win(S.win)
    return
  end
  S.root = root or fn.getcwd()
  S.buf  = create_buf()

  -- Remember the anchor so reopens (toggle / reveal / sticky) stay to its right.
  if anchor_win and api.nvim_win_is_valid(anchor_win) then S.anchor = anchor_win end
  if S.anchor and api.nvim_win_is_valid(S.anchor) then
    api.nvim_set_current_win(S.anchor)
    vim.cmd 'rightbelow vsplit'
  else
    S.anchor = nil
    vim.cmd 'topleft vsplit'
  end
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
  wo.winfixbuf      = true   -- Neovim 0.10+: prevents any buffer replacement in this window
  wo.scrolloff      = 0
  wo.winbar         = ''

  -- Auto-reopen if the window is closed by any means other than M.close()
  api.nvim_create_autocmd('WinClosed', {
    pattern  = tostring(S.win),
    once     = true,
    callback = function()
      S.win = nil
      if S._sticky and S.buf and api.nvim_buf_is_valid(S.buf) then
        vim.schedule(M.open)
      end
    end,
  })

  refresh_git()
  render()
end

function M.close()
  S._sticky = false   -- intentional close — don't auto-reopen
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_close(S.win, true)
  end
  S.win = nil
end

function M.toggle()
  if S.win and api.nvim_win_is_valid(S.win) then
    M.close()
  else
    S._sticky = true  -- reopened manually — stay sticky
    M.open()
  end
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
      api.nvim_win_set_cursor(S.win, { i + HEADER_LINES, 0 })
      break
    end
  end
end

-- ── Highlights ────────────────────────────────────────────────────────────────

local function setup_highlights()
  local hi = api.nvim_set_hl
  -- Header
  hi(0, 'CSTreeRoot',     { fg = '#c0caf5', bold = true })
  hi(0, 'CSTreePath',     { fg = '#3b4166' })
  -- Tree entries
  hi(0, 'CSTreeGuide',    { fg = '#24283b' })  -- structural chars: │ ├ └ connectors
  hi(0, 'CSTreeDirIcon',  { fg = '#7aa2f7' })
  hi(0, 'CSTreeDir',      { fg = '#7aa2f7', bold = true })
  hi(0, 'CSTreeFile',     { fg = '#9aa5ce' })
  hi(0, 'CSTreeFileIcon', { fg = '#3d4574' })  -- single subdued colour for all file icons
  -- Git status
  hi(0, 'CSTreeGitMod',  { fg = '#e0af68' })
  hi(0, 'CSTreeGitAdd',  { fg = '#9ece6a' })
  hi(0, 'CSTreeGitDel',  { fg = '#f7768e' })
  hi(0, 'CSTreeGitNew',  { fg = '#73daca' })
  hi(0, 'CSTreeGitIgn',  { fg = '#3b4166' })
  hi(0, 'CSTreeGitCon',  { fg = '#f7768e', bold = true })
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })

  -- Guard: if any non-tree buffer lands in the tree window, redirect it
  api.nvim_create_autocmd('BufWinEnter', {
    callback = function()
      if not (S.win and api.nvim_win_is_valid(S.win)) then return end
      if api.nvim_get_current_win() ~= S.win then return end
      local buf = api.nvim_get_current_buf()
      if buf == S.buf then return end
      -- A foreign buffer opened in the tree window — move it out
      local path = api.nvim_buf_get_name(buf)
      -- Restore tree in its window immediately
      pcall(api.nvim_win_set_buf, S.win, S.buf)
      -- Then open the file in a proper editor window
      if path ~= '' and fn.filereadable(path) == 1 then
        local ew = editor_win()
        api.nvim_set_current_win(ew)
        pcall(vim.cmd, 'noswapfile edit ' .. fn.fnameescape(path))
      end
    end,
  })
  api.nvim_create_autocmd('BufWritePost', {
    callback = function()
      if S.win and api.nvim_win_is_valid(S.win) then refresh_git(); render() end
    end,
  })

  -- Re-scan on external changes (files added/removed outside nvim, e.g. git/CLI).
  -- render() always reads the disk fresh, so this just re-triggers it.
  local function refresh_if_open()
    if S.win and api.nvim_win_is_valid(S.win) then refresh_git(); render() end
  end
  api.nvim_create_autocmd('FocusGained', { callback = refresh_if_open })
  api.nvim_create_autocmd('WinEnter', {
    callback = function()
      if S.win and api.nvim_get_current_win() == S.win then refresh_if_open() end
    end,
  })

  vim.keymap.set('n', '\\', M.reveal, { silent = true, desc = 'File tree' })
end

-- ── Test exports (pure functions only, no UI) ─────────────────────────────────
M._test = {
  HEADER_LINES    = HEADER_LINES,
  compute_is_last = compute_is_last,
  is_ignored      = is_ignored,
  -- entry index → buffer row
  entry_to_row    = function(idx) return idx + HEADER_LINES end,
  -- buffer row → entry index (nil when cursor is on a header line)
  row_to_entry    = function(row) local i = row - HEADER_LINES; return i > 0 and i or nil end,
}

return M
