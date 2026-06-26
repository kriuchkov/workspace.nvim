-- Winbar: relative path with dir dimmed, filename bright.
local M = {}

function M.render()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then return '%#CSWinbarFile# [No Name]' end
  local rel  = vim.fn.fnamemodify(name, ':~:.')
  local dir  = vim.fn.fnamemodify(rel, ':h')
  local file = vim.fn.fnamemodify(rel, ':t')
  if dir == '.' then
    return '%#CSWinbarFile# ' .. file
  end
  return '%#CSWinbarDir# ' .. dir .. '/%#CSWinbarFile#' .. file
end

local function setup_highlights()
  local hi = vim.api.nvim_set_hl
  -- Slightly darker than editor (#1a1b26) → visible stripe between tabline and content
  hi(0, 'CSWinbarDir',  { fg = '#545c7e', bg = '#0f1117' })
  hi(0, 'CSWinbarFile', { fg = '#9aa5ce', bg = '#0f1117', bold = true })
end

local SKIP_FT = { cs_filetree = true, cs_dirdash = true, cs_outline = true,
                  cs_home = true, cs_notify = true, cs_gitui = true,
                  TelescopePrompt = true,
                  lazy = true, mason = true, help = true, trouble = true }
local SKIP_BT = { terminal = true, nofile = true, prompt = true, quickfix = true }

function M.setup()
  setup_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
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
