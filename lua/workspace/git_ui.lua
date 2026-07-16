-- Git source control:
--   * a REPOSITORIES overview panel (sidebar) — every workspace repo with its
--     branch/dirty/ahead/behind, nested under group dirs like the file tree;
--   * <CR> on a repo opens that repo's CHANGES / staging view in the center
--     window (roomy), where files are staged, diffed, committed and pushed.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_gitui')

local _mini_icons_ok, MiniIcons = pcall(require, 'mini.icons')

-- Status letter + colour per porcelain code, VS Code-style (untracked → green U).
local STATUS_HL = {
  M = 'DiagnosticWarn',  A = 'DiagnosticOk',
  D = 'DiagnosticError', R = 'DiagnosticHint',
  ['?'] = 'DiagnosticOk', U = 'DiagnosticOk', ['!'] = 'Comment',
}
local STATUS_LETTER = { ['?'] = 'U' }

local function active_repo()
  local ok, repos = pcall(require, 'workspace.repos')
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

  local ok, repos = pcall(require, 'workspace.repos')
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
  add('  <CR> open/fold   h/l fold', 'CSInfo')
  add('  r refresh   F pull-all repos', 'CSInfo')
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
  local close = function()
    if M._changes_win and api.nvim_win_is_valid(M._changes_win) then
      pcall(api.nvim_win_close, M._changes_win, true)
    end
    M._changes_win = nil
    pcall(api.nvim_win_close, win, true); M._panel_win = nil
  end

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
    local ok, repos = pcall(require, 'workspace.repos')
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

local function file_icon(name)
  if not _mini_icons_ok then return '', nil end
  local ok, ic, hl = pcall(MiniIcons.get, 'file', name)
  if ok then return ic, hl end
  return '', nil
end

-- Terminal grids can't shrink a font per-cell, so the "smaller" path is faked:
-- intermediate dirs collapse to their first letter (internal/app/commands →
-- i/a/commands) and the whole thing is painted very faint.
local function abbrev_dir(dir)
  local parts = vim.split(dir, '/', { plain = true })
  for i = 1, #parts - 1 do
    if #parts[i] > 0 then parts[i] = parts[i]:sub(1, 1) end
  end
  return table.concat(parts, '/')
end

local function apply_hl()
  local ok, theme = pcall(require, 'workspace.theme')
  local c = ok and theme.colors() or {}
  api.nvim_set_hl(0, 'CSGitDimPath', { fg = c.fg_faint })
end
apply_hl()
api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = apply_hl })

local function build_changes(cwd, width)
  width = width or 42
  local lines, hls, actions = {}, {}, {}
  -- Whole-line highlight (headers, dividers, hints).
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end

  -- One VS Code-style file row: icon + basename, then a faint directory path
  -- (truncated with a leading … when it won't fit), and the status letter
  -- pinned to the right edge so it's always visible in the narrow panel.
  local function file_rows(files, section_name)
    for _, f in ipairs(files) do
      local base = fn.fnamemodify(f.path, ':t')
      local dir  = fn.fnamemodify(f.path, ':h')
      if dir == '.' then dir = '' else dir = abbrev_dir(dir) end
      local icon, ihl = file_icon(base)

      local segs = { { '  ', nil } }
      if icon ~= '' then table.insert(segs, { icon .. '  ', ihl }) end
      table.insert(segs, { base, 'CSTreeFile' })
      local content, col, seg_hls = '', 0, {}
      for _, s in ipairs(segs) do
        if s[2] and s[1] ~= '' then table.insert(seg_hls, { col, col + #s[1], s[2] }) end
        content = content .. s[1]; col = col + #s[1]
      end
      local lw = fn.strdisplaywidth(content)

      -- Faint dir fills the gap between the name and the right-pinned status,
      -- keeping the tail (most specific folder) when truncated.
      local status_col = width - 1          -- display col of the status letter
      local avail = status_col - lw - 2     -- 1 space after name, 1 before status
      local dir_txt = ''
      if dir ~= '' and avail >= 4 then
        if fn.strdisplaywidth(dir) <= avail then
          dir_txt = dir
        else
          local keep = avail - 1
          dir_txt = dir
          -- Strip whole characters, not bytes — byte-wise :sub(2) leaves broken
          -- UTF-8 heads on multibyte path components.
          while dir_txt ~= '' and fn.strdisplaywidth(dir_txt) > keep do
            dir_txt = fn.strcharpart(dir_txt, 1)
          end
          dir_txt = '…' .. dir_txt
        end
      end

      local mid  = dir_txt ~= '' and (' ' .. dir_txt) or ''
      local used = lw + fn.strdisplaywidth(mid)
      local pad  = string.rep(' ', math.max(1, status_col - used))
      local letter = STATUS_LETTER[f.status] or f.status

      table.insert(lines, content .. mid .. pad .. letter)
      local li = #lines - 1
      for _, sh in ipairs(seg_hls) do table.insert(hls, { li, sh[1], sh[2], sh[3] }) end
      if dir_txt ~= '' then
        local ds = #content + 1             -- byte col just after the ' ' in mid
        table.insert(hls, { li, ds, ds + #dir_txt, 'CSGitDimPath' })
      end
      local scol = #content + #mid + #pad
      table.insert(hls, { li, scol, scol + #letter, STATUS_HL[f.status] or 'Normal' })
      actions[li + 1] = { section = section_name, path = f.path, status = f.status }
    end
  end

  local collapsed = M._changes_collapsed or {}
  local function section(which, label, files, hl)
    if #files == 0 then return end
    local c = collapsed[which]
    add('  ' .. (c and '▸' or '▾') .. ' ' .. label .. '  ' .. #files, hl)
    actions[#lines] = { header = which }
    if not c then file_rows(files, which) end
    add('')
  end

  add('')

  local unstaged, staged = parse_status(cwd)
  section('staged',   'STAGED CHANGES', staged,   'CSGit')
  section('unstaged', 'CHANGES',        unstaged, 'CSWinbarDir')
  if #unstaged == 0 and #staged == 0 then
    add('  (working tree clean)', 'Comment')
    add('')
  end

  add('  <CR> open   s stage   d diff   D split', 'CSInfo')
  add('  c commit   P push   r refresh   q back', 'CSInfo')
  return lines, hls, actions
end

function M.show_changes(cwd)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'cs_gitchanges'

  local actions = {}
  local win
  local function render()
    local tw = 42
    if win and api.nvim_win_is_valid(win) then
      tw = math.max(20, api.nvim_win_get_width(win) - 2)  -- minus signcolumn
    end
    local l, h, a = build_changes(cwd, tw)
    paint(buf, l, h)
    actions = a
  end
  render()

  -- Stack CHANGES below the REPOSITORIES panel, in the same narrow sidebar
  -- column (VS Code Source Control layout). Reuse the sub-window if it's open;
  -- otherwise horizontally split it off the repos panel so both share 44 cols.
  if M._changes_win and api.nvim_win_is_valid(M._changes_win) then
    win = M._changes_win
    api.nvim_win_set_buf(win, buf)
    api.nvim_set_current_win(win)
  elseif M._panel_win and api.nvim_win_is_valid(M._panel_win) then
    local rbuf = api.nvim_win_get_buf(M._panel_win)
    local rh   = math.min(api.nvim_buf_line_count(rbuf) + 1, 12)
    api.nvim_set_current_win(M._panel_win)
    vim.cmd 'rightbelow split'
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    vim.wo[win].winfixwidth = true
    pcall(api.nvim_win_set_height, M._panel_win, rh)
    vim.wo[M._panel_win].winfixheight = true
  else
    -- Fallback (no repos panel open): a fresh left panel, never the center —
    -- sidebar.repin_widths pins cs_gitchanges windows to 44 cols and would
    -- clamp a center window holding this buffer.
    vim.cmd 'topleft vsplit'
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    api.nvim_win_set_width(win, 44)
    vim.wo[win].winfixwidth = true
  end
  M._changes_win = win
  vim.wo[win].number     = false
  vim.wo[win].cursorline = true
  vim.wo[win].wrap       = false

  local o = { buffer = buf, nowait = true, silent = true }
  local function cur() return actions[api.nvim_win_get_cursor(win)[1]] end

  -- Fold a section (staged/unstaged). `which` from a header row or a file row's
  -- own section; nil `want` toggles. Re-render, then keep the cursor in bounds.
  local function fold(which, want)
    if not which then return end
    M._changes_collapsed = M._changes_collapsed or {}
    if want == nil then want = not M._changes_collapsed[which] end
    M._changes_collapsed[which] = want or nil
    render()
    local n = api.nvim_buf_line_count(buf)
    if api.nvim_win_get_cursor(win)[1] > n then
      pcall(api.nvim_win_set_cursor, win, { n, 0 })
    end
  end
  local function section_of(a) return a and (a.header or a.section) end

  vim.keymap.set('n', 'r', render, o)
  vim.keymap.set('n', 'q', function()
    if M._panel_win and api.nvim_win_is_valid(M._panel_win) then
      api.nvim_set_current_win(M._panel_win)
    end
  end, o)
  vim.keymap.set('n', 'h', function() fold(section_of(cur()), true)  end, o)
  vim.keymap.set('n', 'l', function() fold(section_of(cur()), false) end, o)

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
    if not a then return end
    if a.header then fold(a.header) return end
    if not a.path then return end
    -- Open in the center window, not this narrow sidebar sub-panel.
    api.nvim_set_current_win(require('workspace.shell').center())
    pcall(vim.cmd, 'edit ' .. fn.fnameescape(cwd .. '/' .. a.path))
  end, o)

  -- D: side-by-side (native) diff in the center window; d: quick unified popup.
  -- diff_from wires ]f/[f cycling across the panel's changed files.
  vim.keymap.set('n', 'D', function()
    local a = cur()
    if not (a and a.path) then return end
    require('workspace.gitdiff').diff_from(cwd, a.path, a.section == 'staged')
  end, o)

  vim.keymap.set('n', 'd', function()
    local a = cur()
    if not (a and a.path) then return end
    -- Untracked files have no diff against the index; show the whole file as
    -- added via --no-index against /dev/null (exits 1, so ignore the status).
    local diff_cmd = a.status == '?'
      and 'diff --no-index --no-color -- /dev/null ' .. fn.shellescape(a.path)
      or (a.section == 'staged'
      and 'diff --staged -- ' .. fn.shellescape(a.path)
      or  'diff -- '          .. fn.shellescape(a.path))
    local diff = fn.system('git -C ' .. fn.shellescape(cwd) .. ' ' .. diff_cmd)
    if diff == '' then
      vim.notify('No diff for ' .. a.path, vim.log.levels.INFO)
      return
    end
    -- Drop the technical header noise (diff --git, index, mode, +++/--- file
    -- lines, rename/binary markers) — the title already names the file, so the
    -- body is just @@ hunks and content.
    local NOISE = {
      '^diff %-%-git', '^index ', '^%-%-%- ', '^%+%+%+ ', '^new file mode',
      '^deleted file mode', '^old mode', '^new mode', '^similarity index',
      '^rename ', '^copy ', '^Binary files', '^\\ No newline',
    }
    local dlines = {}
    for _, l in ipairs(vim.split(diff, '\n')) do
      local drop = false
      for _, pat in ipairs(NOISE) do if l:match(pat) then drop = true; break end end
      if not drop then table.insert(dlines, l) end
    end

    local dbuf = api.nvim_create_buf(false, true)
    vim.bo[dbuf].buftype = 'nofile'; vim.bo[dbuf].bufhidden = 'wipe'
    vim.bo[dbuf].filetype = 'diff'; vim.bo[dbuf].modifiable = true
    api.nvim_buf_set_lines(dbuf, 0, -1, false, dlines)
    vim.bo[dbuf].modifiable = false

    local adds, dels = 0, 0
    for _, l in ipairs(dlines) do
      if l:match('^%+') then adds = adds + 1
      elseif l:match('^%-') then dels = dels + 1 end
    end

    local w = math.floor(vim.o.columns * 0.8)
    local h = math.floor(vim.o.lines * 0.8)
    local dwin = api.nvim_open_win(dbuf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded',
      title = { { '  ' .. a.path .. '  ', 'CSTreeDir' },
                { '+' .. adds .. ' ', 'diffAdded' },
                { '−' .. dels .. ' ',  'diffRemoved' } },
      title_pos = 'center',
      footer = { { ' ]c/[c hunk  ', 'Comment' }, { 'q close ', 'Comment' } },
      footer_pos = 'right',
      width = w, height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
    })
    vim.wo[dwin].wrap = false
    vim.wo[dwin].cursorline = true
    vim.wo[dwin].signcolumn = 'yes:1'   -- 'minimal' style hides it; re-enable for the markers
    vim.wo[dwin].winhighlight = 'FloatBorder:CSGit,FloatTitle:CSTreeDir'

    -- Gutter markers + intra-line (word-level) emphasis: highlight only the
    -- bytes that actually changed between a removed line and its paired added
    -- line, GitHub-style. The DiffAdd/DiffDelete backgrounds come straight from
    -- the theme palette, so the emphasis follows light/dark and re-tints.
    local ns = api.nvim_create_namespace('cs_gitdiff')

    -- Differing middle of two strings after stripping the common prefix/suffix.
    -- Returns nil when the strings are identical or share nothing (whole-line
    -- change — the line background already conveys that).
    local function mid(a, b)
      if a == b then return nil end
      local la, lb, p = #a, #b, 0
      while p < la and p < lb and a:byte(p + 1) == b:byte(p + 1) do p = p + 1 end
      local s = 0
      while s < la - p and s < lb - p and a:byte(la - s) == b:byte(lb - s) do s = s + 1 end
      if p == 0 and s == 0 then return nil end
      return p, la - s, lb - s   -- common prefix len, del-end, add-end (byte offsets)
    end

    local i = 1
    while i <= #dlines do
      local c = dlines[i]:sub(1, 1)
      if c == '-' then
        -- A run of '-' lines immediately followed by '+' lines → pair them up.
        local dstart = i
        while dlines[i] and dlines[i]:sub(1, 1) == '-' do
          api.nvim_buf_set_extmark(dbuf, ns, i - 1, 0,
            { sign_text = '▍', sign_hl_group = 'diffRemoved' })
          i = i + 1
        end
        local astart = i
        while dlines[i] and dlines[i]:sub(1, 1) == '+' do
          api.nvim_buf_set_extmark(dbuf, ns, i - 1, 0,
            { sign_text = '▍', sign_hl_group = 'diffAdded' })
          i = i + 1
        end
        local dcount, acount = astart - dstart, i - astart
        for k = 0, math.min(dcount, acount) - 1 do
          local p, de, ae = mid(dlines[dstart + k]:sub(2), dlines[astart + k]:sub(2))
          if p then
            if de > p then api.nvim_buf_set_extmark(dbuf, ns, dstart + k - 1, 1 + p,
              { end_col = 1 + de, hl_group = 'DiffDelete' }) end
            if ae > p then api.nvim_buf_set_extmark(dbuf, ns, astart + k - 1, 1 + p,
              { end_col = 1 + ae, hl_group = 'DiffAdd' }) end
          end
        end
      elseif c == '+' then
        api.nvim_buf_set_extmark(dbuf, ns, i - 1, 0,
          { sign_text = '▍', sign_hl_group = 'diffAdded' })
        i = i + 1
      else
        i = i + 1
      end
    end

    local dclose = function() pcall(api.nvim_win_close, dwin, true) end
    local do_ = { buffer = dbuf, nowait = true, silent = true }
    vim.keymap.set('n', 'q',     dclose, do_)
    vim.keymap.set('n', '<Esc>', dclose, do_)

    -- Hunk navigation: jump the cursor to the next/prev "@@ … @@" header,
    -- keeping it centered. ]c/[c mirror Neovim's native diff-mode motions.
    local function hunk(flags) fn.search('^@@', flags); vim.cmd 'normal! zz' end
    vim.keymap.set('n', ']c', function() hunk('W')  end, do_)
    vim.keymap.set('n', '[c', function() hunk('bW') end, do_)
    vim.keymap.set('n', '<Tab>',   function() hunk('W')  end, do_)
    vim.keymap.set('n', '<S-Tab>', function() hunk('bW') end, do_)
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
  if M._changes_win and api.nvim_win_is_valid(M._changes_win) then
    pcall(api.nvim_win_close, M._changes_win, true)
  end
  M._changes_win = nil
  if M._panel_win and api.nvim_win_is_valid(M._panel_win) then
    pcall(api.nvim_win_close, M._panel_win, true)
  end
  M._panel_win = nil
end

function M.setup()
  -- <leader>gG = Git source-control panel (uppercase to distinguish from gitsigns hunks)
  vim.keymap.set('n', '<leader>gG', function() M.open() end, { desc = 'Git: source control', silent = true })

  -- Scriptable :Workspace* commands over the same entry points as the keymaps,
  -- so the UI is callable from `:`, mappings, and other Lua without <leader>.
  local function dir_arg(a) return (a and a ~= '') and fn.fnamemodify(a, ':p') or active_repo() end

  api.nvim_create_user_command('WorkspaceGit', function()
    M.open()
  end, { desc = 'Open the git source-control (REPOSITORIES) panel' })

  api.nvim_create_user_command('WorkspaceGitClose', function()
    M.close()
  end, { desc = 'Close the git source-control panels' })

  api.nvim_create_user_command('WorkspaceGitToggle', function()
    if M._panel_win and api.nvim_win_is_valid(M._panel_win) then M.close() else M.open() end
  end, { desc = 'Toggle the git source-control panel' })

  api.nvim_create_user_command('WorkspaceChanges', function(a)
    M.show_changes(dir_arg(a.args))
  end, { nargs = '?', complete = 'dir', desc = 'Show CHANGES for a repo (default: active repo)' })
end

return M
