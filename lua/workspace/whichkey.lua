-- Native which-key: pause on <leader> and a bottom popup lists the possible
-- continuations (next key → action, or → +group). It reads the *actual*
-- registered normal-mode keymaps, so it can never drift from what is bound.
--
-- No timer of our own: we map <leader> and lean on Neovim's built-in timeoutlen.
-- A fast <leader>xy sequence matches the real map directly and never triggers
-- this map; only a pause on the prefix lets <leader> fire and open the popup.
-- Once open we read the rest of the sequence with getcharstr() and run the leaf
-- map's callback / rhs directly. Replaces folke/which-key.nvim.
--
-- Matching is per-byte, which covers every ASCII leader suffix in this config
-- (letters, digits, ! ? -). A continuation keyed by a termcoded special (rare)
-- simply won't resolve and cancels — acceptable for a discoverability aid.
local M = {}

local api, fn = vim.api, vim.fn

-- Group labels keyed by the key sequence after <leader>. Mirrors the groups in
-- workspace.cheatsheet / plugins.ui; anything unlisted shows a generic "+…".
local GROUPS = {
  c  = '+Claude',      cg = '+Generate', g  = '+Git',    gt = '+Git toggle',
  f  = '+Find/Files',  l  = '+LSP',      t  = '+Tabs',   x  = '+Panels',
  s  = '+Search',      w  = '+Workspace', ww = '+Terminals',
  d  = '+Debug',       r  = '+Run/Test', m = '+Marks',   u = '+Toggles',
  j  = '+Jump to mark',
}

local ESC, CTRL_C = '\27', '\3'
local LEADER = vim.g.mapleader or '\\'

-- Raw-byte prefixes to keep out of the popup (e.g. the tabline numeric
-- quick-jumps). Registered by callers via M.hide; mirrors which-key's hidden=true.
local HIDDEN = {}

local function resolve(lhs)
  lhs = lhs:gsub('<[lL]eader>', function() return LEADER end)
  return api.nvim_replace_termcodes(lhs, true, true, true)
end

local function is_hidden(lhs)
  for _, hp in ipairs(HIDDEN) do
    if lhs:sub(1, #hp) == hp then return true end
  end
  return false
end

-- Hide a set of lhs prefixes (each may use <leader>) from the popup, along with
-- everything under them.
function M.hide(prefixes)
  for _, p in ipairs(prefixes) do HIDDEN[#HIDDEN + 1] = resolve(p) end
end

-- ── Keymap collection ─────────────────────────────────────────────────────────

-- Buffer-local maps first so they shadow globals with the same next key.
local function normal_maps()
  local list = api.nvim_buf_get_keymap(0, 'n')
  vim.list_extend(list, api.nvim_get_keymap('n'))
  return list
end

-- For `prefix`, return: entries[key] = {key,label,is_group} for display,
-- leaves[key] = the map object when prefix..key is a complete mapping,
-- and whether any continuations exist at all.
local function collect(prefix)
  local entries, leaves, any = {}, {}, false
  local plen = #prefix
  for _, m in ipairs(normal_maps()) do
    local lhs = m.lhs
    if #lhs > plen and lhs:sub(1, plen) == prefix and not is_hidden(lhs) then
      any = true
      local rest = lhs:sub(plen + 1)
      local k    = rest:sub(1, 1)
      if #rest == 1 then
        if leaves[k] == nil then
          leaves[k]  = m
          entries[k] = { key = k, is_group = false,
            label = (m.desc and m.desc ~= '') and m.desc or (m.rhs or 'action') }
        end
      elseif entries[k] == nil or entries[k].is_group then
        local gid = (prefix .. k):sub(#LEADER + 1)
        entries[k] = { key = k, is_group = true, label = GROUPS[gid] or '+…' }
      end
    end
  end
  return entries, leaves, any
end

-- ── Popup ─────────────────────────────────────────────────────────────────────

local pop = { win = nil, buf = nil }

local function close_pop()
  if pop.win and api.nvim_win_is_valid(pop.win) then pcall(api.nvim_win_close, pop.win, true) end
  pop.win = nil
end

local NS = api.nvim_create_namespace 'cs_whichkey'

local function keydisp(k)
  return k == ' ' and '␣' or fn.keytrans(k)
end

-- Lay the entries out as a row-major grid sized to the editor width.
local function render(prefix, entries)
  local keys = vim.tbl_keys(entries)
  table.sort(keys, function(a, b)
    if a:lower() == b:lower() then return a < b end
    return a:lower() < b:lower()
  end)

  local cells = {}
  local cellw = 0
  for _, k in ipairs(keys) do
    local e = entries[k]
    local text = string.format(' %s → %s ', keydisp(k), e.label)
    cells[#cells + 1] = { text = text, kw = #keydisp(k), is_group = e.is_group }
    cellw = math.max(cellw, #text)
  end
  cellw = cellw + 1

  local width = math.max(20, vim.o.columns - 2)
  local cols  = math.max(1, math.floor(width / cellw))
  cols        = math.min(cols, #cells)
  local rows  = math.ceil(#cells / cols)

  local lines, marks = {}, {}
  for r = 1, rows do
    local parts, col = {}, 0
    for c = 1, cols do
      local idx = (r - 1) * cols + c
      local cell = cells[idx]
      if cell then
        local padded = cell.text .. string.rep(' ', cellw - #cell.text)
        -- key highlight spans " " + key glyph
        marks[#marks + 1] = { row = r - 1, s = col + 1, e = col + 1 + cell.kw,
          hl = cell.is_group and 'CSWkGroup' or 'CSWkKey' }
        parts[#parts + 1] = padded
        col = col + #padded
      end
    end
    lines[r] = table.concat(parts)
  end

  local title = ' ' .. fn.keytrans(prefix) .. ' '

  if not (pop.buf and api.nvim_buf_is_valid(pop.buf)) then
    pop.buf = api.nvim_create_buf(false, true)
    vim.bo[pop.buf].bufhidden = 'wipe'
  end
  api.nvim_buf_set_lines(pop.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(pop.buf, NS, 0, -1)
  for _, mk in ipairs(marks) do
    pcall(api.nvim_buf_add_highlight, pop.buf, NS, mk.hl, mk.row, mk.s, mk.e)
  end

  local cfg = {
    relative = 'editor', anchor = 'SW',
    row = vim.o.lines - 2, col = 0,
    width = width, height = math.min(rows, math.max(1, vim.o.lines - 6)),
    style = 'minimal', border = 'rounded', focusable = false,
    zindex = 200, title = title, title_pos = 'left', noautocmd = true,
  }
  if pop.win and api.nvim_win_is_valid(pop.win) then
    api.nvim_win_set_config(pop.win, cfg)
  else
    pop.win = api.nvim_open_win(pop.buf, false, cfg)
    vim.wo[pop.win].winhighlight = 'Normal:CSWkNormal,FloatBorder:CSWkBorder'
    vim.wo[pop.win].wrap = false
  end
end

-- ── Traversal ─────────────────────────────────────────────────────────────────

local function exec(m)
  close_pop()
  if m.callback then
    vim.schedule(function() pcall(m.callback) end)
  elseif m.rhs and m.rhs ~= '' then
    local keys = api.nvim_replace_termcodes(m.rhs, true, true, true)
    local mode = (m.noremap == 1) and 'n' or 'm'
    vim.schedule(function() api.nvim_feedkeys(keys, mode, false) end)
  end
end

-- Open the popup for `<leader>` and walk the tree as keys are pressed.
function M.open(prefix)
  prefix = prefix or LEADER
  while true do
    local entries, leaves, any = collect(prefix)
    if not any then close_pop(); return end
    render(prefix, entries)
    vim.cmd 'redraw'
    local ok, ch = pcall(fn.getcharstr)
    if not ok or ch == ESC or ch == CTRL_C then close_pop(); return end
    if ch == '\8' or ch == '\127' then
      -- Backspace: step up one level; at the root it closes.
      if #prefix > #LEADER then prefix = prefix:sub(1, #prefix - 1) else close_pop(); return end
    elseif leaves[ch] then
      exec(leaves[ch]); return
    elseif entries[ch] and entries[ch].is_group then
      prefix = prefix .. ch          -- descend; loop re-renders
    else
      close_pop(); return            -- dead end / unknown key
    end
  end
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

local function setup_highlights()
  local ok, theme = pcall(require, 'workspace.theme')
  if not ok then return end
  local c  = theme.colors()
  local hi = api.nvim_set_hl
  hi(0, 'CSWkNormal', { fg = c.fg,     bg = c.bg_dark })
  hi(0, 'CSWkBorder', { fg = c.fg_dim, bg = c.bg_dark })
  hi(0, 'CSWkKey',    { fg = c.cyan,   bg = c.bg_dark, bold = true })
  hi(0, 'CSWkGroup',  { fg = c.blue,   bg = c.bg_dark, bold = true })
end

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = setup_highlights })
  vim.keymap.set('n', LEADER, M.open, { silent = true, desc = 'which-key: leader hints' })
  api.nvim_create_user_command('WhichKey', function() M.open() end,
    { desc = 'Show the leader-key popup' })
end

-- test seam
M._collect = collect

return M
