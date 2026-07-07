-- Tests for the headless stream-json runner: line framing + event parsing.
local assert = require 'luassert'
local runner = require 'claudespace.claude.runner'

describe('line_splitter', function()
  -- jobstart pre-splits stdout on '\n' into list elements: "a\nb\n" -> {'a','b',''}.
  -- The final element is the incomplete tail, continued by the next chunk's first.
  it('emits only complete lines, holding the partial tail', function()
    local got = {}
    local feed = runner.line_splitter(function(l) got[#got + 1] = l end)
    feed { '{"a":1}', '{"b":2}', '{"c":' }
    assert.are.same({ '{"a":1}', '{"b":2}' }, got)
    feed { '3}', '' }
    assert.are.same({ '{"a":1}', '{"b":2}', '{"c":3}' }, got)
  end)

  it('joins a line split across chunk boundaries', function()
    local got = {}
    local feed = runner.line_splitter(function(l) got[#got + 1] = l end)
    feed { 'hel' }
    feed { 'lo', '' }
    assert.are.same({ 'hello' }, got)
  end)

  it('skips empty lines', function()
    local got = {}
    local feed = runner.line_splitter(function(l) got[#got + 1] = l end)
    feed { 'x', '', 'y', '' }
    assert.are.same({ 'x', 'y' }, got)
  end)
end)

describe('parse_event', function()
  it('returns nothing for undecodable input', function()
    assert.are.same({}, runner.parse_event('not json'))
  end)

  it('parses the init event', function()
    local out = runner.parse_event(
      '{"type":"system","subtype":"init","session_id":"abc","model":"claude-opus-4-8"}')
    assert.are.equal(1, #out)
    assert.are.equal('init', out[1].kind)
    assert.are.equal('abc', out[1].session_id)
    assert.are.equal('claude-opus-4-8', out[1].model)
  end)

  it('parses assistant text blocks', function()
    local out = runner.parse_event(
      '{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"}]}}')
    assert.are.equal(1, #out)
    assert.are.equal('text', out[1].kind)
    assert.are.equal('Hi', out[1].text)
  end)

  it('skips empty text blocks but keeps tool_use', function()
    local out = runner.parse_event(
      '{"type":"assistant","message":{"content":[' ..
      '{"type":"text","text":""},' ..
      '{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}')
    assert.are.equal(1, #out)
    assert.are.equal('tool', out[1].kind)
    assert.are.equal('Bash', out[1].name)
  end)

  it('parses a successful result', function()
    local out = runner.parse_event(
      '{"type":"result","subtype":"success","is_error":false,"result":"done",' ..
      '"duration_ms":1500,"num_turns":2,"total_cost_usd":0.01,"session_id":"abc"}')
    assert.are.equal(1, #out)
    local r = out[1]
    assert.are.equal('result', r.kind)
    assert.are.equal('done', r.text)
    assert.is_false(r.is_error)
    assert.are.equal(1500, r.duration_ms)
    assert.are.equal(2, r.num_turns)
    assert.are.same({}, r.denials)
  end)

  it('flags a non-success result as an error', function()
    local r = runner.parse_event(
      '{"type":"result","subtype":"error_max_turns","is_error":true}')[1]
    assert.is_true(r.is_error)
  end)

  it('collects permission denials', function()
    local r = runner.parse_event(
      '{"type":"result","subtype":"success","permission_denials":' ..
      '[{"tool_name":"Edit"},{"tool_name":"Bash"}]}')[1]
    assert.are.same({ 'Edit', 'Bash' }, r.denials)
  end)

  it('ignores unrelated event types', function()
    assert.are.same({}, runner.parse_event('{"type":"rate_limit_event"}'))
  end)

  it('parses a partial text delta into a delta event', function()
    local out = runner.parse_event(
      '{"type":"stream_event","event":{"type":"content_block_delta",' ..
      '"index":0,"delta":{"type":"text_delta","text":"Hi"}}}')
    assert.are.same({ { kind = 'delta', text = 'Hi' } }, out)
  end)

  it('ignores non-text stream events', function()
    assert.are.same({}, runner.parse_event(
      '{"type":"stream_event","event":{"type":"message_start"}}'))
    assert.are.same({}, runner.parse_event(
      '{"type":"stream_event","event":{"type":"content_block_delta",' ..
      '"delta":{"type":"thinking_delta","thinking":"x"}}}'))
  end)
end)
