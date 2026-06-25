-- Tests for test generation module: framework detection
local assert = require 'luassert'

local function detect_test_framework(ft)
  local frameworks = {
    rust = 'Rust built-in #[cfg(test)] with #[test] functions',
    go = 'Go testing package with func TestXxx(t *testing.T)',
    python = 'pytest',
    typescript = 'Jest / Vitest',
    javascript = 'Jest / Vitest',
    lua = 'busted',
  }
  return frameworks[ft] or 'appropriate test framework for ' .. ft
end

describe('detect_test_framework', function()
  it('detects rust', function()
    assert.is.truthy(detect_test_framework('rust'):find('#%[test%]'))
  end)

  it('detects go', function()
    assert.is.truthy(detect_test_framework('go'):find('TestXxx'))
  end)

  it('detects python', function()
    assert.are.equal('pytest', detect_test_framework('python'))
  end)

  it('detects typescript and javascript the same', function()
    assert.are.equal(detect_test_framework('typescript'), detect_test_framework('javascript'))
  end)

  it('detects lua', function()
    assert.are.equal('busted', detect_test_framework('lua'))
  end)

  it('falls back gracefully for unknown filetypes', function()
    local result = detect_test_framework('kotlin')
    assert.is.truthy(result:find('kotlin'))
  end)
end)
