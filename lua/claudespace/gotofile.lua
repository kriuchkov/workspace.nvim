-- Smart "open file under cursor": resolves a path token against several bases
-- (cwd, active repo, the buffer's dir, a Claude session's cwd) and opens it in a
-- real editor window. Bound to gf and double-click, so file mentions in any
-- buffer — including Claude session terminals — are clickable.
local M = {}

local fn = vim.fn

-- Candidate absolute paths for a (possibly relative) token.
local function candidates(p)
  local list = {}
  local seen = {}
  local function add(x)
    x = fn.fnamemodify(x, ':p')
    if not seen[x] then seen[x] = true; list[#list + 1] = x end
  end

  if p:sub(1, 1) == '/' then
    add(p)
  elseif p:sub(1, 1) == '~' then
    add(fn.expand(p))
  else
    add(fn.getcwd() .. '/' .. p)
    local ok, repos = pcall(require, 'claudespace.repos')
    if ok then add(repos.active_cwd() .. '/' .. p) end
    local bufdir = fn.expand('%:p:h')
    if bufdir ~= '' then add(bufdir .. '/' .. p) end
    -- A Claude session terminal: resolve relative to that session's cwd.
    local sid = vim.b.cs_session_id
    if sid then
      local ok2, sessions = pcall(require, 'claudespace.claude.sessions')
      local s = ok2 and sessions.get and sessions.get(sid)
      if s and s.cwd then add(s.cwd .. '/' .. p) end
    end
  end
  return list
end

-- Open the file referenced under the cursor. Returns true if it opened one.
function M.open_under_cursor()
  local cfile = fn.expand('<cfile>')
  if cfile == nil or cfile == '' then return false end
  -- isfname usually drops a :line[:col] suffix — recover it from the WORD.
  local cword = fn.expand('<cWORD>')
  local lnum  = tonumber(cword:match(vim.pesc(cfile) .. ':(%d+)'))

  local target
  for _, c in ipairs(candidates(cfile)) do
    if fn.filereadable(c) == 1 then target = c; break end
  end
  if not target then return false end

  pcall(function() require('claudespace.claude.util').ensure_editor_win() end)
  vim.cmd('edit ' .. fn.fnameescape(target))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    vim.cmd 'normal! zz'
  end
  return true
end

function M.setup()
  local map = vim.keymap.set
  -- gf: try the smart resolver, fall back to the builtin.
  map('n', 'gf', function()
    if not M.open_under_cursor() then pcall(vim.cmd, 'normal! gf') end
  end, { silent = true, desc = 'Open file under cursor (smart)' })

  -- Double-click: open the file under the cursor, else default word select.
  map('n', '<2-LeftMouse>', function()
    if not M.open_under_cursor() then
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes('<2-LeftMouse>', true, false, true), 'n', false)
    end
  end, { silent = true, desc = 'Open file under cursor (click)' })
end

return M
