-- Multi-repo workspace core.
-- A workspace is a root directory (the one holding .claudespace/workspace.json)
-- containing several git repositories ("members"). The linchpin is the *active
-- repo*, derived from the focused buffer's path — git/Claude/tests key off it.
local M = {}

local api, fn, uv = vim.api, vim.fn, vim.uv

local MANIFEST = '.claudespace/workspace.json'
local STATUS_TTL = 4000  -- ms; cache window for a repo's git status

local state = {
  root    = nil,   -- workspace root (abspath)
  name    = nil,
  members = {},    -- { { path, abspath, label, group, pinned } }
  active  = nil,   -- member or nil
  status  = {},    -- abspath -> { branch, ahead, behind, dirty, ts }
  loaded  = false,
  implicit = false,-- true when members came from a scan (no manifest on disk)
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function strip_slash(p) return (p:gsub('/+$', '')) end
local function is_repo(dir)  return fn.isdirectory(dir .. '/.git') == 1 end

local function read_json(path)
  if fn.filereadable(path) == 0 then return nil end
  local ok, data = pcall(fn.json_decode, table.concat(fn.readfile(path), '\n'))
  return ok and type(data) == 'table' and data or nil
end

-- Walk up from `start` looking for the workspace manifest.
local function find_root(start)
  local dir = strip_slash(fn.fnamemodify(start, ':p'))
  while dir and dir ~= '' do
    if fn.filereadable(dir .. '/' .. MANIFEST) == 1 then return dir end
    local parent = fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end
end

-- Depth-limited scan for git repos under root (fallback when no manifest).
local function scan_repos(root)
  local out = fn.systemlist({
    'find', root, '-maxdepth', '4', '-name', '.git', '-not', '-path', '*/node_modules/*',
  })
  if vim.v.shell_error ~= 0 then return {} end
  local dirs = {}
  for _, g in ipairs(out) do
    local d = strip_slash(fn.fnamemodify(g, ':h'))
    if d ~= root then table.insert(dirs, d) end
  end
  return dirs
end

local function make_member(root, abspath, group_override)
  abspath = strip_slash(fn.fnamemodify(abspath, ':p'))
  local rel    = abspath:sub(#root + 2)
  local parent = fn.fnamemodify(rel, ':h')
  return {
    path  = rel,
    abspath = abspath,
    label = fn.fnamemodify(rel, ':t'),
    group = group_override or (parent ~= '.' and parent or 'root'),
  }
end

-- Resolve a manifest's include/exclude globs into member repos.
local function resolve_manifest(root, mf)
  local excluded = {}
  for _, pat in ipairs(mf.exclude or {}) do
    for _, m in ipairs(fn.glob(root .. '/' .. pat, true, true)) do
      excluded[strip_slash(m)] = true
    end
  end
  local seen, members = {}, {}
  for _, pat in ipairs(mf.include or {}) do
    for _, m in ipairs(fn.glob(root .. '/' .. pat, true, true)) do
      m = strip_slash(m)
      if not seen[m] and not excluded[m] and is_repo(m) then
        seen[m] = true
        table.insert(members, make_member(root, m))
      end
    end
  end
  local pin = {}
  for _, p in ipairs(mf.pin or {}) do pin[strip_slash(root .. '/' .. p)] = true end
  for _, mem in ipairs(members) do mem.pinned = pin[mem.abspath] or nil end
  return members
end

local function sort_members(members)
  table.sort(members, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.label < b.label
  end)
end

-- ── Load ──────────────────────────────────────────────────────────────────────

function M.load()
  local cwd  = fn.getcwd()
  local root = find_root(cwd)
  local members

  if root then
    local mf = read_json(root .. '/' .. MANIFEST) or {}
    state.name = mf.name or fn.fnamemodify(root, ':t')
    members = resolve_manifest(root, mf)
    state.implicit = false
  else
    -- No manifest: treat cwd (or its git root) as the workspace and scan.
    root = strip_slash(fn.fnamemodify(cwd, ':p'))
    state.name = fn.fnamemodify(root, ':t')
    members = {}
    for _, d in ipairs(scan_repos(root)) do
      table.insert(members, make_member(root, d))
    end
    state.implicit = true
  end

  sort_members(members)
  state.root    = root
  state.members = members
  state.loaded  = true
  state.status  = {}
  state.active  = nil
  M.refresh_active(true)
  return members
end

-- ── Queries ───────────────────────────────────────────────────────────────────

function M.is_multi()    return #state.members > 1 end
function M.list()        return state.members end
function M.root()        return state.root end
function M.name()        return state.name end
function M.is_implicit() return state.implicit end

-- The member repo containing `path` (longest abspath prefix wins).
function M.of(path)
  if not path or path == '' then return nil end
  local p = fn.fnamemodify(path, ':p')
  local best
  for _, m in ipairs(state.members) do
    if p:sub(1, #m.abspath + 1) == m.abspath .. '/' and
       (not best or #m.abspath > #best.abspath) then
      best = m
    end
  end
  return best
end

function M.active() return state.active end

-- The directory repo-scoped operations (Claude, tests, CLAUDE.md) should run in:
-- the active repo's root, falling back to cwd in single-repo / no-match cases.
function M.active_cwd()
  return (state.active and state.active.abspath) or fn.getcwd()
end

-- Cached status only — never shells out (safe to call from winbar redraw).
function M.status(member)
  return member and state.status[member.abspath] or nil
end

-- ── Active-repo tracking ──────────────────────────────────────────────────────

-- Recompute the active repo from the current buffer; fire an event on change.
function M.refresh_active(force)
  if not state.loaded then return end
  local name = api.nvim_buf_get_name(api.nvim_get_current_buf())
  local m = name ~= '' and M.of(name) or state.active
  if m == state.active and not force then return end
  state.active = m
  if m then M.refresh_status(m) end
  api.nvim_exec_autocmds('User', { pattern = 'ClaudespaceRepoChanged', modeline = false })
end

-- Asynchronously refresh a repo's git status, then redraw the winbar.
function M.refresh_status(member)
  if not member then return end
  local cached = state.status[member.abspath]
  if cached and (uv.now() - cached.ts) < STATUS_TTL then return end
  state.status[member.abspath] = cached or { branch = '', ahead = 0, behind = 0, dirty = 0, ts = 0 }
  vim.system(
    { 'git', '-C', member.abspath, 'status', '--porcelain=v1', '--branch' },
    { text = true },
    vim.schedule_wrap(function(res)
      local st = { branch = '', ahead = 0, behind = 0, dirty = 0, ts = uv.now() }
      if res.code == 0 then
        local lines = vim.split(res.stdout or '', '\n', { trimempty = true })
        for i, line in ipairs(lines) do
          if i == 1 and line:sub(1, 2) == '##' then
            local head = line:sub(4)  -- text after "## "
            if head:match('^No commits yet on ') then
              st.branch = head:gsub('^No commits yet on ', '')
            elseif head:match('%(no branch%)') then
              st.branch = 'detached'
            else
              st.branch = head:match('^([^%.%s]+)') or ''
            end
            st.ahead  = tonumber(line:match('ahead (%d+)'))  or 0
            st.behind = tonumber(line:match('behind (%d+)')) or 0
          elseif line ~= '' then
            st.dirty = st.dirty + 1
          end
        end
      end
      state.status[member.abspath] = st
      pcall(vim.cmd, 'redrawstatus!')
    end)
  )
end

-- ── Manifest authoring ────────────────────────────────────────────────────────

-- Generate a starter manifest from a scan: one glob per parent dir of a repo.
function M.init_manifest()
  local cwd  = fn.getcwd()
  local root = find_root(cwd) or strip_slash(fn.fnamemodify(cwd, ':p'))
  local dir  = root .. '/.claudespace'
  local path = dir .. '/' .. fn.fnamemodify(MANIFEST, ':t')

  local parents, exact = {}, {}
  for _, d in ipairs(scan_repos(root)) do
    local rel = d:sub(#root + 2)
    local p   = fn.fnamemodify(rel, ':h')
    if p == '.' then exact[rel] = true else parents[p] = true end
  end
  local include = {}
  for p in pairs(parents) do table.insert(include, p .. '/*') end
  for e in pairs(exact)   do table.insert(include, e) end
  table.sort(include)

  local manifest = {
    name    = fn.fnamemodify(root, ':t'),
    include = include,
    exclude = {},
    pin     = {},
  }
  fn.mkdir(dir, 'p')
  fn.writefile(vim.split(fn.json_encode(manifest), '\n'), path)
  M.load()
  vim.notify(('claudespace: wrote %s (%d repos)'):format(
    fn.fnamemodify(path, ':~'), #state.members), vim.log.levels.INFO)
end

-- ── Overview float (verification surface for phase 1) ─────────────────────────

function M.show()
  if not state.loaded then M.load() end
  local active = state.active
  local lines, line_member = {}, {}
  local function add(text, member) lines[#lines + 1] = text; line_member[#lines] = member end

  add('')
  add('  ' .. (state.name or '?')
      .. (state.implicit and '  (scanned — :ClaudespaceWorkspaceInit to pin)' or ''))
  add('')
  local last_group
  for _, m in ipairs(state.members) do
    if m.group ~= last_group then add('  ' .. m.group); last_group = m.group end
    local st   = state.status[m.abspath]
    local mark = (m == active) and '▎' or ' '
    local info = ''
    if st then
      if st.branch ~= '' then info = info .. '  ' .. st.branch end
      if st.dirty  > 0  then info = info .. ' ●' .. st.dirty  end
      if st.ahead  > 0  then info = info .. ' ↑' .. st.ahead  end
      if st.behind > 0  then info = info .. ' ↓' .. st.behind end
    end
    add(mark .. '   ' .. m.label .. info, m)
    M.refresh_status(m)
  end
  add('')
  add('  ⏎ jump   g git   c claude   q close')

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 56
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' Repos ', title_pos = 'center',
    width = width, height = math.min(#lines, vim.o.lines - 4),
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })

  local function close() pcall(api.nvim_win_close, win, true) end
  local function member_here()
    return line_member[api.nvim_win_get_cursor(win)[1]]
  end
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', function()
    local m = member_here(); if not m then return end
    close()
    pcall(function() require('claudespace.filetree').focus_path(m.abspath) end)
  end, o)
  vim.keymap.set('n', 'g', function()
    local m = member_here(); if not m then return end
    close()
    pcall(function() require('claudespace.git_ui').open(nil, m.abspath) end)
  end, o)
  vim.keymap.set('n', 'c', function()
    local m = member_here(); if not m then return end
    close()
    pcall(function() require('claudespace.claude.sessions').new(m.abspath) end)
  end, o)
  for _, k in ipairs { 'q', '<Esc>' } do vim.keymap.set('n', k, close, o) end

  -- place cursor on the first repo line
  for i = 1, #lines do
    if line_member[i] then pcall(api.nvim_win_set_cursor, win, { i, 0 }); break end
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  M.load()

  api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
    callback = function() M.refresh_active() end,
  })
  -- A cwd change can mean a different workspace → full reload (re-scan). On mere
  -- focus regain, only re-stat the active repo (the scan is too heavy to repeat).
  api.nvim_create_autocmd('DirChanged', { callback = function() M.load() end })
  api.nvim_create_autocmd('FocusGained', {
    callback = function()
      if state.active then
        state.status[state.active.abspath] = nil  -- bust TTL so it refetches
        M.refresh_status(state.active)
      end
    end,
  })

  api.nvim_create_user_command('ClaudespaceWorkspaceInit', M.init_manifest,
    { desc = 'Generate .claudespace/workspace.json from a repo scan' })
  api.nvim_create_user_command('ClaudespaceRepos', M.show,
    { desc = 'Show workspace repos' })

  vim.keymap.set('n', '<leader>wp', M.show, { silent = true, desc = 'Workspace: repos overview' })
end

return M
