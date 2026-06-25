-- PR description generation
-- <leader>gp — generates title + body from commits and diff vs base branch

local function get_base_branch()
  -- Try common base branch names
  for _, b in ipairs({ 'main', 'master', 'develop' }) do
    local out = vim.fn.system('git rev-parse --verify ' .. b .. ' 2>/dev/null')
    if vim.v.shell_error == 0 and out ~= '' then return b end
  end
  return 'main'
end

local function generate_pr()
  local base = get_base_branch()
  local branch = vim.trim(vim.fn.system 'git symbolic-ref --short HEAD 2>/dev/null')
  if vim.v.shell_error ~= 0 or branch == '' then
    vim.notify('claudespace: not in a git repo or on a detached HEAD', vim.log.levels.WARN)
    return
  end
  if branch == base then
    vim.notify('claudespace: not on a feature branch', vim.log.levels.WARN)
    return
  end

  local log = vim.fn.system('git log ' .. base .. '..HEAD --oneline 2>/dev/null')
  local diff = vim.fn.system('git diff ' .. base .. '...HEAD --stat 2>/dev/null')

  if log == '' then
    vim.notify('claudespace: no commits ahead of ' .. base, vim.log.levels.WARN)
    return
  end

  local prompt = table.concat({
    'Generate a GitHub pull request description for this branch.',
    'Branch: ' .. branch .. ' (base: ' .. base .. ')',
    '',
    'Commits:',
    log,
    '',
    'Changed files:',
    diff,
    '',
    'Output format (return ONLY this, no extra text):',
    'TITLE: <concise title under 72 chars>',
    '---',
    '## Summary',
    '<2-4 bullet points of what changed and why>',
    '',
    '## Test plan',
    '<bulleted checklist of how to verify this works>',
  }, '\n')

  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(prompt, '\n'), tmp)
  vim.notify('claudespace: generating PR description…', vim.log.levels.INFO)

  vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print', {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.fn.delete(tmp)
      if not data then return end
      local result = vim.trim(table.concat(data, '\n'))
      if result == '' then return end

      -- Parse title vs body
      local title = result:match('^TITLE: ([^\n]+)') or branch
      local body = result:gsub('^TITLE: [^\n]+\n%-%-%-\n?', '')

      -- Open in a new buffer for editing before copying
      local buf = vim.api.nvim_create_buf(false, true)
      local lines = {}
      table.insert(lines, '# ' .. title)
      table.insert(lines, '')
      for _, l in ipairs(vim.split(body, '\n')) do
        table.insert(lines, l)
      end
      table.insert(lines, '')
      table.insert(lines, '---')
      table.insert(lines, '-- Press <leader>y to copy body to clipboard, q to close --')

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = 'markdown'
      vim.bo[buf].buftype = 'nofile'
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
    end,
  })
end

vim.keymap.set('n', '<leader>gp', generate_pr, { desc = 'Claude: generate PR description' })
