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

local groups     = {}   -- { [id] = { name, color_idx, collapsed } }
local buf_group  = {}   -- { [bufnr] = group_id }
local next_gid   = 1
local _path_map  = {}   -- path → group_name (loaded from disk, used on BufAdd)

-- ── Per-directory persistence ─────────────────────────────────────────────────

local function groups_dir()
  return vim.fn.stdpath('data') .. '/claudespace_groups'
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
  local saved = { groups = {}, path_groups = path_groups }
  for gid, g in pairs(groups) do
    table.insert(saved.groups, { id = gid, name = g.name,
      color_idx = g.color_idx, collapsed = g.collapsed })
  end
  local ok, json = pcall(vim.fn.json_encode, saved)
  if ok then pcall(vim.fn.writefile, { json }, groups_file()) end
end

local function reset_state()
  groups    = {}
  buf_group = {}
  next_gid  = 1
  _path_map = {}
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

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    local gname = _path_map[path]
    if gname then M.group_add(bufnr, gname) end
  end
  vim.cmd 'redrawtabline'
end

local BORDER = '#3b4261'  -- separator colour (tokyonight storm border)
local RAIL   = '#0d0e16'  -- tab bar rail (darkest)
local EDITOR = '#1a1b26'  -- editor background
local ACTIVE = '#24283b'  -- active tab: lighter than editor → clearly pops above it

local function setup_group_hls()
  local hi = vim.api.nvim_set_hl
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
end

local function group_hl(gid)
  if not groups[gid] then return 'TabLine' end
  return 'CSGroup' .. groups[gid].color_idx
end

local function group_tint(gid)
  if not groups[gid] then return nil end
  return 'CSGroupT' .. groups[gid].color_idx
end

-- Public: add current buffer to a named group (creates group if needed)
function M.group_add(bufnr, name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  -- find existing group by name
  for gid, g in pairs(groups) do
    if g.name == name then
      buf_group[bufnr] = gid
      vim.cmd 'redrawtabline'
      return gid
    end
  end
  -- create new group
  local color_idx = ((next_gid - 1) % #GROUP_COLORS) + 1
  local gid = next_gid; next_gid = next_gid + 1
  groups[gid] = { name = name, color_idx = color_idx, collapsed = false }
  buf_group[bufnr] = gid
  vim.cmd 'redrawtabline'
  return gid
end

function M.group_remove(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  buf_group[bufnr] = nil
  vim.cmd 'redrawtabline'
end

-- Toggle collapse of the group the current buffer belongs to
function M.group_toggle_collapse()
  local gid = buf_group[vim.api.nvim_get_current_buf()]
  if not gid or not groups[gid] then
    vim.notify('Tab: current buffer is not in a group', vim.log.levels.WARN)
    return
  end
  groups[gid].collapsed = not groups[gid].collapsed
  -- If we just collapsed and active buf is in this group, stay on it
  vim.cmd 'redrawtabline'
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
    vim.cmd 'redrawtabline'
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
    vim.cmd 'redrawtabline'
  end)
end

function _G.CSGroupToggle(gid)
  if groups[gid] then
    groups[gid].collapsed = not groups[gid].collapsed
    vim.cmd 'redrawtabline'
  end
end

-- ── Buffer list ───────────────────────────────────────────────────────────────

local function listed_bufs()
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_valid(b) then goto next end
    if not vim.bo[b].buflisted then goto next end
    if EXCLUDE_FT[vim.bo[b].filetype] then goto next end
    if EXCLUDE_BT[vim.bo[b].buftype] then goto next end
    local name = vim.api.nvim_buf_get_name(b)
    local short = name == '' and '[No Name]' or vim.fn.fnamemodify(name, ':t')
    table.insert(bufs, {
      bufnr    = b,
      name     = short == '' and '[No Name]' or short,
      modified = vim.bo[b].modified,
      terminal = vim.bo[b].buftype == 'terminal',
      gid      = buf_group[b],
    })
    ::next::
  end
  return bufs
end

-- Sort: by group (ascending gid), ungrouped last; within group by insertion order
local function sorted_bufs(bufs)
  -- Collect group order (first appearance)
  local gid_order = {}
  local seen = {}
  for _, b in ipairs(bufs) do
    if b.gid and not seen[b.gid] then
      seen[b.gid] = true
      table.insert(gid_order, b.gid)
    end
  end
  table.sort(gid_order)

  local result = {}
  for _, gid in ipairs(gid_order) do
    for _, b in ipairs(bufs) do
      if b.gid == gid then table.insert(result, b) end
    end
  end
  for _, b in ipairs(bufs) do
    if not b.gid then table.insert(result, b) end
  end
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

function M.render()
  local bufs = sorted_bufs(listed_bufs())
  local cur   = vim.api.nvim_get_current_buf()
  local t     = {}
  local prev_gid = nil   -- track group boundaries
  local pos   = 0        -- position index for CSTabSwitch

  -- Count buffers per group for collapsed label
  local group_counts = {}
  for _, b in ipairs(bufs) do
    if b.gid then group_counts[b.gid] = (group_counts[b.gid] or 0) + 1 end
  end

  for _, buf in ipairs(bufs) do
    local gid = buf.gid
    local grp = gid and groups[gid]

    -- Group label when a new group starts
    if gid ~= prev_gid then
      if grp then
        local count = group_counts[gid] or 0
        local active_inside = grp.collapsed and (function()
          for _, b2 in ipairs(bufs) do
            if b2.gid == gid and b2.bufnr == cur then return true end
          end
        end)()
        local marker = active_inside and ' ●' or ''
        local label = grp.collapsed
          and (' ▶ ' .. grp.name .. ' (' .. count .. ')' .. marker .. ' ')
          or  (' ▼ ' .. grp.name .. ' ')
        t[#t+1] = '%#' .. group_hl(gid) .. '#'
        t[#t+1] = '%' .. gid .. '@v:lua.CSGroupToggle@'
        t[#t+1] = label
        t[#t+1] = '%T'
      elseif prev_gid then
        -- separator between last group and ungrouped
        t[#t+1] = '%#TabLineFill#  '
      end
      prev_gid = gid
    end

    -- Skip collapsed group members (but still count them)
    if grp and grp.collapsed then goto continue end

    pos = pos + 1
    local sel  = buf.bufnr == cur
    local tint = group_tint(gid)

    -- Tab background: selected uses TabLineSel, grouped gets a colour tint
    if sel then
      t[#t+1] = '%#TabLineSel#'
    elseif tint then
      t[#t+1] = '%#' .. tint .. '#'
    else
      t[#t+1] = '%#TabLine#'
    end

    t[#t+1] = '%' .. pos .. '@v:lua.CSTabSwitch@'
    t[#t+1] = buf.terminal and ' ⚡ ' or '  '
    t[#t+1] = buf.name

    -- Modified dot: own highlight so it pops without polluting filename colour
    if buf.modified then
      t[#t+1] = sel and '%#CSTabModified# ●' or '%#CSTabModifiedNC# ●'
      -- Reset to tab highlight for the trailing space
      if sel then t[#t+1] = '%#TabLineSel#'
      elseif tint then t[#t+1] = '%#' .. tint .. '#'
      else t[#t+1] = '%#TabLine#' end
    end
    t[#t+1] = ' %T'

    -- Close button: always dim, visually separated from filename
    t[#t+1] = '%' .. buf.bufnr .. '@v:lua.CSTabClose@'
    t[#t+1] = sel and '%#CSTabCloseActive#× ' or '%#CSTabClose#× '
    t[#t+1] = '%T'

    ::continue::
  end

  t[#t+1] = '%#TabLineFill#'
  return table.concat(t)
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
        vim.api.nvim_set_current_buf(b.bufnr)
        return
      end
    end
  end
end

function _G.CSTabClose(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  buf_group[bufnr] = nil  -- remove from group on close
  if vim.bo[bufnr].buftype == 'terminal' then
    M.close_terminal(bufnr)
  else
    M.close_normal(bufnr)
  end
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
  if #bufs <= 1 then vim.cmd 'enew'; return end
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == buf then idx = i; break end end
  local target = bufs[idx < #bufs and idx + 1 or idx - 1]
  if target and vim.api.nvim_get_current_buf() == buf then
    vim.api.nvim_set_current_buf(target.bufnr)
  end
end

-- ── Navigation ────────────────────────────────────────────────────────────────

function M.prev()
  local bufs = visible_sorted_bufs()
  if #bufs < 2 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == cur then idx = i; break end end
  vim.api.nvim_set_current_buf(bufs[idx <= 1 and #bufs or idx - 1].bufnr)
end

function M.next()
  local bufs = visible_sorted_bufs()
  if #bufs < 2 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 1
  for i, b in ipairs(bufs) do if b.bufnr == cur then idx = i; break end end
  vim.api.nvim_set_current_buf(bufs[idx >= #bufs and 1 or idx + 1].bufnr)
end

function M.goto_n(n)
  local bufs = visible_sorted_bufs()
  if bufs[n] then vim.api.nvim_set_current_buf(bufs[n].bufnr) end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  setup_group_hls()
  vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_group_hls })

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
  -- Apply saved group when a file is opened later in the session
  vim.api.nvim_create_autocmd('BufAdd', {
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      local gname = _path_map[path]
      if gname then M.group_add(ev.buf, gname) end
    end,
  })

  vim.o.showtabline = 2
  vim.o.tabline = '%!v:lua.require("claudespace.tabline").render()'

  local map = vim.keymap.set
  map('n', '<A-,>', M.prev, { silent = true, desc = 'Prev tab' })
  map('n', '<A-.>', M.next, { silent = true, desc = 'Next tab' })
  map('n', '<A-c>', function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype == 'terminal' then M.close_terminal(buf)
    else M.close_normal(buf) end
  end, { silent = true, desc = 'Close tab' })
  for i = 1, 5 do
    map('n', '<A-' .. i .. '>', function() M.goto_n(i) end, { silent = true })
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
    { silent = true, desc = 'Tab: collapse/expand group' })

  map('n', '<leader>tc', M.group_pick_color,
    { silent = true, desc = 'Tab: change group color' })

  map('n', '<leader>tr', M.group_rename,
    { silent = true, desc = 'Tab: rename group' })
end

return M
