-- Shell command assistant, documentation generator, multi-file composer.
local util = require 'claudespace.claude.util'
local run  = util.run
local M    = {}

local function lsp_hover(bufnr)
  local ok, params = pcall(vim.lsp.util.make_position_params)
  if not ok then return nil end
  local res = vim.lsp.buf_request_sync(bufnr, 'textDocument/hover', params, 800)
  if not res then return nil end
  for _, r in pairs(res) do
    local c = r.result and r.result.contents
    if c then
      local v = type(c) == 'string' and c or c.value
      if v and vim.trim(v) ~= '' then return vim.trim(v) end
    end
  end
end

-- ── Shell command assistant ───────────────────────────────────────────────────

function M.shell()
  vim.ui.input({ prompt = '$ task: ' }, function(task)
    if not task or task == '' then return end
    run(table.concat({
      'Generate a shell command for: ' .. task,
      'Working directory: ' .. vim.fn.getcwd(),
      'Shell: ' .. (vim.o.shell or 'bash'),
      'Return ONLY the raw command. No explanation, no markdown fences.',
    }, '\n'), 'generating command…', function(cmd)
      cmd = vim.trim(cmd):gsub('^`+', ''):gsub('`+$', '')
      util.preview_float({ '$ ' .. cmd }, ' Shell Command ', function()
        vim.cmd 'botright 12split'
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(0, buf)
        vim.fn.termopen(cmd, { cwd = vim.fn.getcwd() })
        vim.cmd 'startinsert'
      end)
    end, { model = 'claude-haiku-4-5-20251001' })
  end)
end

-- ── Documentation generator ──────────────────────────────────────────────────

local DOC_STYLES = {
  go         = 'Go doc comment (// FuncName …)',
  rust       = 'Rust doc comment (/// with # Arguments, # Returns, # Errors sections)',
  typescript = 'JSDoc (/** @param {type} name @returns {type} */)',
  javascript = 'JSDoc (/** @param {type} name @returns {type} */)',
  python     = 'Google-style docstring (Args: Returns: Raises:)',
  lua        = 'LuaDoc (--- @param name type desc  --- @return type)',
}

function M.docs()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft    = vim.bo[bufnr].filetype
  local row   = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, math.max(0, row - 3), math.min(total, row + 30), false)
  local hover = lsp_hover(bufnr)
  local style = DOC_STYLES[ft] or ('appropriate doc comment for ' .. ft)

  local parts = {
    'Write a ' .. style .. ' for the function/type below.',
    'Be concise. Cover: what it does, params, return value, errors if relevant.',
    'Return ONLY the doc comment — no code, no markdown fences.',
  }
  if hover then parts[#parts + 1] = 'LSP signature: ' .. hover end
  parts[#parts + 1] = ''
  parts[#parts + 1] = '```' .. ft
  parts[#parts + 1] = table.concat(lines, '\n')
  parts[#parts + 1] = '```'

  run(table.concat(parts, '\n'), 'writing docs…', function(result)
    local doc = vim.split(result:gsub('^```%w*\n?', ''):gsub('\n?```$', ''), '\n')
    util.preview_float(doc, ' Claude Docs ', function()
      vim.api.nvim_buf_set_lines(bufnr, row - 1, row - 1, false, doc)
      vim.notify('claudespace: docs inserted', vim.log.levels.INFO)
    end)
  end, { model = 'claude-sonnet-4-6' })
end

-- ── Multi-file composer ───────────────────────────────────────────────────────

local FILE_START = '%-%-%-FILE:([^\n]+)%-%-%-'
local FILE_END   = '%-%-%-ENDFILE%-%-%-'

local function parse_file_blocks(response)
  local files = {}
  for path, content in response:gmatch(FILE_START .. '\n(.-)\n' .. FILE_END) do
    files[vim.trim(path)] = vim.split(vim.trim(content), '\n')
  end
  return files
end

local function open_bufs()
  local result = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == ''
       and vim.api.nvim_buf_get_name(b) ~= '' then
      result[#result + 1] = {
        bufnr = b,
        path  = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':~:.'),
      }
    end
  end
  return result
end

-- Float with y=apply, n=skip, q=cancel. Returns nothing; calls cb(action).
local function composer_float(diff_lines, title, cb)
  local display = vim.list_extend(vim.deepcopy(diff_lines),
    { '', '  y  apply    n  skip    q  cancel all' })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
  vim.bo[buf].modifiable = false

  local width  = math.min(math.floor(vim.o.columns * 0.80), 120)
  local height = math.min(#display + 2, math.floor(vim.o.lines * 0.7))
  local win    = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines  - height) / 2),
    title = title, title_pos = 'center',
  })
  vim.wo[win].wrap = false

  -- Highlight diff lines
  local hl = vim.api.nvim_buf_add_highlight
  for i, l in ipairs(diff_lines) do
    if l:sub(1, 1) == '+' then hl(buf, -1, 'DiffAdd',    i - 1, 0, -1) end
    if l:sub(1, 1) == '-' then hl(buf, -1, 'DiffDelete', i - 1, 0, -1) end
    if l:sub(1, 2) == '@@' then hl(buf, -1, 'DiffChange', i - 1, 0, -1) end
  end

  local function close() pcall(vim.api.nvim_win_close, win, true) end
  vim.keymap.set('n', 'y', function() close(); cb('apply') end,  { buffer = buf, nowait = true })
  vim.keymap.set('n', 'n', function() close(); cb('skip')  end,  { buffer = buf, nowait = true })
  vim.keymap.set('n', 'q', function() close(); cb('cancel') end, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', function() close(); cb('cancel') end, { buffer = buf, nowait = true })
end

local function apply_changes(changes)
  local paths   = vim.tbl_keys(changes)
  local idx     = 1
  local cwd     = vim.fn.getcwd()

  local function next_file()
    if idx > #paths then
      vim.notify('claudespace: composer done', vim.log.levels.INFO); return
    end
    local rel      = paths[idx]
    local new_lines = changes[rel]
    local abs      = cwd .. '/' .. rel
    local bufnr    = vim.fn.bufnr(abs)

    local old_lines = {}
    if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
      old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    elseif vim.fn.filereadable(abs) == 1 then
      old_lines = vim.fn.readfile(abs)
    end

    -- Unified diff via vim.diff
    local old_str  = table.concat(old_lines, '\n') .. '\n'
    local new_str  = table.concat(new_lines, '\n') .. '\n'
    local diff_str = vim.diff(old_str, new_str, {
      result_type = 'unified',
      ctxlen      = 3,
      algorithm   = 'myers',
    })
    local diff_lines = diff_str and vim.split(diff_str, '\n') or new_lines

    local title = (' %d/%d  %s '):format(idx, #paths, rel)
    composer_float(diff_lines, title, function(action)
      if action == 'cancel' then return end
      if action == 'apply' then
        if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        else
          vim.fn.writefile(new_lines, abs)
        end
        vim.notify('Applied: ' .. rel, vim.log.levels.INFO)
      end
      idx = idx + 1
      vim.schedule(next_file)
    end)
  end

  next_file()
end

function M.compose()
  local bufs = open_bufs()
  if #bufs == 0 then
    vim.notify('claudespace: no open file buffers', vim.log.levels.WARN); return
  end

  vim.ui.input({ prompt = 'Composer: ' }, function(task)
    if not task or task == '' then return end

    local parts = {
      'Edit the project files to accomplish this task: ' .. task,
      '',
      'For each file you change, output EXACTLY this format (no extra text outside blocks):',
      '---FILE: relative/path/to/file ---',
      '<complete new file content>',
      '---ENDFILE---',
      '',
      'Current files:',
    }
    for _, b in ipairs(bufs) do
      local lines = vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false)
      if #lines <= 500 then
        parts[#parts + 1] = ''
        parts[#parts + 1] = '---FILE: ' .. b.path .. ' ---'
        parts[#parts + 1] = table.concat(lines, '\n')
        parts[#parts + 1] = '---ENDFILE---'
      end
    end

    run(table.concat(parts, '\n'), 'composing…', function(response)
      local changes = parse_file_blocks(response)
      if vim.tbl_isempty(changes) then
        util.read_float(vim.split(response, '\n'), ' Composer Response ', 'markdown')
        return
      end
      apply_changes(changes)
    end, { model = 'claude-sonnet-4-6' })
  end)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  local map = vim.keymap.set
  map('n', '<leader>c!', M.shell,   { desc = 'Claude: shell command',      silent = true })
  map('n', '<leader>co', M.docs,    { desc = 'Claude: generate docs',      silent = true })
  map('n', '<leader>cE', M.compose, { desc = 'Claude: multi-file compose', silent = true })
end

return M
