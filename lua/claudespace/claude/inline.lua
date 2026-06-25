-- Inline code editing with Claude
-- Usage: select code in Visual mode, press <leader>ce, enter instruction

local function inline_edit()
  local src_buf = vim.api.nvim_get_current_buf()
  local start_line = vim.fn.line "'<"
  local end_line = vim.fn.line "'>"
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local original = table.concat(lines, '\n')
  local ft = vim.bo.filetype

  vim.ui.input({ prompt = 'Claude instruction: ' }, function(instruction)
    if not instruction or instruction == '' then return end

    local prompt = table.concat({
      'Rewrite the following ' .. ft .. ' code according to this instruction:',
      instruction,
      '',
      'Return ONLY the rewritten code, no explanations, no markdown fences.',
      '',
      original,
    }, '\n')

    local tmp = vim.fn.tempname()
    vim.fn.writefile(vim.split(prompt, '\n'), tmp)
    vim.notify('claudespace: rewriting…', vim.log.levels.INFO)

    vim.fn.jobstart('cat ' .. vim.fn.shellescape(tmp) .. ' | claude --print', {
      stdout_buffered = true,
      on_stdout = function(_, data)
        vim.fn.delete(tmp)
        if not data then return end
        local result = vim.trim(table.concat(data, '\n'))
        if result == '' then return end

        -- Show diff in a float before applying
        local buf = vim.api.nvim_create_buf(false, true)
        local result_lines = vim.split(result, '\n')

        local diff_lines = { '--- original', '+++ claude', '' }
        for _, l in ipairs(lines) do table.insert(diff_lines, '- ' .. l) end
        for _, l in ipairs(result_lines) do table.insert(diff_lines, '+ ' .. l) end
        table.insert(diff_lines, '')
        table.insert(diff_lines, 'Press y to apply, n to cancel')

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)
        vim.bo[buf].modifiable = false

        local width = math.floor(vim.o.columns * 0.7)
        local height = math.min(#diff_lines + 2, math.floor(vim.o.lines * 0.6))
        local win = vim.api.nvim_open_win(buf, true, {
          relative = 'editor',
          width = width,
          height = height,
          col = math.floor((vim.o.columns - width) / 2),
          row = math.floor((vim.o.lines - height) / 2),
          style = 'minimal',
          border = 'rounded',
          title = ' Claude Edit Preview ',
          title_pos = 'center',
        })

        local function close() pcall(vim.api.nvim_win_close, win, true) end

        vim.keymap.set('n', 'y', function()
          close()
          vim.api.nvim_buf_set_lines(src_buf, start_line - 1, end_line, false, result_lines)
          vim.notify('claudespace: edit applied', vim.log.levels.INFO)
        end, { buffer = buf, nowait = true })

        vim.keymap.set('n', 'n', close, { buffer = buf, nowait = true })
        vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })
        vim.keymap.set('n', '<Esc>', close, { buffer = buf, nowait = true })
      end,
    })
  end)
end

vim.keymap.set('v', '<leader>ce', inline_edit, { desc = 'Claude: edit selection' })
