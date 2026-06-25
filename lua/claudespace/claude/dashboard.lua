-- Dashboard shown on startup (no file argument)
-- Shows recent files, Claude sessions, and quick actions

local M = {}

local function center(str, width)
  local pad = math.floor((width - vim.fn.strdisplaywidth(str)) / 2)
  return string.rep(' ', math.max(pad, 0)) .. str
end

local function render()
  local width = math.min(vim.o.columns, 80)
  local lines = {}
  local highlights = {}  -- { line, col_start, col_end, hl_group }
  local actions = {}     -- { line_index -> function }

  local function hl(line_idx, text, group)
    local col = #lines[line_idx] - #text
    table.insert(highlights, { line_idx - 1, col, col + #text, group })
  end

  local function blank() table.insert(lines, '') end

  -- Header
  blank()
  blank()
  table.insert(lines, center('claudespace.nvim', width))
  hl(#lines, 'claudespace.nvim', 'Title')
  table.insert(lines, center('Neovim + Claude AI', width))
  hl(#lines, 'Neovim + Claude AI', 'Comment')
  blank()
  blank()

  -- Active Claude sessions
  local ok, state = pcall(require, 'claude-multi.state')
  local sessions = ok and state.get_sessions() or {}
  if #sessions > 0 then
    table.insert(lines, center('─── Active Sessions ───', width))
    hl(#lines, '─── Active Sessions ───', 'Special')
    blank()
    for _, s in ipairs(sessions) do
      local label = '  ⚡ ' .. (s.name or 'Chat')
      if s.branch then label = label .. '  [' .. s.branch .. ']' end
      table.insert(lines, center(label, width))
      local ln = #lines
      hl(ln, label:gsub('^%s+', ''), 'Identifier')
      local captured = s
      actions[ln] = function()
        state.set_active_session_id(captured.id)
        require('claude-multi.terminal').open_in_current_window(captured)
      end
    end
    blank()
    blank()
  end

  -- Quick actions
  table.insert(lines, center('─── Quick Actions ───', width))
  hl(#lines, '─── Quick Actions ───', 'Special')
  blank()

  local quick = {
    { key = '<leader>cn', label = 'New Claude session',     fn = function() require('claude-multi').new_session_here() end },
    { key = '<leader>ff', label = 'Find file',              fn = function() vim.cmd 'Telescope find_files' end },
    { key = '<leader>fg', label = 'Live grep',              fn = function() vim.cmd 'Telescope live_grep' end },
    { key = '<leader>fr', label = 'Recent files',           fn = function() vim.cmd 'Telescope oldfiles' end },
    { key = '\\',         label = 'File tree',              fn = function() vim.cmd 'Neotree reveal' end },
  }

  for _, item in ipairs(quick) do
    local line = center(string.format('%-14s  %s', item.key, item.label), width)
    table.insert(lines, line)
    local ln = #lines
    hl(ln, item.key, 'Keyword')
    actions[ln] = item.fn
  end

  blank()
  blank()

  -- Recent files
  local recent = vim.v.oldfiles or {}
  if #recent > 0 then
    table.insert(lines, center('─── Recent Files ───', width))
    hl(#lines, '─── Recent Files ───', 'Special')
    blank()
    local count = 0
    for _, f in ipairs(recent) do
      if vim.fn.filereadable(f) == 1 and count < 8 then
        count = count + 1
        local short = vim.fn.fnamemodify(f, ':~:.')
        local label = '  ' .. short
        table.insert(lines, center(label, width))
        local ln = #lines
        hl(ln, short, 'String')
        local captured = f
        actions[ln] = function() vim.cmd('edit ' .. vim.fn.fnameescape(captured)) end
      end
    end
  end

  blank()
  return lines, highlights, actions
end

function M.open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'claudespace-dashboard'
  vim.api.nvim_buf_set_name(buf, 'claudespace')

  local lines, highlights, actions = render()

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace 'claudespace_dashboard'
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = 'no'
  vim.wo.cursorline = true

  -- Position cursor on first action line
  local first_action = nil
  for ln in pairs(actions) do
    if not first_action or ln < first_action then first_action = ln end
  end
  if first_action then
    vim.api.nvim_win_set_cursor(0, { first_action, 0 })
  end

  -- <CR> triggers the action for the current line
  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local fn = actions[row]
    if fn then fn() end
  end, { buffer = buf, nowait = true })

  -- Quick keys
  vim.keymap.set('n', 'q', '<cmd>bdelete<CR>', { buffer = buf })
  vim.keymap.set('n', 'e', '<cmd>enew<CR>', { buffer = buf })
end

return M
