-- lazygit in a floating window.
-- Floating terminal + proper cleanup.
local M = {}

local api = vim.api
local fn  = vim.fn

local _buf  = nil
local _win  = nil
local _prev = nil

local function git_root()
  local dir = vim.bo.buftype == 'terminal' and fn.getcwd()
           or fn.fnamemodify(fn.resolve(fn.expand '%:p'), ':h')
  local root = fn.trim(fn.system('git -C ' .. fn.shellescape(dir) .. ' rev-parse --show-toplevel 2>/dev/null'))
  return (vim.v.shell_error == 0 and root ~= '') and root or fn.getcwd()
end

local function open_float()
  local W = math.ceil(vim.o.columns * 0.92)
  local H = math.ceil(vim.o.lines   * 0.88) - 1
  local r = math.ceil((vim.o.lines   - H) / 2)
  local c = math.ceil((vim.o.columns - W) / 2)

  if _buf == nil or not api.nvim_buf_is_valid(_buf) then
    _buf = api.nvim_create_buf(false, true)
  end

  _win = api.nvim_open_win(_buf, true, {
    style    = 'minimal',
    relative = 'editor',
    row = r, col = c, width = W, height = H,
    border = 'rounded',
  })

  vim.wo[_win].winblend  = 0
  vim.wo[_win].signcolumn = 'no'
  api.nvim_set_hl(0, 'LazyGitFloat',  { link = 'Normal',      default = true })
  api.nvim_set_hl(0, 'LazyGitBorder', { link = 'FloatBorder', default = true })
  vim.wo[_win].winhl = 'NormalFloat:LazyGitFloat,FloatBorder:LazyGitBorder'

  -- Resize on terminal resize
  api.nvim_create_autocmd('VimResized', {
    once = true,
    callback = function()
      if not api.nvim_win_is_valid(_win) then return end
      local nW = math.ceil(vim.o.columns * 0.92)
      local nH = math.ceil(vim.o.lines   * 0.88) - 1
      local nr = math.ceil((vim.o.lines   - nH) / 2)
      local nc = math.ceil((vim.o.columns - nW) / 2)
      api.nvim_win_set_config(_win, { relative = 'editor', row = nr, col = nc, width = nW, height = nH })
    end,
  })
end

local function on_exit(_, code)
  if code ~= 0 then return end
  vim.cmd 'silent! checktime'
  if api.nvim_win_is_valid(_win)  then api.nvim_win_close(_win, true) end
  if api.nvim_buf_is_valid(_buf)  then api.nvim_buf_delete(_buf, { force = true }) end
  if api.nvim_win_is_valid(_prev) then api.nvim_set_current_win(_prev) end
  _win = nil; _buf = nil; _prev = nil
end

function M.open(path)
  if fn.executable 'lazygit' ~= 1 then
    vim.notify('lazygit not found in PATH', vim.log.levels.ERROR); return
  end

  _prev = api.nvim_get_current_win()
  open_float()

  local root = path or git_root()
  local cmd  = { 'lazygit', '-p', root }

  vim.schedule(function()
    fn.jobstart(cmd, { term = true, on_exit = on_exit })
    vim.cmd 'startinsert'
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', function(o)
    M.open(o.args ~= '' and o.args or nil)
  end, { nargs = '?', complete = 'dir' })
end

return M
