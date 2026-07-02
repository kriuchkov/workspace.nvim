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

-- Collect the git roots whose file-level status we need. Single-repo: the tree's
-- own git root. Multi-repo: only repos the user has expanded (their files are
-- visible) — avoids running `git status` across every repo on each refresh.
local function git_roots()
  local ok, repos = pcall(require, 'claudespace.repos')
  if ok and repos.is_multi() then
    local roots = {}
    for _, m in ipairs(repos.list()) do
      -- changed-only mode needs the full change set, so scan every repo then.
      if S.changed_only or S.expanded[m.abspath] then roots[#roots + 1] = m.abspath end
    end
    return roots
  end
  local gr = fn.trim(fn.system(
    'git -C ' .. fn.shellescape(S.root) .. ' rev-parse --show-toplevel 2>/dev/null'))
  if vim.v.shell_error ~= 0 or gr == '' then return {} end
  return { gr }
end

-- In a multi-repo workspace the tree is rooted at the workspace root so every
-- member repo is visible; otherwise it falls back to cwd.
local function default_root()
  local ok, repos = pcall(require, 'claudespace.repos')
  if ok and repos.is_multi() then return repos.root() end
  return fn.getcwd()
end

local REPO_GLYPH = vim.fn.nr2char(0xf1b2)  -- cube — marks a member repo root

-- Repo lookups are hot (every dir node, every render). Cache abspath→member and
-- the active repo once per render instead of re-scanning repos.list() each time.
local function build_repo_cache()
  S.repo_set, S.active_path = {}, nil
  local ok, repos = pcall(require, 'claudespace.repos')
  if not (ok and repos.is_multi()) then return end
  for _, m in ipairs(repos.list()) do S.repo_set[m.abspath] = m end
  local a = repos.active()
  S.active_path = a and a.abspath or nil
end

local function repo_member(path)      return S.repo_set and S.repo_set[path] or nil end
local function is_repo_path(path)     return repo_member(path) ~= nil end
local function active_repo_path()     return S.active_path end

-- Annotation (branch ●dirty ↑ahead ↓behind) for a repo root, from the cached
-- status — no git call here.
local function repo_annotation(m)
  local repos = require('claudespace.repos')
  local st = repos.status(m)
  if not st then repos.refresh_status(m); return '  …' end
  local s = st.branch ~= '' and ('  ' .. st.branch) or ''
  if st.dirty  > 0 then s = s .. ' ●' .. st.dirty  end
  if st.ahead  > 0 then s = s .. ' ↑' .. st.ahead  end
  if st.behind > 0 then s = s .. ' ↓' .. st.behind end
  return s
end

-- Name highlight for a repo root: active wins, then dirty, then ahead, else clean.
local function repo_name_hl(m, active)
  if active then return 'CSTreeRepoActive' end
  local st = require('claudespace.repos').status(m)
  if st and st.dirty  and st.dirty  > 0 then return 'CSTreeRepoDirty' end
  if st and st.ahead  and st.ahead  > 0 then return 'CSTreeRepoAhead' end
  return 'CSTreeRepoClean'
end

-- ── Diagnostics ───────────────────────────────────────────────────────────────
-- Diagnostics exist only for loaded buffers (open files). Map their paths to
-- error/warn counts; dir/repo nodes aggregate the files beneath them.

local function build_diag()
  local m = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) then
      local name = api.nvim_buf_get_name(b)
      if name ~= '' then
        local ok, c = pcall(vim.diagnostic.count, b)
        if ok then
          local e = c[vim.diagnostic.severity.ERROR] or 0
          local w = c[vim.diagnostic.severity.WARN] or 0
          if e > 0 or w > 0 then m[name] = { e = e, w = w } end
        end
      end
    end
  end
  return m
end

-- Returns the badge text + the byte length of its error part (for highlighting).
local function diag_badge(path, is_dir)
  if not S.diag or not next(S.diag) then return nil end
  local e, w = 0, 0
  if is_dir then
    for p, c in pairs(S.diag) do
      if p:sub(1, #path + 1) == path .. '/' then e = e + c.e; w = w + c.w end
    end
  else
    local c = S.diag[path]; if c then e, w = c.e, c.w end
  end
  if e == 0 and w == 0 then return nil end
  local etext = e > 0 and ('  ✖' .. e) or ''
  local wtext = w > 0 and ('  ⚠' .. w) or ''
  return etext .. wtext, #etext
end

local function refresh_git()
  S.git_map, S.ignored_set, S.has_git = {}, {}, false
  for _, gr in ipairs(git_roots()) do
    -- --ignored shows !! entries so we can grey out gitignored paths
    local out = fn.system(
      'git -C ' .. fn.shellescape(gr) .. ' status --porcelain --ignored 2>/dev/null')
    if vim.v.shell_error == 0 then
      S.has_git = true
      for line in out:gmatch('[^\n]+') do
        local xy  = line:sub(1, 2)
        local rel = line:sub(4):gsub('^"', ''):gsub('"$', '')
        rel = rel:match('^.+ %-> (.+)$') or rel
        rel = rel:gsub('/$', '')  -- ignored dirs arrive with trailing slash
        local abs = gr .. '/' .. rel
        local ch  = (xy:sub(1,1) ~= ' ' and xy:sub(1,1)) or xy:sub(2,2)
        S.git_map[abs] = ch
        if ch == '!' then S.ignored_set[abs] = true end
      end
    end
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
  if not S.has_git then return nil end
  if S.git_map[path] then return GIT_HL[S.git_map[path]] end
  if is_ignored(path, S.ignored_set) then return 'CSTreeGitIgn' end
  return nil
end

-- ── Scanning ──────────────────────────────────────────────────────────────────

local function visible_children(dir)
  local ok, items = pcall(fn.readdir, dir)
  if not ok or not items then return {} end
  local out = {}
  for _, name in ipairs(items) do
    if not ALWAYS_HIDE[name] and (S.show_hidden or name:sub(1, 1) ~= '.') then
      out[#out + 1] = name
    end
  end
  return out
end

-- "Compact folders" (VS Code style): collapse a chain of single-child directories
-- into one node (internal/core/ports). Stops at repo roots so they keep their own
-- annotated node. Returns the deepest path + the combined display name.
local function compact(dir, name)
  local disp, real = name, dir
  while true do
    local kids = visible_children(real)
    if #kids ~= 1 then break end
    local child = real .. '/' .. kids[1]
    if fn.isdirectory(child) ~= 1 or is_repo_path(child) then break end
    disp, real = disp .. '/' .. kids[1], child
  end
  return real, disp
end

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
    local path = dir .. '/' .. name
    if fn.isdirectory(path) == 1 then
      local real, disp = compact(path, name)
      table.insert(entries, { depth = depth, name = disp, path = real, is_dir = true })
      if S.expanded[real] then
        for _, child in ipairs(scan(real, depth + 1)) do
          table.insert(entries, child)
        end
      end
    else
      table.insert(entries, { depth = depth, name = name, path = path, is_dir = false })
    end
    ::skip::
  end
  return entries
end

-- Changed-only view: build the tree from git_map (changed files across repos),
-- emitting each file's ancestor dirs on first encounter. All dirs are expanded.
local function scan_changed()
  local files = {}
  for abs, ch in pairs(S.git_map) do
    if ch ~= '!' and abs:sub(1, #S.root + 1) == S.root .. '/'
       and fn.isdirectory(abs) ~= 1 then
      files[#files + 1] = abs
    end
  end
  table.sort(files)

  local entries, seen = {}, {}
  for _, abs in ipairs(files) do
    local parts = vim.split(abs:sub(#S.root + 2), '/')
    local acc = S.root
    for i = 1, #parts - 1 do
      acc = acc .. '/' .. parts[i]
      if not seen[acc] then
        seen[acc] = true
        entries[#entries + 1] = { depth = i - 1, name = parts[i], path = acc, is_dir = true }
      end
    end
    entries[#entries + 1] = { depth = #parts - 1, name = parts[#parts], path = abs, is_dir = false }
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

-- Mark e.is_last on every entry (no later sibling at the same depth) for the
-- indent guides. O(n · maxdepth): walk backwards tracking whether a later
-- sibling exists per depth; crossing to a shallower depth resets deeper levels.
local function compute_is_last(entries)
  local seen = {}   -- depth -> a later sibling exists
  for i = #entries, 1, -1 do
    local d = entries[i].depth
    entries[i].is_last = not seen[d]
    seen[d] = true
    for dd in pairs(seen) do if dd > d then seen[dd] = nil end end
  end
end

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  build_repo_cache()
  if S.diag == nil or S.diag_dirty then S.diag = build_diag(); S.diag_dirty = false end
  S.entries = S.changed_only and scan_changed() or scan(S.root, 0)
  compute_is_last(S.entries)

  -- Header: icon + project name (bold), dimmer full path below
  local project  = fn.fnamemodify(S.root, ':t')
  local fullpath = fn.fnamemodify(S.root, ':~')
  local hint     = S.changed_only and '  ·changes'
                or (not S.show_hidden and '  ·hidden' or '')
  local lines = {
    ' 󰉋 ' .. project .. hint,
    '  ' .. fullpath,
  }
  local hls = {}
  local function hi(ln, cs, ce, grp) table.insert(hls, { ln, cs, ce, grp }) end

  hi(0, 0, -1, 'CSTreeRoot')
  hi(1, 0, -1, 'CSTreePath')

  -- anc_last[d] = is_last of the current ancestor at depth d. Maintained as we
  -- walk in DFS order so the indent guides cost O(depth), not a backward scan.
  local anc_last = {}
  for idx, e in ipairs(S.entries) do
    -- Build indent: guide char per ancestor level
    local indent = ' '
    for d = 0, e.depth - 1 do
      indent = indent .. (anc_last[d] and '  ' or '│ ')
    end
    anc_last[e.depth] = e.is_last

    -- Connector: ├ or └ (only for depth > 0)
    local connector = e.depth == 0 and '  '
                   or (e.is_last     and '└ ' or '├ ')

    local icon, icon_hl = get_file_icon(e.name, e.is_dir, S.expanded[e.path])
    local member = e.is_dir and repo_member(e.path) or nil
    local active = member and (e.path == active_repo_path()) or false
    local glyph  = member and (REPO_GLYPH .. ' ') or ''
    local annot  = member and repo_annotation(member) or nil
    local badge, elen = diag_badge(e.path, e.is_dir)
    local line = indent .. connector .. icon .. glyph .. e.name .. (annot or '') .. (badge or '')
    lines[#lines + 1] = line

    local ln        = #lines - 1
    local icon_col  = #indent + #connector
    local glyph_col = icon_col + #icon
    local name_col  = glyph_col + #glyph
    local name_end  = name_col + #e.name
    hi(ln, 0, icon_col, 'CSTreeGuide')          -- dim the structural prefix
    hi(ln, icon_col, glyph_col, icon_hl)         -- chevron
    if member then
      hi(ln, glyph_col, name_col, active and 'CSTreeRepoActive' or 'CSTreeRepoGlyph')
      hi(ln, name_col, name_end, repo_name_hl(member, active))
    else
      hi(ln, name_col, name_end, git_hl(e.path) or (e.is_dir and 'CSTreeDir' or 'CSTreeFile'))
    end
    if annot then hi(ln, name_end, name_end + #annot, 'Comment') end
    if badge then
      local bcol = name_end + #(annot or '')
      if elen > 0          then hi(ln, bcol, bcol + elen, 'DiagnosticError') end
      if #badge > elen     then hi(ln, bcol + elen, bcol + #badge, 'DiagnosticWarn') end
    end
  end

  if S.changed_only and #S.entries == 0 then
    lines[#lines + 1] = '  (no changes)'
    hi(#lines - 1, 0, -1, 'Comment')
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
  '  i          repo info (workspace)',
  '  s          git stage / unstage',
  '  gd         git diff',
  '  c          changed-only view (toggle)',
  '  f          find files in this repo',
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

-- Show the workspace info card for the repo at (or containing) the cursor entry.
local function repo_info()
  local e = entry_at_cursor()
  require('claudespace.repos').show_info(e and e.path or S.root)
end

-- Fuzzy-find files within the repo at (or containing) the cursor entry.
local function find_in_repo()
  local e = entry_at_cursor()
  local path = e and e.path or S.root
  local repos = require('claudespace.repos')
  repos.find_files(repos.at(path) or repos.of(path))
end

-- ── Inline git ────────────────────────────────────────────────────────────────

local function git_root_of(path)
  local ok, repos = pcall(require, 'claudespace.repos')
  local m = ok and repos.of(path)
  if m then return m.abspath end
  local dir = fn.isdirectory(path) == 1 and path or fn.fnamemodify(path, ':h')
  local gr  = fn.trim(fn.system('git -C ' .. fn.shellescape(dir) .. ' rev-parse --show-toplevel 2>/dev/null'))
  return (vim.v.shell_error == 0 and gr ~= '') and gr or nil
end

-- Stage a file (or everything under a dir); toggles staged↔unstaged for a file.
local function git_stage()
  local e = entry_at_cursor()
  if not e then return end
  local root = git_root_of(e.path)
  if not root then vim.notify('Not in a git repo', vim.log.levels.WARN); return end
  local rel = e.path:sub(#root + 2)
  local C   = 'git -C ' .. fn.shellescape(root) .. ' '
  if e.is_dir then
    fn.system(C .. 'add -- ' .. fn.shellescape(rel))
  else
    local st = fn.systemlist(C .. 'status --porcelain -- ' .. fn.shellescape(rel))
    local x  = st[1] and st[1]:sub(1, 1) or ' '
    if x ~= ' ' and x ~= '?' then
      fn.system(C .. 'restore --staged -- ' .. fn.shellescape(rel))
    else
      fn.system(C .. 'add -- ' .. fn.shellescape(rel))
    end
  end
  refresh_git(); render()
  pcall(function()
    local repos = require('claudespace.repos')
    if repos.of(e.path) then repos.refresh_status(repos.of(e.path)) end
  end)
end

-- Show the diff of the file at the cursor in a scratch split.
local function git_diff()
  local e = entry_at_cursor()
  if not e or e.is_dir then return end
  local root = git_root_of(e.path)
  if not root then vim.notify('Not in a git repo', vim.log.levels.WARN); return end
  local rel  = e.path:sub(#root + 2)
  local diff = fn.system('git -C ' .. fn.shellescape(root) .. ' diff HEAD -- ' .. fn.shellescape(rel))
  if vim.trim(diff) == '' then vim.notify('No diff for ' .. e.name, vim.log.levels.INFO); return end
  api.nvim_set_current_win(editor_win())
  vim.cmd 'botright new'
  local dbuf = api.nvim_get_current_buf()
  vim.bo[dbuf].buftype = 'nofile'; vim.bo[dbuf].bufhidden = 'wipe'
  vim.bo[dbuf].filetype = 'diff'
  api.nvim_buf_set_lines(dbuf, 0, -1, false, vim.split(diff, '\n'))
  vim.bo[dbuf].modifiable = false
  vim.keymap.set('n', 'q', '<cmd>bd<CR>', { buffer = dbuf, silent = true })
end

-- Toggle "changed-only" view: just the git-modified files across all repos.
local function toggle_changed()
  S.changed_only = (not S.changed_only) or nil
  refresh_git()   -- git_roots() now covers every repo while changed_only is on
  render()
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
  k('n', 'i',     repo_info,         o)
  k('n', 's',     git_stage,         o)
  k('n', 'gd',    git_diff,          o)
  k('n', 'c',     toggle_changed,    o)
  k('n', 'f',     find_in_repo,      o)
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
  S.root = root or default_root()
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
    local ok = pcall(api.nvim_win_close, S.win, true)
    if not ok and api.nvim_win_is_valid(S.win) then
      -- Tree is the last window — can't close it; show an empty buffer instead.
      api.nvim_set_current_win(S.win)
      vim.wo[S.win].winfixbuf = false
      pcall(vim.cmd, 'enew')
    end
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

-- Reveal and focus an arbitrary path (used by the repos overview to jump into a
-- repo). Expands the target dir and all ancestors up to the tree root.
function M.focus_path(target)
  if not target or target == '' then return end
  if not (S.win and api.nvim_win_is_valid(S.win)) then M.open() end
  if target:sub(1, #S.root) ~= S.root then return end

  local path = target
  while #path >= #S.root do
    if fn.isdirectory(path) == 1 then S.expanded[path] = true end
    local up = fn.fnamemodify(path, ':h')
    if up == path or #up < #S.root then break end
    path = up
  end

  refresh_git()
  render()
  api.nvim_set_current_win(S.win)
  for i, e in ipairs(S.entries) do
    if e.path == target then
      pcall(api.nvim_win_set_cursor, S.win, { i + HEADER_LINES, 0 })
      break
    end
  end
end

-- ── Highlights ────────────────────────────────────────────────────────────────

local function setup_highlights()
  local hi = api.nvim_set_hl
  local c  = require('claudespace.theme').colors()
  -- Header
  hi(0, 'CSTreeRoot',     { fg = c.fg, bold = true })
  hi(0, 'CSTreePath',     { fg = c.fg_dim })
  -- Tree entries
  hi(0, 'CSTreeGuide',    { fg = c.border })  -- structural chars: │ ├ └ connectors
  hi(0, 'CSTreeDirIcon',  { fg = c.blue })
  hi(0, 'CSTreeDir',      { fg = c.blue, bold = true })
  hi(0, 'CSTreeFile',     { fg = c.fg })
  -- Repo roots: a cube glyph + status-coloured name; active repo stands out.
  hi(0, 'CSTreeRepoGlyph',  { fg = c.fg_dim })
  hi(0, 'CSTreeRepoActive', { fg = c.cyan, bold = true })
  hi(0, 'CSTreeRepoClean',  { fg = c.fg, bold = true })
  hi(0, 'CSTreeRepoDirty',  { fg = c.warn, bold = true })
  hi(0, 'CSTreeRepoAhead',  { fg = c.green, bold = true })
  hi(0, 'CSTreeFileIcon', { fg = c.fg_dim })  -- single subdued colour for all file icons
  -- Git status
  hi(0, 'CSTreeGitMod',  { fg = c.git_change })
  hi(0, 'CSTreeGitAdd',  { fg = c.git_add_fg })
  hi(0, 'CSTreeGitDel',  { fg = c.git_delete })
  hi(0, 'CSTreeGitNew',  { fg = c.cyan })
  hi(0, 'CSTreeGitIgn',  { fg = c.fg_faint })
  hi(0, 'CSTreeGitCon',  { fg = c.red, bold = true })
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = setup_highlights })

  -- Refresh diagnostic badges when diagnostics change. Debounced (300ms) — LSP
  -- pushes diagnostics rapidly while typing and a full re-render walks the FS.
  local diag_timer
  api.nvim_create_autocmd({ 'DiagnosticChanged', 'BufDelete' }, {
    callback = function()
      S.diag_dirty = true   -- rebuild the diag map on the next render
      if not (S.win and api.nvim_win_is_valid(S.win)) then return end
      if diag_timer then diag_timer:stop() end
      diag_timer = vim.defer_fn(function()
        if S.win and api.nvim_win_is_valid(S.win) then render() end
      end, 300)
    end,
  })

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
