-- Tests for agents panel: AGENTS.md parser
local assert = require 'luassert'

-- Inline the parser so we can test it without loading the full module
local function parse_agents_md(content_lines)
  local agents = {}
  local current = nil
  for _, line in ipairs(content_lines) do
    local name = line:match('^##%s+(.+)$')
    if name then
      current = { name = name, description = '' }
      table.insert(agents, current)
    elseif current and line:match('^[^#]') and line ~= '' then
      if current.description == '' then
        current.description = line
      end
    end
  end
  return agents
end

describe('parse_agents_md', function()
  it('parses empty file', function()
    assert.are.same({}, parse_agents_md({}))
  end)

  it('parses single agent', function()
    local agents = parse_agents_md {
      '# Agents',
      '',
      '## Rust Expert',
      'Specializes in Rust and systems programming.',
    }
    assert.are.equal(1, #agents)
    assert.are.equal('Rust Expert', agents[1].name)
    assert.are.equal('Specializes in Rust and systems programming.', agents[1].description)
  end)

  it('parses multiple agents', function()
    local agents = parse_agents_md {
      '## Backend',
      'Go and Rust services.',
      '',
      '## Frontend',
      'TypeScript and React.',
    }
    assert.are.equal(2, #agents)
    assert.are.equal('Backend', agents[1].name)
    assert.are.equal('Frontend', agents[2].name)
  end)

  it('ignores h1 headings', function()
    local agents = parse_agents_md { '# Title', '## Agent One', 'desc' }
    assert.are.equal(1, #agents)
    assert.are.equal('Agent One', agents[1].name)
  end)

  it('uses only first description line', function()
    local agents = parse_agents_md {
      '## Agent',
      'First line.',
      'Second line.',
    }
    assert.are.equal('First line.', agents[1].description)
  end)
end)
