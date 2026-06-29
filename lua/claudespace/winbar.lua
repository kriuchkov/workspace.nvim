-- Winbar: path breadcrumb (left) + current symbol via nvim-navic (right).
local M = {}

local api = vim.api

function M.render()
  local buf  = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(buf)

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

  -- Symbol context (right, via nvim-navic)
  local navic_part = ''
  local ok_nav, navic = pcall(require, 'nvim-navic')
  if ok_nav and navic.is_available(buf) then
    local loc = navic.get_location({}, buf)
    if loc and loc ~= '' then
      navic_part = '%=%#CSWinbarNav# ' .. loc .. ' '
    end
  end

  return path_part .. navic_part
end

local function setup_highlights()
  local hi = api.nvim_set_hl
  hi(0, 'CSWinbarDir',  { fg = '#545c7e', bg = '#13151f' })
  hi(0, 'CSWinbarFile', { fg = '#a9b1d6', bg = '#13151f', bold = true })
  hi(0, 'CSWinbarNav',  { fg = '#7aa2f7', bg = '#13151f' })
end

local SKIP_FT = {
  cs_filetree = true, cs_dirdash = true, cs_outline = true,
  cs_home = true, cs_notify = true, cs_gitui = true,
  TelescopePrompt = true, lazy = true, mason = true,
  help = true, trouble = true, dap_repl = true,
  ['dapui_watches'] = true, ['dapui_stacks'] = true,
  ['dapui_breakpoints'] = true, ['dapui_scopes'] = true,
}
local SKIP_BT = { terminal = true, nofile = true, prompt = true, quickfix = true }

function M.setup()
  setup_highlights()
  api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })
  api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    callback = function()
      if SKIP_FT[vim.bo.filetype] or SKIP_BT[vim.bo.buftype] then
        vim.wo.winbar = ''
      else
        vim.wo.winbar = '%!v:lua.require("claudespace.winbar").render()'
      end
    end,
  })
end

return M
