local map = vim.keymap.set

-- ── nvim-dap ──────────────────────────────────────────────────────────────────

vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/nvim-neotest/nvim-nio',   -- dap-ui dependency
  'https://github.com/rcarriga/nvim-dap-ui',
}

local ok_dap, dap = pcall(require, 'dap')
if not ok_dap then return end

-- dap-ui
local ok_ui, dapui = pcall(require, 'dapui')
if ok_ui then
  dapui.setup {
    icons = { expanded = '▾', collapsed = '▸', current_frame = '▸' },
    layouts = {
      {
        elements = {
          { id = 'scopes',      size = 0.40 },
          { id = 'breakpoints', size = 0.15 },
          { id = 'stacks',      size = 0.25 },
          { id = 'watches',     size = 0.20 },
        },
        size = 40, position = 'left',
      },
      {
        elements = {
          { id = 'repl',    size = 0.5 },
          { id = 'console', size = 0.5 },
        },
        size = 12, position = 'bottom',
      },
    },
  }
  dap.listeners.after.event_initialized['dapui_config'] = function() dapui.open() end
  dap.listeners.before.event_terminated['dapui_config'] = function() dapui.close() end
  dap.listeners.before.event_exited['dapui_config']     = function() dapui.close() end
end

-- Inline virtual text
require('claudespace.dap.virtual_text').setup {
  enabled       = true,
  commented     = false,
  virt_text_pos = 'eol',
  all_frames    = false,
  highlight_changed_variables = true,
}

-- ── Adapter configs ───────────────────────────────────────────────────────────

-- Go
require('claudespace.dap.go').setup()

-- Rust: codelldb via mason
local codelldb_bin = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb'
dap.adapters.codelldb = {
  type = 'server', port = '${port}',
  executable = { command = codelldb_bin, args = { '--port', '${port}' } },
}
dap.configurations.rust = {
  {
    type    = 'codelldb',
    request = 'launch',
    name    = 'Debug binary',
    program = function()
      return vim.fn.input('Binary path: ', vim.fn.getcwd() .. '/target/debug/', 'file')
    end,
    cwd          = '${workspaceFolder}',
    stopOnEntry  = false,
  },
}

-- Auto-install DAP adapters
vim.schedule(function()
  local ok_mr, mr = pcall(require, 'mason-registry')
  if not ok_mr then return end
  mr.refresh(function()
    for _, name in ipairs { 'delve', 'codelldb' } do
      local ok_pkg, pkg = pcall(mr.get_package, name)
      if ok_pkg and not pkg:is_installed() then
        vim.notify('DAP: installing ' .. name .. '…', vim.log.levels.INFO)
        pkg:install()
      end
    end
  end)
end)

-- ── Keymaps ───────────────────────────────────────────────────────────────────
-- F-keys match VS Code defaults; <leader>d prefix for discoverability.

map('n', '<F5>',        dap.continue,          { desc = 'Debug: continue',        silent = true })
map('n', '<F10>',       dap.step_over,         { desc = 'Debug: step over',       silent = true })
map('n', '<F11>',       dap.step_into,         { desc = 'Debug: step into',       silent = true })
map('n', '<F12>',       dap.step_out,          { desc = 'Debug: step out',        silent = true })
map('n', '<leader>dc',  dap.continue,          { desc = 'Debug: continue',        silent = true })
map('n', '<leader>do',  dap.step_over,         { desc = 'Debug: step over',       silent = true })
map('n', '<leader>di',  dap.step_into,         { desc = 'Debug: step into',       silent = true })
map('n', '<leader>dO',  dap.step_out,          { desc = 'Debug: step out',        silent = true })
map('n', '<leader>db',  dap.toggle_breakpoint, { desc = 'Debug: breakpoint',      silent = true })
map('n', '<leader>dB',  function()
  dap.set_breakpoint(vim.fn.input 'Condition: ')
end,                                            { desc = 'Debug: cond breakpoint', silent = true })
map('n', '<leader>dl',  dap.run_last,          { desc = 'Debug: run last',        silent = true })
map('n', '<leader>dr',  dap.repl.open,         { desc = 'Debug: REPL',            silent = true })
map('n', '<leader>dq',  dap.terminate,         { desc = 'Debug: terminate',       silent = true })
map('n', '<leader>dx',  dap.clear_breakpoints, { desc = 'Debug: clear all bp',    silent = true })
map('n', '<leader>du',  function()
  if ok_ui then dapui.toggle() end
end,                                            { desc = 'Debug: toggle UI',       silent = true })
map({ 'n', 'v' }, '<leader>de', function()
  if ok_ui then dapui.eval() end
end,                                            { desc = 'Debug: eval expr',       silent = true })

-- Breakpoint sign styling
vim.fn.sign_define('DapBreakpoint',          { text = '●', texthl = 'DiagnosticError' })
vim.fn.sign_define('DapBreakpointCondition', { text = '◆', texthl = 'DiagnosticWarn' })
vim.fn.sign_define('DapBreakpointRejected',  { text = '○', texthl = 'DiagnosticHint' })
vim.fn.sign_define('DapStopped',             { text = '▸', texthl = 'DiagnosticOk', linehl = 'CursorLine' })
vim.fn.sign_define('DapLogPoint',            { text = '◉', texthl = 'DiagnosticInfo' })

-- ── neotest ───────────────────────────────────────────────────────────────────

vim.pack.add {
  'https://github.com/nvim-neotest/neotest',
}

if pcall(require, 'neotest') then
  local adapters = {
    require('claudespace.neotest_go') { experimental = { test_table = true } },
  }

  require('neotest').setup {
    adapters = adapters,
    output   = { open_on_run = false },
    status   = { virtual_text = true, signs = true },
    icons    = {
      passed   = '✓',
      running  = '◌',
      failed   = '✗',
      skipped  = '○',
      unknown  = '?',
      running_animated = { '◐', '◓', '◑', '◒' },
    },
    summary = { open = 'botright vsplit | vertical resize 40' },
    quickfix = { open = false },
  }

  local nt = require 'neotest'

  map('n', '<leader>rr', function() nt.run.run() end,
    { desc = 'Test: run nearest',   silent = true })
  map('n', '<leader>rR', function() nt.run.run(vim.fn.expand '%') end,
    { desc = 'Test: run file',      silent = true })
  map('n', '<leader>rs', function() nt.summary.toggle() end,
    { desc = 'Test: summary panel', silent = true })
  map('n', '<leader>ro', function() nt.output.open { enter = true } end,
    { desc = 'Test: output',        silent = true })
  map('n', '<leader>rp', function() nt.output_panel.toggle() end,
    { desc = 'Test: output panel',  silent = true })
  map('n', '<leader>rd', function() nt.run.run { strategy = 'dap' } end,
    { desc = 'Test: debug nearest', silent = true })
  map('n', ']r', function() nt.jump.next { status = 'failed' } end,
    { desc = 'Next failed test',    silent = true })
  map('n', '[r', function() nt.jump.prev { status = 'failed' } end,
    { desc = 'Prev failed test',    silent = true })
end
