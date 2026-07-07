-- Claude session manager — owns the full lifecycle of claude terminal sessions.
-- A "session" is a terminal buffer running the `claude` CLI.
local M = {}

local api = vim.api
local fn  = vim.fn

-- ── State ─────────────────────────────────────────────────────────────────────

local sessions  = {}    -- { [id] = { id, name, cwd, bufnr } }
local order     = {}    -- insertion order: list of ids
local active_id = nil
local next_id   = 1

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function ordered()
  local t = {}
  for _, id in ipairs(order) do
    if sessions[id] then table.insert(t, sessions[id]) end
  end
  return t
end

local function live_buf(id)
  local s = sessions[id]; if not s then return nil end
  if s.bufnr and api.nvim_buf_is_valid(s.bufnr)
    and vim.bo[s.bufnr].buftype == 'terminal' then
    return s.bufnr
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and vim.b[b].cs_session_id == id then
      s.bufnr = b; return b
    end
  end
end

local function name_buf(buf, name)
  -- prevent E95 duplicate name by silently failing if already set
  pcall(api.nvim_buf_set_name, buf, name .. ' [claude]')
end

local function win_opts()
  vim.wo.winbar    = ''
  vim.wo.scrolloff = 0
end

-- Claude sessions are shown in the bottom bar (claudespace.claude.bottombar),
-- not the top tabline — no grouping needed.
local function group_claude(_) end

local shell = require('claudespace.shell')

-- Open `buf` in the single center window and collapse any duplicate Claude panes.
local function open_center(buf)
  local win = shell.open(buf)
  shell.consolidate(win, function(w)
    local b = api.nvim_win_get_buf(w)
    return vim.b[b] and vim.b[b].cs_session_id ~= nil
  end)
  return win
end

-- Build the launch command. flag '' = fresh chat, ' --continue' = resume the
-- most recent conversation in the cwd, ' --resume' = pick from past sessions.
local function claude_cmd(flag)
  return "zsh -i -c 'claude" .. (flag or '') .. "'"
end

-- Claude stores each conversation as ~/.claude/projects/<enc-cwd>/<uuid>.jsonl,
-- where enc-cwd is the absolute path with '/' and '.' replaced by '-'.
local function project_dir(cwd)
  return fn.expand('~/.claude/projects/') .. (cwd:gsub('[/.]', '-'))
end

-- A conversation id is later interpolated into the launch shell string
-- (`claude --resume <id>`), so accept only the hex+dash shape of a real UUID.
-- This blocks shell injection from a crafted *.jsonl filename or a tampered
-- workspace file (e.g. an id containing a quote that breaks out of the command).
local function valid_id(uuid)
  return type(uuid) == 'string' and uuid:match('^[%x][%x%-]*$') ~= nil
end

-- Conversation UUIDs for a cwd, newest-first (invalid-shaped names filtered out).
local function session_ids(cwd)
  local files = fn.glob(project_dir(cwd) .. '/*.jsonl', true, true)
  table.sort(files, function(a, b) return fn.getftime(a) > fn.getftime(b) end)
  local ids = {}
  for _, f in ipairs(files) do
    local id = fn.fnamemodify(f, ':t:r')
    if valid_id(id) then ids[#ids + 1] = id end
  end
  return ids
end

-- Return uuid only if it's a valid, still-present conversation for cwd, else nil.
local function resume_id(cwd, uuid)
  if not valid_id(uuid) then return nil end
  if fn.filereadable(project_dir(cwd) .. '/' .. uuid .. '.jsonl') == 0 then return nil end
  return uuid
end

-- Ids already bound to a live session (so siblings in the same cwd don't collide).
local function claimed_ids()
  local set = {}
  for _, s in pairs(sessions) do if s.claude_id then set[s.claude_id] = true end end
  return set
end

-- Claude writes the conversation file a moment after launch. Grab the newest id
-- for this cwd that no other session has claimed, so we can --resume the *exact*
-- conversation on workspace restore instead of --continue (which would point
-- every same-cwd session at the single latest one).
local function capture_id(sess)
  vim.defer_fn(function()
    if not sessions[sess.id] or sess.claude_id then return end
    local claimed = claimed_ids()
    for _, uuid in ipairs(session_ids(sess.cwd)) do
      if not claimed[uuid] then sess.claude_id = uuid; return end
    end
  end, 3000)
end

local util = require('claudespace.claude.util')
local ensure_editor_win = util.ensure_editor_win

-- Delete buf if it's a listed empty [No Name] buffer (cleanup after M.new replaces it).
local function wipe_empty(buf)
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  if fn.bufname(buf) ~= '' then return end
  if api.nvim_buf_line_count(buf) > 1 then return end
  if (fn.getbufline(buf, 1)[1] or '') ~= '' then return end
  if vim.bo[buf].buftype ~= '' then return end
  pcall(api.nvim_buf_delete, buf, { force = false })
end

-- ── Core operations ───────────────────────────────────────────────────────────

---Create and open a new Claude session in the current window.
---@param cwd? string
-- The repo a session belongs to (by cwd), for grouping/labelling.
local function session_repo(s)
  local ok, repos = pcall(require, 'claudespace.repos')
  return ok and repos.of(s.cwd) or nil
end

function M.new(cwd, flag)
  if not cwd then
    -- Start in the active repo so Claude picks up that repo's CLAUDE.md cascade.
    local ok, repos = pcall(require, 'claudespace.repos')
    local m = ok and repos.active()
    cwd = (m and m.abspath) or fn.getcwd()
  end
  local id   = next_id; next_id = next_id + 1
  local name = 'Chat ' .. id
  local sess = { id = id, name = name, cwd = cwd }
  sessions[id] = sess
  table.insert(order, id)
  active_id = id

  local win = shell.center()
  local prev_buf = api.nvim_win_get_buf(win)
  local buf = api.nvim_create_buf(true, false)
  vim.b[buf].cs_session_id = id
  open_center(buf)
  local job_id = fn.termopen(claude_cmd(flag), { cwd = cwd })
  sess.bufnr  = buf
  sess.job_id = job_id
  capture_id(sess)

  -- No auto-injection of @.claude/WORKSPACE.md on start — it pre-fills the prompt
  -- unasked. Use <leader>ci (context.inject) to push it into a session on demand.

  vim.schedule(function()
    if api.nvim_buf_is_valid(buf) then name_buf(buf, name) end
    wipe_empty(prev_buf)
  end)

  api.nvim_create_autocmd('TermClose', {
    buffer = buf, once = true,
    callback = function()
      vim.schedule(function() M._on_close(id, buf) end)
    end,
  })

  win_opts()
  vim.cmd 'startinsert'
end

---Open (focus) an existing session in the current window.
---@param id number
function M.open(id)
  local sess = sessions[id]; if not sess then return end
  local buf  = live_buf(id)
  if buf then
    open_center(buf)
  else
    -- process died but session entry survived — restart
    buf = api.nvim_create_buf(true, false)
    vim.b[buf].cs_session_id = id
    open_center(buf)
    fn.termopen(claude_cmd(' --continue'), { cwd = sess.cwd })  -- resume the conversation
    sess.bufnr = buf
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then name_buf(buf, sess.name) end
    end)
    api.nvim_create_autocmd('TermClose', {
      buffer = buf, once = true,
      callback = function()
        vim.schedule(function() M._on_close(id, buf) end)
      end,
    })
  end
  active_id = id
  win_opts()
end

---Open active session, or create one if none exist.
function M.toggle()
  local list = ordered()
  if #list == 0 then M.new(); return end
  M.open((sessions[active_id] or list[1]).id)
end

---Jump to the n-th Claude session (matches the numbers in the bottom bar).
function M.goto_index(n)
  local list = ordered()
  if list[n] then M.open(list[n].id) end
end

---New session resuming the most recent conversation in the (active) repo.
function M.continue(cwd) M.new(cwd, ' --continue') end

---New session running Claude's `--resume` picker to restore any past conversation.
function M.resume(cwd) M.new(cwd, ' --resume') end

---Next session (wraps).
function M.next()
  local list = ordered(); if #list == 0 then return end
  local idx = 1
  for i, s in ipairs(list) do if s.id == active_id then idx = i; break end end
  M.open(list[idx >= #list and 1 or idx + 1].id)
end

---Previous session (wraps).
function M.prev()
  local list = ordered(); if #list == 0 then return end
  local idx = 1
  for i, s in ipairs(list) do if s.id == active_id then idx = i; break end end
  M.open(list[idx <= 1 and #list or idx - 1].id)
end

---Rename a session.
---@param id number
---@param name string
function M.rename(id, name)
  local sess = sessions[id]
  if not sess or not name or name == '' then return end
  sess.name = name
  local buf = live_buf(id)
  if buf then name_buf(buf, name) end
end

---Interactively rename the session in the current window (or the active one).
function M.rename_current()
  local id = vim.b[api.nvim_get_current_buf()].cs_session_id or active_id
  if not id then vim.notify('No active Claude session', vim.log.levels.WARN); return end
  local sess = sessions[id]; if not sess then return end
  vim.ui.input({ prompt = 'Session name: ', default = sess.name }, function(name)
    if name and name ~= '' then M.rename(id, name) end
  end)
end

---Telescope picker — fuzzy-find and switch / close sessions.
function M.pick()
  local ok_tel = pcall(require, 'telescope')
  if not ok_tel then
    -- fallback: vim.ui.select
    local list = ordered()
    if #list == 0 then vim.notify('No Claude sessions', vim.log.levels.WARN); return end
    vim.ui.select(
      vim.tbl_map(function(s)
        return (s.id == active_id and '⚡ ' or '  ') .. s.name
      end, list),
      { prompt = 'Claude session:' },
      function(_, idx) if idx then M.open(list[idx].id) end end
    )
    return
  end

  local pickers      = require 'telescope.pickers'
  local finders      = require 'telescope.finders'
  local conf         = require('telescope.config').values
  local actions      = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  pickers.new({}, {
    prompt_title = 'Claude Sessions',
    finder = finders.new_table {
      results = (function()
        local list = ordered()
        table.sort(list, function(a, b)
          local ra = (session_repo(a) or {}).label or ''
          local rb = (session_repo(b) or {}).label or ''
          if ra ~= rb then return ra < rb end
          return a.id < b.id
        end)
        return list
      end)(),
      entry_maker = function(s)
        local active = s.id == active_id
        local repo   = session_repo(s)
        local tag    = repo and ('[' .. repo.label .. '] ') or ''
        local label  = (active and '⚡ ' or '  ') .. tag .. s.name
        return {
          value = s, display = label,
          ordinal = (repo and repo.label or '') .. ' ' .. s.name,
        }
      end,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(pbuf, map_)
      actions.select_default:replace(function()
        actions.close(pbuf)
        local sel = action_state.get_selected_entry()
        if sel then M.open(sel.value.id) end
      end)
      local function close_sel()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        actions.close(pbuf)
        M._on_close(sel.value.id, live_buf(sel.value.id) or -1)
      end
      map_('i', '<C-x>', close_sel)
      map_('n', '<C-x>', close_sel)
      return true
    end,
  }):find()
end

-- ── Close handler ─────────────────────────────────────────────────────────────

function M._on_close(id, buf)
  if vim.v.dying > 0 then return end

  local list = ordered()
  local closed_idx = 1
  for i, s in ipairs(list) do if s.id == id then closed_idx = i; break end end

  sessions[id] = nil
  for i = #order, 1, -1 do if order[i] == id then table.remove(order, i); break end end

  local remaining = ordered()
  if active_id == id then
    if #remaining > 0 then
      active_id = remaining[math.min(math.max(1, closed_idx - 1), #remaining)].id
    else
      active_id = nil
    end
  end

  -- Neovim automatically redirects windows showing a deleted buffer.
  -- Deleting with force=true handles terminal buffers (process already exited).
  vim.defer_fn(function()
    if buf and buf > 0 and api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end, 150)
end

-- ── Persistence ───────────────────────────────────────────────────────────────

---Returns a snapshot of current sessions for workspace persistence.
function M.get_persistence_data()
  return vim.tbl_map(function(s)
    return { name = s.name, cwd = s.cwd, claude_id = s.claude_id }
  end, ordered())
end

---Start a session in a background buffer (no visible window).
---termopen() requires a window, so we briefly open a 1-line split then close it.
local function start_background(sess, flag)
  local orig_win = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(true, false)
  vim.b[buf].cs_session_id = sess.id
  group_claude(buf)
  sess.bufnr = buf

  -- termopen needs the buffer current in a window to size the PTY. Use a float
  -- with noautocmd instead of a split: it doesn't reflow the real layout (no
  -- flicker) and fires no Win* autocmds. Everything here is synchronous, so the
  -- float never paints before we close it.
  local tmp_win = api.nvim_open_win(buf, true, {
    relative = 'editor', width = 80, height = 24,
    row = 0, col = 0, focusable = false, style = 'minimal', noautocmd = true,
  })
  sess.job_id = fn.termopen(claude_cmd(flag or ' --continue'), { cwd = sess.cwd })
  -- Close the float — process keeps running in the buffer
  pcall(api.nvim_win_close, tmp_win, true)
  pcall(api.nvim_set_current_win, orig_win)

  vim.schedule(function()
    if api.nvim_buf_is_valid(buf) then name_buf(buf, sess.name) end
  end)

  api.nvim_create_autocmd('TermClose', {
    buffer = buf, once = true,
    callback = function()
      vim.schedule(function() M._on_close(sess.id, buf) end)
    end,
  })
end

---Restore sessions from persisted data (called by workspace.load).
---Sessions are started in background — user opens them with <leader>cc/cs.
---@param data table  list of {name, cwd}
function M.restore(data)
  if not data or #data == 0 then return end
  -- Resume each session on its *own* conversation. Prefer the stored claude_id;
  -- otherwise fall back to the recent on-disk conversations for that cwd, handing
  -- each same-cwd session a distinct one so they don't all collapse onto --continue.
  local pool = {}   -- cwd -> list of available uuids (newest-first)
  local used = {}
  for _, entry in ipairs(data) do
    if valid_id(entry.claude_id) then used[entry.claude_id] = true end
  end
  local function next_uuid(cwd)
    if pool[cwd] == nil then pool[cwd] = session_ids(cwd) end
    for i, uuid in ipairs(pool[cwd]) do
      if not used[uuid] then
        used[uuid] = true
        table.remove(pool[cwd], i)
        return uuid
      end
    end
  end

  for _, entry in ipairs(data) do
    if entry.cwd and entry.name then
      local id   = next_id; next_id = next_id + 1
      -- resume_id validates the persisted id AND that its file still exists;
      -- otherwise hand out a distinct recent conversation for the cwd.
      local uuid = resume_id(entry.cwd, entry.claude_id) or next_uuid(entry.cwd)
      local sess = { id = id, name = entry.name, cwd = entry.cwd, claude_id = uuid }
      sessions[id] = sess
      table.insert(order, id)
      if not active_id then active_id = id end
      start_background(sess, uuid and (' --resume ' .. uuid) or ' --continue')
    end
  end
  vim.notify(
    ('Claude: restored %d session(s) — <leader>cs to pick'):format(#data),
    vim.log.levels.INFO
  )
end

-- ── Public read-only API ──────────────────────────────────────────────────────

function M.list()       return ordered() end
function M.active()     return sessions[active_id] end
function M.active_id_() return active_id end
function M.get(id)      return sessions[id] end

-- ── Past sessions (on-disk history) ───────────────────────────────────────────
-- The CLI has no machine-readable "list sessions", so read the transcript files
-- directly: id from the <uuid>.jsonl filename, a title from the `custom-title`
-- line (or the first user message), recency from the mtime. Resume = --resume id.

-- Harness-injected user turns that are not real messages: <command-*>/<task-*>/
-- <local-command-*> tags, compaction continuations, and local-command caveats.
local function is_noise(text)
  return text:match('^<') ~= nil
      or text:match('^This session is being continued') ~= nil
      or text:match('^Caveat:') ~= nil
end

-- Real conversational text for a transcript line → (role, text), or nil for tool
-- results, meta injections, and (for user turns) harness noise.
local function message_text(ev)
  if type(ev) ~= 'table' or not ev.message then return nil end
  if ev.isMeta or ev.toolUseResult then return nil end     -- meta / tool-result turn
  local role = ev.message.role or ev.type
  local c    = ev.message.content
  local text
  if type(c) == 'string' then
    text = c
  elseif type(c) == 'table' then
    local parts = {}
    for _, b in ipairs(c) do if b.type == 'text' and b.text then parts[#parts + 1] = b.text end end
    text = #parts > 0 and table.concat(parts, '\n') or nil
  end
  if not text then return nil end
  text = vim.trim(text)
  if text == '' then return nil end
  if role == 'user' and is_noise(text) then return nil end  -- only user text is tag-noise
  return role, text
end

-- Titles/transcripts are re-read on every history() open and delete-refresh, and
-- transcripts on every picker cursor move. Memoise by path+mtime — a session file
-- only changes when resumed or renamed, both of which bump the mtime.
local _title_cache, _transcript_cache = {}, {}
local _transcript_order = {}          -- insertion order for the transcript LRU
local TRANSCRIPT_CACHE_MAX = 12

local function session_title(path)
  local mt = fn.getftime(path)
  local c  = _title_cache[path]
  if c and c.mtime == mt then return c.title end

  local title
  local f = io.open(path)
  if f then
    local n = 0
    for line in f:lines() do
      n = n + 1
      if n > 80 then break end
      local ok, ev = pcall(vim.json.decode, line)
      if ok and type(ev) == 'table' then
        if ev.type == 'custom-title' and ev.customTitle then title = ev.customTitle; break end
        local role, text = message_text(ev)
        if role == 'user' then title = text; break end
      end
    end
    f:close()
  end
  _title_cache[path] = { mtime = mt, title = title }
  return title
end

local function rel_time(t)
  local d = os.time() - t
  if d < 60    then return d .. 's' end
  if d < 3600  then return math.floor(d / 60) .. 'm' end
  if d < 86400 then return math.floor(d / 3600) .. 'h' end
  return math.floor(d / 86400) .. 'd'
end

-- Every project dir worth scanning: the workspace repos and the cwd.
local function history_cwds()
  local set, list = {}, {}
  local function add(c) if c and c ~= '' and not set[c] then set[c] = true; list[#list + 1] = c end end
  local ok, repos = pcall(require, 'claudespace.repos')
  if ok then
    add(repos.root and repos.root())
    for _, m in ipairs(repos.list and repos.list() or {}) do add(m.abspath) end
  end
  add(fn.getcwd())
  return list
end

-- Past conversations across the workspace, newest first.
function M.past_sessions()
  local seen, out = {}, {}
  for _, cwd in ipairs(history_cwds()) do
    for _, f in ipairs(fn.glob(project_dir(cwd) .. '/*.jsonl', true, true)) do
      local id = fn.fnamemodify(f, ':t:r')
      if valid_id(id) and not seen[f] then
        seen[f] = true
        out[#out + 1] = {
          id = id, cwd = cwd, path = f, mtime = fn.getftime(f),
          title = session_title(f) or '(untitled)',
          repo  = fn.fnamemodify(cwd, ':t'),
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.mtime > b.mtime end)
  return out
end

-- Render a transcript as markdown: "### You" / "### Claude" blocks, harness noise
-- (tool results, meta turns, command tags) filtered out via message_text.
-- Memoised by path+mtime — the picker re-reads on every cursor move otherwise.
local function transcript_lines(path)
  local mt = fn.getftime(path)
  local c  = _transcript_cache[path]
  if c and c.mtime == mt then return c.lines end

  local lines = {}
  local f = io.open(path)
  if not f then return { '(cannot read transcript)' } end
  for line in f:lines() do
    local ok, ev = pcall(vim.json.decode, line)
    if ok then
      local role, text = message_text(ev)
      if text then
        lines[#lines + 1] = '### ' .. (role == 'user' and 'You' or 'Claude')
        for _, l in ipairs(vim.split(text, '\n')) do lines[#lines + 1] = l end
        lines[#lines + 1] = ''
      end
    end
  end
  f:close()
  if #lines == 0 then lines = { '(empty transcript)' } end
  -- Cap the cache: transcripts can be thousands of lines, so keep only the most
  -- recently read few rather than growing unbounded for the whole nvim session.
  if not _transcript_cache[path] then
    _transcript_order[#_transcript_order + 1] = path
    while #_transcript_order > TRANSCRIPT_CACHE_MAX do
      _transcript_cache[table.remove(_transcript_order, 1)] = nil
    end
  end
  _transcript_cache[path] = { mtime = mt, lines = lines }
  return lines
end

local function view_transcript(entry)
  util.read_float(
    transcript_lines(entry.path), ' ' .. fn.strcharpart(entry.title, 0, 50) .. ' ', 'markdown',
    { at_end = true })
end

-- Guard: only ever delete files under ~/.claude/projects (they come from our own
-- glob, but keep the destructive op defensive).
local function delete_session(entry)
  if not entry.path:match('/%.claude/projects/') then return false end
  if os.remove(entry.path) == nil then return false end
  _title_cache[entry.path], _transcript_cache[entry.path] = nil, nil  -- evict cached data
  return true
end

-- Browse past sessions with a live transcript preview.
-- ⏎ resume · C-o transcript float · C-d delete.
function M.history()
  local function label(e)
    -- strcharpart, not :sub, so a multibyte title isn't cut mid-character.
    return ('%-4s [%s]  %s'):format(rel_time(e.mtime), e.repo,
      fn.strcharpart(e.title:gsub('%s+', ' '), 0, 80))
  end
  local function resume(e) M.new(e.cwd, ' --resume ' .. e.id) end

  if #M.past_sessions() == 0 then
    vim.notify('No past Claude sessions found', vim.log.levels.WARN)
    return
  end

  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(M.past_sessions(), { prompt = 'Claude sessions', format_item = label },
      function(e) if e then resume(e) end end)
    return
  end
  local finders    = require 'telescope.finders'
  local conf       = require('telescope.config').values
  local actions    = require 'telescope.actions'
  local astate     = require 'telescope.actions.state'
  local previewers = require 'telescope.previewers'

  local function make_finder()
    return finders.new_table {
      results = M.past_sessions(),
      entry_maker = function(e)
        return { value = e, display = label(e), ordinal = e.title .. ' ' .. e.repo }
      end,
    }
  end

  pickers.new({}, {
    prompt_title = 'Claude sessions  (⏎ resume · C-o transcript · C-d delete)',
    finder = make_finder(),
    sorter = conf.generic_sorter {},
    previewer = previewers.new_buffer_previewer {
      title = 'Transcript',
      define_preview = function(self, entry)
        local lines = transcript_lines(entry.value.path)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = 'markdown'
        -- Scroll to the newest message (the end) rather than the first line.
        local win = self.state.winid
        if win and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_set_cursor, win, { #lines, 0 })
          vim.api.nvim_win_call(win, function() vim.cmd 'normal! zb' end)
        end
      end,
    },
    attach_mappings = function(pb, map)
      actions.select_default:replace(function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then resume(e.value) end
      end)
      map({ 'i', 'n' }, '<C-o>', function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then view_transcript(e.value) end
      end)
      map({ 'i', 'n' }, '<C-d>', function()
        local e = astate.get_selected_entry()
        if not e then return end
        if fn.confirm('Delete session "' .. e.value.title:sub(1, 40) .. '"?', '&Yes\n&No', 2) ~= 1 then
          return
        end
        if delete_session(e.value) then
          astate.get_current_picker(pb):refresh(make_finder(), { reset_prompt = false })
        else
          vim.notify('Could not delete session', vim.log.levels.ERROR)
        end
      end)
      return true
    end,
  }):find()
end

-- Background slash-command running now lives in claudespace.claude.runner (the
-- structured stream-json runner); this module only owns interactive sessions.

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  -- Window opts for all Claude terminal buffers
  api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
    callback = function()
      local buf = api.nvim_get_current_buf()
      if vim.bo[buf].buftype ~= 'terminal' then return end
      if not vim.b[buf].cs_session_id then return end
      win_opts()
    end,
  })

  -- Auto-scroll background Claude terminals while not focused
  local timer = vim.uv.new_timer()
  api.nvim_create_autocmd('VimLeave', { callback = function() timer:stop() end })
  timer:start(500, 200, vim.schedule_wrap(function()
    local cur = api.nvim_get_current_win()
    for _, win in ipairs(api.nvim_list_wins()) do
      if not api.nvim_win_is_valid(win) or win == cur then goto continue end
      local b = api.nvim_win_get_buf(win)
      if not api.nvim_buf_is_valid(b) then goto continue end
      if vim.bo[b].buftype ~= 'terminal' or not vim.b[b].cs_session_id then goto continue end
      local lc = api.nvim_buf_line_count(b)
      local ok, cur_ = pcall(api.nvim_win_get_cursor, win)
      if ok and cur_[1] >= lc - 15 then
        pcall(api.nvim_win_set_cursor, win, { lc, 0 })
      end
      ::continue::
    end
  end))

  -- Keymaps
  local map = vim.keymap.set

  map('n', '<leader>cc', M.toggle,
    { desc = 'Claude: open/toggle', silent = true })

  map('n', '<leader>cn', function() M.new() end,
    { desc = 'Claude: new session', silent = true })

  map('n', '<leader>cu', function() M.resume() end,
    { desc = 'Claude: resume past session (--resume)', silent = true })

  api.nvim_create_user_command('ClaudeResume',   function() M.resume() end,   { desc = 'Resume a past Claude session' })
  api.nvim_create_user_command('ClaudeContinue', function() M.continue() end, { desc = 'Continue the most recent Claude conversation' })

  map('n', '<leader>ch', M.prev,
    { desc = 'Claude: prev session', silent = true })

  map('n', '<leader>cl', M.next,
    { desc = 'Claude: next session', silent = true })

  map('n', '<leader>cs', M.pick,
    { desc = 'Claude: pick session', silent = true })

  map('n', '<leader>cH', M.history,
    { desc = 'Claude: past session history', silent = true })
  api.nvim_create_user_command('ClaudeHistory', function() M.history() end,
    { desc = 'Browse past Claude sessions' })

  map('n', '<leader>cR', M.rename_current,
    { desc = 'Claude: rename session', silent = true })

  -- Alt-based session cycling works from inside a Claude terminal too (unlike the
  -- <leader> keys, which are <Space> and would clash with typing). <A-h>/<A-l>.
  map({ 'n', 't' }, '<A-h>', M.prev, { silent = true, desc = 'Claude: prev session' })
  map({ 'n', 't' }, '<A-l>', M.next, { silent = true, desc = 'Claude: next session' })

  -- Numeric quick-jump to bottom-bar session N (¹²³ …), hidden from which-key.
  -- Works from a Claude terminal too ({n,t}, matching the other session keys).
  for i = 1, 9 do
    map('n', '<leader>c' .. i, function() M.goto_index(i) end, { silent = true })
  end
  local ok_wk, wk = pcall(require, 'which-key')
  if ok_wk and wk.add then
    local spec = {}
    for i = 1, 9 do spec[#spec + 1] = { '<leader>c' .. i, hidden = true } end
    wk.add(spec)
  end
end

-- ── Test exports ──────────────────────────────────────────────────────────────

M._test = {
  reset        = function() sessions = {}; order = {}; active_id = nil; next_id = 1 end,
  get_sessions = function() return ordered() end,
  get_state    = function()
    return { sessions = sessions, order = order, active_id = active_id }
  end,
}

return M
