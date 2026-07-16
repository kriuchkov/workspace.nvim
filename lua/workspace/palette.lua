-- Command palette: filterable list of all workspace actions.
-- <leader>P opens it; uses vim.ui.select so telescope enhances it automatically.
local M = {}

local ACTIONS = {
  -- File
  { group = 'File',      label = 'Find files',              keys = '<leader>ff', action = function() vim.cmd 'Telescope find_files' end },
  { group = 'File',      label = 'Live grep',               keys = '<leader>fg', action = function() vim.cmd 'Telescope live_grep' end },
  { group = 'File',      label = 'Live grep (glob scoped)',  keys = '<leader>fG', action = function() require('workspace.search').live_grep_glob() end },
  { group = 'File',      label = 'Live grep (active repo)',  keys = '<leader>fR', action = function() require('workspace.search').live_grep_repo() end },
  { group = 'File',      label = 'Recent files',            keys = '<leader>fr', action = function() vim.cmd 'Telescope oldfiles' end },
  { group = 'File',      label = 'Buffers',                 keys = '<leader>fb', action = function() vim.cmd 'Telescope buffers' end },
  { group = 'File',      label = 'Search/replace (word)',   keys = '<leader>sr', action = function() require('grug-far').open { prefills = { search = vim.fn.expand '<cword>' } } end },
  { group = 'File',      label = 'Search/replace',          keys = '<leader>sR', action = function() require('grug-far').open() end },
  -- Workspace
  { group = 'Workspace', label = 'Switch workspace',        keys = '<leader>ws', action = function() require('workspace.workspace').switch() end },
  { group = 'Workspace', label = 'Save workspace',          keys = '<leader>wS', action = function() require('workspace.workspace').save() end },
  { group = 'Workspace', label = 'List workspaces',         keys = '<leader>wl', action = function() require('workspace.workspace').show_list() end },
  { group = 'Workspace', label = 'Home screen',             keys = '<leader>wh', action = function() require('workspace.home').open() end },
  { group = 'Workspace', label = 'Create from template',    keys = '',           action = function() require('workspace.templates').pick() end },
  -- Panels
  { group = 'Panel',     label = 'File tree: toggle',       keys = '<leader>e',  action = function() require('workspace.filetree').toggle() end },
  { group = 'Panel',     label = 'Outline: toggle',         keys = '<leader>xo', action = function() require('workspace.outline').toggle() end },
  { group = 'Panel',     label = 'Marks',                   keys = '<leader>M',  action = function() require('workspace.marks').show() end },
  { group = 'Panel',     label = 'Notifications',           keys = '<leader>N',  action = function() require('workspace.notify').open() end },
  { group = 'Panel',     label = 'Diagnostics',             keys = '<leader>xx', action = function() vim.cmd 'Trouble diagnostics toggle' end },
  { group = 'Panel',     label = 'Symbols panel',           keys = '<leader>xs', action = function() vim.cmd 'Trouble symbols toggle focus=false' end },
  -- Git
  { group = 'Git',       label = 'Git: staging panel',      keys = '<leader>gG', action = function() require('workspace.git_ui').open() end },
  { group = 'Git',       label = 'Git: lazygit',            keys = '<leader>gg', action = function() vim.cmd 'LazyGit' end },
  { group = 'Git',       label = 'Git: diff current file',   keys = '<leader>gd', action = function() vim.cmd 'WSDiff' end },
  { group = 'Git',       label = 'Git: file history',        keys = '<leader>gh', action = function() vim.cmd 'WSFileHistory' end },
  { group = 'Git',       label = 'Git: repo log',            keys = '<leader>gl', action = function() vim.cmd 'WSLog' end },
  -- Test / Run
  { group = 'Test',      label = 'Test: run nearest',       keys = '<leader>rr', action = function() require('neotest').run.run() end },
  { group = 'Test',      label = 'Test: run file',          keys = '<leader>rR', action = function() require('neotest').run.run(vim.fn.expand '%') end },
  { group = 'Test',      label = 'Test: summary panel',     keys = '<leader>rs', action = function() require('neotest').summary.toggle() end },
  { group = 'Test',      label = 'Test: debug nearest',     keys = '<leader>rd', action = function() require('neotest').run.run { strategy = 'dap' } end },
  { group = 'Task',      label = 'Tasks: pick',             keys = '<leader>rp', action = function() require('workspace.tasks').pick() end },
  -- Debug
  { group = 'Debug',     label = 'Debug: continue (F5)',    keys = '<F5>',       action = function() require('dap').continue() end },
  { group = 'Debug',     label = 'Debug: breakpoint',       keys = '<leader>db', action = function() require('dap').toggle_breakpoint() end },
  { group = 'Debug',     label = 'Debug: toggle UI',        keys = '<leader>du', action = function() require('dapui').toggle() end },
  { group = 'Debug',     label = 'Debug: terminate',        keys = '<leader>dq', action = function() require('dap').terminate() end },
  -- LSP
  { group = 'LSP',       label = 'Rename symbol',           keys = '<leader>ln', action = function() vim.lsp.buf.rename() end },
  { group = 'LSP',       label = 'Code action',             keys = '<leader>la', action = function() vim.lsp.buf.code_action() end },
  { group = 'LSP',       label = 'Format buffer',           keys = '<leader>lf', action = function() vim.lsp.buf.format { async = true } end },
}

function M.register(action)
  table.insert(ACTIONS, action)
end

function M.open()
  vim.ui.select(ACTIONS, {
    prompt = 'Command palette',
    format_item = function(a)
      local pad  = string.rep(' ', math.max(1, 26 - #a.label))
      local grp  = string.format('[%-9s]', a.group)
      local keys = a.keys ~= '' and ('  ' .. a.keys) or ''
      return a.label .. pad .. grp .. keys
    end,
  }, function(choice)
    if choice then choice.action() end
  end)
end

function M.setup()
  vim.keymap.set('n', '<leader>P', M.open, { desc = 'Command palette', silent = true })
end

return M
