-- Command palette: filterable list of all claudespace actions.
-- <leader>P opens it; uses vim.ui.select so which-key/telescope enhance it.
local M = {}

-- Static action registry
local ACTIONS = {
  -- Navigation
  { group = 'File',      label = 'Find files',           keys = '<leader>ff', action = function() vim.cmd 'Telescope find_files' end },
  { group = 'File',      label = 'Live grep',            keys = '<leader>fg', action = function() vim.cmd 'Telescope live_grep' end },
  { group = 'File',      label = 'Recent files',         keys = '<leader>fr', action = function() vim.cmd 'Telescope oldfiles' end },
  { group = 'File',      label = 'Buffers',              keys = '<leader>fb', action = function() vim.cmd 'Telescope buffers' end },
  -- Workspace
  { group = 'Workspace', label = 'Switch workspace',     keys = '<leader>ws', action = function() require('claudespace.workspace').switch() end },
  { group = 'Workspace', label = 'Save workspace',       keys = '<leader>ww', action = function() require('claudespace.workspace').save() end },
  { group = 'Workspace', label = 'List workspaces',      keys = '<leader>wl', action = function() require('claudespace.workspace').show_list() end },
  { group = 'Workspace', label = 'Home screen',          keys = '<leader>wh', action = function() require('claudespace.home').open() end },
  { group = 'Workspace', label = 'Create from template', keys = '',           action = function() require('claudespace.templates').pick() end },
  -- Panels
  { group = 'Panel',     label = 'File tree: toggle',    keys = '<leader>e',  action = function() require('claudespace.filetree').toggle() end },
  { group = 'Panel',     label = 'Outline: toggle',      keys = '<leader>xo', action = function() require('claudespace.outline').toggle() end },
  { group = 'Panel',     label = 'Marks: show',          keys = '<leader>M',  action = function() require('claudespace.marks').show() end },
  { group = 'Panel',     label = 'Notifications',        keys = '<leader>N',  action = function() require('claudespace.notify').open() end },
  -- Git
  { group = 'Git',       label = 'Git status',           keys = '<leader>gs', action = function() require('claudespace.git_ui').open() end },
  { group = 'Git',       label = 'Git log (Telescope)',  keys = '',           action = function() vim.cmd 'Telescope git_commits' end },
  -- Tasks
  { group = 'Task',      label = 'Pick task',            keys = '<leader>rr', action = function() require('claudespace.tasks').pick() end },
  { group = 'Task',      label = 'Test runner UI',       keys = '<leader>ru', action = function() require('claudespace.test_ui').run() end },
  -- Diagnostics
  { group = 'Diag',      label = 'Diagnostics toggle',   keys = '<leader>xx', action = function() vim.cmd 'Trouble diagnostics toggle' end },
  { group = 'Diag',      label = 'Buffer diagnostics',   keys = '<leader>xb', action = function() vim.cmd 'Trouble diagnostics toggle filter.buf=0' end },
  -- Claude
  { group = 'Claude',    label = 'New Claude session',   keys = '<leader>cn', action = function() vim.cmd 'ClaudeNew' end },
  { group = 'Claude',    label = 'Inject workspace context', keys = '<leader>ci', action = function() require('claudespace.claude.context').inject() end },
}

-- Allow other modules to register actions
function M.register(action)
  table.insert(ACTIONS, action)
end

function M.open()
  local items = {}
  for _, a in ipairs(ACTIONS) do
    table.insert(items, a)
  end

  vim.ui.select(items, {
    prompt = 'Command palette',
    format_item = function(a)
      local pad = string.rep(' ', math.max(1, 24 - #a.label))
      local grp = string.format('[%-9s]', a.group)
      local keys = a.keys ~= '' and ('  ' .. a.keys) or ''
      return a.label .. pad .. grp .. keys
    end,
  }, function(choice)
    if choice then choice.action() end
  end)
end

function M.setup()
  vim.keymap.set('n', '<leader>P', M.open, { desc = 'Command palette' })
end

return M
