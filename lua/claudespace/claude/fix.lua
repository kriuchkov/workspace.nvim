-- Fix LSP diagnostics and explain code via Claude.
local util = require 'claudespace.claude.util'
local run  = util.run
local M    = {}

local function strip_fences(s)
  return (s:gsub('^```%w*\n', ''):gsub('\n```$', ''):gsub('^```\n', ''))
end

-- Fix LSP diagnostics at cursor (falls back to all diagnostics in the buffer).
function M.fix()
  local bufnr  = vim.api.nvim_get_current_buf()
  local row    = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

  local diags = vim.diagnostic.get(bufnr, { lnum = row })
  if #diags == 0 then diags = vim.diagnostic.get(bufnr) end
  if #diags == 0 then
    vim.notify('claudespace: no diagnostics', vim.log.levels.WARN); return
  end

  local ft    = vim.bo[bufnr].filetype
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local min_lnum, max_lnum = math.huge, 0
  local diag_msgs = {}
  for _, d in ipairs(diags) do
    if d.lnum < min_lnum then min_lnum = d.lnum end
    if d.lnum > max_lnum then max_lnum = d.lnum end
    diag_msgs[#diag_msgs + 1] = ('  line %d [%s]: %s'):format(
      d.lnum + 1, d.source or 'lsp', d.message)
  end

  -- Context: ±15 lines around affected range
  local ctx_s = math.max(0, min_lnum - 15)
  local ctx_e = math.min(#lines, max_lnum + 16)
  local ctx   = {}
  for i = ctx_s + 1, ctx_e do
    ctx[#ctx + 1] = ('%4d  %s'):format(i, lines[i])
  end

  run(table.concat({
    'Fix the ' .. ft .. ' errors in `' .. fname .. '`.',
    '', 'Errors:', table.concat(diag_msgs, '\n'), '',
    'Code (lines ' .. (ctx_s + 1) .. '–' .. ctx_e .. '):',
    '```' .. ft, table.concat(ctx, '\n'), '```', '',
    'Return ONLY the corrected code for the shown range.',
    'No explanations, no markdown fences, preserve indentation exactly.',
  }, '\n'), 'fixing…', function(result)
    local fixed = vim.split(strip_fences(result), '\n', { plain = true })

    local orig = {}
    for i = ctx_s + 1, ctx_e do orig[#orig + 1] = '- ' .. lines[i] end
    local new = {}
    for _, l in ipairs(fixed) do new[#new + 1] = '+ ' .. l end
    local preview = { '--- original', '+++ fixed', '' }
    vim.list_extend(preview, orig)
    vim.list_extend(preview, new)

    util.preview_float(preview, ' Claude Fix ', function()
      vim.api.nvim_buf_set_lines(bufnr, ctx_s, ctx_e, false, fixed)
      vim.notify('claudespace: fix applied', vim.log.levels.INFO)
    end)
  end)
end

local EXPLAIN_MODEL = 'claude-sonnet-4-6'

-- Gather LSP hover text for the current cursor position (non-blocking, 800ms timeout).
local function lsp_hover_text(bufnr)
  local ok, params = pcall(vim.lsp.util.make_position_params)
  if not ok then return nil end
  local results = vim.lsp.buf_request_sync(bufnr, 'textDocument/hover', params, 800)
  if not results then return nil end
  local parts = {}
  for _, res in pairs(results) do
    local c = res.result and res.result.contents
    if c then
      if type(c) == 'string' then
        parts[#parts + 1] = c
      elseif c.value then
        parts[#parts + 1] = c.value
      elseif vim.islist and vim.islist(c) then
        for _, item in ipairs(c) do
          parts[#parts + 1] = type(item) == 'string' and item or (item.value or '')
        end
      end
    end
  end
  local text = vim.trim(table.concat(parts, '\n'))
  return text ~= '' and text or nil
end

-- Navic breadcrumb scope (name-only, no icons).
local function navic_scope(bufnr)
  local ok, nav = pcall(require, 'claudespace.navic')
  if not ok or not nav.is_available(bufnr) then return nil end
  local data = nav.get_data(bufnr)
  if not data or #data == 0 then return nil end
  local names = {}
  for _, item in ipairs(data) do names[#names + 1] = item.name end
  return table.concat(names, ' > ')
end

local function explain(is_visual)
  local bufnr = vim.api.nvim_get_current_buf()
  local ft    = vim.bo[bufnr].filetype
  local lines
  if is_visual then
    local s, e = vim.fn.line "'<", vim.fn.line "'>"
    lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  else
    local row   = vim.api.nvim_win_get_cursor(0)[1]
    local total = vim.api.nvim_buf_line_count(bufnr)
    lines = vim.api.nvim_buf_get_lines(bufnr, math.max(0, row - 10), math.min(total, row + 10), false)
  end

  local hover = lsp_hover_text(bufnr)
  local scope = navic_scope(bufnr)

  local parts = {
    'Explain this ' .. ft .. ' code concisely in plain prose.',
    'Cover: what it does, key design decisions, any gotchas.',
  }
  if scope then parts[#parts + 1] = 'Scope: ' .. scope end
  if hover then
    parts[#parts + 1] = ''
    parts[#parts + 1] = 'LSP type info:'
    parts[#parts + 1] = '```'
    parts[#parts + 1] = hover
    parts[#parts + 1] = '```'
  end
  parts[#parts + 1] = ''
  parts[#parts + 1] = '```' .. ft
  parts[#parts + 1] = table.concat(lines, '\n')
  parts[#parts + 1] = '```'

  util.stream_float(table.concat(parts, '\n'), ' Claude Explain ', { model = EXPLAIN_MODEL })
end

function M.explain_normal() explain(false) end
function M.explain_visual() explain(true)  end

function M.setup()
  local map = vim.keymap.set
  map('n', '<leader>cf', M.fix,           { desc = 'Claude: fix diagnostic', silent = true })
  map('n', '<leader>ck', M.explain_normal, { desc = 'Claude: explain code',  silent = true })
  map('v', '<leader>ck', M.explain_visual, { desc = 'Claude: explain code',  silent = true })
end

return M
