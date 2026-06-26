-- Git staging UI: view status, stage/unstage files, diff, commit, push.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_gitui')

local STATUS_HL = {
  M = 'DiagnosticWarn',  A = 'DiagnosticOk',
  D = 'DiagnosticError', R = 'DiagnosticHint',
  ['?'] = 'Comment',     ['!'] = 'Comment',
}

local function git(cmd)
  local cwd = fn.getcwd()
  return fn.trim(fn.system('git -C ' .. fn.shellescape(cwd) .. ' ' .. cmd .. ' 2>/dev/null'))
end

local function git_branch()
  return git('branch --show-current')
end

local function parse_status()
  local unstaged, staged = {}, {}
  local out = fn.system('git -C ' .. fn.shellescape(fn.getcwd()) .. ' status --porcelain=v1 2>/dev/null')
  for line in out:gmatch('[^\n]+') do
    if #line >= 4 then
      local x, y = line:sub(1,1), line:sub(2,2)
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

local function build(unstaged, staged)
  local lines, hls, actions = {}, {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end
  local function act(a) actions[#lines] = a end

  local branch = git_branch()
  local cwd    = fn.fnamemodify(fn.getcwd(), ':~')
  add('')
  add('  Git Status  [' .. branch .. ']  ' .. cwd, 'CSTreeDir')
  add('')

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

  add('  s stage/unstage  d diff  c commit  P push  r refresh  q close', 'CSInfo')
  return lines, hls, actions
end

function M.open()
  local unstaged, staged = parse_status()
  local lines, hls, actions = build(unstaged, staged)

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].bufhidden  = 'wipe'
  vim.bo[buf].filetype   = 'cs_gitui'
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  local win = api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' Git ', title_pos = 'center',
    width  = math.min(70, vim.o.columns - 4),
    height = math.min(#lines + 1, math.floor(vim.o.lines * 0.7)),
    row = math.floor((vim.o.lines - math.min(#lines + 1, math.floor(vim.o.lines * 0.7))) / 2),
    col = math.floor((vim.o.columns - math.min(70, vim.o.columns - 4)) / 2),
  })
  vim.wo[win].number = false
  vim.wo[win].cursorline = true

  local o = { buffer = buf, nowait = true, silent = true }
  local close = function() pcall(api.nvim_win_close, win, true) end

  local function refresh()
    local u2, s2 = parse_status()
    local l2, h2, a2 = build(u2, s2)
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, l2)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(h2) do api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3]) end
    actions = a2
  end

  local function current_action()
    local row = api.nvim_win_get_cursor(win)[1]
    return actions[row]
  end

  vim.keymap.set('n', 'q',     close, o)
  vim.keymap.set('n', '<Esc>', close, o)
  vim.keymap.set('n', 'r',     refresh, o)

  vim.keymap.set('n', 's', function()
    local a = current_action()
    if not a then return end
    if a.section == 'unstaged' then
      fn.system('git -C ' .. fn.shellescape(fn.getcwd()) .. ' add -- ' .. fn.shellescape(a.path))
    else
      fn.system('git -C ' .. fn.shellescape(fn.getcwd()) .. ' restore --staged -- ' .. fn.shellescape(a.path))
    end
    refresh()
  end, o)

  vim.keymap.set('n', '<CR>', function()
    local a = current_action()
    if not a then return end
    close()
    pcall(vim.cmd, 'edit ' .. fn.fnameescape(a.path))
  end, o)

  vim.keymap.set('n', 'd', function()
    local a = current_action()
    if not a then return end
    local diff_cmd = a.section == 'staged'
      and 'git diff --staged -- ' .. fn.shellescape(a.path)
      or  'git diff -- '          .. fn.shellescape(a.path)
    local diff = fn.system('git -C ' .. fn.shellescape(fn.getcwd()) .. ' ' .. diff_cmd)
    if diff == '' then
      vim.notify('No diff for ' .. a.path, vim.log.levels.INFO)
      return
    end
    close()
    vim.cmd 'botright new'
    local dbuf = api.nvim_get_current_buf()
    vim.bo[dbuf].buftype = 'nofile'; vim.bo[dbuf].bufhidden = 'wipe'
    vim.bo[dbuf].filetype = 'diff'; vim.bo[dbuf].modifiable = true
    api.nvim_buf_set_lines(dbuf, 0, -1, false, vim.split(diff, '\n'))
    vim.bo[dbuf].modifiable = false
    vim.keymap.set('n', 'q', function() vim.cmd 'bd' end, { buffer = dbuf, silent = true })
  end, o)

  vim.keymap.set('n', 'c', function()
    local cwd  = fn.getcwd()
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
        refresh()
      end)
    end

    -- Try to generate via Claude; fall back to blank input on any failure
    if fn.executable('claude') == 0 then
      do_commit()
      return
    end

    vim.notify('Generating commit message…', vim.log.levels.INFO)
    local prompt = 'Generate a concise, conventional-commits git commit message for this diff.\n'
                .. 'Rules: imperative mood, ≤72 chars, no quotes, no explanation — output ONLY the message.\n\n'
                .. diff

    -- Run in background so UI doesn't freeze on large diffs
    local result = {}
    fn.jobstart({ 'claude', '--print', prompt }, {
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
    local out = fn.system('git -C ' .. fn.shellescape(fn.getcwd()) .. ' push 2>&1')
    vim.notify(out ~= '' and out or 'Push complete.', vim.log.levels.INFO)
    refresh()
  end, o)
end

function M.setup()
  vim.keymap.set('n', '<leader>gs', M.open, { desc = 'Git: status / staging' })
end

return M
