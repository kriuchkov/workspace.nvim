-- Custom tabline with Chrome-style buffer groups.
local M = {}

local EXCLUDE_FT = { ['cs_filetree'] = true, ['cs_outline'] = true,
                     ['cs_home'] = true, ['TelescopePrompt'] = true,
                     ['lazy'] = true, ['mason'] = true, ['help'] = true }
local EXCLUDE_BT = { ['quickfix'] = true, ['prompt'] = true }

-- ── Groups ────────────────────────────────────────────────────────────────────
-- 8 colours that cycle (Chrome uses a similar palette)
local GROUP_COLORS = {
  { bg = '#f28b82', fg = '#1a1b26' },  -- red
  { bg = '#fbbc04', fg = '#1a1b26' },  -- yellow
  { bg = '#34a853', fg = '#1a1b26' },  -- green
  { bg = '#4285f4', fg = '#ffffff' },  -- blue
  { bg = '#a142f4', fg = '#ffffff' },  -- purple
  { bg = '#ff7043', fg = '#1a1b26' },  -- orange
  { bg = '#24c1e0', fg = '#1a1b26' },  -- cyan
  { bg = '#e67c73', fg = '#1a1b26' },  -- pink
}

local groups         = {}   -- { [id] = { name, color_idx, collapsed } }
local buf_group      = {}   -- { [bufnr] = group_id }
local next_gid       = 1
local _path_map      = {}   -- path → group_name (loaded from disk, used on BufAdd)
local buf_labels     = {}   -- { [bufnr] = custom_label } overrides the filename in tabline
local _tabline_cache = nil  -- nil = dirty; string = last rendered result

local _mini_icons_ok, MiniIcons = pcall(require, 'mini.icons')
local _icon_hl_cache = {}   -- { [composite_group] = true }; reset on ColorScheme

local buf_access = {}       -- { [bufnr] = seq } last-visited order (for recency dim)
local access_seq = 0

M._pinned     = {}          -- { [bufnr] = true } pinned tabs float left, survive close-all
local _pinned_paths = {}    -- { [path] = true } loaded from disk, reapplied on BufAdd
local buf_order = {}        -- { [bufnr] = seq } explicit order for move-left/right
local order_seq = 0
local git_status = {}       -- { [path] = 'new' | 'mod' } refreshed async from git
local PIN_GLYPH = '▎'       -- accent bar marking pinned tabs (font-independent)

local TAB_MAXW  = 24                          -- truncate filenames beyond this width
local RECENT_N  = 2                           -- this many MRU inactive tabs stay bright
local SUPER     = { '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹' } -- quick-jump numbers (<leader>1..9 / Alt+1..9)
local CAP_L, CAP_R = '', ''                 -- rounded pill caps around the active tab

-- Invalidate cache and schedule a tabline redraw.
-- Must be declared here so all functions below can close over it.
local function invalidate()
  _tabline_cache = nil
  vim.cmd 'redrawtabline'
end

-- Forward-declared so the mouse handlers (defined earlier) can use the safe
-- buffer switch (defined later).
local set_buf_safe

-- ── Per-directory persistence ─────────────────────────────────────────────────

local _session_dir_override = nil   -- overridable in tests

local function groups_dir()
  return _session_dir_override or (vim.fn.stdpath('data') .. '/claudespace_groups')
end

-- Encode cwd to a safe filename (replace / with %, like nvim swapfiles)
local function groups_file()
  local cwd = vim.fn.getcwd():gsub('[/\\]', '%%')
  return groups_dir() .. '/' .. cwd .. '.json'
end

local function save_session()
  vim.fn.mkdir(groups_dir(), 'p')
  local path_groups = {}
  for bufnr, gid in pairs(buf_group) do
    if vim.api.nvim_buf_is_valid(bufnr) and groups[gid] then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= '' then path_groups[path] = groups[gid].name end
    end
  end
  local pinned_paths = {}
  for bufnr in pairs(M._pinned) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= '' then pinned_paths[#pinned_paths + 1] = path end
    end
  end
  local saved = { groups = {}, path_groups = path_groups, pinned = pinned_paths }
  for gid, g in pairs(groups) do
    table.insert(saved.groups, { id = gid, name = g.name,
      color_idx = g.color_idx, collapsed = g.collapsed })
  end
  local ok, json = pcall(vim.fn.json_encode, saved)
  if ok then pcall(vim.fn.writefile, { json }, groups_file()) end
end

local function reset_state()
  groups         = {}
  buf_group      = {}
  next_gid       = 1
  _path_map      = {}
  buf_labels     = {}
  M._pinned      = {}
  _pinned_paths  = {}
  buf_order      = {}
  order_seq      = 0
  _tabline_cache = nil
end

local function load_session()
  local file = groups_file()
  if vim.fn.filereadable(file) == 0 then return end
  local lines = vim.fn.readfile(file)
  if not lines or #lines == 0 then return end
  local ok, data = pcall(vim.fn.json_decode, table.concat(lines, ''))
  if not ok or type(data) ~= 'table' then return end

  for _, g in ipairs(data.groups or {}) do
    groups[g.id] = { name = g.name, color_idx = g.color_idx, collapsed = g.collapsed or false }
    if g.id >= next_gid then next_gid = g.id + 1 end
  end
  _path_map = data.path_groups or {}
  _pinned_paths = {}
  for _, p in ipairs(data.pinned or {}) do _pinned_paths[p] = true end

  M.reapply_groups()
end

-- ── Auto-grouping by git root / monorepo package ─────────────────────────────

local _git_group_cache = {}   -- { [dir] = group_name | false }
local _auto_group_enabled = true

local MONOREPO_DIRS = { 'packages', 'apps', 'services', 'modules', 'libs', 'crates' }

local function git_group_for(path)
  if path == '' then return nil end
  local dir = vim.fn.fnamemodify(path, ':h')
  if _git_group_cache[dir] ~= nil then
    return _git_group_cache[dir] or nil
  end
  local root = vim.fn.trim(vim.fn.system(
    'git -C ' .. vim.fn.shellescape(dir) .. ' rev-parse --show-toplevel 2>/dev/null'
  ))
  if vim.v.shell_error ~= 0 or root == '' then
    _git_group_cache[dir] = false; return nil
  end
  -- Monorepo: check if file is under a well-known subdir
  local rel = path:sub(#root + 2)
  for _, mdir in ipairs(MONOREPO_DIRS) do
    local pkg = rel:match('^' .. mdir .. '/([^/]+)')
    if pkg then _git_group_cache[dir] = pkg; return pkg end
  end
  -- Fall back: name of the git root
  local name = vim.fn.fnamemodify(root, ':t')
  _git_group_cache[dir] = name
  return name
end

---Auto-assign a buffer to a group based on its git root / monorepo package.
---Only assigns if the buffer has no group yet and auto-grouping is enabled.
function M.auto_group(bufnr)
  if not _auto_group_enabled then return end
  if buf_group[bufnr] then return end   -- already manually grouped
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return end
  local name = git_group_for(path)
  if name then M.group_add(bufnr, name) end
end

---Toggle auto-grouping on/off.
function M.toggle_auto_group()
  _auto_group_enabled = not _auto_group_enabled
  vim.notify('Auto-grouping ' .. (_auto_group_enabled and 'on' or 'off'), vim.log.levels.INFO)
  if _auto_group_enabled then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then M.auto_group(b) end
    end
  end
end

-- Re-scan all open buffers and assign groups from _path_map.
-- Called after load_session() and after workspace restore to catch any
-- buffers that were added before _path_map was populated.
function M.reapply_groups()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      local gname = _path_map[path]
      if gname then M.group_add(bufnr, gname) end
      if _pinned_paths[path] then M._pinned[bufnr] = true end
    end
  end
  invalidate()
end

local BORDER = '#3b4261'  -- separator colour (tokyonight storm border)
local RAIL   = '#0d0e16'  -- tab bar rail (darkest)
local EDITOR = '#1a1b26'  -- editor background
local ACTIVE = '#24283b'  -- active tab: lighter than editor → clearly pops above it

local function setup_group_hls()
  local hi = vim.api.nvim_set_hl
  _icon_hl_cache = {}   -- icon fg colours may change with the theme → rebuild lazily
  for i, c in ipairs(GROUP_COLORS) do
    hi(0, 'CSGroup'  .. i, { bg = c.bg, fg = c.fg, bold = true })
    hi(0, 'CSGroupT' .. i, { bg = RAIL, fg = c.bg })
  end
  hi(0, 'WinSeparator', { fg = BORDER })

  -- Rail: darkest layer; underline draws a thin border below the whole tab bar
  hi(0, 'TabLineFill', { bg = RAIL, sp = '#2a2d3e', underline = true })
  -- Inactive: dim text, sunken into rail
  hi(0, 'TabLine',     { bg = RAIL, fg = '#3b4166', sp = '#2a2d3e', underline = true })
  -- Active: LIGHTER than editor → floats above it; blue accent replaces the grey separator
  hi(0, 'TabLineSel',  { bg = ACTIVE, fg = '#c0caf5', bold = true,
                         sp = '#7aa2f7', underline = true })

  hi(0, 'CSTabClose',       { bg = RAIL,   fg = '#252840' })
  hi(0, 'CSTabCloseActive', { bg = ACTIVE, fg = '#414868' })
  hi(0, 'CSTabModified',    { bg = ACTIVE, fg = '#e0af68' })
  hi(0, 'CSTabModifiedNC',  { bg = RAIL,   fg = '#5c4a1e' })

  -- Recently-used inactive tab: brighter than the sunken default (recency gradient)
  hi(0, 'TabLineRecent', { bg = RAIL, fg = '#828bb8', sp = '#2a2d3e', underline = true })
  -- Quick-jump number (Alt+1..5)
  hi(0, 'CSTabNum',    { bg = RAIL,   fg = '#4a4f6a', sp = '#2a2d3e', underline = true })
  hi(0, 'CSTabNumSel', { bg = ACTIVE, fg = '#7aa2f7', sp = '#7aa2f7', underline = true })
  -- Pill caps around the active tab (tab colour on the rail)
  hi(0, 'CSTabCap', { bg = RAIL, fg = ACTIVE, sp = '#2a2d3e', underline = true })

  -- Diagnostics badges (error / warning) on both tab backgrounds
  hi(0, 'CSTabDiagErr',     { bg = RAIL,   fg = '#f7768e', sp = '#2a2d3e', underline = true })
  hi(0, 'CSTabDiagErrSel',  { bg = ACTIVE, fg = '#f7768e', sp = '#7aa2f7', underline = true })
  hi(0, 'CSTabDiagWarn',    { bg = RAIL,   fg = '#e0af68', sp = '#2a2d3e', underline = true })
  hi(0, 'CSTabDiagWarnSel', { bg = ACTIVE, fg = '#e0af68', sp = '#7aa2f7', underline = true })
  -- Overflow marker (‹N / N›) when tabs don't fit
  hi(0, 'CSTabMore', { bg = RAIL, fg = '#7aa2f7', sp = '#2a2d3e', underline = true })

  -- Git-coloured tab names: new/untracked = green, modified = orange
  hi(0, 'CSTabGitNew',    { bg = RAIL,   fg = '#9ece6a', sp = '#2a2d3e', underline = true })
  hi(0, 'CSTabGitNewSel', { bg = ACTIVE, fg = '#9ece6a', sp = '#7aa2f7', underline = true, bold = true })
  hi(0, 'CSTabGitMod',    { bg = RAIL,   fg = '#e0af68', sp = '#2a2d3e', underline = true })
  hi(0, 'CSTabGitModSel', { bg = ACTIVE, fg = '#e0af68', sp = '#7aa2f7', underline = true, bold = true })
  -- Pinned inactive tab: distinct background so it stands out even if the pin
  -- glyph is missing from the font (font-independent indicator).
  hi(0, 'TabLinePinned', { bg = '#26344d', fg = '#c0caf5', sp = '#2a2d3e', underline = true })
  -- Pin glyph (bright, bold)
  hi(0, 'CSTabPin',    { bg = '#26344d', fg = '#e0af68', sp = '#2a2d3e', underline = true, bold = true })
  hi(0, 'CSTabPinSel', { bg = ACTIVE,    fg = '#e0af68', sp = '#7aa2f7', underline = true, bold = true })
end

local function group_hl(gid)
  if not groups[gid] then return 'TabLine' end
  return 'CSGroup' .. groups[gid].color_idx
end

local function group_tint(gid)
  if not groups[gid] then return nil end
  return 'CSGroupT' .. groups[gid].color_idx
end

-- Truncate a label to TAB_MAXW chars (multibyte-safe), adding an ellipsis.
local function truncate(s)
  if vim.fn.strchars(s) <= TAB_MAXW then return s end
  return vim.fn.strcharpart(s, 0, TAB_MAXW - 1) .. '…'
end

-- Filetype icon (glyph + base hl) for a buffer's path, via mini.icons.
local function buf_icon(path)
  if not _mini_icons_ok or not path or path == '' then return nil, nil end
  local fname = vim.fn.fnamemodify(path, ':t')
  if fname == '' then return nil, nil end
  local ok, ic, hl = pcall(MiniIcons.get, 'file', fname)
  if not ok then return nil, nil end
  return ic, hl
end

-- Composite highlight: icon's fg colour on the tab's background (RAIL/ACTIVE),
-- keeping the tab's bottom border (underline). Cached; rebuilt on ColorScheme.
local function icon_hl(base_hl, sel)
  if not base_hl then return nil end
  local grp = 'CSTabIc_' .. base_hl .. (sel and '_S' or '_N')
  if not _icon_hl_cache[grp] then
    local fg = vim.api.nvim_get_hl(0, { name = base_hl, link = false }).fg
    vim.api.nvim_set_hl(0, grp, {
      fg = fg,
      bg = sel and ACTIVE or RAIL,
      sp = sel and '#7aa2f7' or '#2a2d3e',
      underline = true,
    })
    _icon_hl_cache[grp] = true
  end
  return grp
end

-- Public: add current buffer to a named group (creates group if needed)
function M.group_add(bufnr, name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  -- find existing group by name
  for gid, g in pairs(groups) do
    if g.name == name then
      buf_group[bufnr] = gid
      invalidate()
      return gid
    end
  end
  -- create new group
  local color_idx = ((next_gid - 1) % #GROUP_COLORS) + 1
  local gid = next_gid; next_gid = next_gid + 1
  groups[gid] = { name = name, color_idx = color_idx, collapsed = false }
  buf_group[bufnr] = gid
  invalidate()
  return gid
end

function M.group_remove(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  buf_group[bufnr] = nil
  invalidate()
end

-- Toggle collapse of the group the current buffer belongs to.
-- If the current buffer has no group, shows a picker of all collapsed groups.
function M.group_toggle_collapse()
  local gid = buf_group[vim.api.nvim_get_current_buf()]
  if gid and groups[gid] then
    groups[gid].collapsed = not groups[gid].collapsed
    invalidate()
    return
  end
  -- Current buffer not in a group — offer picker of collapsed groups
  local collapsed = {}
  for id, g in pairs(groups) do
    if g.collapsed then table.insert(collapsed, { id = id, name = g.name }) end
  end
  if #collapsed == 0 then
    vim.notify('No collapsed groups', vim.log.levels.INFO); return
  end
  table.sort(collapsed, function(a, b) return a.name < b.name end)
  local labels = vim.tbl_map(function(g) return '▶ ' .. g.name end, collapsed)
  vim.ui.select(labels, { prompt = 'Expand group:' }, function(_, idx)
    if not idx then return end
    groups[collapsed[idx].id].collapsed = false
    invalidate()
  end)
end

-- Pick a new color for the current buffer's group
local COLOR_NAMES = {
  'red', 'yellow', 'green', 'blue', 'purple', 'orange', 'cyan', 'pink'
}

function M.group_pick_color()
  local gid = buf_group[vim.api.nvim_get_current_buf()]
  if not gid or not groups[gid] then
    vim.notify('Tab: current buffer is not in a group', vim.log.levels.WARN)
    return
  end
  local items = {}
  for i, name in ipairs(COLOR_NAMES) do
    local marker = (groups[gid].color_idx == i) and ' ✓' or ''
    table.insert(items, { label = name .. marker, idx = i })
  end
  vim.ui.select(items, {
    prompt = 'Group color',
    format_item = function(item) return item.label end,
  }, function(item)
    if not item then return end
    groups[gid].color_idx = item.idx
    setup_group_hls()
    invalidate()
  end)
end

function M.group_rename()
  local gid = buf_group[vim.api.nvim_get_current_buf()]
  if not gid or not groups[gid] then
    vim.notify('Tab: current buffer is not in a group', vim.log.levels.WARN)
    return
  end
  local old_name = groups[gid].name
  vim.ui.input({ prompt = 'Rename group: ', default = old_name }, function(name)
    if not name or name == '' or name == old_name then return end
    groups[gid].name = name
    for path, gname in pairs(_path_map) do
      if gname == old_name then _path_map[path] = name end
    end
    invalidate()
  end)
end

-- Set or clear a custom display label for the current buffer's tab.
function M.rename_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local current = buf_labels[bufnr] or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
  vim.ui.input({ prompt = 'Tab label: ', default = current }, function(label)
    if label == nil then return end  -- cancelled
    if label == '' then
      buf_labels[bufnr] = nil        -- clear custom label → back to filename
    else
      buf_labels[bufnr] = label
    end
    invalidate()
  end)
end

function _G.CSGroupToggle(gid)
  if groups[gid] then
    groups[gid].collapsed = not groups[gid].collapsed
    invalidate()
  end
end

-- ── Buffer list ───────────────────────────────────────────────────────────────

local function listed_bufs()
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_valid(b) then goto next end
    if not vim.bo[b].buflisted then goto next end
    if vim.b[b].cs_session_id then goto next end   -- Claude sessions live in the bottom bar
    if EXCLUDE_FT[vim.bo[b].filetype] then goto next end
    if EXCLUDE_BT[vim.bo[b].buftype] then goto next end
    if not buf_order[b] then order_seq = order_seq + 1; buf_order[b] = order_seq end
    table.insert(bufs, {
      bufnr    = b,
      path     = vim.api.nvim_buf_get_name(b),
      modified = vim.bo[b].modified,
      terminal = vim.bo[b].buftype == 'terminal',
      gid      = buf_group[b],
      pinned   = M._pinned[b] or false,
      order    = buf_order[b],
    })
    ::next::
  end

  -- Disambiguate duplicate basenames by prefixing the parent dir
  -- (file/repository.go vs todotxt/repository.go). Custom labels win.
  local base_count = {}
  for _, e in ipairs(bufs) do
    if e.path ~= '' and not e.terminal then
      local base = vim.fn.fnamemodify(e.path, ':t')
      base_count[base] = (base_count[base] or 0) + 1
    end
  end
  for _, e in ipairs(bufs) do
    if buf_labels[e.bufnr] then
      e.name = buf_labels[e.bufnr]
    elseif e.path == '' then
      e.name = '[No Name]'
    elseif e.terminal then
      e.name = vim.fn.fnamemodify(e.path, ':t')
    else
      local base = vim.fn.fnamemodify(e.path, ':t')
      if (base_count[base] or 0) > 1 then
        e.name = vim.fn.fnamemodify(e.path, ':h:t') .. '/' .. base
      else
        e.name = base
      end
    end
  end
  return bufs
end

-- Sort: pinned first (float left), then by group (ascending gid), ungrouped last;
-- within every section by explicit buf_order (so move-left/right works).
local function sorted_bufs(bufs)
  local by_order = function(a, b) return (a.order or 0) < (b.order or 0) end

  -- Pinned float to the front regardless of group
  local pinned = {}
  for _, b in ipairs(bufs) do
    if b.pinned then table.insert(pinned, b) end
  end
  table.sort(pinned, by_order)

  -- Remaining grouped, in gid order
  local gid_order, seen = {}, {}
  for _, b in ipairs(bufs) do
    if not b.pinned and b.gid and not seen[b.gid] then
      seen[b.gid] = true
      table.insert(gid_order, b.gid)
    end
  end
  table.sort(gid_order)

  local result = {}
  for _, b in ipairs(pinned) do table.insert(result, b) end
  for _, gid in ipairs(gid_order) do
    local bucket = {}
    for _, b in ipairs(bufs) do
      if not b.pinned and b.gid == gid then table.insert(bucket, b) end
    end
    table.sort(bucket, by_order)
    for _, b in ipairs(bucket) do table.insert(result, b) end
  end
  local ungrouped = {}
  for _, b in ipairs(bufs) do
    if not b.pinned and not b.gid then table.insert(ungrouped, b) end
  end
  table.sort(ungrouped, by_order)
  for _, b in ipairs(ungrouped) do table.insert(result, b) end
  return result
end

-- Visible (non-collapsed) bufs in tabline visual order
local function visible_sorted_bufs()
  local result = {}
  for _, b in ipairs(sorted_bufs(listed_bufs())) do
    local grp = b.gid and groups[b.gid]
    if not (grp and grp.collapsed) then
      table.insert(result, b)
    end
  end
  return result
end

-- ── Render ────────────────────────────────────────────────────────────────────

-- Display width of a tabline-encoded string (strips %#..#, %N@..@, %T, %% codes).
local function vwidth(s)
  s = s:gsub('%%#.-#', '')
       :gsub('%%%d+@[^@]*@', '')
       :gsub('%%T', '')
       :gsub('%%%%', '%%')
  return vim.fn.strdisplaywidth(s)
end

-- Diagnostics badge for a buffer: red ● N for errors, else yellow ● N for warnings.
local function diag_seg(bufnr, sel)
  if not (vim.diagnostic and vim.diagnostic.count) then return nil end
  local ok, c = pcall(vim.diagnostic.count, bufnr)
  if not ok then return nil end
  local e = c[vim.diagnostic.severity.ERROR]
  local w = c[vim.diagnostic.severity.WARN]
  if e and e > 0 then
    return (sel and '%#CSTabDiagErrSel#' or '%#CSTabDiagErr#') .. ' ●' .. e
  elseif w and w > 0 then
    return (sel and '%#CSTabDiagWarnSel#' or '%#CSTabDiagWarn#') .. ' ●' .. w
  end
  return nil
end

-- Highlight prefix to colour a tab name by git status (new=green, modified=orange).
local function git_name_hl(path, sel)
  local st = path ~= '' and git_status[path]
  if st == 'new' then return sel and '%#CSTabGitNewSel#' or '%#CSTabGitNew#' end
  if st == 'mod' then return sel and '%#CSTabGitModSel#' or '%#CSTabGitMod#' end
  return nil
end

-- Refresh git status map asynchronously (one `git status` per cwd; render reads cache).
local function refresh_git_status()
  if not vim.system then return end
  local cwd = vim.fn.getcwd()
  vim.system({ 'git', '-C', cwd, 'rev-parse', '--show-toplevel' }, { text = true }, function(res)
    if res.code ~= 0 then return end
    local root = vim.trim(res.stdout or '')
    if root == '' then return end
    vim.system({ 'git', '-C', root, 'status', '--porcelain' }, { text = true }, function(r2)
      if r2.code ~= 0 then return end
      local map = {}
      for line in (r2.stdout or ''):gmatch('[^\n]+') do
        local code = line:sub(1, 2)
        local p    = line:sub(4):gsub('^"', ''):gsub('"$', '')
        p = p:match('%-> (.+)$') or p            -- renames: "old -> new"
        local abs = root .. '/' .. p
        map[abs] = (code:find('?') or code:find('A')) and 'new' or 'mod'
      end
      vim.schedule(function()
        git_status = map
        _tabline_cache = nil
        vim.cmd 'redrawtabline'
      end)
    end)
  end)
end
M.refresh_git_status = refresh_git_status

function M.render()
  if _tabline_cache then return _tabline_cache end

  local bufs = sorted_bufs(listed_bufs())
  local cur   = vim.api.nvim_get_current_buf()
  local prev_gid = nil   -- track group boundaries
  local pos   = 0        -- position index for CSTabSwitch
  local group_pos = 0    -- group index for <leader>N quick-jump numbering
  local buf_pos   = 0    -- buffer index WITHIN the current group (Alt+G then B)

  -- Count buffers per group for collapsed label
  local group_counts = {}
  for _, b in ipairs(bufs) do
    if b.gid then group_counts[b.gid] = (group_counts[b.gid] or 0) + 1 end
  end

  -- Recency: the RECENT_N most-recently-visited inactive tabs stay bright,
  -- the rest dim further (visual "what did I touch lately").
  local recent_set = {}
  do
    local lst = {}
    for _, b in ipairs(bufs) do
      if b.bufnr ~= cur then
        lst[#lst + 1] = { bufnr = b.bufnr, seq = buf_access[b.bufnr] or 0 }
      end
    end
    table.sort(lst, function(a, b) return a.seq > b.seq end)
    for i = 1, math.min(RECENT_N, #lst) do
      if lst[i].seq > 0 then recent_set[lst[i].bufnr] = true end
    end
  end

  -- Build each tab (with its leading group label, if any) as a self-contained
  -- "unit" so we can measure widths and window them on overflow.
  local units = {}   -- { { str, w, sel } }

  for _, buf in ipairs(bufs) do
    local gid = buf.gid
    local grp = gid and groups[gid]
    local u   = {}   -- parts of the current unit

    -- Group label when a new group starts
    if gid ~= prev_gid then
      buf_pos = 0   -- restart buffer numbering for the new group
      if grp then
        group_pos = group_pos + 1
        local num = (group_pos <= #SUPER) and (SUPER[group_pos] .. ' ') or ''
        local count = group_counts[gid] or 0
        local active_inside = grp.collapsed and (function()
          for _, b2 in ipairs(bufs) do
            if b2.gid == gid and b2.bufnr == cur then return true end
          end
        end)()
        local marker = active_inside and ' ●' or ''
        local label = grp.collapsed
          and (' ' .. num .. '▶ ' .. grp.name .. ' (' .. count .. ')' .. marker .. ' ')
          or  (' ' .. num .. '▼ ' .. grp.name .. ' ')
        u[#u+1] = '%#' .. group_hl(gid) .. '#'
        u[#u+1] = '%' .. gid .. '@v:lua.CSGroupToggle@'
        u[#u+1] = label
        u[#u+1] = '%T'
      elseif prev_gid then
        u[#u+1] = '%#TabLineFill#  '   -- separator between last group and ungrouped
      end
      prev_gid = gid
    end

    -- Collapsed group members: emit a label-only unit (if any), skip the body
    if grp and grp.collapsed then
      if #u > 0 then
        local s = table.concat(u)
        units[#units+1] = { str = s, w = vwidth(s), sel = false }
      end
      goto continue
    end

    pos = pos + 1
    local sel  = buf.bufnr == cur
    local tint = group_tint(gid)

    -- Base highlight: selected > pinned > group tint > recently-used > sunken default
    local base = sel and 'TabLineSel'
      or (buf.pinned and 'TabLinePinned')
      or tint
      or (recent_set[buf.bufnr] and 'TabLineRecent' or 'TabLine')
    local tab_hl = '%#' .. base .. '#'

    if sel then u[#u+1] = '%#CSTabCap#' .. CAP_L end   -- left pill cap

    u[#u+1] = tab_hl
    u[#u+1] = '%' .. pos .. '@v:lua.CSTabSwitch@'

    -- Pin marker: accent bar at the very left edge (font-independent)
    if buf.pinned then
      u[#u+1] = (sel and '%#CSTabPinSel#' or '%#CSTabPin#') .. PIN_GLYPH .. tab_hl
    end

    -- Buffer number within its group (Alt+<group><this>)
    buf_pos = buf_pos + 1
    if buf_pos <= #SUPER then
      u[#u+1] = (sel and '%#CSTabNumSel#' or '%#CSTabNum#') .. ' ' .. SUPER[buf_pos] .. ' ' .. tab_hl
    else
      u[#u+1] = '  '
    end

    -- Icon (or terminal bolt)
    if buf.terminal then
      u[#u+1] = '⚡ '
    else
      local ic, ihl = buf_icon(buf.path)
      local ig = ic and icon_hl(ihl, sel)
      if ig then u[#u+1] = '%#' .. ig .. '#' .. ic .. ' ' .. tab_hl end
    end
    -- Name, optionally coloured by git status
    local nhl = git_name_hl(buf.path, sel)
    if nhl then u[#u+1] = nhl .. truncate(buf.name) .. tab_hl
    else u[#u+1] = truncate(buf.name) end

    -- Modified dot
    if buf.modified then
      u[#u+1] = (sel and '%#CSTabModified#' or '%#CSTabModifiedNC#') .. ' ●' .. tab_hl
    end
    -- Diagnostics badge (errors/warnings)
    local dseg = diag_seg(buf.bufnr, sel)
    if dseg then u[#u+1] = dseg .. tab_hl end
    u[#u+1] = ' %T'

    -- Close button
    u[#u+1] = '%' .. buf.bufnr .. '@v:lua.CSTabClose@'
    u[#u+1] = sel and '%#CSTabCloseActive#× ' or '%#CSTabClose#× '
    u[#u+1] = '%T'

    if sel then u[#u+1] = '%#CSTabCap#' .. CAP_R end   -- right pill cap

    local s = table.concat(u)
    units[#units+1] = { str = s, w = vwidth(s), sel = sel }

    ::continue::
  end

  -- ── Overflow: window the units around the active tab if they exceed the bar ──
  local t = {}
  local total = 0
  for _, u in ipairs(units) do total = total + u.w end

  if total <= vim.o.columns then
    for _, u in ipairs(units) do t[#t+1] = u.str end
  else
    local act = 1
    for i, u in ipairs(units) do if u.sel then act = i; break end end
    local budget = vim.o.columns - 8   -- reserve for the ‹N / N› markers
    local l, r, used = act, act, units[act].w
    while true do
      local grew = false
      if r < #units and used + units[r + 1].w <= budget then
        r = r + 1; used = used + units[r].w; grew = true
      end
      if l > 1 and used + units[l - 1].w <= budget then
        l = l - 1; used = used + units[l].w; grew = true
      end
      if not grew then break end
    end
    if l > 1 then t[#t+1] = '%#CSTabMore#‹' .. (l - 1) .. ' ' end
    for i = l, r do t[#t+1] = units[i].str end
    if r < #units then t[#t+1] = '%#CSTabMore# ' .. (#units - r) .. '›' end
  end

  t[#t+1] = '%#TabLineFill#'
  _tabline_cache = table.concat(t)
  return _tabline_cache
end

-- ── Click handlers ────────────────────────────────────────────────────────────

function _G.CSTabSwitch(idx)
  local bufs = sorted_bufs(listed_bufs())
  -- idx counts only visible (non-collapsed) tabs
  local visible = 0
  for _, b in ipairs(bufs) do
    local grp = b.gid and groups[b.gid]
    if not (grp and grp.collapsed) then
      visible = visible + 1
      if visible == idx then
        set_buf_safe(b.bufnr)
        return
      end
    end
  end
end

function _G.CSTabClose(bufnr)
  M.close(bufnr)   -- single safe close path
end

-- ── Buffer lifecycle ──────────────────────────────────────────────────────────

function M.close_terminal(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local job = vim.b[buf] and vim.b[buf].terminal_job_id
  if job then pcall(vim.fn.jobstop, job) end
  M._switch_away(buf)
  vim.defer_fn(function()
    if vim.v.dying > 0 then return end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end, 150)
end

function M.close_normal(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified then
    local choice = vim.fn.confirm('Save before closing?', '&Save\n&Discard\n&Cancel', 1)
    if choice == 1 then vim.api.nvim_buf_call(buf, function() vim.cmd 'write' end)
    elseif choice == 3 then return end
  end
  M._switch_away(buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

function M._switch_away(buf)
  local bufs = visible_sorted_bufs()
  if #bufs <= 1 then pcall(vim.cmd, 'enew'); return end
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == buf then idx = i; break end end
  local target = bufs[idx < #bufs and idx + 1 or idx - 1]
  if target and vim.api.nvim_get_current_buf() == buf then
    set_buf_safe(target.bufnr)   -- safe: won't E1513 from a winfixbuf window
  end
end

-- ── Pin / move / bulk-close ───────────────────────────────────────────────────

-- Delete a buffer in bulk ops: never touches pinned or unsaved buffers.
local function safe_delete(bufnr)
  if M._pinned[bufnr] then return false end
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  if vim.bo[bufnr].modified or vim.bo[bufnr].buftype == 'terminal' then return false end
  buf_group[bufnr] = nil
  pcall(vim.api.nvim_buf_delete, bufnr, {})
  return true
end

local function cur_index(vis)
  local cur = vim.api.nvim_get_current_buf()
  for i, b in ipairs(vis) do if b.bufnr == cur then return i end end
end

function M.toggle_pin(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M._pinned[bufnr] = (not M._pinned[bufnr]) or nil
  invalidate()
end

-- Move the current tab one slot left (-1) or right (+1) within its section.
function M.move(dir)
  local vis = visible_sorted_bufs()
  local ci  = cur_index(vis)
  if not ci then return end
  local ni = ci + dir
  if ni < 1 or ni > #vis then return end
  local cur, other = vis[ci].bufnr, vis[ni].bufnr
  buf_order[cur], buf_order[other] = buf_order[other], buf_order[cur]
  invalidate()
end

function M.close_others()
  local cur = vim.api.nvim_get_current_buf()
  for _, b in ipairs(visible_sorted_bufs()) do
    if b.bufnr ~= cur then safe_delete(b.bufnr) end
  end
  invalidate()
end

function M.close_left()
  local vis = visible_sorted_bufs()
  local ci  = cur_index(vis)
  if not ci then return end
  for i = 1, ci - 1 do safe_delete(vis[i].bufnr) end
  invalidate()
end

function M.close_right()
  local vis = visible_sorted_bufs()
  local ci  = cur_index(vis)
  if not ci then return end
  for i = ci + 1, #vis do safe_delete(vis[i].bufnr) end
  invalidate()
end

function M.close_all()
  local cur = vim.api.nvim_get_current_buf()
  for _, b in ipairs(visible_sorted_bufs()) do
    if b.bufnr ~= cur then safe_delete(b.bufnr) end
  end
  if not M._pinned[cur] and not vim.bo[cur].modified
    and vim.bo[cur].buftype ~= 'terminal' then
    M.close_normal(cur)   -- switches away to a pinned tab or a fresh buffer
  end
  invalidate()
end

-- Close every buffer in the current buffer's group (terminals are stopped;
-- pinned / unsaved buffers are kept, like the other bulk-close ops).
function M.close_group()
  local cur = vim.api.nvim_get_current_buf()
  local gid = buf_group[cur]
  if not gid then
    vim.notify('Current buffer is not in a group', vim.log.levels.WARN); return
  end
  local name = (groups[gid] and groups[gid].name) or '?'

  -- Move the window onto a buffer outside this group before deleting.
  local outside
  for _, b in ipairs(visible_sorted_bufs()) do
    if buf_group[b.bufnr] ~= gid then outside = b.bufnr; break end
  end
  if outside then vim.api.nvim_set_current_buf(outside) else vim.cmd 'enew' end

  local closed, kept = 0, 0
  for bn, g in pairs(vim.deepcopy(buf_group)) do
    if g == gid and vim.api.nvim_buf_is_valid(bn) then
      if vim.bo[bn].buftype == 'terminal' then
        M.close_terminal(bn); closed = closed + 1
      elseif safe_delete(bn) then
        closed = closed + 1
      else
        kept = kept + 1
      end
    end
  end
  if kept == 0 and groups[gid] then groups[gid] = nil end
  invalidate()
  vim.notify(('Closed group "%s" — %d closed%s'):format(
    name, closed, kept > 0 and (', ' .. kept .. ' kept (unsaved/pinned)') or ''),
    vim.log.levels.INFO)
end

-- ── Navigation ────────────────────────────────────────────────────────────────

-- Open a buffer in the center content window (never splits, never throws): a
-- click while focus is in the tree/a bar can't E1513 — the shell routes it.
function set_buf_safe(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end
  require('claudespace.shell').open(bufnr)
end

function M.prev()
  local bufs = visible_sorted_bufs()
  if #bufs < 2 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == cur then idx = i; break end end
  set_buf_safe(bufs[idx <= 1 and #bufs or idx - 1].bufnr)
end

function M.next()
  local bufs = visible_sorted_bufs()
  if #bufs < 2 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == cur then idx = i; break end end
  set_buf_safe(bufs[idx >= #bufs and 1 or idx + 1].bufnr)
end

function M.goto_n(n)
  local bufs = visible_sorted_bufs()
  if bufs[n] then set_buf_safe(bufs[n].bufnr) end
end

-- Drop dead-buffer entries from every bufnr-keyed state table.
function M.prune()
  for _, t in ipairs { buf_group, buf_labels, M._pinned, buf_order, buf_access } do
    for k in pairs(t) do
      if type(k) == 'number' and not vim.api.nvim_buf_is_valid(k) then t[k] = nil end
    end
  end
  invalidate()
end

-- The single safe entry point for closing a buffer (mouse ✕ and keymaps route
-- here): dispatches terminal vs normal, then prunes stale state.
function M.close(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  buf_group[bufnr] = nil
  pcall(function()
    if vim.bo[bufnr].buftype == 'terminal' then M.close_terminal(bufnr)
    else M.close_normal(bufnr) end
  end)
  M.prune()
end

-- Save the buffer (if it's a real file with unsaved edits) then close it — <A-w>.
-- A failed write aborts the close so nothing is lost; nameless buffers can't be
-- written, so those fall through to M.close's save/discard prompt.
function M.write_close(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.bo[bufnr].buftype == '' and vim.bo[bufnr].modified
     and vim.api.nvim_buf_get_name(bufnr) ~= '' then
    local ok = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd 'write' end)
    if not ok then return end
  end
  M.close(bufnr)
end

-- Groups in tabline order (first appearance of each gid in the sorted buffers).
local function ordered_groups()
  local seen, out = {}, {}
  for _, b in ipairs(sorted_bufs(listed_bufs())) do
    if b.gid and groups[b.gid] and not seen[b.gid] then
      seen[b.gid] = true
      out[#out + 1] = b.gid
    end
  end
  return out
end

-- Jump to the n-th group: focus its most-recently-used buffer (expand if collapsed).
function M.goto_group(n)
  local gid = ordered_groups()[n]
  if not gid then return end
  local best, best_seq
  for _, b in ipairs(sorted_bufs(listed_bufs())) do
    if b.gid == gid then
      local seq = buf_access[b.bufnr] or 0
      if not best or seq > best_seq then best, best_seq = b.bufnr, seq end
    end
  end
  if not best then return end
  if groups[gid].collapsed then groups[gid].collapsed = false; invalidate() end
  set_buf_safe(best)
end

-- The buffer shown in the center content window (so nav triggered from the tree
-- or a panel acts on the center's tab, not the panel buffer).
local function center_buf()
  local shell = require('claudespace.shell')
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if shell.is_center(w) then return vim.api.nvim_win_get_buf(w) end
  end
  return vim.api.nvim_get_current_buf()
end

-- Jump to the n-th buffer within the center's group (matches the visible per-group
-- numbers). Used by <A-1..9>. When the center shows a Claude session / ungrouped
-- buffer, fall back to the first tab group so file tabs stay reachable.
function M.goto_buf_n(n)
  local gid = buf_group[center_buf()]
  if not gid then gid = ordered_groups()[1] end
  local idx = 0
  for _, b in ipairs(sorted_bufs(listed_bufs())) do
    if b.gid == gid then
      idx = idx + 1
      if idx == n then set_buf_safe(b.bufnr); return end
    end
  end
  -- No matching group buffer (e.g. all ungrouped): fall back to the n-th visible.
  local vis = visible_sorted_bufs()
  if vis[n] then set_buf_safe(vis[n].bufnr) end
end

-- Open the b-th buffer within the g-th group.
function M.goto_group_buf(g, b)
  local gid = ordered_groups()[g]
  if not gid then return end
  if groups[gid].collapsed then groups[gid].collapsed = false; invalidate() end
  local idx = 0
  for _, buf in ipairs(sorted_bufs(listed_bufs())) do
    if buf.gid == gid then
      idx = idx + 1
      if idx == b then set_buf_safe(buf.bufnr); return end
    end
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  setup_group_hls()
  vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_group_hls })

  -- Keep state tables free of dead buffers.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    callback = function() vim.schedule(M.prune) end,
  })

  -- Persist groups per directory
  vim.api.nvim_create_autocmd('VimLeave', { callback = save_session })
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function() vim.schedule(load_session) end,
  })
  -- When cwd changes (cd, :tcd, etc.) — save old, load new directory's groups
  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      save_session()
      reset_state()
      load_session()
    end,
  })
  -- Apply saved group when a file is opened; fall back to auto-grouping
  vim.api.nvim_create_autocmd('BufAdd', {
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if _pinned_paths[path] then M._pinned[ev.buf] = true end
      local gname = _path_map[path]
      if gname then
        M.group_add(ev.buf, gname)
      else
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then M.auto_group(ev.buf) end
        end)
      end
    end,
  })

  -- Git status: refresh async on start, save, focus, and cwd change (render reads cache)
  vim.api.nvim_create_autocmd(
    { 'BufWritePost', 'FocusGained', 'DirChanged' },
    { callback = function() refresh_git_status() end }
  )
  vim.schedule(refresh_git_status)

  -- Invalidate cache on events that change what/how tabs look.
  -- BufEnter: active tab changes highlight.
  -- BufAdd/BufDelete/BufHidden: tab list changes.
  -- BufModifiedSet: ● modified dot appears/disappears.
  vim.api.nvim_create_autocmd(
    { 'BufEnter', 'BufAdd', 'BufDelete', 'BufHidden', 'BufModifiedSet', 'DiagnosticChanged' },
    { callback = function(ev)
        if ev.event == 'BufEnter' then
          access_seq = access_seq + 1
          buf_access[ev.buf] = access_seq
        end
        _tabline_cache = nil
      end }
  )

  -- Auto-expand a collapsed group when one of its buffers becomes active
  vim.api.nvim_create_autocmd('BufWinEnter', {
    callback = function()
      local gid = buf_group[vim.api.nvim_get_current_buf()]
      if gid and groups[gid] and groups[gid].collapsed then
        groups[gid].collapsed = false
        invalidate()
      end
    end,
  })

  vim.o.showtabline = 2
  vim.o.tabline = '%!v:lua.require("claudespace.tabline").render()'

  local map = vim.keymap.set
  -- Alt keys are terminal-safe ({n,t}) — they aren't typed text. Leader keys stay
  -- normal-mode only: <leader> is <Space>, and mapping it in a terminal would add
  -- timeout latency to every space typed into Claude (use <Esc><Esc> there).
  local NT = { 'n', 't' }
  map(NT, '<A-,>', M.prev, { silent = true, desc = 'Prev tab' })
  map(NT, '<A-.>', M.next, { silent = true, desc = 'Next tab' })
  map(NT, '<A-c>', function() M.close() end, { silent = true, desc = 'Close tab' })
  map(NT, '<A-w>', function() M.write_close() end, { silent = true, desc = 'Save & close tab' })
  --   <leader>G   → group G            (fires after timeoutlen if no 2nd digit)
  --   <leader>GB  → group G, buffer B  (e.g. <leader>12 = group 1, buffer 2)
  for g = 1, 9 do
    map('n', '<leader>' .. g, function() M.goto_group(g) end,
      { silent = true, desc = 'Tab: group ' .. g })
    map(NT, '<A-' .. g .. '>', function() M.goto_buf_n(g) end, { silent = true })
    for b = 1, 9 do
      map('n', '<leader>' .. g .. b, function() M.goto_group_buf(g, b) end,
        { silent = true })
    end
  end
  -- Keep all the numeric quick-jump maps out of the which-key popup (clutter).
  local ok_wk, wk = pcall(require, 'which-key')
  if ok_wk and wk.add then
    local spec = {}
    for g = 1, 9 do
      spec[#spec + 1] = { '<leader>' .. g, hidden = true }
      for b = 1, 9 do spec[#spec + 1] = { '<leader>' .. g .. b, hidden = true } end
    end
    wk.add(spec)
  end

  -- Group keymaps
  map('n', '<leader>tg', function()
    local buf = vim.api.nvim_get_current_buf()
    -- Show existing groups as choices
    local choices = {}
    for _, g in pairs(groups) do table.insert(choices, g.name) end
    table.insert(choices, '+ New group…')
    vim.ui.select(choices, { prompt = 'Add to group' }, function(choice)
      if not choice then return end
      if choice == '+ New group…' then
        vim.ui.input({ prompt = 'Group name: ' }, function(name)
          if name and name ~= '' then M.group_add(buf, name) end
        end)
      else
        M.group_add(buf, choice)
      end
    end)
  end, { silent = true, desc = 'Tab: add to group' })

  map('n', '<leader>tG', function()
    M.group_remove(vim.api.nvim_get_current_buf())
  end, { silent = true, desc = 'Tab: remove from group' })

  map('n', '<leader>tt', M.group_toggle_collapse,
    { silent = true, desc = 'Tab: collapse/expand current group' })

  -- Pick any group to toggle (useful when multiple groups exist)
  map('n', '<leader>tT', function()
    local all = {}
    for id, g in pairs(groups) do
      table.insert(all, { id = id, name = g.name, collapsed = g.collapsed })
    end
    if #all == 0 then vim.notify('No groups', vim.log.levels.INFO); return end
    table.sort(all, function(a, b) return a.name < b.name end)
    local labels = vim.tbl_map(function(g)
      return (g.collapsed and '▶ ' or '▾ ') .. g.name
    end, all)
    vim.ui.select(labels, { prompt = 'Toggle group:' }, function(_, idx)
      if not idx then return end
      groups[all[idx].id].collapsed = not groups[all[idx].id].collapsed
      invalidate()
    end)
  end, { silent = true, desc = 'Tab: pick group to toggle' })

  map('n', '<leader>tc', M.group_pick_color,
    { silent = true, desc = 'Tab: change group color' })

  map('n', '<leader>tr', M.group_rename,
    { silent = true, desc = 'Tab: rename group' })

  map('n', '<leader>tR', M.rename_buf,
    { silent = true, desc = 'Tab: rename current tab label' })

  map('n', '<leader>tA', M.toggle_auto_group,
    { silent = true, desc = 'Tab: toggle auto-grouping by git root' })

  -- Pin / move / close actions
  map('n', '<leader>tp', function() M.toggle_pin() end,
    { silent = true, desc = 'Tab: pin/unpin (float left)' })
  map('n', '<leader>tw', function() M.close() end, { silent = true, desc = 'Tab: close current' })
  map('n', '<leader>tq', M.close_group,  { silent = true, desc = 'Tab: close group (all its buffers)' })
  map('n', '<leader>to', M.close_others, { silent = true, desc = 'Tab: close others' })
  map('n', '<leader>th', M.close_left,   { silent = true, desc = 'Tab: close to the left' })
  map('n', '<leader>tl', M.close_right,  { silent = true, desc = 'Tab: close to the right' })
  map('n', '<leader>tx', M.close_all,    { silent = true, desc = 'Tab: close all (keep pinned)' })
  map('n', '<leader>t,', function() M.move(-1) end, { silent = true, desc = 'Tab: move left' })
  map('n', '<leader>t.', function() M.move(1) end,  { silent = true, desc = 'Tab: move right' })

  -- Run auto-group on all existing buffers at startup
  vim.schedule(function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then M.auto_group(b) end
    end
  end)
end

-- ── Test exports ─────────────────────────────────────────────────────────────
M._test = {
  -- Control session dir so tests don't touch real data
  set_session_dir = function(d) _session_dir_override = d end,
  -- Direct references so tests can both read and mutate internal state
  reset_state     = reset_state,
  get_groups      = function() return groups end,
  get_buf_group   = function() return buf_group end,
  get_buf_labels  = function() return buf_labels end,
  -- Expose internals needed to verify save/load round-trip
  save_session    = save_session,
  load_session    = load_session,
}

return M
