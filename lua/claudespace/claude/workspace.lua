-- Workspace-level Claude features for multi-repo development:
--   #3 cross-repo context picker  — add files from any repo to the session
--   #5 broadcast prompt           — run one task across many repos (fleet)
--   #7 workspace-wide commit      — AI commit message per dirty repo
local M = {}

local api, fn = vim.api, vim.fn

local function repos()    return require('claudespace.repos') end
local function context()  return require('claudespace.claude.context') end
local function sessions() return require('claudespace.claude.sessions') end

-- ── #3 Cross-repo context picker ──────────────────────────────────────────────

function M.add_files()
  local members = repos().list()
  if #members == 0 then
    vim.notify('No repos in workspace', vim.log.levels.WARN); return
  end
  local ok, tb = pcall(require, 'telescope.builtin')
  if not ok then
    vim.notify('telescope required for the cross-repo picker', vim.log.levels.WARN); return
  end
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local dirs = {}
  for _, m in ipairs(members) do dirs[#dirs + 1] = m.abspath end

  local function send(paths)
    if #paths == 0 then return end
    if not sessions().active() then
      vim.notify('Open a Claude session first (<leader>cc)', vim.log.levels.WARN); return
    end
    -- Cross-repo files live outside the session's cwd, so reference them by
    -- absolute path; Claude attaches each @mention.
    local text = '@' .. table.concat(paths, ' @') .. '\n'
    if context().send_to_active(text) then
      vim.notify(('Added %d file(s) to Claude context'):format(#paths), vim.log.levels.INFO)
    end
  end

  tb.find_files {
    prompt_title = 'Add to Claude context (Tab to mark, ⏎ to add)',
    search_dirs  = dirs,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local multi  = picker:get_multi_selection()
        local paths  = {}
        if #multi > 0 then
          for _, e in ipairs(multi) do paths[#paths + 1] = e.path or e.value or e[1] end
        else
          local e = action_state.get_selected_entry()
          if e then paths[1] = e.path or e.value or e[1] end
        end
        actions.close(prompt_bufnr)
        send(paths)
      end)
      return true
    end,
  }
end

-- ── #5 Broadcast prompt (fleet) ───────────────────────────────────────────────

-- Multi-select repos (Tab to mark); falls back to all when telescope is absent.
local function pick_repos(cb)
  local list = repos().list()
  if not pcall(require, 'telescope') then cb(list); return end
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Broadcast to which repos? (Tab to mark, ⏎ to run)',
    finder = finders.new_table {
      results     = list,
      entry_maker = function(m) return { value = m, display = m.path, ordinal = m.path } end,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker  = action_state.get_current_picker(prompt_bufnr)
        local multi   = picker:get_multi_selection()
        local targets = {}
        if #multi > 0 then
          for _, e in ipairs(multi) do targets[#targets + 1] = e.value end
        else
          local e = action_state.get_selected_entry()
          if e then targets[1] = e.value end
        end
        actions.close(prompt_bufnr)
        cb(targets)
      end)
      return true
    end,
  }):find()
end

local function show_broadcast(task, targets, results)
  local lines = { '# Broadcast results', '', '**Task:** ' .. task, '' }
  for _, m in ipairs(targets) do
    lines[#lines + 1] = '## ' .. m.path
    for _, l in ipairs(vim.split(results[m.path] or '(no output)', '\n')) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = ''
  end
  vim.cmd 'botright vsplit'
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype   = 'markdown'
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].bufhidden  = 'wipe'
  vim.bo[buf].modifiable = false
  vim.wo.wrap = true; vim.wo.linebreak = true; vim.wo.breakindent = true
  vim.keymap.set('n', 'q', '<cmd>bd<CR>', { buffer = buf, silent = true })
end

function M.broadcast()
  if #repos().list() == 0 then
    vim.notify('No repos in workspace', vim.log.levels.WARN); return
  end
  vim.ui.input({ prompt = 'Broadcast task: ' }, function(task)
    if not task or task == '' then return end
    pick_repos(function(targets)
      if #targets == 0 then return end
      vim.notify(('Broadcasting to %d repo(s)…'):format(#targets), vim.log.levels.INFO)
      local results, done = {}, 0
      for _, m in ipairs(targets) do
        vim.system({ 'claude', '--print', task }, { cwd = m.abspath, text = true },
          vim.schedule_wrap(function(res)
            results[m.path] = (res.code == 0 and vim.trim(res.stdout or ''))
              or ('ERROR: ' .. vim.trim((res.stderr or '') ~= '' and res.stderr or tostring(res.code)))
            done = done + 1
            if done == #targets then
              show_broadcast(task, targets, results)
            else
              vim.notify(('Broadcast %d/%d…'):format(done, #targets), vim.log.levels.INFO)
            end
          end))
      end
    end)
  end)
end

-- ── #7 Workspace-wide commit ──────────────────────────────────────────────────

local function commit_next(dirty, i)
  if i > #dirty then vim.notify('Workspace commit complete', vim.log.levels.INFO); return end
  local m = dirty[i]
  fn.system({ 'git', '-C', m.abspath, 'add', '-A' })
  local diff = fn.system({ 'git', '-C', m.abspath, 'diff', '--staged' })

  local function ask(prefill)
    vim.ui.input(
      { prompt = ('[%d/%d] %s — message (empty skips): '):format(i, #dirty, m.label),
        default = prefill or '' },
      function(msg)
        if msg and msg ~= '' then
          local out = fn.system({ 'git', '-C', m.abspath, 'commit', '-m', msg })
          vim.notify(m.label .. ': ' .. vim.trim(out), vim.log.levels.INFO)
          repos().refresh_status(m)
        else
          vim.notify(m.label .. ': skipped (left staged)', vim.log.levels.INFO)
        end
        commit_next(dirty, i + 1)
      end)
  end

  if fn.executable('claude') == 0 or vim.trim(diff) == '' then ask(); return end
  vim.system(
    { 'claude', '--print',
      'Generate a concise conventional-commits message for this staged diff. '
      .. 'Imperative mood, ≤72 chars, no quotes or fences — output ONLY the message.\n\n' .. diff },
    { cwd = m.abspath, text = true },
    vim.schedule_wrap(function(res)
      ask(res.code == 0 and vim.trim(res.stdout or '') or nil)
    end))
end

function M.commit_all()
  local dirty = {}
  for _, m in ipairs(repos().list()) do
    local out = fn.systemlist({ 'git', '-C', m.abspath, 'status', '--porcelain' })
    if vim.v.shell_error == 0 and #out > 0 then dirty[#dirty + 1] = m end
  end
  if #dirty == 0 then
    vim.notify('Workspace clean — nothing to commit', vim.log.levels.INFO); return
  end
  vim.notify(('%d repo(s) with changes — generating messages…'):format(#dirty), vim.log.levels.INFO)
  commit_next(dirty, 1)
end

-- ── #4 Cross-repo grep → Claude ───────────────────────────────────────────────

function M.grep()
  local members = repos().list()
  if #members == 0 then vim.notify('No repos in workspace', vim.log.levels.WARN); return end
  vim.ui.input({ prompt = 'Grep workspace for: ' }, function(pat)
    if not pat or pat == '' then return end
    -- Run from the workspace root with relative dirs so matches print as
    -- `services/wallet/x.go:NN:…` rather than long absolute paths.
    local root = repos().root()
    local args = { 'rg', '--line-number', '--no-heading', '--color=never', '--max-count=40' }
    for _, m in ipairs(members) do args[#args + 1] = m.path end
    args[#args + 1] = '--'; args[#args + 1] = pat
    vim.system(args, { cwd = root, text = true }, vim.schedule_wrap(function(res)
      local out = vim.trim(res.stdout or '')
      if out == '' then vim.notify('No matches for: ' .. pat, vim.log.levels.INFO); return end
      local lines = vim.split(out, '\n')
      if #lines > 250 then
        lines = vim.list_slice(lines, 1, 250); lines[#lines + 1] = '… (truncated)'
      end
      if sessions().active() then
        local text = 'Workspace matches for `' .. pat .. '`:\n```\n'
          .. table.concat(lines, '\n') .. '\n```\n'
        if context().send_to_active(text) then
          vim.notify(('Sent %d match line(s) to Claude'):format(#lines), vim.log.levels.INFO)
        end
      else
        require('claudespace.claude.util').read_float(lines, ' rg: ' .. pat .. ' ', 'grep')
        vim.notify('No active Claude session — showing matches (open a session, then <leader>cG)', vim.log.levels.INFO)
      end
    end))
  end)
end

-- ── #2 Scaffold CLAUDE.md for the active repo ─────────────────────────────────

function M.scaffold_claude_md()
  local cwd = repos().active_cwd()
  local m   = repos().at(cwd) or { abspath = cwd, label = fn.fnamemodify(cwd, ':t') }
  local path = m.abspath .. '/CLAUDE.md'

  local function go()
    vim.notify('Generating CLAUDE.md for ' .. m.label .. '…', vim.log.levels.INFO)
    local prompt = 'Analyze this repository and write its CLAUDE.md. Include: a one-line purpose, '
      .. 'an overview, key directories/files, build & test commands, and important conventions. '
      .. 'Be concise and concrete. Output ONLY the markdown content, no code fences.'
    vim.system({ 'claude', '--print', prompt }, { cwd = m.abspath, text = true },
      vim.schedule_wrap(function(res)
        if res.code ~= 0 then
          vim.notify('claude failed: ' .. vim.trim(res.stderr or tostring(res.code)), vim.log.levels.ERROR)
          return
        end
        local content = vim.trim(res.stdout or '')
        if content == '' then vim.notify('Empty result', vim.log.levels.WARN); return end
        fn.writefile(vim.split(content, '\n'), path)
        require('claudespace.claude.util').ensure_editor_win()
        vim.cmd('edit ' .. fn.fnameescape(path))
        vim.notify('Wrote ' .. fn.fnamemodify(path, ':~:.') .. ' — review & edit', vim.log.levels.INFO)
      end))
  end

  if fn.filereadable(path) == 1 then
    vim.ui.select({ 'Overwrite', 'Cancel' },
      { prompt = m.label .. '/CLAUDE.md already exists:' },
      function(c) if c == 'Overwrite' then go() end end)
  else
    go()
  end
end

-- ── #8 Pre-commit review of the active repo ───────────────────────────────────

function M.review()
  local cwd  = repos().active_cwd()
  local diff = fn.system({ 'git', '-C', cwd, 'diff', '--staged' })
  if vim.trim(diff) == '' then diff = fn.system({ 'git', '-C', cwd, 'diff', 'HEAD' }) end
  if vim.trim(diff) == '' then vim.notify('No changes to review', vim.log.levels.INFO); return end
  vim.notify('Reviewing diff in ' .. fn.fnamemodify(cwd, ':t') .. '…', vim.log.levels.INFO)
  vim.system(
    { 'claude', '--print',
      'Review this diff. List concrete bugs, risks and improvements as short bullets. '
      .. 'If it looks good, say so briefly.\n\n' .. diff },
    { cwd = cwd, text = true },
    vim.schedule_wrap(function(res)
      local out = res.code == 0 and vim.trim(res.stdout or '')
        or ('claude failed: ' .. vim.trim(res.stderr or tostring(res.code)))
      require('claudespace.claude.util').read_float(
        vim.split(out, '\n'), ' Review: ' .. fn.fnamemodify(cwd, ':t') .. ' ', 'markdown')
    end))
end

-- ── #6 Bump a shared package across its dependents ────────────────────────────

function M.bump_dependents()
  local candidates = repos().depended_upon()
  if #candidates == 0 then
    vim.notify('No intra-workspace dependencies detected', vim.log.levels.INFO); return
  end
  local labels = {}
  for _, m in ipairs(candidates) do labels[#labels + 1] = m.path end
  vim.ui.select(labels, { prompt = 'Bump which package in its dependents?' }, function(choice)
    if not choice then return end
    local pkg
    for _, m in ipairs(candidates) do if m.path == choice then pkg = m end end
    if not pkg then return end
    local mod  = repos().module_path(pkg)
    local deps = repos().dependents(pkg.path)
    if not mod then vim.notify(pkg.label .. ' has no Go module path', vim.log.levels.WARN); return end
    if #deps == 0 then vim.notify('Nothing depends on ' .. pkg.path, vim.log.levels.INFO); return end

    vim.ui.select({ 'Run go get @latest + tidy', 'Cancel' },
      { prompt = ('Update %d dependent(s) of %s?'):format(#deps, pkg.label) },
      function(c)
        if c ~= 'Run go get @latest + tidy' then return end
        vim.notify(('Bumping %s in %d repo(s)…'):format(pkg.label, #deps), vim.log.levels.INFO)
        local results, done = {}, 0
        for _, dep in ipairs(deps) do
          vim.system({ 'sh', '-c', ('go get %s@latest && go mod tidy'):format(mod) },
            { cwd = dep.abspath, text = true },
            vim.schedule_wrap(function(res)
              results[dep.path] = res.code == 0 and 'ok'
                or ('FAILED: ' .. vim.trim((res.stderr or '') .. (res.stdout or '')))
              done = done + 1
              if done == #deps then
                local lines = { '# Bump ' .. pkg.path .. ' (' .. mod .. ')', '' }
                for _, d in ipairs(deps) do
                  lines[#lines + 1] = ('- %s: %s'):format(d.path, results[d.path] or '?')
                end
                require('claudespace.claude.util').read_float(lines, ' Bump results ', 'markdown')
                repos().refresh_status(pkg)
              end
            end))
        end
      end)
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  local map = vim.keymap.set
  -- Workspace / fleet actions live under the <leader>cw submenu (were top-level).
  map('n', '<leader>cwb', M.broadcast,          { silent = true, desc = 'Broadcast prompt to repos' })
  map('n', '<leader>cwc', M.commit_all,         { silent = true, desc = 'Workspace-wide commit' })
  map('n', '<leader>cwg', M.grep,               { silent = true, desc = 'Cross-repo grep → Claude' })
  map('n', '<leader>cws', M.scaffold_claude_md, { silent = true, desc = 'Scaffold CLAUDE.md (active repo)' })
  map('n', '<leader>cwr', M.review,             { silent = true, desc = 'Review diff (active repo)' })
  map('n', '<leader>cwu', M.bump_dependents,    { silent = true, desc = 'Bump shared package in dependents' })
  local ok_wk, wk = pcall(require, 'which-key')
  if ok_wk and wk.add then wk.add { { '<leader>cw', group = 'workspace' } } end

  api.nvim_create_user_command('ClaudeBroadcast', M.broadcast,        { desc = 'Broadcast a Claude task across repos' })
  api.nvim_create_user_command('ClaudeCommitAll', M.commit_all,       { desc = 'Workspace-wide AI commit' })
  api.nvim_create_user_command('ClaudeGrep',      M.grep,             { desc = 'Cross-repo grep into Claude' })
  api.nvim_create_user_command('ClaudeScaffoldMd',M.scaffold_claude_md,{ desc = 'Scaffold CLAUDE.md for the active repo' })
  api.nvim_create_user_command('ClaudeReview',    M.review,           { desc = 'Review the active repo diff' })
  api.nvim_create_user_command('ClaudeBumpDeps',  M.bump_dependents,  { desc = 'Bump a shared package across dependents' })
end

return M
