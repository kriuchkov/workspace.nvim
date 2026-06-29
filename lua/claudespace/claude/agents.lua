-- Agent panel: shows available agents from AGENTS.md (project + global)
-- and currently running Claude sessions

local function parse_agents_md(path)
  if vim.fn.filereadable(path) == 0 then return {} end
  local agents = {}
  local lines = vim.fn.readfile(path)
  local current = nil

  for _, line in ipairs(lines) do
    local name = line:match('^##%s+(.+)$')
    if name then
      current = { name = name, description = '' }
      table.insert(agents, current)
    elseif current and line:match('^[^#]') and line ~= '' then
      current.description = current.description == '' and line or current.description
    end
  end
  return agents
end

local function open_agents_panel()
  local project_agents = parse_agents_md(vim.fn.getcwd() .. '/AGENTS.md')
  local global_agents = parse_agents_md(vim.fn.expand '~/.claude/AGENTS.md')

  local lines = {}
  local entries = {}

  local function add_section(title, agents, source)
    if #agents == 0 then return end
    table.insert(lines, '# ' .. title)
    table.insert(lines, '')
    for _, a in ipairs(agents) do
      local idx = #lines + 1
      table.insert(lines, '  ' .. a.name)
      if a.description ~= '' then
        table.insert(lines, '  ' .. a.description)
      end
      entries[idx] = { name = a.name, source = source }
      table.insert(lines, '')
    end
  end

  -- Active Claude sessions
  local cs = require('claudespace.claude.sessions')
  local active_sessions = cs.list()
  if #active_sessions > 0 then
    table.insert(lines, '# Active Sessions')
    table.insert(lines, '')
    for _, s in ipairs(active_sessions) do
      table.insert(lines, '  ⚡ ' .. (s.name or 'Chat'))
      entries[#lines] = { session_id = s.id }
      table.insert(lines, '')
    end
  end

  add_section('Project Agents', project_agents, 'project')
  add_section('Global Agents', global_agents, 'global')

  if #lines == 0 then
    lines = { 'No AGENTS.md found.', '', 'Create one at ./AGENTS.md or ~/.claude/AGENTS.md' }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = 'nofile'

  local width = 60
  local height = math.min(#lines + 2, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 3),
    style = 'minimal',
    border = 'rounded',
    title = ' Claude Agents ',
    title_pos = 'center',
  })

  local function close() pcall(vim.api.nvim_win_close, win, true) end

  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local entry = entries[row]
    if not entry then return end
    close()
    local cs = require('claudespace.claude.sessions')
    if entry.session_id then
      cs.open(entry.session_id)
    else
      cs.new()
      if entry.name then
        vim.defer_fn(function()
          vim.notify('claudespace: type  /agent ' .. entry.name .. '  in Claude to activate', vim.log.levels.INFO)
        end, 500)
      end
    end
  end, { buffer = buf })

  vim.keymap.set('n', 'q', close, { buffer = buf })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf })
end

vim.keymap.set('n', '<leader>ca', open_agents_panel, { desc = 'Claude: agents panel' })
