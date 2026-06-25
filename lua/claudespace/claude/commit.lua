-- Generate commit messages with Claude
-- Usage: <leader>gc in normal mode (works in any buffer when staged changes exist)

local function generate_commit_message()
  local diff = vim.fn.system('git diff --staged')
  if vim.v.shell_error ~= 0 then
    vim.notify('claudespace: not in a git repository', vim.log.levels.ERROR)
    return
  end
  if vim.trim(diff) == '' then
    vim.notify('claudespace: no staged changes', vim.log.levels.WARN)
    return
  end

  local prompt = table.concat({
    'Generate a concise git commit message for this diff.',
    'Use conventional commits format: type(scope): description',
    'Types: feat, fix, refactor, docs, test, chore, perf, style',
    'Rules: imperative mood, max 72 chars subject, no period at end.',
    'Return ONLY the commit message, nothing else.',
    '',
    '```diff',
    diff,
    '```',
  }, '\n')

  -- Write prompt to temp file and pipe to claude CLI
  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(prompt, '\n'), tmp)

  vim.notify('claudespace: generating commit message…', vim.log.levels.INFO)

  vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print', {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.fn.delete(tmp)
      if not data or #data == 0 then return end
      local msg = vim.trim(table.concat(data, '\n'))
      if msg == '' then return end

      -- If a gitcommit buffer is open, replace subject + body (not git comments)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == 'gitcommit' then
          local msg_lines = vim.split(msg, '\n')
          vim.api.nvim_buf_set_lines(buf, 0, #msg_lines, false, msg_lines)
          vim.notify('claudespace: commit message inserted', vim.log.levels.INFO)
          return
        end
      end

      -- Otherwise put in system clipboard and notify
      vim.fn.setreg('+', msg)
      vim.notify('claudespace: commit message copied to clipboard:\n' .. msg, vim.log.levels.INFO)
    end,
    on_stderr = function(_, data)
      if data and data[1] ~= '' then
        vim.notify('claudespace: ' .. table.concat(data, '\n'), vim.log.levels.ERROR)
      end
    end,
  })
end

vim.keymap.set('n', '<leader>gc', generate_commit_message, { desc = 'Claude: generate commit message' })
