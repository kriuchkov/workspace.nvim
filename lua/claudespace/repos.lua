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
  state.root     = root
  state.members  = members
  state.loaded   = true
  state.status   = {}
  state.purpose  = {}
  state.depgraph = nil
  state.active   = nil
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

-- The member whose root is exactly `path` (repos.of matches descendants only).
function M.at(path)
  path = strip_slash(fn.fnamemodify(path, ':p'))
  for _, m in ipairs(state.members) do
    if m.abspath == path then return m end
  end
end

-- ── Workspace map (for Claude context) ────────────────────────────────────────

-- One-line purpose of a repo: first heading/prose line of its CLAUDE.md/README.
function M.purpose(member)
  if state.purpose[member.abspath] == nil then
    -- Skip uninformative titles (the filename or the repo's own name); keep the
    -- first one as a fallback but prefer a real description line.
    local generic = {
      ['claude.md'] = true, ['readme'] = true, ['readme.md'] = true,
      [member.label:lower()] = true,
    }
    local result, fallback
    for _, f in ipairs { '/CLAUDE.md', '/README.md' } do
      local p = member.abspath .. f
      if fn.filereadable(p) == 1 then
        for _, line in ipairs(fn.readfile(p, '', 20)) do
          local t = vim.trim(line):gsub('^#+%s*', '')
          if t ~= '' and not t:match('^%-%-%-') and not t:match('^!%[') then
            if generic[t:lower()] then
              fallback = fallback or t
            else
              result = t; break
            end
          end
        end
      end
      if result then break end
    end
    state.purpose[member.abspath] = result or fallback or false
  end
  return state.purpose[member.abspath] or nil
end

local function go_module_path(abspath)
  local gomod = abspath .. '/go.mod'
  if fn.filereadable(gomod) == 0 then return nil end
  for _, line in ipairs(fn.readfile(gomod, '', 5)) do
    local m = line:match('^module%s+(%S+)')
    if m then return m end
  end
end

local function js_name(abspath)
  local pkg = abspath .. '/package.json'
  if fn.filereadable(pkg) == 0 then return nil end
  local ok, data = pcall(fn.json_decode, table.concat(fn.readfile(pkg), '\n'))
  if ok and type(data) == 'table' then return data.name end
end

-- Intra-workspace dependency edges: repo.path -> { dep repo.path, ... }.
-- Resolves Go (go.mod requires → module), Rust (Cargo.toml path deps) and
-- JS/TS (package.json deps by package name) against other members.
function M.dependency_graph()
  if state.depgraph then return state.depgraph end
  local go_mod, js_pkg = {}, {}
  for _, m in ipairs(state.members) do
    local gp = go_module_path(m.abspath); if gp then go_mod[gp] = m.path end
    local jn = js_name(m.abspath);        if jn then js_pkg[jn] = m.path end
  end

  local graph = {}
  for _, m in ipairs(state.members) do
    local deps = {}
    local function edge(to) if to and to ~= m.path then deps[to] = true end end

    local gomod = m.abspath .. '/go.mod'
    if fn.filereadable(gomod) == 1 then
      for _, line in ipairs(fn.readfile(gomod)) do
        local dep = line:match('^%s+(%S+)%s+v') or line:match('^require%s+(%S+)%s+v')
        if dep then edge(go_mod[dep]) end
      end
    end

    local cargo = m.abspath .. '/Cargo.toml'
    if fn.filereadable(cargo) == 1 then
      for _, line in ipairs(fn.readfile(cargo)) do
        local p = line:match('path%s*=%s*"([^"]+)"')
        if p then
          local target = strip_slash(fn.fnamemodify(m.abspath .. '/' .. p, ':p'))
          local tm = M.at(target); if tm then edge(tm.path) end
        end
      end
    end

    local pkg = m.abspath .. '/package.json'
    if fn.filereadable(pkg) == 1 then
      local ok, data = pcall(fn.json_decode, table.concat(fn.readfile(pkg), '\n'))
      if ok and type(data) == 'table' then
        for _, field in ipairs { 'dependencies', 'devDependencies' } do
          if type(data[field]) == 'table' then
            for name in pairs(data[field]) do edge(js_pkg[name]) end
          end
        end
      end
    end

    local list = {}
    for d in pairs(deps) do list[#list + 1] = d end
    if #list > 0 then table.sort(list); graph[m.path] = list end
  end
  state.depgraph = graph
  return graph
end

function M.module_path(member) return go_module_path(member.abspath) end

-- Members that depend on `path` (reverse edges of the dependency graph).
function M.dependents(path)
  local by_path = {}
  for _, m in ipairs(state.members) do by_path[m.path] = m end
  local out = {}
  for from, tos in pairs(M.dependency_graph()) do
    for _, to in ipairs(tos) do
      if to == path then out[#out + 1] = by_path[from]; break end
    end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

-- Members that at least one other member depends on (bump candidates).
function M.depended_upon()
  local set, by_path = {}, {}
  for _, m in ipairs(state.members) do by_path[m.path] = m end
  for _, tos in pairs(M.dependency_graph()) do
    for _, to in ipairs(tos) do set[to] = true end
  end
  local out = {}
  for p in pairs(set) do if by_path[p] then out[#out + 1] = by_path[p] end end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

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

  -- Write indented JSON by hand (json_encode is compact) so the manifest stays
  -- easy to hand-edit.
  local function arr(t)
    if #t == 0 then return '[]' end
    local items = {}
    for _, v in ipairs(t) do items[#items + 1] = '    ' .. fn.json_encode(v) end
    return '[\n' .. table.concat(items, ',\n') .. '\n  ]'
  end
  local json = table.concat({
    '{',
    '  "name": ' .. fn.json_encode(fn.fnamemodify(root, ':t')) .. ',',
    '  "include": ' .. arr(include) .. ',',
    '  "exclude": [],',
    '  "pin": []',
    '}',
  }, '\n')
  fn.mkdir(dir, 'p')
  fn.writefile(vim.split(json, '\n'), path)
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
  vim.wo[win].wrap = true; vim.wo[win].linebreak = true; vim.wo[win].breakindent = true

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

-- Info card for a repo (resolved from an exact root or any path inside it):
-- purpose, branch/status, module, and its place in the dependency graph.
function M.show_info(path)
  if not state.loaded then M.load() end
  local m = M.at(path) or M.of(path)
  if not m then vim.notify('Not inside a workspace repo', vim.log.levels.WARN); return end

  M.refresh_status(m)  -- refresh the shared cache for other surfaces
  local st = state.status[m.abspath] or {}
  -- For the card itself, fetch branch + dirty synchronously (one repo, fast) so
  -- they always show even on the very first open before the async cache fills.
  local branch = vim.trim(fn.system({ 'git', '-C', m.abspath, 'rev-parse', '--abbrev-ref', 'HEAD' }))
  if vim.v.shell_error ~= 0 or branch == '' or branch == 'HEAD' then branch = st.branch or branch end
  local dirty = 0
  local d = fn.systemlist({ 'git', '-C', m.abspath, 'status', '--porcelain' })
  if vim.v.shell_error == 0 then dirty = #d end

  local lines, hls = {}, {}
  local function add(s, hl)
    lines[#lines + 1] = s
    if hl then hls[#hls + 1] = { #lines - 1, 0, -1, hl } end
  end

  add('')
  add('  ' .. m.label .. '   ' .. m.path, 'CSTreeDir')
  local sline = '  '
  if branch ~= '' then sline = sline .. branch .. '   ' end
  sline = sline .. (dirty     > 0 and ('●' .. dirty     .. ' ') or '')
                .. (st.ahead  and st.ahead  > 0 and ('↑' .. st.ahead  .. ' ') or '')
                .. (st.behind and st.behind > 0 and ('↓' .. st.behind .. ' ') or '')
  if vim.trim(sline) ~= '' then add(sline, 'Comment') end
  local purpose = M.purpose(m)
  if purpose then add('  ' .. purpose, 'String') end
  local mod = M.module_path(m)
  if mod then add('  module: ' .. mod, 'Comment') end
  add('')

  local deps = M.dependency_graph()[m.path]
  add('  Depends on', 'CSWinbarDir')
  if deps then for _, d in ipairs(deps) do add('    → ' .. d) end else add('    (none)', 'Comment') end
  add('')

  local dependents = M.dependents(m.path)
  add('  Depended on by (' .. #dependents .. ')', 'CSWinbarDir')
  if #dependents > 0 then
    for _, d in ipairs(dependents) do add('    ← ' .. d.path) end
  else
    add('    (none)', 'Comment')
  end
  add('')

  local last = fn.systemlist({ 'git', '-C', m.abspath, 'log', '-1', '--pretty=%h  %s' })
  if vim.v.shell_error == 0 and last[1] then add('  last: ' .. last[1], 'Comment'); add('') end

  add('  g git   c claude   ⏎ tree   q close', 'Comment')

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local NSI = api.nvim_create_namespace('cs_repoinfo')
  for _, h in ipairs(hls) do api.nvim_buf_add_highlight(buf, NSI, h[4], h[1], h[2], h[3]) end
  vim.bo[buf].modifiable = false
  local width  = 62
  local height = math.min(#lines, vim.o.lines - 4)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' ' .. m.label .. ' ', title_pos = 'center',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].wrap = true; vim.wo[win].linebreak = true; vim.wo[win].breakindent = true

  local function close() pcall(api.nvim_win_close, win, true) end
  local function act(fnc) return function() close(); pcall(fnc) end end
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'g', act(function() require('claudespace.git_ui').open(nil, m.abspath) end), o)
  vim.keymap.set('n', 'c', act(function() require('claudespace.claude.sessions').new(m.abspath) end), o)
  vim.keymap.set('n', '<CR>', act(function() require('claudespace.filetree').focus_path(m.abspath) end), o)
  for _, k in ipairs { 'q', '<Esc>' } do vim.keymap.set('n', k, close, o) end
end

-- Open a terminal in a bottom split rooted at the active repo (not the whole
-- workspace) — for `go test ./...` / `cargo test` in the right service.
function M.terminal()
  local cwd = M.active_cwd()
  vim.cmd 'botright split'
  api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.28))
  local buf = api.nvim_create_buf(true, false)
  api.nvim_win_set_buf(0, buf)
  fn.termopen(vim.o.shell, { cwd = cwd })
  vim.cmd 'startinsert'
  vim.notify('Terminal in ' .. fn.fnamemodify(cwd, ':t'), vim.log.levels.INFO)
end

local function scoped_member(member)
  return member or M.at(M.active_cwd())
    or { abspath = M.active_cwd(), label = fn.fnamemodify(M.active_cwd(), ':t') }
end

-- Launch from a real editor window so the selected file doesn't try to open in
-- the tree / a winfixbuf window (which silently fails).
local function in_editor()
  pcall(function() require('claudespace.claude.util').ensure_editor_win() end)
end

-- Fuzzy-find files scoped to a single repo (defaults to the active one).
function M.find_files(member)
  member = scoped_member(member)
  local ok, tb = pcall(require, 'telescope.builtin')
  if not ok then vim.notify('telescope required for file search', vim.log.levels.WARN); return end
  in_editor()
  tb.find_files({ cwd = member.abspath, prompt_title = 'Files in ' .. (member.label or '?') })
end

-- Live-grep scoped to a single repo (defaults to the active one).
function M.grep_files(member)
  member = scoped_member(member)
  local ok, tb = pcall(require, 'telescope.builtin')
  if not ok then vim.notify('telescope required for grep', vim.log.levels.WARN); return end
  in_editor()
  tb.live_grep({ cwd = member.abspath, prompt_title = 'Grep in ' .. (member.label or '?') })
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
  vim.keymap.set('n', '<leader>wT', M.terminal, { silent = true, desc = 'Workspace: terminal in active repo' })
  vim.keymap.set('n', '<leader>fr', function() M.find_files() end,
    { silent = true, desc = 'Find files in active repo' })
  vim.keymap.set('n', '<leader>fG', function() M.grep_files() end,
    { silent = true, desc = 'Grep in active repo' })
end

return M
