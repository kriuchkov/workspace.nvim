-- Workspace manager — user-case tests.
-- Uses a temp WDIR per test so nothing touches real workspace state.
local assert = require 'luassert'
local ws     = require 'claudespace.workspace'

-- ── Fixtures ──────────────────────────────────────────────────────────────────

local wdir, projdir, orig_cwd

local function make_file(path, content)
  vim.fn.writefile({ content or '-- test' }, path)
end

local function listed_paths()
  local paths = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      local p = vim.api.nvim_buf_get_name(buf)
      if p ~= '' then table.insert(paths, p) end
    end
  end
  return paths
end

local function close_all_bufs()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

before_each(function()
  orig_cwd = vim.fn.getcwd()
  wdir     = vim.fn.tempname()
  projdir  = vim.fn.tempname()
  vim.fn.mkdir(wdir,    'p')
  vim.fn.mkdir(projdir, 'p')
  ws._set_wdir(wdir)
  ws._current = nil
  make_file(projdir .. '/a.lua')
  make_file(projdir .. '/b.lua')
  vim.cmd('cd ' .. vim.fn.fnameescape(projdir))
end)

after_each(function()
  close_all_bufs()
  vim.cmd('cd ' .. vim.fn.fnameescape(orig_cwd))
  vim.fn.delete(wdir,    'rf')
  vim.fn.delete(projdir, 'rf')
  ws._current = nil
end)

-- ── save() ────────────────────────────────────────────────────────────────────

describe('workspace save()', function()
  it('creates a workspace JSON file on disk', function()
    ws.save('proj')
    assert.equals(1, vim.fn.filereadable(wdir .. '/ws_proj.json'))
  end)

  it('persists cwd, name, and active file', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    ws.save('proj')
    local raw  = table.concat(vim.fn.readfile(wdir .. '/ws_proj.json'), '')
    local data = vim.fn.json_decode(raw)
    assert.equals('proj',   data.name)
    assert.equals(projdir,  data.cwd)
    assert.is_truthy(data.active:find('a%.lua'))
  end)

  it('includes all listed file buffers', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/b.lua'))
    ws.save('proj')
    local data = vim.fn.json_decode(
      table.concat(vim.fn.readfile(wdir .. '/ws_proj.json'), ''))
    assert.equals(2, #data.files)
  end)

  it('sets _current to the saved name', function()
    ws.save('proj')
    assert.equals('proj', ws._current)
  end)

  it('writes _last so it survives restart', function()
    ws.save('proj')
    assert.equals('proj', ws._read_last())
  end)

  it('uses cwd basename as default name', function()
    local base = vim.fn.fnamemodify(projdir, ':t')
    ws.save()
    assert.equals(base, ws._current)
  end)

  it('silent=true skips the notify', function()
    local got = {}
    local orig = vim.notify
    vim.notify = function(msg) table.insert(got, msg) end
    ws.save('proj', true)
    vim.notify = orig
    assert.equals(0, #got)
  end)

  it('silent=false (default) shows a notify', function()
    local got = {}
    local orig = vim.notify
    vim.notify = function(msg) table.insert(got, msg) end
    ws.save('proj')
    vim.notify = orig
    assert.equals(1, #got)
    assert.is_truthy(got[1]:find('proj'))
  end)
end)

-- ── list() / _update_index ────────────────────────────────────────────────────

describe('workspace list()', function()
  it('returns empty table when no workspaces saved', function()
    assert.same({}, ws.list())
  end)

  it('returns saved workspaces', function()
    ws.save('alpha')
    ws.save('beta')
    local list = ws.list()
    assert.equals(2, #list)
    local names = {}
    for _, w in ipairs(list) do names[w.name] = true end
    assert.is_truthy(names['alpha'])
    assert.is_truthy(names['beta'])
  end)

  it('does not duplicate on repeated saves with same name', function()
    ws.save('proj')
    ws.save('proj')
    assert.equals(1, #ws.list())
  end)
end)

-- ── current_name() ────────────────────────────────────────────────────────────

describe('workspace current_name()', function()
  it('returns _current when set', function()
    ws._current = 'myws'
    assert.equals('myws', ws.current_name())
  end)

  it('falls back to cwd basename when _current is nil', function()
    ws._current = nil
    local expected = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
    assert.equals(expected, ws.current_name())
  end)
end)

-- ── _write_last / _read_last ──────────────────────────────────────────────────

describe('workspace last persistence', function()
  it('roundtrips the workspace name', function()
    ws._write_last('myproject')
    assert.equals('myproject', ws._read_last())
  end)

  it('returns nil when no last file exists', function()
    assert.is_nil(ws._read_last())
  end)
end)

-- ── load() ────────────────────────────────────────────────────────────────────

describe('workspace load()', function()
  it('restores cwd to the saved directory', function()
    local other = vim.fn.tempname()
    vim.fn.mkdir(other, 'p')
    vim.cmd('cd ' .. vim.fn.fnameescape(other))
    ws.save('other')
    ws._current = nil
    vim.cmd('cd ' .. vim.fn.fnameescape(projdir))

    ws.load('other')
    assert.equals(other, vim.fn.getcwd())

    vim.fn.delete(other, 'rf')
  end)

  it('opens saved files as listed buffers', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/b.lua'))
    ws.save('proj')
    close_all_bufs()
    ws._current = nil

    ws.load('proj')

    local paths = listed_paths()
    local has_a = vim.tbl_contains(paths, projdir .. '/a.lua')
    local has_b = vim.tbl_contains(paths, projdir .. '/b.lua')
    assert.is_truthy(has_a)
    assert.is_truthy(has_b)
  end)

  it('focuses the previously active file', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    ws.save('proj')
    close_all_bufs()
    ws._current = nil

    ws.load('proj')

    local active = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    assert.is_truthy(active:find('a%.lua'))
  end)

  it('sets _current to the loaded workspace name', function()
    ws.save('proj')
    ws._current = nil
    ws.load('proj')
    assert.equals('proj', ws._current)
  end)

  it('closes unmodified listed buffers before restoring', function()
    -- open a file that is NOT part of the workspace
    local extra = projdir .. '/extra.lua'
    make_file(extra)
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    ws.save('proj')
    close_all_bufs()

    -- open extra as a fresh unmodified buffer
    vim.cmd('edit ' .. vim.fn.fnameescape(extra))
    ws._current = nil
    ws.load('proj')

    local paths = listed_paths()
    assert.is_falsy(vim.tbl_contains(paths, extra))
  end)

  it('preserves modified buffers during load', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    ws.save('proj')

    -- create and dirty a buffer that is not in the workspace
    local extra = projdir .. '/dirty.lua'
    make_file(extra)
    vim.cmd('edit ' .. vim.fn.fnameescape(extra))
    local dirty_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(dirty_buf, 0, -1, false, { '-- dirty' })
    -- buffer now has unsaved changes
    assert.is_truthy(vim.bo[dirty_buf].modified)

    ws._current = nil
    ws.load('proj')

    assert.is_truthy(vim.api.nvim_buf_is_valid(dirty_buf))
  end)

  it('shows an error and does not crash for a missing workspace', function()
    local errors = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.ERROR then table.insert(errors, msg) end
    end
    ws.load('does_not_exist')
    vim.notify = orig
    assert.equals(1, #errors)
    assert.is_truthy(errors[1]:find('not found'))
  end)

  it('shows an error and does not crash for corrupt JSON', function()
    vim.fn.writefile({ '{bad json' }, wdir .. '/ws_bad.json')
    local errors = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.ERROR then table.insert(errors, msg) end
    end
    ws.load('bad')
    vim.notify = orig
    assert.equals(1, #errors)
    assert.is_truthy(errors[1]:find('corrupt'))
  end)
end)

-- ── save + load roundtrip ─────────────────────────────────────────────────────

describe('workspace save/load roundtrip', function()
  it('restores the exact file list after a session break', function()
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/a.lua'))
    vim.cmd('edit ' .. vim.fn.fnameescape(projdir .. '/b.lua'))
    ws.save('session')

    -- simulate "closing Neovim"
    close_all_bufs()
    ws._current = nil

    ws.load('session')

    local paths = listed_paths()
    assert.equals(2, #paths)
    assert.is_truthy(vim.tbl_contains(paths, projdir .. '/a.lua'))
    assert.is_truthy(vim.tbl_contains(paths, projdir .. '/b.lua'))
  end)
end)

-- ── delete() ─────────────────────────────────────────────────────────────────

describe('workspace delete()', function()
  it('removes the workspace file from disk', function()
    ws.save('todel')
    -- bypass confirm dialog
    local orig = vim.fn.confirm
    vim.fn.confirm = function() return 1 end
    ws.delete('todel')
    vim.fn.confirm = orig
    assert.equals(0, vim.fn.filereadable(wdir .. '/ws_todel.json'))
  end)

  it('removes the workspace from the index', function()
    ws.save('todel')
    local orig = vim.fn.confirm
    vim.fn.confirm = function() return 1 end
    ws.delete('todel')
    vim.fn.confirm = orig
    local names = {}
    for _, w in ipairs(ws.list()) do names[w.name] = true end
    assert.is_falsy(names['todel'])
  end)

  it('clears _current when the active workspace is deleted', function()
    ws.save('todel')
    assert.equals('todel', ws._current)
    local orig = vim.fn.confirm
    vim.fn.confirm = function() return 1 end
    ws.delete('todel')
    vim.fn.confirm = orig
    assert.is_nil(ws._current)
  end)

  it('does nothing when user cancels the confirm', function()
    ws.save('keep')
    local orig = vim.fn.confirm
    vim.fn.confirm = function() return 2 end  -- "No"
    ws.delete('keep')
    vim.fn.confirm = orig
    assert.equals(1, vim.fn.filereadable(wdir .. '/ws_keep.json'))
  end)
end)
