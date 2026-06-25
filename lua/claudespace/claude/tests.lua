-- Generate tests with Claude for current file or visual selection

local function detect_test_framework(ft)
  local frameworks = {
    rust = 'Rust built-in #[cfg(test)] with #[test] functions',
    go = 'Go testing package with func TestXxx(t *testing.T)',
    python = 'pytest',
    typescript = 'Jest / Vitest',
    javascript = 'Jest / Vitest',
    lua = 'busted',
  }
  return frameworks[ft] or 'appropriate test framework for ' .. ft
end

local function generate_tests(lines, ft)
  local code = table.concat(lines, '\n')
  local framework = detect_test_framework(ft)

  local prompt = table.concat({
    'Generate comprehensive tests for this ' .. ft .. ' code.',
    'Use ' .. framework .. '.',
    'Cover: happy path, edge cases, error cases.',
    'Return ONLY the test code, no explanations.',
    '',
    code,
  }, '\n')

  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(prompt, '\n'), tmp)
  vim.notify('claudespace: generating tests…', vim.log.levels.INFO)

  vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print', {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.fn.delete(tmp)
      if not data then return end
      local result = vim.trim(table.concat(data, '\n'))
      if result == '' then return end

      -- Open in a vertical split
      vim.cmd 'vsplit'
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, '\n'))
      vim.bo[buf].filetype = ft
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.api.nvim_buf_set_name(buf, 'claude-tests.' .. ft)
      vim.notify('claudespace: tests generated', vim.log.levels.INFO)
    end,
  })
end

-- Generate tests for entire file
vim.keymap.set('n', '<leader>ct', function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  generate_tests(lines, vim.bo.filetype)
end, { desc = 'Claude: generate tests (file)' })

-- Generate tests for visual selection
vim.keymap.set('v', '<leader>ct', function()
  local start_l = vim.fn.line "'<"
  local end_l = vim.fn.line "'>"
  local lines = vim.api.nvim_buf_get_lines(0, start_l - 1, end_l, false)
  generate_tests(lines, vim.bo.filetype)
end, { desc = 'Claude: generate tests (selection)' })
