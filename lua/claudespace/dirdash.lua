-- Directory dashboard: replaces netrw when opening a directory.
-- Shows git status, recent commits, and README preview.
local M = {}

local api = vim.api
local fn  = vim.fn
local ns  = api.nvim_create_namespace('cs_dirdash')

-- ── Data gathering ────────────────────────────────────────────────────────────

local function git_info(dir)
  local root = fn.trim(fn.system('git -C ' .. fn.shellescape(dir) .. ' rev-parse --show-toplevel 2>/dev/null'))
  if vim.v.shell_error ~= 0 or root == '' then return nil end
  local branch = fn.trim(fn.system('git -C ' .. fn.shellescape(dir) .. ' branch --show-current 2>/dev/null'))
  local log1   = fn.trim(fn.system('git -C ' .. fn.shellescape(dir) .. ' log -1 --pretty=%h\\ %s 2>/dev/null'))
  -- Array form avoids shell interpreting %<(52,trunc) as process substitution in zsh
  local log5   = fn.system({ 'git', '-C', dir, 'log', '-5',
                              '--pretty=format:%h  %<(52,trunc)%s  %ar' })
  local status = fn.system('git -C ' .. fn.shellescape(dir) .. ' status --porcelain 2>/dev/null')
  local mod, new = 0, 0
  for line in status:gmatch('[^\n]+') do
    if line:sub(1, 2) == '??' then new = new + 1 else mod = mod + 1 end
  end
  return { branch = branch, log1 = log1, log5 = log5, mod = mod, new = new }
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function build(dir)
  local lines, hls = {}, {}
  local function add(line, hl)
    table.insert(lines, line)
    if hl then table.insert(hls, { #lines - 1, 0, -1, hl }) end
  end
  local SEP = '  ' .. string.rep('─', 50)

  add('')
  add('  ' .. fn.fnamemodify(dir, ':~'), 'CSTreeDir')

  -- Show workspace name if this directory is a saved workspace
  local ok_ws, ws = pcall(require, 'claudespace.workspace')
  if ok_ws then
    for _, w in ipairs(ws.list()) do
      if w.cwd == dir then
        local marker = (ws._current == w.name) and ' (active)' or ''
        add('  ⬡ workspace: ' .. w.name .. marker, 'CSWorkspace')
        break
      end
    end
  end
  add('')

  local g = git_info(dir)
  if g then
    add('  Git', 'CSWinbarDir')
    add(SEP)
    add('   branch   ' .. (g.branch ~= '' and g.branch or '(detached HEAD)'), 'CSGit')
    if g.log1 ~= '' then add('   commit   ' .. g.log1) end
    local st = ''
    if g.mod  > 0 then st = g.mod  .. ' modified' end
    if g.new  > 0 then st = st .. (st ~= '' and ', ' or '') .. g.new .. ' untracked' end
    if st == '' then add('   status   clean', 'CSTreeGitAdd')
    else             add('   status   ' .. st, 'CSTreeGitMod') end
    add('')

    if g.log5 ~= '' then
      add('  Recent commits', 'CSWinbarDir')
      add(SEP)
      for line in g.log5:gmatch('[^\n]+') do
        if line ~= '' then add('  ' .. line) end
      end
      add('')
    end
  end

  local readme
  for _, name in ipairs({ 'README.md', 'readme.md', 'README', 'README.txt', 'README.rst' }) do
    if fn.filereadable(dir .. '/' .. name) == 1 then readme = dir .. '/' .. name; break end
  end
  if readme then
    add('  ' .. fn.fnamemodify(readme, ':t'), 'CSWinbarDir')
    add(SEP)
    for _, l in ipairs(fn.readfile(readme, '', 30)) do
      add('  ' .. l)
    end
  end

  return lines, hls
end

-- ── Buffer management ─────────────────────────────────────────────────────────

local function apply(buf, lines, hls)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end
end

function M.open(dir)
  dir = fn.fnamemodify(dir, ':p'):gsub('[/\\]+$', '')

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile  = false
  vim.bo[buf].filetype  = 'cs_dirdash'

  apply(buf, build(dir))

  api.nvim_set_current_buf(buf)

  -- Apply editor window options (dirdash is read-only info, not a file)
  local wo = vim.wo[0]
  wo.number         = false
  wo.relativenumber = false
  wo.signcolumn     = 'no'
  wo.wrap           = false
  wo.cursorline     = true
  wo.winbar         = ''

  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'q',    function() vim.cmd 'bd' end, o)
  vim.keymap.set('n', 'r',    function() apply(buf, build(dir)) end, o)
  vim.keymap.set('n', '\\',   function() require('claudespace.filetree').open(dir) end, o)
  vim.keymap.set('n', '<CR>', function() require('claudespace.filetree').open(dir) end, o)
  vim.keymap.set('n', 'w', function()
    local ws = require('claudespace.workspace')
    vim.ui.input({ prompt  = 'Save workspace as: ',
                   default = fn.fnamemodify(dir, ':t') }, function(name)
      if name and name ~= '' then
        vim.cmd('cd ' .. fn.fnameescape(dir))
        ws.save(name)
        apply(buf, build(dir))
      end
    end)
  end, o)
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup()
  api.nvim_create_autocmd('BufEnter', {
    callback = function(ev)
      local name = api.nvim_buf_get_name(ev.buf)
      if fn.isdirectory(name) == 1 and vim.bo[ev.buf].filetype ~= 'cs_dirdash' then
        local orig = ev.buf
        vim.schedule(function()
          if not api.nvim_buf_is_valid(orig) then return end
          M.open(name)
          -- Remove the bare directory buffer so it doesn't linger as a tab
          if api.nvim_buf_is_valid(orig) and api.nvim_get_current_buf() ~= orig then
            pcall(api.nvim_buf_delete, orig, { force = true })
          end
        end)
      end
    end,
  })
end

return M
