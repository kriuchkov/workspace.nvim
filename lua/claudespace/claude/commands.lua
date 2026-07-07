-- Claude custom-command runner.
--
-- Lists `.claude/commands/**/*.md` across the workspace repos (and the cwd) and
-- runs a chosen command in a *background* Claude session — no switch into the
-- terminal buffer. A file `<name>.md` is invoked as `/<name>`; a nested file
-- `git/pr.md` as `/git:pr` (Claude's namespacing).
local M = {}

local fn = vim.fn

-- Directories to scan: every workspace repo, plus the current working dir.
local function roots()
  local seen, out = {}, {}
  local function add(d)
    if not d or d == '' then return end
    d = fn.fnamemodify(d, ':p'):gsub('/$', '')
    if not seen[d] then seen[d] = true; out[#out + 1] = d end
  end
  local ok, repos = pcall(require, 'claudespace.repos')
  if ok and repos.list then
    for _, m in ipairs(repos.list() or {}) do add(m.abspath) end
  end
  add(fn.getcwd())
  return out
end

local function strip_quotes(s) return (s:gsub('^["\']', ''):gsub('["\']$', '')) end

-- Frontmatter-aware metadata: `description` (or first body line) and
-- `argument-hint` — the latter tells the picker the command takes arguments.
local function meta(path)
  local f = io.open(path)
  if not f then return '', nil end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()

  local i = 1
  while lines[i] and vim.trim(lines[i]) == '' do i = i + 1 end
  local desc, hint
  if lines[i] and vim.trim(lines[i]) == '---' then
    for j = i + 1, #lines do
      local t = vim.trim(lines[j])
      if t == '---' then break end
      local d = t:match('^description:%s*(.+)$');   if d and not desc then desc = strip_quotes(d) end
      local h = t:match('^argument%-hint:%s*(.+)$'); if h and not hint then hint = strip_quotes(h) end
    end
  end
  if not desc then
    for _, l in ipairs(lines) do
      local t = vim.trim(l)
      if t ~= '' and t ~= '---' then desc = t; break end
    end
  end
  return desc or '', hint
end

-- All discovered commands, sorted by name. Each: { name, path, cwd, repo, desc }.
function M.discover()
  local out, seen = {}, {}
  for _, root in ipairs(roots()) do
    local dir = root .. '/.claude/commands'
    if fn.isdirectory(dir) == 1 then
      for _, path in ipairs(fn.glob(dir .. '/**/*.md', true, true)) do
        if not seen[path] then
          seen[path] = true
          local rel  = path:sub(#dir + 2, -4)   -- strip "<dir>/" prefix and ".md"
          local desc, arghint = meta(path)
          out[#out + 1] = {
            name = rel:gsub('/', ':'),           -- nested dirs → namespaced command
            path = path,
            cwd  = root,
            repo = fn.fnamemodify(root, ':t'),
            desc = desc,
            arghint = arghint,                   -- non-nil ⇒ command takes arguments
          }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function run(entry, args)
  args = args and vim.trim(args) or ''
  local cmd = '/' .. entry.name .. (args ~= '' and (' ' .. args) or '')
  -- Headless stream-json runner: structured events (exact completion, live tool
  -- activity, real result) instead of scraping a background terminal session.
  require('claudespace.claude.runner')
    .run_command(entry.cwd, cmd, ('/%s (%s)'):format(entry.name, entry.repo))
end

-- Prompt for arguments (seeded with the command's argument-hint) then run.
local function run_with_args(entry)
  local hint = entry.arghint and (' [' .. entry.arghint .. ']') or ''
  vim.ui.input({ prompt = ('/%s args%s: '):format(entry.name, hint) }, function(args)
    if args == nil then return end   -- cancelled: don't run
    run(entry, args)
  end)
end

-- ⏎ behaviour: prompt for args when the command declares them, else run directly.
local function run_default(entry)
  if entry.arghint then run_with_args(entry) else run(entry) end
end

local function open_file(entry)
  require('claudespace.shell').open(fn.bufadd(entry.path))
end

function M.pick()
  local items = M.discover()
  if #items == 0 then
    vim.notify('No Claude commands found (.claude/commands/*.md)', vim.log.levels.WARN)
    return
  end

  local label = function(e) return ('/%s   [%s]   %s'):format(e.name, e.repo, e.desc) end

  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(items, { prompt = 'Claude commands', format_item = label },
      function(e) if e then run_default(e) end end)
    return
  end

  local finders     = require('telescope.finders')
  local conf        = require('telescope.config').values
  local actions     = require('telescope.actions')
  local astate      = require('telescope.actions.state')
  local previewers  = require('telescope.previewers')

  pickers.new({}, {
    prompt_title = 'Claude tasks  (⏎ run · C-a args · C-o edit)',
    finder = finders.new_table {
      results = items,
      entry_maker = function(e)
        return { value = e, display = label(e), ordinal = e.name .. ' ' .. e.repo, path = e.path }
      end,
    },
    sorter = conf.generic_sorter {},
    previewer = previewers.vim_buffer_cat.new {},
    attach_mappings = function(pb, map)
      actions.select_default:replace(function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then run_default(e.value) end
      end)
      -- Always prompt for arguments, even when no hint was declared.
      map({ 'i', 'n' }, '<C-a>', function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then run_with_args(e.value) end
      end)
      map({ 'i', 'n' }, '<C-o>', function()
        local e = astate.get_selected_entry(); actions.close(pb)
        if e then open_file(e.value) end
      end)
      return true
    end,
  }):find()
end

return M
