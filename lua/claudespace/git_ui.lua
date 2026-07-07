-- Git source control:
--   * a REPOSITORIES overview panel (sidebar) — every workspace repo with its
--     branch/dirty/ahead/behind, nested under group dirs like the file tree;
--   * <CR> on a repo opens that repo's CHANGES / staging view in the center
--     window (roomy), where files are staged, diffed, committed and pushed.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_gitui')

local STATUS_HL = {
  M = 'DiagnosticWarn',  A = 'DiagnosticOk',
  D = 'DiagnosticError', R = 'DiagnosticHint',
  ['?'] = 'Comment',     ['!'] = 'Comment',
}

local function active_repo()
  local ok, repos = pcall(require, 'claudespace.repos')
  local m = ok and repos.active()
  return (m and m.abspath) or fn.getcwd()
end

-- A workspace member is only shown in source control if it is actually a git
-- repo. Container dirs matched by the workspace globs (e.g. `services/`) have no
-- `.git` and nothing to commit — they still appear as group headers via their
-- children's paths, just not as a bare row. Cheap stat, no subprocess.
local function is_git_repo(abspath)
  return vim.uv.fs_stat(abspath .. '/.git') ~= nil
end

-- Staged / unstaged file lists for one repo.
local function parse_status(cwd)
  local unstaged, staged = {}, {}
  local out = fn.system('git -C ' .. fn.shellescape(cwd) .. ' status --porcelain=v1 2>/dev/null')
  for line in out:gmatch('[^\n]+') do
    if #line >= 4 then
      local x, y = line:sub(1, 1), line:sub(2, 2)
      local path = line:sub(4)
      path = path:match('^"(.+)"$') or path
      path = path:match('.+ %-> (.+)') or path
      if x ~= ' ' and x ~= '?' and x ~= '!' then
        table.insert(staged,   { status = x, path = path })
      end
      if y ~= ' ' then
        table.insert(unstaged, { status = y == '?' and '?' or y, path = path })
      end
    end
  end
  return unstaged, staged
end

-- build_repos calls repo_status for every visible repo on each render (fold,
-- cursor, refresh); a short TTL cache avoids re-spawning `git status` N times
-- per interaction. Explicit refresh (r / F) clears it.
local _status_cache = {}
local STATUS_TTL_MS = 2000
local function clear_status_cache() _status_cache = {} end

-- Lightweight, synchronous per-repo status: branch + dirty/ahead/behind.
local function repo_status(abspath)
  local now = vim.uv.now()
  local cached = _status_cache[abspath]
  if cached and (now - cached.ts) < STATUS_TTL_MS then return cached.st end

  local out = fn.system('git -C ' .. fn.shellescape(abspath)
                      .. ' status --porcelain=v1 --branch 2>/dev/null')
  local st = { branch = '', ahead = 0, behind = 0, dirty = 0 }
  for line in out:gmatch('[^\n]+') do
    if line:sub(1, 2) == '##' then
      local head = line:sub(4)
      if head:match('^No commits yet on ') then
        st.branch = head:gsub('^No commits yet on ', '')
      else
        st.branch = head:match('^(.-)%.%.%.') or head:match('^([^%s]+)') or head
      end
      st.ahead  = tonumber(line:match('ahead (%d+)'))  or 0
      st.behind = tonumber(line:match('behind (%d+)')) or 0
    else
      st.dirty = st.dirty + 1
    end
  end
  _status_cache[abspath] = { st = st, ts = now }
  return st
end

-- ── buffer render helper ───────────────────────────────────────────────────────

local function paint(buf, lines, hls)
  -- The CHANGES buffer is bufhidden='wipe'; an async flow (e.g. the Claude
  -- commit-message generation) can refresh after it's gone.
  if not api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end
end

-- ── REPOSITORIES overview (sidebar) ────────────────────────────────────────────

local function build_repos(selected)
  local lines, hls, actions = {}, {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end
  local function act(a) actions[#lines] = a end

  local ok, repos = pcall(require, 'claudespace.repos')
  local list = ok and repos.list() or {}
  if #list == 0 then
    -- No workspace: treat the active repo as the single member.
    local abs = active_repo()
    list = { { abspath = abs, label = fn.fnamemodify(abs, ':t'), path = fn.fnamemodify(abs, ':t') } }
  end

  add('')
  add('  REPOSITORIES', 'CSTreeDir')

  -- Build a path tree from the members. A node is a *repo* when a git member
  -- sits exactly at its path, a *container* when members nest under it — and can
  -- be both (e.g. `services` is a repo that also holds `services/*`). A both-node
  -- renders once, as a foldable repo header, so nothing is duplicated.
  local root = { children = {}, order = {} }
  local function ensure(path)
    local node = root
    local acc = ''
    for _, seg in ipairs(vim.split(path, '/')) do
      acc = acc == '' and seg or (acc .. '/' .. seg)
      if not node.children[seg] then
        node.children[seg] = { label = seg, path = acc, children = {}, order = {} }
        table.insert(node.order, seg)
      end
      node = node.children[seg]
    end
    return node
  end
  for _, m in ipairs(list) do
    if is_git_repo(m.abspath) then           -- only real repos; container-only dirs stay implicit
      local n = ensure(m.path or m.label or '')
      n.is_repo, n.abspath = true, m.abspath
    end
  end

  local collapsed = M._collapsed or {}
  local function walk(node, depth)
    table.sort(node.order)
    for _, seg in ipairs(node.order) do
      local n        = node.children[seg]
      local has_kids = #n.order > 0
      local folded   = collapsed[n.path] or false
      local indent   = '  ' .. string.rep('  ', depth)
      if n.is_repo then
        local st   = repo_status(n.abspath)  -- subprocess only for visible rows
        local info = st.branch
          .. (st.dirty  > 0 and (' ●' .. st.dirty)  or '')
          .. (st.ahead  > 0 and (' ↑' .. st.ahead)  or '')
          .. (st.behind > 0 and (' ↓' .. st.behind) or '')
        -- Foldable repo: chevron. Leaf repo: selection mark.
        local chev = has_kids and (folded and '▸ ' or '▾ ')
                  or ((n.abspath == selected) and '▸ ' or '  ')
        add(indent .. chev .. n.label .. '  ' .. info,
          (n.abspath == selected) and 'CSTreeRepoActive' or 'Normal')
        act({ section = 'repo', abspath = n.abspath, path = n.path, foldable = has_kids })
      else
        add(indent .. (folded and '▸ ' or '▾ ') .. n.label, 'CSTreeDir')
        act({ section = 'group', path = n.path })
      end
      if has_kids and not folded then walk(n, depth + 1) end
    end
  end
  walk(root, 0)

  add('')
  add('  <CR> open/fold   h/l fold   r refresh   F pull all', 'CSInfo')
  return lines, hls, actions
end

function M.open(anchor_win)
  M._selected = M._selected or active_repo()

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'cs_gitui'

  local actions = {}
  local function render()
    local l, h, a = build_repos(M._selected)
    paint(buf, l, h)
    actions = a
  end
  render()

  local win
  if anchor_win and api.nvim_win_is_valid(anchor_win) then
    api.nvim_set_current_win(anchor_win)
    vim.cmd 'rightbelow vsplit'
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    api.nvim_win_set_width(win, 44)   -- matches sidebar FIXED_WIDTH.cs_gitui
    vim.wo[win].winfixwidth = true
  else
    local h = math.min(#actions + 8, math.floor(vim.o.lines * 0.7))
    win = api.nvim_open_win(buf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded',
      title = ' Repositories ', title_pos = 'center',
      width = 40, height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - 40) / 2),
    })
  end
  vim.wo[win].number = false
  vim.wo[win].cursorline = true
  M._panel_win = win

  local o = { buffer = buf, nowait = true, silent = true }
  local function cur() return actions[api.nvim_win_get_cursor(win)[1]] end
  local close = function() pcall(api.nvim_win_close, win, true); M._panel_win = nil end

  -- Re-render in place, keeping the cursor on its row (group headers stay put
  -- when folding, so the row is a stable anchor).
  local function rerender()
    local row = api.nvim_win_get_cursor(win)[1]
    render()
    pcall(api.nvim_win_set_cursor, win, { math.min(row, api.nvim_buf_line_count(buf)), 0 })
  end

  local function set_fold(path, want)
    M._collapsed = M._collapsed or {}
    M._collapsed[path] = want or nil
    rerender()
  end

  vim.keymap.set('n', 'q',     close,  o)
  vim.keymap.set('n', '<Esc>', close,  o)
  vim.keymap.set('n', 'r',     function() clear_status_cache(); render() end, o)

  local function open_repo(abspath)
    M._selected = abspath
    render()                    -- move the ▸ marker
    M.show_changes(abspath)     -- open its changes in the center window
  end

  vim.keymap.set('n', '<CR>', function()
    local a = cur()
    if not a then return end
    if a.section == 'group' then
      set_fold(a.path, not (M._collapsed and M._collapsed[a.path]))
    elseif a.section == 'repo' then
      open_repo(a.abspath)
    end
  end, o)

  -- h collapse / l expand-or-open, tree-style. A repo that is also a container
  -- (foldable) collapses/expands with h/l but still opens on <CR>.
  vim.keymap.set('n', 'h', function()
    local a = cur()
    if not a then return end
    if a.section == 'group' or (a.section == 'repo' and a.foldable) then set_fold(a.path, true) end
  end, o)
  vim.keymap.set('n', 'l', function()
    local a = cur()
    if not a then return end
    if a.section == 'group' then
      set_fold(a.path, false)
    elseif a.section == 'repo' then
      if a.foldable and M._collapsed and M._collapsed[a.path] then set_fold(a.path, false)
      else open_repo(a.abspath) end
    end
  end, o)

  -- Fleet action: fetch + fast-forward pull every workspace repo at once.
  vim.keymap.set('n', 'F', function()
    local ok, repos = pcall(require, 'claudespace.repos')
    local list = ok and repos.list() or {}
    if #list == 0 then vim.notify('Not a multi-repo workspace', vim.log.levels.INFO); return end
    local remaining, results = #list, {}
    vim.notify('Fetch/pull ' .. remaining .. ' repos…', vim.log.levels.INFO)
    local function finish(label, code)
      results[#results + 1] = '  ' .. label .. (code == 0 and ' ✓' or ' ✗')
      remaining = remaining - 1
      if remaining == 0 then
        vim.schedule(function()
          table.sort(results)
          vim.notify('Pull all repos:\n' .. table.concat(results, '\n'), vim.log.levels.INFO)
          clear_status_cache()
          if M._panel_win and api.nvim_win_is_valid(M._panel_win) then render() end
        end)
      end
    end
    for _, m in ipairs(list) do
      local label = m.label or fn.fnamemodify(m.abspath, ':t')
      local job = fn.jobstart({ 'git', '-C', m.abspath, 'pull', '--ff-only' }, {
        on_exit = function(_, code) finish(label, code) end,
      })
      -- A failed launch never fires on_exit — count it now so the summary still fires.
      if job <= 0 then finish(label, -1) end
    end
  end, o)
end

-- ── CHANGES / staging (center window) ──────────────────────────────────────────

local function build_changes(cwd)
  local lines, hls, actions = {}, {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end
  local function act(a) actions[#lines] = a end

  local st = repo_status(cwd)
  add('')
  add('  CHANGES  [' .. st.branch .. ']  ' .. fn.fnamemodify(cwd, ':~'), 'CSTreeDir')
  add('')

  local unstaged, staged = parse_status(cwd)
  if #unstaged > 0 then
    add('  ─ Unstaged (' .. #unstaged .. ') ─────────────────────────────', 'CSWinbarDir')
    for _, f in ipairs(unstaged) do
      add('  ' .. f.status .. '  ' .. f.path, STATUS_HL[f.status] or 'Normal')
      act({ section = 'unstaged', path = f.path, status = f.status })
    end
    add('')
  end
  if #staged > 0 then
    add('  ─ Staged (' .. #staged .. ') ───────────────────────────────', 'CSGit')
    for _, f in ipairs(staged) do
      add('  ' .. f.status .. '  ' .. f.path, STATUS_HL[f.status] or 'Normal')
      act({ section = 'staged', path = f.path, status = f.status })
    end
    add('')
  end
  if #unstaged == 0 and #staged == 0 then
    add('  (nothing to commit, working tree clean)', 'Comment')
    add('')
  end

  add('  s stage/unstage  d diff  c commit  P push  r refresh  q back', 'CSInfo')
  return lines, hls, actions
end

function M.show_changes(cwd)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  -- NB: a distinct filetype (not cs_gitui) so sidebar.repin_widths — which pins
  -- every cs_gitui window to 44 cols — doesn't shrink this center content window.
  vim.bo[buf].filetype  = 'cs_gitchanges'

  local actions = {}
  local function render()
    local l, h, a = build_changes(cwd)
    paint(buf, l, h)
    actions = a
  end
  render()

  local win = require('claudespace.shell').open(buf)  -- center + focus
  vim.wo[win].number = false
  vim.wo[win].cursorline = true

  local o = { buffer = buf, nowait = true, silent = true }
  local function cur() return actions[api.nvim_win_get_cursor(win)[1]] end

  vim.keymap.set('n', 'r', render, o)
  vim.keymap.set('n', 'q', function()
    if M._panel_win and api.nvim_win_is_valid(M._panel_win) then
      api.nvim_set_current_win(M._panel_win)
    end
  end, o)

  vim.keymap.set('n', 's', function()
    local a = cur()
    if not (a and a.path) then return end
    if a.section == 'unstaged' then
      fn.system('git -C ' .. fn.shellescape(cwd) .. ' add -- ' .. fn.shellescape(a.path))
    else
      fn.system('git -C ' .. fn.shellescape(cwd) .. ' restore --staged -- ' .. fn.shellescape(a.path))
    end
    render()
  end, o)

  vim.keymap.set('n', '<CR>', function()
    local a = cur()
    if not (a and a.path) then return end
    pcall(vim.cmd, 'edit ' .. fn.fnameescape(cwd .. '/' .. a.path))
  end, o)

  vim.keymap.set('n', 'd', function()
    local a = cur()
    if not (a and a.path) then return end
    local diff_cmd = a.section == 'staged'
      and 'diff --staged -- ' .. fn.shellescape(a.path)
      or  'diff -- '          .. fn.shellescape(a.path)
    local diff = fn.system('git -C ' .. fn.shellescape(cwd) .. ' ' .. diff_cmd)
    if diff == '' then
      vim.notify('No diff for ' .. a.path, vim.log.levels.INFO)
      return
    end
    vim.cmd 'botright new'
    local dbuf = api.nvim_get_current_buf()
    vim.bo[dbuf].buftype = 'nofile'; vim.bo[dbuf].bufhidden = 'wipe'
    vim.bo[dbuf].filetype = 'diff'; vim.bo[dbuf].modifiable = true
    api.nvim_buf_set_lines(dbuf, 0, -1, false, vim.split(diff, '\n'))
    vim.bo[dbuf].modifiable = false
    vim.keymap.set('n', 'q', function() vim.cmd 'bd' end, { buffer = dbuf, silent = true })
  end, o)

  vim.keymap.set('n', 'c', function()
    local diff = fn.trim(fn.system('git -C ' .. fn.shellescape(cwd) .. ' diff --staged 2>/dev/null'))
    if diff == '' then
      vim.notify('Nothing staged to commit', vim.log.levels.WARN)
      return
    end

    local function do_commit(prefill)
      vim.ui.input({ prompt = 'Commit message: ', default = prefill or '' }, function(msg)
        if not msg or msg == '' then return end
        local out = fn.system('git -C ' .. fn.shellescape(cwd)
                            .. ' commit -m ' .. fn.shellescape(msg) .. ' 2>&1')
        vim.notify(out, vim.log.levels.INFO)
        render()
      end)
    end

    -- Try to generate via Claude; fall back to blank input on any failure.
    if fn.executable('claude') == 0 then do_commit(); return end

    vim.notify('Generating commit message…', vim.log.levels.INFO)
    local prompt = 'Generate a concise, conventional-commits git commit message for this diff.\n'
                .. 'Rules: imperative mood, ≤72 chars, no quotes, no explanation — output ONLY the message.\n\n'
                .. diff
    local result = {}
    fn.jobstart({ 'claude', '--print', prompt }, {
      cwd = cwd,
      stdout_buffered = true,
      on_stdout = function(_, data) if data then vim.list_extend(result, data) end end,
      on_exit = function(_, code)
        vim.schedule(function()
          local generated = code == 0 and fn.trim(table.concat(result, '\n')) or ''
          do_commit(generated ~= '' and generated or nil)
        end)
      end,
    })
  end, o)

  vim.keymap.set('n', 'P', function()
    vim.notify('Pushing…', vim.log.levels.INFO)
    local out = fn.system('git -C ' .. fn.shellescape(cwd) .. ' push 2>&1')
    vim.notify(out ~= '' and out or 'Push complete.', vim.log.levels.INFO)
    render()
  end, o)
end

function M.close()
  if M._panel_win and api.nvim_win_is_valid(M._panel_win) then
    pcall(api.nvim_win_close, M._panel_win, true)
  end
  M._panel_win = nil
end

function M.setup()
  -- <leader>gG = Git source-control panel (uppercase to distinguish from gitsigns hunks)
  vim.keymap.set('n', '<leader>gG', function() M.open() end, { desc = 'Git: source control', silent = true })
end

return M
