-- Code generation operations: inline edit, generate at cursor, generate tests.
local util         = require 'claudespace.claude.util'
local run          = util.run
local preview_float = util.preview_float
local M            = {}

-- ── Inline edit (visual selection) ───────────────────────────────────────────

local function inline_edit()
  local src_buf    = vim.api.nvim_get_current_buf()
  local start_line = vim.fn.line "'<"
  local end_line   = vim.fn.line "'>"
  local lines      = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local ft         = vim.bo.filetype

  vim.ui.input({ prompt = 'Claude instruction: ' }, function(instruction)
    if not instruction or instruction == '' then return end

    run(table.concat({
      'Rewrite the following ' .. ft .. ' code according to this instruction:',
      instruction, '',
      'Return ONLY the rewritten code, no explanations, no markdown fences.',
      '', table.concat(lines, '\n'),
    }, '\n'), 'rewriting…', function(result)
      local result_lines = vim.split(result, '\n')
      local diff = { '--- original', '+++ claude', '' }
      for _, l in ipairs(lines)        do table.insert(diff, '- ' .. l) end
      for _, l in ipairs(result_lines) do table.insert(diff, '+ ' .. l) end

      preview_float(diff, ' Claude Edit Preview ', function()
        vim.api.nvim_buf_set_lines(src_buf, start_line - 1, end_line, false, result_lines)
        vim.notify('claudespace: edit applied', vim.log.levels.INFO)
      end)
    end)
  end)
end

vim.keymap.set('v', '<leader>ce', inline_edit, { desc = 'Claude: edit selection' })

-- ── Generate at cursor ────────────────────────────────────────────────────────

function M.generate()
  local buf   = vim.api.nvim_get_current_buf()
  local win   = vim.api.nvim_get_current_win()
  local row   = vim.api.nvim_win_get_cursor(win)[1]
  local total = vim.api.nvim_buf_line_count(buf)
  local ft    = vim.bo[buf].filetype
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')

  local before = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 40), row, false)
  local after  = vim.api.nvim_buf_get_lines(buf, row, math.min(total, row + 10), false)

  vim.ui.input({ prompt = 'Generate: ' }, function(instruction)
    if not instruction or instruction == '' then return end

    run(table.concat({
      'File: ' .. fname .. (ft ~= '' and '  filetype: ' .. ft or ''),
      '', 'Context before insertion point:',
      table.concat(before, '\n'),
      '<<<INSERT_HERE>>>',
      table.concat(after,  '\n'),
      '', 'Task: ' .. instruction, '',
      'Return ONLY the raw text to insert. No explanation. No markdown fences.',
    }, '\n'), 'generating…', function(text)
      if text == '' then
        vim.notify('Claude returned empty result', vim.log.levels.WARN); return
      end
      local result = vim.split(text, '\n', { plain = true })
      preview_float(result, ' Claude: insert preview ', function()
        vim.api.nvim_buf_set_lines(buf, row, row, false, result)
        vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
        vim.notify('Inserted ' .. #result .. ' line(s)', vim.log.levels.INFO)
      end)
    end)
  end)
end

-- ── Generate tests ────────────────────────────────────────────────────────────

local test_frameworks = {
  rust       = 'Rust built-in #[cfg(test)] with #[test] functions',
  go         = 'Go testing package with func TestXxx(t *testing.T)',
  python     = 'pytest',
  typescript = 'Jest / Vitest',
  javascript = 'Jest / Vitest',
  lua        = 'busted',
}

local function generate_tests(lines, ft)
  local framework = test_frameworks[ft] or ('appropriate test framework for ' .. ft)
  run(table.concat({
    'Generate comprehensive tests for this ' .. ft .. ' code.',
    'Use ' .. framework .. '.',
    'Cover: happy path, edge cases, error cases.',
    'Return ONLY the test code, no explanations.',
    '', table.concat(lines, '\n'),
  }, '\n'), 'generating tests…', function(result)
    vim.cmd 'vsplit'
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, '\n'))
    vim.bo[buf].filetype  = ft
    vim.bo[buf].buftype   = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_name(buf, 'claude-tests.' .. ft)
    vim.notify('claudespace: tests generated', vim.log.levels.INFO)
  end)
end

vim.keymap.set('n', '<leader>ct', function()
  generate_tests(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.bo.filetype)
end, { desc = 'Claude: generate tests (file)' })

vim.keymap.set('v', '<leader>ct', function()
  local s, e = vim.fn.line "'<", vim.fn.line "'>"
  generate_tests(vim.api.nvim_buf_get_lines(0, s - 1, e, false), vim.bo.filetype)
end, { desc = 'Claude: generate tests (selection)' })

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  vim.keymap.set('n', '<leader>cg', M.generate,
    { desc = 'Claude: generate at cursor', silent = true })
end

return M
