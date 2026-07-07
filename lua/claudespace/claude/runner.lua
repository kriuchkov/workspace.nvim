-- Structured, headless Claude runner built on the CLI's stream-json protocol.
--
-- claudespace.claude.sessions runs `claude` in a terminal buffer and *scrapes*
-- it: run_and_watch polls the buffer tail and guesses "done" from an idle
-- period, then regexes a preview out of box-drawing chrome. This module instead
-- spawns
--   claude --print --output-format stream-json --verbose <prompt>
-- and parses the JSONL event stream, so tool activity, the final answer, and
-- completion are known *exactly* — no PTY, no polling, no scraping.
local M = {}

local fn  = vim.fn
local api = vim.api

-- ── stdout line framing ───────────────────────────────────────────────────────

-- jobstart delivers stdout as a list of strings split on '\n', where the first
-- element continues the previous chunk's last element and the final element is
-- an incomplete line held until more arrives (see :h channel-lines). Returns a
-- feeder that emits only complete lines.
function M.line_splitter(on_line)
  local pending = ''
  return function(chunk)
    chunk[1] = pending .. chunk[1]
    pending  = table.remove(chunk)
    for _, line in ipairs(chunk) do
      if line ~= '' then on_line(line) end
    end
  end
end

-- ── event parsing ─────────────────────────────────────────────────────────────

-- Normalise one JSONL event line into zero or more high-level events. Pure and
-- side-effect free so it can be unit-tested without a running job. Kinds:
--   { kind='init',   session_id, model }
--   { kind='text',   text }              -- an assistant text block
--   { kind='tool',   name, input }       -- an assistant tool_use block
--   { kind='result', text, is_error, duration_ms, num_turns, cost, session_id,
--     denials }  -- denials: list of tools blocked by the shared permission set
function M.parse_event(line)
  local ok, ev = pcall(vim.json.decode, line)
  if not ok or type(ev) ~= 'table' then return {} end
  local t = ev.type

  if t == 'system' and ev.subtype == 'init' then
    return { { kind = 'init', session_id = ev.session_id, model = ev.model } }

  elseif t == 'stream_event' and type(ev.event) == 'table' then
    -- Only present with --include-partial-messages: per-token text deltas that
    -- power live streaming. The full 'assistant' block still arrives afterwards.
    local e = ev.event
    if e.type == 'content_block_delta' and e.delta and e.delta.type == 'text_delta'
        and e.delta.text and e.delta.text ~= '' then
      return { { kind = 'delta', text = e.delta.text } }
    end
    return {}

  elseif t == 'assistant' and ev.message and type(ev.message.content) == 'table' then
    local out = {}
    for _, block in ipairs(ev.message.content) do
      if block.type == 'text' and block.text and block.text ~= '' then
        out[#out + 1] = { kind = 'text', text = block.text }
      elseif block.type == 'tool_use' then
        out[#out + 1] = { kind = 'tool', name = block.name, input = block.input }
      end
    end
    return out

  elseif t == 'result' then
    -- permission_denials is [{ tool_name, ... }] — headless can't prompt, so a
    -- tool outside the shared allowlist lands here instead of a live dialog.
    local denials = {}
    for _, d in ipairs(ev.permission_denials or {}) do
      denials[#denials + 1] = d.tool_name or d.tool or '?'
    end
    return { {
      kind        = 'result',
      text        = ev.result,
      is_error    = ev.is_error == true or ev.subtype ~= 'success',
      duration_ms = ev.duration_ms,
      num_turns   = ev.num_turns,
      cost        = ev.total_cost_usd,
      session_id  = ev.session_id,
      denials     = denials,
    } }
  end

  return {}
end

-- ── in-flight jobs & usage ─────────────────────────────────────────────────────

-- Active headless jobs (job id → label), so runaway/slow runs can be cancelled.
M._jobs = {}
-- Accumulated usage for this nvim session, surfaced in the statusline / :ClaudeUsage.
M._usage = { runs = 0, turns = 0, cost = 0 }

function M.active()
  local n = 0
  for _ in pairs(M._jobs) do n = n + 1 end
  return n
end

function M.usage() return M._usage end

---Stop all running headless jobs. Returns how many were signalled.
function M.cancel_all()
  local n = 0
  for job in pairs(M._jobs) do pcall(fn.jobstop, job); n = n + 1 end
  M._jobs = {}
  return n
end

-- ── driver ────────────────────────────────────────────────────────────────────

---Run a prompt headlessly and stream structured events to callbacks.
---@param opts table {
---  cwd?, prompt, model?, permission_mode?, extra_args?, partial?, label?,
---  on_init?(info), on_delta?(text), on_text?(block), on_tool?(name),
---  on_result?(res), on_error?(msg) }
---@return integer? job  jobstart channel id, or nil if launch failed
function M.run(opts)
  opts = opts or {}
  local cmd = { 'claude', '--print', '--output-format', 'stream-json', '--verbose' }
  -- Per-token deltas for live streaming; the full 'assistant' block still follows.
  if opts.partial then cmd[#cmd + 1] = '--include-partial-messages' end
  if opts.model then vim.list_extend(cmd, { '--model', opts.model }) end
  if opts.permission_mode then
    vim.list_extend(cmd, { '--permission-mode', opts.permission_mode })
  end
  if opts.extra_args then vim.list_extend(cmd, opts.extra_args) end
  cmd[#cmd + 1] = opts.prompt or ''

  -- Forward-declared (above feed and jobstart) so both the result handler and
  -- on_exit can de-register by job id — their closures are built before the
  -- jobstart call assigns it.
  local job
  local got_result = false
  local feed = M.line_splitter(function(line)
    for _, e in ipairs(M.parse_event(line)) do
      if     e.kind == 'init'   and opts.on_init   then opts.on_init(e)
      elseif e.kind == 'delta'  and opts.on_delta  then opts.on_delta(e.text)
      elseif e.kind == 'text'   and opts.on_text   then opts.on_text(e.text)
      elseif e.kind == 'tool'   and opts.on_tool   then opts.on_tool(e.name)
      elseif e.kind == 'result' then
        got_result = true
        -- The result is the last event; the work is done even if the process
        -- lingers before exiting. De-register now so active() (statusline
        -- spinner) doesn't count a finished run.
        if job then M._jobs[job] = nil end
        M._usage.runs  = M._usage.runs  + 1
        M._usage.turns = M._usage.turns + (e.num_turns or 0)
        M._usage.cost  = M._usage.cost  + (e.cost or 0)
        if opts.on_result then opts.on_result(e) end
      end
    end
  end)

  local stderr = {}
  job = fn.jobstart(cmd, {
    cwd             = opts.cwd,
    stdout_buffered = false,
    on_stdout = function(_, data) if data then feed(data) end end,
    on_stderr = function(_, data)
      if not data then return end
      for _, l in ipairs(data) do if l ~= '' then stderr[#stderr + 1] = l end end
    end,
    on_exit = function(_, code)
      if job then M._jobs[job] = nil end
      -- A clean run ends via the result event. Only surface a non-zero exit that
      -- produced no result (bad flag, network failure). A later SIGTERM after the
      -- result — e.g. the job killed on VimLeave or via :ClaudeCancel — is not an
      -- error.
      if code ~= 0 and not got_result and opts.on_error then
        opts.on_error(#stderr > 0 and table.concat(stderr, '\n')
          or ('claude exited with code ' .. code))
      end
    end,
  })

  if job <= 0 then
    if opts.on_error then opts.on_error('failed to launch claude') end
    return nil
  end
  M._jobs[job] = opts.label or opts.prompt or 'claude'
  -- The prompt goes on argv, so close stdin immediately — otherwise the CLI
  -- waits 3s for piped input before proceeding ("no stdin data received in 3s").
  pcall(fn.chanclose, job, 'stdin')
  return job
end

-- ── command runner (structured replacement for the terminal-scraping path) ─────

-- Last completed result, viewable with :ClaudeLastResult.
M._last = nil

---Run a slash / custom command headlessly in cwd. Shows a spinner that reflects
---live tool activity, then notifies with the *actual* result — no scraping, no
---idle-tail guessing. Never opens or focuses a terminal.
---@param cwd string
---@param cmd string   e.g. "/ship"
---@param label? string
function M.run_command(cwd, cmd, label)
  label = label or cmd
  local util = require('claudespace.claude.util')
  local base = 'Claude · ' .. label
  local stop, set_label = util.spinner(base)

  M.run {
    cwd = cwd, prompt = cmd,
    on_tool = function(name)
      if set_label then set_label(base .. ' · ' .. name .. '…') end
    end,
    on_result = function(res)
      stop()
      M._last = res
      if res.is_error then
        vim.notify(base .. ' — failed\n' .. (res.text or ''), vim.log.levels.ERROR)
        return
      end
      local preview = (res.text or ''):gsub('%s+$', '')
      -- Headless can't prompt: a blocked tool means the command silently did
      -- less than in the TUI. Surface it (WARN) rather than reporting a clean win.
      local denied = res.denials and #res.denials > 0
      vim.notify(
        ('%s — done (%.1fs, %d turn%s)%s  :ClaudeLastResult%s'):format(
          base, (res.duration_ms or 0) / 1000,
          res.num_turns or 0, res.num_turns == 1 and '' or 's',
          denied and (' · blocked: ' .. table.concat(res.denials, ', ')) or '',
          preview ~= '' and ('\n' .. preview:sub(1, 200)) or ''),
        denied and vim.log.levels.WARN or vim.log.levels.INFO)
    end,
    on_error = function(msg)
      stop()
      vim.notify(base .. ' — error\n' .. msg, vim.log.levels.ERROR)
    end,
  }
end

---Open the last headless result in a read-only float.
function M.show_last()
  if not (M._last and M._last.text) then
    vim.notify('No Claude result yet', vim.log.levels.WARN)
    return
  end
  require('claudespace.claude.util').read_float(
    vim.split(M._last.text, '\n'), ' Claude result ', 'markdown')
end

function M.setup()
  api.nvim_create_user_command('ClaudeLastResult', M.show_last,
    { desc = 'Show the last headless Claude command result' })

  api.nvim_create_user_command('ClaudeCancel', function()
    local n = M.cancel_all()
    vim.notify(
      n > 0 and ('Cancelled ' .. n .. ' Claude job' .. (n == 1 and '' or 's'))
             or 'No active Claude jobs',
      n > 0 and vim.log.levels.INFO or vim.log.levels.WARN)
  end, { desc = 'Cancel running headless Claude jobs' })

  api.nvim_create_user_command('ClaudeUsage', function()
    local u = M._usage
    vim.notify(('Claude session: %d run%s · %d turns · $%.4f'):format(
      u.runs, u.runs == 1 and '' or 's', u.turns, u.cost), vim.log.levels.INFO)
  end, { desc = 'Show accumulated headless Claude usage' })

  vim.keymap.set('n', '<leader>cx', function() vim.cmd 'ClaudeCancel' end,
    { desc = 'Claude: cancel running jobs' })
end

return M
