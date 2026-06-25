-- Code review with Claude
-- n: <leader>cr — review current file
-- v: <leader>cr — review visual selection

local function review(lines, ft, context)
  if #lines == 0 then
    vim.notify('claudespace: buffer is empty', vim.log.levels.WARN)
    return
  end
  if ft == '' then ft = 'text' end
  local code = table.concat(lines, '\n')

  local prompt = table.concat({
    'Review this ' .. ft .. ' code. Be concise and direct.',
    'Focus on: bugs, security issues, performance problems, code smells.',
    'Format each finding as: [SEVERITY] line N: description',
    'SEVERITY: BUG | SECURITY | PERF | STYLE',
    'If no issues found, say "No issues found."',
    context and ('Context: ' .. context) or '',
    '',
    '```' .. ft,
    code,
    '```',
  }, '\n')

  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(prompt, '\n'), tmp)
  vim.notify('claudespace: reviewing…', vim.log.levels.INFO)

  vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print', {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.fn.delete(tmp)
      if not data then return end
      local result = vim.trim(table.concat(data, '\n'))
      if result == '' then return end

      -- Show in a float
      local result_lines = vim.split(result, '\n')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, result_lines)
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = 'markdown'

      local width = math.floor(vim.o.columns * 0.65)
      local height = math.min(#result_lines + 2, math.floor(vim.o.lines * 0.5))
      local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 3),
        style = 'minimal',
        border = 'rounded',
        title = ' Claude Review ',
        title_pos = 'center',
      })

      local function close() pcall(vim.api.nvim_win_close, win, true) end
      vim.keymap.set('n', 'q', close, { buffer = buf })
      vim.keymap.set('n', '<Esc>', close, { buffer = buf })

      -- Copy to quickfix list so user can navigate to lines
      local qf_items = {}
      for _, line in ipairs(result_lines) do
        local severity, lnum, msg = line:match('%[(%w+)%] line (%d+): (.+)')
        if severity and lnum then
          table.insert(qf_items, {
            lnum = tonumber(lnum),
            text = '[' .. severity .. '] ' .. msg,
            type = severity == 'BUG' and 'E' or severity == 'SECURITY' and 'E' or 'W',
          })
        end
      end
      if #qf_items > 0 then
        vim.fn.setqflist(qf_items)
        vim.notify('claudespace: ' .. #qf_items .. ' findings added to quickfix (<leader>xq)', vim.log.levels.INFO)
      end
    end,
  })
end

vim.keymap.set('n', '<leader>cr', function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  review(lines, vim.bo.filetype)
end, { desc = 'Claude: review file' })

vim.keymap.set('v', '<leader>cr', function()
  local s = vim.fn.line "'<"
  local e = vim.fn.line "'>"
  local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
  review(lines, vim.bo.filetype, 'lines ' .. s .. '-' .. e)
end, { desc = 'Claude: review selection' })
