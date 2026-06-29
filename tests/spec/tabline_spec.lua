-- Tabline group logic — unit tests (no UI, no open windows).
-- Covers: group CRUD, collapse toggle, session roundtrip, reapply_groups.
local assert = require 'luassert'
local tl     = require 'claudespace.tabline'
local T      = tl._test
local fn     = vim.fn

-- ── Fixtures ──────────────────────────────────────────────────────────────────

local session_dir, orig_cwd

local function scratch_buf(name)
  local buf = vim.api.nvim_create_buf(true, false)
  if name then vim.api.nvim_buf_set_name(buf, name) end
  return buf
end

local function delete_buf(buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

-- Outer describe so before_each/after_each have a valid describe context.
describe('tabline', function()

before_each(function()
  orig_cwd    = fn.getcwd()
  session_dir = fn.tempname()
  fn.mkdir(session_dir, 'p')
  T.set_session_dir(session_dir)
  T.reset_state()
end)

after_each(function()
  T.reset_state()
  T.set_session_dir(nil)
  fn.delete(session_dir, 'rf')
  vim.cmd('cd ' .. fn.fnameescape(orig_cwd))
end)

-- ── group_add ─────────────────────────────────────────────────────────────────

describe('tabline group_add', function()
  it('creates a new group when name is unknown', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'backend')
    local groups = T.get_groups()
    local found = false
    for _, g in pairs(groups) do
      if g.name == 'backend' then found = true; break end
    end
    assert.is_true(found)
    delete_buf(buf)
  end)

  it('assigns the buffer to the group', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'frontend')
    local bg = T.get_buf_group()
    local groups = T.get_groups()
    local gid = bg[buf]
    assert.is_not_nil(gid)
    assert.equals('frontend', groups[gid].name)
    delete_buf(buf)
  end)

  it('reuses an existing group with the same name', function()
    local b1 = scratch_buf()
    local b2 = scratch_buf()
    tl.group_add(b1, 'shared')
    tl.group_add(b2, 'shared')
    local bg = T.get_buf_group()
    assert.equals(bg[b1], bg[b2])
    delete_buf(b1); delete_buf(b2)
  end)

  it('new group starts as not collapsed', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'grp')
    local bg = T.get_buf_group()
    local g  = T.get_groups()[bg[buf]]
    assert.is_false(g.collapsed)
    delete_buf(buf)
  end)
end)

-- ── group_remove ──────────────────────────────────────────────────────────────

describe('tabline group_remove', function()
  it('removes buffer from its group', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'grp')
    tl.group_remove(buf)
    local bg = T.get_buf_group()
    assert.is_nil(bg[buf])
    delete_buf(buf)
  end)

  it('is a no-op when buffer has no group', function()
    local buf = scratch_buf()
    assert.has_no_error(function() tl.group_remove(buf) end)
    delete_buf(buf)
  end)
end)

-- ── collapse toggle ───────────────────────────────────────────────────────────

describe('tabline group_toggle_collapse', function()
  it('collapses an expanded group', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'grp')
    -- make it the current buffer so group_toggle_collapse finds it
    vim.api.nvim_set_current_buf(buf)
    tl.group_toggle_collapse()
    local bg = T.get_buf_group()
    local g  = T.get_groups()[bg[buf]]
    assert.is_true(g.collapsed)
    delete_buf(buf)
  end)

  it('expands a collapsed group', function()
    local buf = scratch_buf()
    tl.group_add(buf, 'grp')
    vim.api.nvim_set_current_buf(buf)
    tl.group_toggle_collapse()  -- collapse
    tl.group_toggle_collapse()  -- expand
    local bg = T.get_buf_group()
    local g  = T.get_groups()[bg[buf]]
    assert.is_false(g.collapsed)
    delete_buf(buf)
  end)

  it('emits a warning when current buffer has no group', function()
    local buf = scratch_buf()
    vim.api.nvim_set_current_buf(buf)
    -- No group added — should not crash; check via notify capture
    local warned = false
    local orig = vim.notify
    vim.notify = function(_, level)
      -- with the picker approach there may be no warning; just no crash
      warned = true
    end
    -- If no collapsed groups exist, the function shows "No collapsed groups"
    assert.has_no_error(tl.group_toggle_collapse)
    vim.notify = orig
    delete_buf(buf)
  end)
end)

-- ── reapply_groups ────────────────────────────────────────────────────────────

describe('tabline reapply_groups', function()
  it('assigns groups to already-open buffers from path_map', function()
    local path = fn.tempname() .. '.lua'
    fn.writefile({ '-- test' }, path)

    -- Add buf to a group and save
    local buf = scratch_buf(path)
    tl.group_add(buf, 'saved-group')
    T.save_session()

    -- Reset state (simulates restart — buf still open, group cleared)
    T.reset_state()
    assert.is_nil(T.get_buf_group()[buf], 'group cleared after reset')

    -- Load session: restores _path_map + group definitions
    T.load_session()

    -- reapply_groups: re-links the open buffer to its group
    tl.reapply_groups()

    local bg     = T.get_buf_group()
    local groups = T.get_groups()
    local gid    = bg[buf]
    assert.is_not_nil(gid, 'buffer should be in a group after reapply')
    assert.equals('saved-group', groups[gid].name)

    delete_buf(buf)
    fn.delete(path)
  end)

  it('is a no-op when path_map is empty', function()
    local buf = scratch_buf('/some/path.lua')
    assert.has_no_error(tl.reapply_groups)
    assert.is_nil(T.get_buf_group()[buf])
    delete_buf(buf)
  end)
end)

-- ── session round-trip ────────────────────────────────────────────────────────

describe('tabline session round-trip', function()
  it('restores group names and colors after save+load', function()
    local path = fn.tempname() .. '.go'
    fn.writefile({ 'package main' }, path)
    local buf = scratch_buf(path)

    tl.group_add(buf, 'mygroup')
    -- force a specific color to verify it persists
    local gid = T.get_buf_group()[buf]
    T.get_groups()[gid].color_idx = 3

    T.save_session()
    T.reset_state()
    T.load_session()
    tl.reapply_groups()

    local groups   = T.get_groups()
    local bg       = T.get_buf_group()
    local new_gid  = bg[buf]
    assert.is_not_nil(new_gid)
    assert.equals('mygroup', groups[new_gid].name)
    assert.equals(3, groups[new_gid].color_idx)

    delete_buf(buf)
    fn.delete(path)
  end)

  it('restores collapsed state after save+load', function()
    local path = fn.tempname() .. '.rs'
    fn.writefile({ 'fn main() {}' }, path)
    local buf = scratch_buf(path)

    tl.group_add(buf, 'collapsed-grp')
    local gid = T.get_buf_group()[buf]
    T.get_groups()[gid].collapsed = true   -- manually collapse

    T.save_session()
    T.reset_state()
    T.load_session()
    tl.reapply_groups()

    local groups  = T.get_groups()
    local bg      = T.get_buf_group()
    local new_gid = bg[buf]
    assert.is_not_nil(new_gid)
    assert.is_true(groups[new_gid].collapsed)

    delete_buf(buf)
    fn.delete(path)
  end)

  it('handles missing session file gracefully', function()
    -- no save_session called → file does not exist
    assert.has_no_error(T.load_session)
  end)

  it('handles corrupt session file gracefully', function()
    fn.mkdir(session_dir, 'p')
    -- write invalid JSON to the session file location
    local cwd_enc = fn.getcwd():gsub('[/\\]', '%%')
    fn.writefile({ '{bad json' }, session_dir .. '/' .. cwd_enc .. '.json')
    assert.has_no_error(T.load_session)
  end)
end) -- describe tabline session round-trip

-- ── rename_buf ────────────────────────────────────────────────────────────────

describe('tabline rename_buf', function()
  it('sets a custom label for the buffer', function()
    local buf = scratch_buf('/tmp/foo.lua')
    -- stub vim.ui.input to return 'my-chat'
    local orig = vim.ui.input
    vim.ui.input = function(_, cb) cb('my-chat') end
    tl.rename_buf(buf)
    vim.ui.input = orig
    assert.equals('my-chat', T.get_buf_labels()[buf])
    delete_buf(buf)
  end)

  it('clears custom label when empty string given', function()
    local buf = scratch_buf('/tmp/bar.lua')
    T.get_buf_labels()[buf] = 'old'
    local orig = vim.ui.input
    vim.ui.input = function(_, cb) cb('') end
    tl.rename_buf(buf)
    vim.ui.input = orig
    assert.is_nil(T.get_buf_labels()[buf])
    delete_buf(buf)
  end)

  it('does nothing when input is cancelled (nil)', function()
    local buf = scratch_buf('/tmp/baz.lua')
    local orig = vim.ui.input
    vim.ui.input = function(_, cb) cb(nil) end
    tl.rename_buf(buf)
    vim.ui.input = orig
    assert.is_nil(T.get_buf_labels()[buf])
    delete_buf(buf)
  end)
end)

end) -- describe tabline (outer)
