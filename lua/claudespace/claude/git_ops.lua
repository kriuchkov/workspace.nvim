-- Git-related Claude operations: commit message, PR description, code review.
local run = require('claudespace.claude.util').run

-- ── Commit message ────────────────────────────────────────────────────────────

local function generate_commit_message()
  local diff = vim.fn.system 'git diff --staged'
  if vim.v.shell_error ~= 0 then
    vim.notify('claudespace: not in a git repository', vim.log.levels.ERROR); return
  end
  if vim.trim(diff) == '' then
    vim.notify('claudespace: no staged changes', vim.log.levels.WARN); return
  end

  run(table.concat({
    'Generate a concise git commit message for this diff.',
    'Use conventional commits format: type(scope): description',
    'Types: feat, fix, refactor, docs, test, chore, perf, style',
    'Rules: imperative mood, max 72 chars subject, no period at end.',
    'Return ONLY the commit message, nothing else.',
    '',
    '```diff', diff, '```',
  }, '\n'), 'generating commit message…', function(msg)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'gitcommit' then
        local msg_lines = vim.split(msg, '\n')
        vim.api.nvim_buf_set_lines(buf, 0, #msg_lines, false, msg_lines)
        vim.notify('claudespace: commit message inserted', vim.log.levels.INFO)
        return
      end
    end
    vim.fn.setreg('+', msg)
    vim.notify('claudespace: commit message copied to clipboard:\n' .. msg, vim.log.levels.INFO)
  end)
end

vim.keymap.set('n', '<leader>gc', generate_commit_message, { desc = 'Claude: generate commit message' })

-- ── PR description ────────────────────────────────────────────────────────────

local function get_base_branch()
  for _, b in ipairs { 'main', 'master', 'develop' } do
    local out = vim.fn.system('git rev-parse --verify ' .. b .. ' 2>/dev/null')
    if vim.v.shell_error == 0 and out ~= '' then return b end
  end
  return 'main'
end

local function generate_pr()
  local base   = get_base_branch()
  local branch = vim.trim(vim.fn.system 'git symbolic-ref --short HEAD 2>/dev/null')
  if vim.v.shell_error ~= 0 or branch == '' then
    vim.notify('claudespace: not in a git repo or on a detached HEAD', vim.log.levels.WARN); return
  end
  if branch == base then
    vim.notify('claudespace: not on a feature branch', vim.log.levels.WARN); return
  end

  local log  = vim.fn.system('git log ' .. base .. '..HEAD --oneline 2>/dev/null')
  local diff = vim.fn.system('git diff ' .. base .. '...HEAD --stat 2>/dev/null')
  if log == '' then
    vim.notify('claudespace: no commits ahead of ' .. base, vim.log.levels.WARN); return
  end

  run(table.concat({
    'Generate a GitHub pull request description for this branch.',
    'Branch: ' .. branch .. ' (base: ' .. base .. ')',
    '', 'Commits:', log, '', 'Changed files:', diff, '',
    'Output format (return ONLY this, no extra text):',
    'TITLE: <concise title under 72 chars>',
    '---',
    '## Summary',
    '<2-4 bullet points of what changed and why>',
    '',
    '## Test plan',
    '<bulleted checklist of how to verify this works>',
  }, '\n'), 'generating PR description…', function(result)
    local title = result:match('^TITLE: ([^\n]+)') or branch
    local body  = result:gsub('^TITLE: [^\n]+\n%-%-%-\n?', '')

    local buf = vim.api.nvim_create_buf(false, true)
    local lines = { '# ' .. title, '' }
    for _, l in ipairs(vim.split(body, '\n')) do table.insert(lines, l) end
    vim.list_extend(lines, { '', '---', '-- Press <leader>y to copy, q to close --' })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype  = 'markdown'
    vim.bo[buf].buftype   = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_name(buf, 'claude-pr-description.md')
    vim.cmd 'vsplit'
    vim.api.nvim_win_set_buf(0, buf)

    vim.keymap.set('n', '<leader>y', function()
      vim.fn.setreg('+', title .. '\n\n' .. body)
      vim.notify('claudespace: PR description copied to clipboard', vim.log.levels.INFO)
    end, { buffer = buf, desc = 'Copy PR description' })
    vim.keymap.set('n', 'q', function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf })
  end)
end

-- <leader>cP (Claude namespace) — <leader>gp belongs to gitsigns (preview hunk).
vim.keymap.set('n', '<leader>cgp', generate_pr, { desc = 'generate PR description' })

-- ── Code review ───────────────────────────────────────────────────────────────

local function review(lines, ft, context)
  if #lines == 0 then
    vim.notify('claudespace: buffer is empty', vim.log.levels.WARN); return
  end
  if ft == '' then ft = 'text' end

  run(table.concat({
    'Review this ' .. ft .. ' code. Be concise and direct.',
    'Focus on: bugs, security issues, performance problems, code smells.',
    'Format each finding as: [SEVERITY] line N: description',
    'SEVERITY: BUG | SECURITY | PERF | STYLE',
    'If no issues found, say "No issues found."',
    context and ('Context: ' .. context) or '',
    '', '```' .. ft, table.concat(lines, '\n'), '```',
  }, '\n'), 'reviewing…', function(result)
    local result_lines = vim.split(result, '\n')
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, result_lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype   = 'markdown'

    local width  = math.floor(vim.o.columns * 0.65)
    local height = math.min(#result_lines + 2, math.floor(vim.o.lines * 0.5))
    local win    = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded',
      width = width, height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines  - height) / 3),
      title = ' Claude Review ', title_pos = 'center',
    })

    local function close() pcall(vim.api.nvim_win_close, win, true) end
    vim.keymap.set('n', 'q',     close, { buffer = buf })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf })

    local qf = {}
    for _, line in ipairs(result_lines) do
      local sev, lnum, msg = line:match '%[(%w+)%] line (%d+): (.+)'
      if sev and lnum then
        table.insert(qf, { lnum = tonumber(lnum), text = '[' .. sev .. '] ' .. msg,
          type = (sev == 'BUG' or sev == 'SECURITY') and 'E' or 'W' })
      end
    end
    if #qf > 0 then
      vim.fn.setqflist(qf)
      vim.notify('claudespace: ' .. #qf .. ' findings in quickfix (<leader>xq)', vim.log.levels.INFO)
    end
  end)
end

vim.keymap.set('n', '<leader>cgr', function()
  review(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.bo.filetype)
end, { desc = 'review file' })

vim.keymap.set('v', '<leader>cgr', function()
  local s, e = vim.fn.line "'<", vim.fn.line "'>"
  review(vim.api.nvim_buf_get_lines(0, s - 1, e, false), vim.bo.filetype, 'lines ' .. s .. '-' .. e)
end, { desc = 'review selection' })
