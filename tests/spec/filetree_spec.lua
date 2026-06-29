-- Filetree — pure-logic unit tests (no UI, no open windows).
-- Covers: header offset, cursor↔entry mapping, is_last calculation, ignored-path propagation.
local assert = require 'luassert'

-- Stub MiniIcons so filetree.lua can be required without the plugin loaded
package.preload['mini.icons'] = function()
  return { get = function() return '', 'MiniIconsGrey', false end }
end
_G.MiniIcons = { get = function() return '', 'MiniIconsGrey', false end }

local ft = require 'claudespace.filetree'
local T  = ft._test

-- ── Header offset ─────────────────────────────────────────────────────────────

describe('filetree header', function()
  it('HEADER_LINES is 2 (name + path)', function()
    assert.equals(2, T.HEADER_LINES)
  end)

  it('entry_to_row: first entry maps to row 3', function()
    assert.equals(3, T.entry_to_row(1))
  end)

  it('entry_to_row: tenth entry maps to row 12', function()
    assert.equals(12, T.entry_to_row(10))
  end)

  it('row_to_entry: row 3 maps to entry 1', function()
    assert.equals(1, T.row_to_entry(3))
  end)

  it('row_to_entry: header rows return nil', function()
    assert.is_nil(T.row_to_entry(1))
    assert.is_nil(T.row_to_entry(2))
  end)

  it('row_to_entry is the inverse of entry_to_row', function()
    for i = 1, 20 do
      assert.equals(i, T.row_to_entry(T.entry_to_row(i)))
    end
  end)
end)

-- ── compute_is_last ───────────────────────────────────────────────────────────

local function make_entry(depth, name)
  return { depth = depth, name = name, path = '/' .. name, is_dir = false }
end

describe('compute_is_last', function()
  it('single entry is always last', function()
    local entries = { make_entry(0, 'a') }
    T.compute_is_last(entries)
    assert.is_true(entries[1].is_last)
  end)

  it('flat list: only the final entry is last', function()
    local entries = {
      make_entry(0, 'a'),
      make_entry(0, 'b'),
      make_entry(0, 'c'),
    }
    T.compute_is_last(entries)
    assert.is_false(entries[1].is_last)
    assert.is_false(entries[2].is_last)
    assert.is_true(entries[3].is_last)
  end)

  it('nested: last child of expanded dir is marked last', function()
    -- parent at depth 0, two children at depth 1
    local entries = {
      make_entry(0, 'dir'),
      make_entry(1, 'child1'),
      make_entry(1, 'child2'),  -- last child
      make_entry(0, 'sibling'), -- dir has a sibling → dir.is_last = false
    }
    T.compute_is_last(entries)
    assert.is_false(entries[1].is_last)  -- dir has sibling after
    assert.is_false(entries[2].is_last)  -- child1 has child2 after
    assert.is_true(entries[3].is_last)   -- child2: next entry is depth 0 < 1
    assert.is_true(entries[4].is_last)   -- sibling: nothing after
  end)

  it('last dir with children is marked last', function()
    -- Regression: the last root-level dir has children after it in the flat list.
    -- It must still be marked is_last=true so its children get '  ' guides, not '│'.
    local entries = {
      make_entry(0, 'other'),
      make_entry(0, 'last_dir'),
      make_entry(1, 'kid1'),
      make_entry(1, 'kid2'),
    }
    T.compute_is_last(entries)
    assert.is_false(entries[1].is_last)  -- 'other' has sibling last_dir
    assert.is_true(entries[2].is_last)   -- 'last_dir': no depth-0 sibling after it
    assert.is_false(entries[3].is_last)  -- kid1 has sibling kid2
    assert.is_true(entries[4].is_last)   -- kid2: last in list
  end)

  it('guide propagation: children of last dir see no vertical guide', function()
    -- zsh is the last depth-0 item and is expanded; its children must NOT draw │
    -- because their ancestor (zsh) is the last sibling at depth 0.
    local entries = {
      make_entry(0, 'git'),   -- not last
      make_entry(0, 'zsh'),   -- last depth-0
      make_entry(1, '.zshrc'), -- only child
    }
    T.compute_is_last(entries)
    assert.is_false(entries[1].is_last)
    assert.is_true(entries[2].is_last)   -- zsh is last → children see '  ' not '│'
    assert.is_true(entries[3].is_last)   -- .zshrc is only/last child
  end)

  it('empty entries list does not error', function()
    assert.has_no_error(function() T.compute_is_last({}) end)
  end)
end)

-- ── is_ignored ────────────────────────────────────────────────────────────────

describe('is_ignored', function()
  local ignored = {
    ['/repo/vendor'] = true,
    ['/repo/.build'] = true,
  }

  it('direct child of ignored dir returns true', function()
    assert.is_true(T.is_ignored('/repo/vendor/lib.go', ignored))
  end)

  it('deep descendant of ignored dir returns true', function()
    assert.is_true(T.is_ignored('/repo/vendor/pkg/sub/file.go', ignored))
  end)

  it('exact match of ignored path returns false (not a child)', function()
    -- exact path itself is not a CHILD of itself
    assert.is_false(T.is_ignored('/repo/vendor', ignored))
  end)

  it('path with ignored dir as prefix but different name returns false', function()
    -- /repo/vendor_extra should NOT match /repo/vendor
    assert.is_false(T.is_ignored('/repo/vendor_extra/file.go', ignored))
  end)

  it('unrelated path returns false', function()
    assert.is_false(T.is_ignored('/repo/src/main.go', ignored))
  end)

  it('second ignored dir also matches', function()
    assert.is_true(T.is_ignored('/repo/.build/out.o', ignored))
  end)

  it('empty ignored_set always returns false', function()
    assert.is_false(T.is_ignored('/repo/anything', {}))
  end)
end)
