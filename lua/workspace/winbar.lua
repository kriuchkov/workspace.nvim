-- Winbar: path breadcrumb (left) + current symbol via nvim-navic (right).
local M = {}

local api = vim.api

function M.render()
  local buf  = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(buf)

  -- Workspace / active-repo segment (left, multi-repo only)
  local ws_part = ''
  local ok_repos, repos = pcall(require, 'workspace.repos')
  if ok_repos and repos.is_multi() then
    local m = repos.active()
    if m then
      local st     = repos.status(m)
      local branch = (st and st.branch ~= '') and ('%#CSWinbarWsBranch# ' .. st.branch) or ''
      local dirty  = (st and st.dirty > 0) and ('%#CSWinbarWsDirty# ●' .. st.dirty) or ''
      ws_part = '%#CSWinbarWs# ' .. repos.name() .. ' › ' .. m.label .. branch .. dirty .. '%#CSWinbarDir#  '
    end
  end

  -- Path segment (left)
  local path_part
  if name == '' then
    path_part = '%#CSWinbarFile# [No Name]'
  else
    local rel  = vim.fn.fnamemodify(name, ':~:.')
    local dir  = vim.fn.fnamemodify(rel, ':h')
    local file = vim.fn.fnamemodify(rel, ':t')
    if dir == '.' then
      path_part = '%#CSWinbarFile# ' .. file
    else
      path_part = '%#CSWinbarDir# ' .. dir .. '/%#CSWinbarFile#' .. file
    end
  end

  -- Clickable button: list this file's functions & structures (also <leader>fs)
  local sym_btn = name ~= ''
    and ('%@v:lua.CSSymbolsPick@%#CSWinbarSym#  󰊕 %X%#CSWinbarFile#') or ''

  -- Symbol context (right, via nvim-navic)
  local navic_part = ''
  local ok_nav, navic = pcall(require, 'nvim-navic')
  if ok_nav and navic.is_available(buf) then
    local loc = navic.get_location({}, buf)
    if loc and loc ~= '' then
      navic_part = '%=%#CSWinbarNav# ' .. loc .. ' '
    end
  end

  return ws_part .. path_part .. sym_btn .. navic_part
end

local function setup_highlights()
  local hi = api.nvim_set_hl
  local c  = require('workspace.theme').colors()
  hi(0, 'CSWinbarDir',  { fg = c.fg_dim, bg = c.bg })
  hi(0, 'CSWinbarFile', { fg = c.fg, bg = c.bg, bold = true })
  hi(0, 'CSWinbarSym',  { fg = c.cyan, bg = c.bg })
  hi(0, 'CSWinbarNav',  { fg = c.blue, bg = c.bg })
  hi(0, 'CSWinbarWs',       { fg = c.cyan, bg = c.bg, bold = true })
  hi(0, 'CSWinbarWsBranch', { fg = c.green, bg = c.bg })
  hi(0, 'CSWinbarWsDirty',  { fg = c.warn, bg = c.bg })
end

local SKIP_FT = {
  cs_filetree = true, cs_dirdash = true, cs_outline = true,
  cs_home = true, cs_notify = true, cs_gitui = true, cs_mdtoc = true,
  TelescopePrompt = true, lazy = true, mason = true,
  help = true, trouble = true, dap_repl = true,
  ['dapui_watches'] = true, ['dapui_stacks'] = true,
  ['dapui_breakpoints'] = true, ['dapui_scopes'] = true,
}
local SKIP_BT = { terminal = true, nofile = true, prompt = true, quickfix = true }

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = setup_highlights })
  api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    callback = function()
      -- Panels (gitdiff labels, diag/todo hints) own their winbar: the w: flag
      -- keeps it from being wiped by the nofile rule below on every re-entry.
      if vim.w.cs_winbar then return end
      if SKIP_FT[vim.bo.filetype] or SKIP_BT[vim.bo.buftype] then
        vim.wo.winbar = ''
      else
        vim.wo.winbar = '%!v:lua.require("workspace.winbar").render()'
      end
    end,
  })
end

return M
