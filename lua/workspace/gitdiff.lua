-- Native git diff/history viewer — a workspace-integrated replacement for
-- diffview.nvim. Everything renders in the single center window (per the shell
-- region model) instead of a private tabpage, so it never fights the layout and
-- `q` always closes cleanly, restoring whatever was in the center before.
--
-- Views:
--   * file_diff  — side-by-side old│new for one file, via Neovim's native diff
--                  mode (real ]c/[c, folds, synced scroll, theme diff colours);
--   * file_history / repo_log — a commit list; pick one to diff or show it.
local M = {}

local api = vim.api
local fn  = vim.fn

-- ── git helpers ────────────────────────────────────────────────────────────────

-- Lines of `<rev>:<path>` (rev '' = staged index). nil when the blob is absent
-- (new/untracked file at that rev) so callers can render an empty side.
local function show(cwd, rev, path)
  local out = fn.systemlist { 'git', '-C', cwd, 'show', rev .. ':' .. path }
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function worktree_lines(cwd, path)
  local p = cwd .. '/' .. path
  if fn.filereadable(p) == 0 then return nil end
  return fn.readfile(p)
end

local function ft_of(path)
  return vim.filetype.match { filename = path } or ''
end

-- Ordered changed-file list (for ]f/[f cycling) — staged and working-tree
-- entries, mirroring the CHANGES panel so navigation matches what's on screen.
local function changed_files(cwd)
  local out = fn.systemlist { 'git', '-C', cwd, 'status', '--porcelain=v1' }
  local files = {}
  for _, line in ipairs(out) do
    if #line >= 4 then
      local x, y = line:sub(1, 1), line:sub(2, 2)
      local path = line:sub(4)
      path = path:match('^"(.+)"$') or path
      path = path:match('.+ %-> (.+)') or path
      if x ~= ' ' and x ~= '?' and x ~= '!' then files[#files + 1] = { path = path, staged = true } end
      if y ~= ' ' then files[#files + 1] = { path = path, staged = false } end
    end
  end
  return files
end

-- Best-granularity intra-line (word-level) diff highlighting: the internal diff
-- with histogram + linematch gives tight DiffText spans on the changed bytes.
local function ensure_diffopt()
  local seen = {}
  for _, o in ipairs(vim.opt.diffopt:get()) do seen[o:gsub(':.*', '')] = true end
  for _, o in ipairs { 'internal', 'indent-heuristic', 'algorithm:histogram', 'linematch:60' } do
    if not seen[o:gsub(':.*', '')] then vim.opt.diffopt:append(o) end
  end
end

-- ── view lifecycle ──────────────────────────────────────────────────────────────
-- A "view" owns the center window. `prev` is the buffer to restore on close;
-- `extra` are side windows (the right diff pane) to tear down first.

local function begin_view()
  -- The center window may have been closed manually (:q instead of our q map);
  -- a stale handle here would fail every later nvim_win_set_buf.
  if M._view and not api.nvim_win_is_valid(M._view.center) then M._view = nil end
  if not M._view then
    local cwin = require('workspace.shell').center()
    M._view = { center = cwin, prev = api.nvim_win_get_buf(cwin) }
  end
  return M._view
end

-- Winbars on our scratch buffers must survive WinEnter: workspace.winbar wipes
-- the winbar of any nofile buffer unless the window carries this flag.
local function set_winbar(win, text)
  vim.wo[win].winbar = text
  pcall(api.nvim_win_set_var, win, 'cs_winbar', true)
end

local function clear_extra()
  local v = M._view
  if not v then return end
  if v.extra then
    for _, w in ipairs(v.extra) do
      if api.nvim_win_is_valid(w) then
        api.nvim_win_call(w, function() vim.cmd 'diffoff' end)
        pcall(api.nvim_win_close, w, true)
      end
    end
    v.extra = nil
  end
  if api.nvim_win_is_valid(v.center) then
    api.nvim_win_call(v.center, function() vim.cmd 'diffoff' end)
  end
end

function M.close()
  local v = M._view
  if not v then return end
  M._view = nil
  if v.extra then
    for _, w in ipairs(v.extra) do
      if api.nvim_win_is_valid(w) then
        api.nvim_win_call(w, function() vim.cmd 'diffoff' end)
        pcall(api.nvim_win_close, w, true)
      end
    end
  end
  if api.nvim_win_is_valid(v.center) then
    api.nvim_win_call(v.center, function() vim.cmd 'diffoff' end)
    -- Drop the keep-winbar flag first: restoring `prev` fires BufWinEnter and
    -- workspace.winbar then repaints the normal breadcrumb.
    pcall(api.nvim_win_del_var, v.center, 'cs_winbar')
    if v.prev and api.nvim_buf_is_valid(v.prev) then
      pcall(api.nvim_win_set_buf, v.center, v.prev)
    end
  end
end

-- Read-only scratch buffer holding `lines`, with a winbar-friendly name and `q`
-- (and <Esc>) bound to close the whole view.
local function scratch(lines, name, ft)
  local b = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(b, 0, -1, false, lines or {})
  vim.bo[b].buftype    = 'nofile'
  vim.bo[b].bufhidden  = 'wipe'
  vim.bo[b].modifiable = false
  vim.bo[b].filetype   = ft or ''
  vim.bo[b].swapfile   = false
  pcall(api.nvim_buf_set_name, b, name)
  vim.keymap.set('n', 'q',     M.close, { buffer = b, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', M.close, { buffer = b, nowait = true, silent = true })
  return b
end

-- ── side-by-side file diff ───────────────────────────────────────────────────────

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- Left/right (lines,label) for a diff mode: 'staged' HEAD│index,
-- 'unstaged' index│working, 'head' HEAD│working (all changes since last commit).
local function sides(cwd, path, mode)
  local function side(spec)
    if spec == 'work' then return worktree_lines(cwd, path) or {}, 'working' end
    return show(cwd, spec, path) or {}, (spec == '' and 'index' or spec)
  end
  local lspec, rspec
  if     mode == 'staged'   then lspec, rspec = 'HEAD', ''
  elseif mode == 'head'     then lspec, rspec = 'HEAD', 'work'
  else                           lspec, rspec = '', 'work' end
  local ll, llab = side(lspec)
  local rl, rlab = side(rspec)
  return ll, path .. '  [' .. llab .. ']', rl, path .. '  [' .. rlab .. ']'
end

-- Show `path` as old│new. `opts.staged` diffs HEAD→index; otherwise index→work,
-- and when that's empty (fully-staged file) it falls back to HEAD→working so the
-- view is never a blank "identical" fold. `opts.left`/`opts.right` = explicit revs.
function M.file_diff(cwd, path, opts)
  opts = opts or {}
  local ft = ft_of(path)

  local left_lines, left_label, right_lines, right_label
  if opts.left ~= nil or opts.right ~= nil then
    local lrev, rrev = opts.left or 'HEAD', opts.right or ''
    left_lines,  left_label  = show(cwd, lrev, path) or {}, path .. '  [' .. lrev .. ']'
    right_lines, right_label = show(cwd, rrev, path) or {}, path .. '  [' .. (rrev == '' and 'index' or rrev) .. ']'
  else
    local mode = opts.staged and 'staged' or 'unstaged'
    left_lines, left_label, right_lines, right_label = sides(cwd, path, mode)
    if same(left_lines, right_lines) then
      -- No diff for the requested pair → show everything vs HEAD instead.
      local ll, llab, rl, rlab = sides(cwd, path, 'head')
      if same(ll, rl) then
        vim.notify('No changes for ' .. path, vim.log.levels.INFO)
        return
      end
      left_lines, left_label, right_lines, right_label = ll, llab, rl, rlab
    end
  end

  ensure_diffopt()
  local v = begin_view()
  clear_extra()
  -- Remember the changed-file cursor for ]f/[f, if the caller supplied one.
  v.nav = opts.files and { cwd = cwd, files = opts.files, idx = opts.idx } or nil

  -- ]f/[f step through changed files; count shows position when navigating.
  local pos = v.nav and (' (' .. v.nav.idx .. '/' .. #v.nav.files .. ')') or ''

  local lb = scratch(left_lines, 'diff:old ' .. left_label, ft)
  api.nvim_win_set_buf(v.center, lb)
  api.nvim_set_current_win(v.center)
  set_winbar(v.center, '  ◀ ' .. left_label)

  vim.cmd 'rightbelow vsplit'
  local rwin = api.nvim_get_current_win()
  local rb   = scratch(right_lines, 'diff:new ' .. right_label, ft)
  api.nvim_win_set_buf(rwin, rb)
  local hint = v.nav and '   ]f/[f files   ]c/[c hunks   q close' or '   ]c/[c hunks   q close'
  set_winbar(rwin, '  ▶ ' .. right_label .. pos .. hint)
  v.extra = { rwin }

  if v.nav then
    for _, b in ipairs { lb, rb } do
      vim.keymap.set('n', ']f', M.next_file, { buffer = b, nowait = true, silent = true })
      vim.keymap.set('n', '[f', M.prev_file, { buffer = b, nowait = true, silent = true })
    end
  end

  for _, w in ipairs { v.center, rwin } do
    api.nvim_win_call(w, function()
      vim.cmd 'diffthis'
      vim.wo.foldlevel = 0
      vim.wo.wrap = false
    end)
  end
  api.nvim_set_current_win(rwin)
  api.nvim_win_call(rwin, function() pcall(vim.cmd, 'normal! gg]c') end)
end

-- Step to the next/prev changed file in the active diff view.
local function step_file(delta)
  local v = M._view
  if not (v and v.nav) then return end
  local n = v.nav
  local i = n.idx + delta
  if i < 1 or i > #n.files then
    vim.notify('No more changed files', vim.log.levels.INFO)
    return
  end
  local f = n.files[i]
  M.file_diff(n.cwd, f.path, { files = n.files, idx = i, staged = f.staged })
end
function M.next_file() step_file(1)  end
function M.prev_file() step_file(-1) end

-- Diff a file with ]f/[f cycling over the repo's whole changed-file set.
function M.diff_from(cwd, path, staged)
  local files = changed_files(cwd)
  for i, f in ipairs(files) do
    if f.path == path and f.staged == staged then
      M.file_diff(cwd, path, { files = files, idx = i, staged = staged })
      return
    end
  end
  M.file_diff(cwd, path, { staged = staged })
end

-- Diff whichever file is in the current buffer against the index.
function M.diff_current()
  local abs = fn.expand('%:p')
  if abs == '' then vim.notify('No file in buffer', vim.log.levels.WARN) return end
  local cwd = fn.systemlist({ 'git', '-C', fn.expand('%:p:h'), 'rev-parse', '--show-toplevel' })[1]
  if not cwd or cwd == '' then vim.notify('Not a git repo', vim.log.levels.WARN) return end
  local rel = fn.fnamemodify(abs, ':.')
  if abs:sub(1, #cwd) == cwd then rel = abs:sub(#cwd + 2) end
  M.diff_from(cwd, rel, false)
end

-- ── commit list (history / log) ──────────────────────────────────────────────────

local LOG_FMT = '%h%x09%an%x09%ad%x09%s'

local function parse_log(out)
  local commits = {}
  for _, line in ipairs(out) do
    local h, an, ad, s = line:match('^(%S+)\t(.-)\t(.-)\t(.*)$')
    if h then commits[#commits + 1] = { hash = h, author = an, date = ad, subject = s } end
  end
  return commits
end

-- A center-window list of commits. `on_select(commit)` fires on <CR>.
local function commit_list(cwd, title, commits, on_select)
  local lines, hls = {}, {}
  local function add(s, hl)
    lines[#lines + 1] = s
    if hl then hls[#hls + 1] = { #lines - 1, 0, -1, hl } end
  end
  add('')
  add('  ' .. title, 'CSTreeDir')
  add('')
  local row_to_commit = {}
  for _, c in ipairs(commits) do
    add(('  %s  %s  %s'):format(c.hash, c.date, c.subject))
    row_to_commit[#lines] = c
    hls[#hls + 1] = { #lines - 1, 2, 2 + #c.hash, 'DiagnosticHint' }               -- hash
    hls[#hls + 1] = { #lines - 1, 4 + #c.hash, 4 + #c.hash + #c.date, 'Comment' }   -- date
  end
  if #commits == 0 then add('  (no commits)', 'Comment') end
  add('')
  add('  <CR> open   q back', 'CSInfo')

  local v = begin_view()
  clear_extra()
  local buf = scratch(lines, title, 'cs_gitlog')
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local lns = api.nvim_create_namespace('cs_gitlog')
  for _, h in ipairs(hls) do api.nvim_buf_add_highlight(buf, lns, h[4], h[1], h[2], h[3]) end
  api.nvim_win_set_buf(v.center, buf)
  api.nvim_set_current_win(v.center)
  vim.wo[v.center].cursorline = true
  set_winbar(v.center, '  ' .. title .. '   <CR> open   q back')

  vim.keymap.set('n', '<CR>', function()
    local c = row_to_commit[api.nvim_win_get_cursor(v.center)[1]]
    if c then on_select(c) end
  end, { buffer = buf, nowait = true, silent = true })
end

-- History of a single file: pick a commit → diff that file commit^ vs commit.
function M.file_history(cwd, path)
  local out = fn.systemlist { 'git', '-C', cwd, 'log', '-n', '500',
    '--format=' .. LOG_FMT, '--date=short', '--', path }
  commit_list(cwd, 'HISTORY  ' .. path, parse_log(out), function(c)
    M.file_diff(cwd, path, { left = c.hash .. '^', right = c.hash })
  end)
end

-- Repo-wide log: pick a commit → show its full diff (unified) in the center.
-- Synchronous git log would freeze the UI on huge histories — cap it. 500
-- commits is plenty for a picker; older history stays reachable via lazygit.
function M.repo_log(cwd)
  local out = fn.systemlist { 'git', '-C', cwd, 'log', '-n', '500',
    '--format=' .. LOG_FMT, '--date=short' }
  commit_list(cwd, 'LOG  ' .. fn.fnamemodify(cwd, ':t'), parse_log(out), function(c)
    local diff = fn.systemlist { 'git', '-C', cwd, 'show', '--stat', '-p', c.hash }
    local v = begin_view()
    clear_extra()
    local buf = scratch(diff, 'commit ' .. c.hash, 'git')
    api.nvim_win_set_buf(v.center, buf)
    api.nvim_set_current_win(v.center)
    set_winbar(v.center, '  commit ' .. c.hash .. '  ' .. c.subject)
  end)
end

-- ── entry points ─────────────────────────────────────────────────────────────────

local function repo_root(cwd)
  cwd = cwd or fn.getcwd()
  local top = fn.systemlist({ 'git', '-C', cwd, 'rev-parse', '--show-toplevel' })[1]
  return (top and top ~= '') and top or cwd
end

function M.setup()
  ensure_diffopt()
  local map = vim.keymap.set
  local function cur_rel()
    local abs = fn.expand('%:p')
    if abs == '' then return nil, nil end
    local root = repo_root(fn.expand('%:p:h'))
    local rel  = (abs:sub(1, #root) == root) and abs:sub(#root + 2) or fn.fnamemodify(abs, ':.')
    return root, rel
  end

  map('n', '<leader>gd', M.diff_current,
    { desc = 'Git: diff current file (side-by-side)', silent = true })
  map('n', '<leader>gh', function()
    local root, rel = cur_rel()
    if rel then M.file_history(root, rel) end
  end, { desc = 'Git: file history', silent = true })
  map('n', '<leader>gl', function() M.repo_log(repo_root()) end,
    { desc = 'Git: repo log', silent = true })
  map('n', '<leader>gD', M.close, { desc = 'Git: close diff', silent = true })

  local cmd = api.nvim_create_user_command
  cmd('WSDiff',        function() M.diff_current() end, { desc = 'Side-by-side diff of the current file' })
  cmd('WSFileHistory', function()
    local root, rel = cur_rel()
    if rel then M.file_history(root, rel) else vim.notify('No file in buffer', vim.log.levels.WARN) end
  end, { desc = 'Commit history of the current file' })
  cmd('WSLog',       function() M.repo_log(repo_root()) end, { desc = 'Repo commit log' })
  cmd('WSDiffClose', function() M.close() end,              { desc = 'Close the git diff view' })
end

return M
