-- Tests for dashboard helpers
local assert = require 'luassert'

local function center(str, width)
  local pad = math.floor((width - vim.fn.strdisplaywidth(str)) / 2)
  return string.rep(' ', math.max(pad, 0)) .. str
end

describe('dashboard center()', function()
  it('centers a short string in a wide column', function()
    local result = center('hi', 10)
    assert.are.equal(10, #result + 2)  -- 4 spaces + 'hi' + 4 spaces = 10 (approx)
    assert.is.truthy(result:find('hi'))
  end)

  it('does not add negative padding', function()
    local result = center('a very long string that exceeds width', 5)
    assert.is.truthy(result:find('a very long'))
    -- Should start at column 0 (no negative indent)
    assert.are.equal('a', result:sub(1, 1))
  end)

  it('centers consistently', function()
    local r1 = center('abc', 20)
    local r2 = center('abc', 20)
    assert.are.equal(r1, r2)
  end)
end)
