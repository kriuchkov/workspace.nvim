-- Self-driving tour of claudespace.nvim for asciinema recordings.
--
-- Loaded by `scripts/demo.sh <target> tour`. Walks the headline features on a
-- timer with on-screen captions via direct module calls, then quits so the
-- recording ends cleanly. Tuned for the multi-repo `workspace` demo; degrades
-- gracefully on the single-repo demos. LSP / Claude steps are best-effort (they
-- need gopls / the `claude` CLI) and placed late so the server has time to
-- attach. Fleet commands (<leader>cw…) prompt for input, so the tour only names
-- them — it never blocks waiting for typing.
local api = vim.api
local fn  = vim.fn

local function mod(name) local ok, m = pcall(require, name); return ok and m or nil end

-- Files to visit are inferred from the cwd layout (demo.sh cd's into it).
local function pick(globs)
  for _, g in ipairs(globs) do
    local hits = fn.glob(g, true, true)
    if #hits > 0 then return hits[1] end
  end
end
local main_file  = pick { 'services/vega/main.go', 'main.go', 'src/main.rs' }
local lib_file   = pick { 'packages/nebula/nebula.go', 'greeter.go' }
local other_file = pick { 'services/lyra/lyra.go', 'src/main.rs' }
local doc_file   = pick { 'TOUR.md', 'README.md', '*.md' }

-- ── Caption bubble ─────────────────────────────────────────────────────────────
local cap_buf, cap_win
local function caption(text)
  if not (cap_buf and api.nvim_buf_is_valid(cap_buf)) then
    cap_buf = api.nvim_create_buf(false, true)
  end
  api.nvim_buf_set_lines(cap_buf, 0, -1, false, { '  ' .. text .. '  ' })
  local w = fn.strdisplaywidth(text) + 4
  local cfg = {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = w, height = 1, row = 1, col = math.max(0, math.floor((vim.o.columns - w) / 2)),
    focusable = false, zindex = 300,
  }
  if cap_win and api.nvim_win_is_valid(cap_win) then
    api.nvim_win_set_config(cap_win, cfg)
  else
    cap_win = api.nvim_open_win(cap_buf, false, cfg)
    vim.wo[cap_win].winhighlight = 'Normal:CSMdH1,FloatBorder:CSMdH1'
  end
end

-- ── Window helpers ───────────────────────────────────────────────────────────
-- Close every float except the caption (overview / hover / pickers).
local function close_floats()
  for _, w in ipairs(api.nvim_list_wins()) do
    if w ~= cap_win and api.nvim_win_is_valid(w)
       and api.nvim_win_get_config(w).relative ~= '' then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

-- Close auxiliary terminal splits (e.g. the test runner) so they don't get
-- mistaken for the center content window by the next step.
local function close_aux_terminals()
  for _, w in ipairs(api.nvim_list_wins()) do
    local ok, b = pcall(api.nvim_win_get_buf, w)
    if ok and vim.bo[b].buftype == 'terminal' and not vim.b[b].cs_session_id then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

-- Focus the center window and open `path` there (clearing winfixbuf so it can
-- replace a Claude terminal), so files always land in the main area.
local function edit(path)
  if not path then return end
  local sh, win = mod('claudespace.shell'), nil
  if sh then pcall(function() win = sh.center(); api.nvim_set_current_win(win) end) end
  if win and api.nvim_win_is_valid(win) then pcall(function() vim.wo[win].winfixbuf = false end) end
  pcall(vim.cmd, 'edit ' .. fn.fnameescape(path))
end

local function goto_word(word)
  if fn.search('\\<' .. word .. '\\>', 'w') > 0 then vim.cmd 'normal! zz' end
end

-- ── Steps ────────────────────────────────────────────────────────────────────────
-- Each step: { delay_after_ms, caption, action }.
local steps = {
  { 1900, 'claudespace.nvim — a multi-repo workspace', function() end },

  { 2600, '\\   file tree — services/ opens to its repo roots (git status each)',
    function()
      local ft = mod('claudespace.filetree')
      -- focus_path opens the tree (if closed) and expands services/ + ancestors.
      if ft then pcall(ft.focus_path, fn.getcwd() .. '/services') end
    end },

  { 2600, '<leader>wp   repos overview — branches, active repo',
    function() local r = mod('claudespace.repos'); if r and r.show then pcall(r.show) end end },

  { 1400, '', function() close_floats() end },

  { 2200, 'open services/vega — this repo becomes the active one',
    function() edit(main_file) end },

  { 2400, 'open packages/nebula — a shared repo; go.work ties them for gopls',
    function() edit(lib_file) end },

  { 2400, 'open services/lyra — the tree\'s active-repo highlight follows',
    function() edit(other_file) end },

  { 2400, 'gopls: K hovers docs for the symbol under the cursor',
    function() edit(lib_file); goto_word('Greeter'); pcall(vim.lsp.buf.hover) end },

  { 2200, 'gd jumps to the definition — across modules',
    function()
      close_floats(); edit(main_file); goto_word('New')
      if next(vim.lsp.get_clients { bufnr = 0 }) then pcall(vim.lsp.buf.definition) end
    end },

  { 2200, '<leader>xo   symbols outline (cursor-synced)',
    function() local o = mod('claudespace.outline'); if o then pcall(o.toggle) end end },

  { 1400, '', function() local o = mod('claudespace.outline'); if o then pcall(o.toggle) end end },

  { 3000, '<leader>ru   run the active repo\'s tests',
    function()
      edit(main_file)   -- ensure the active repo (services/vega) is current
      local t = mod('claudespace.tasks'); if t and t.run then pcall(t.run, 'test') end
    end },

  { 2600, 'Fleet: <leader>cwb broadcast · cwg cross-repo grep · cwc commit-all · cwu bump shared lib',
    function() close_aux_terminals(); close_floats(); edit(main_file) end },

  -- Claude sessions boot the CLI (~2-3s); one action per step, long pauses.
  { 3600, '<leader>cn   a Claude session, bound to the active repo',
    function() local s = mod('claudespace.claude.sessions'); if s then pcall(s.new) end end },

  { 3600, '<leader>cn again   a second session joins the bottom bar',
    function() local s = mod('claudespace.claude.sessions'); if s then pcall(s.new) end end },

  { 2800, '<A-h> / <A-l>   cycle between the sessions',
    function() local s = mod('claudespace.claude.sessions'); if s then pcall(s.prev) end end },

  { 2800, '<leader>mp   markdown preview: tables, callouts, <details>',
    function()
      edit(doc_file)
      local md = mod('claudespace.mdpreview'); if md then pcall(md.enable, 0) end
    end },

  { 2200, ']l / <CR>   jump between & follow links',
    function() local md = mod('claudespace.mdpreview'); if md then pcall(md.goto_link, 1) end end },

  { 2000, '<leader>ub   theme to light…',
    function() local th = mod('claudespace.theme'); if th then th.set('light') end end },

  { 1700, '…and back to dark',
    function() local th = mod('claudespace.theme'); if th then th.set('dark') end end },

  { 3000, 'Try it:  scripts/demo.sh   ·   github.com/kriuchkov/claudespace.nvim',
    function() end },
}

local function run(i)
  local step = steps[i]
  if not step then
    vim.defer_fn(function() pcall(vim.cmd, 'qa!') end, 900)
    return
  end
  if step[2] ~= '' then caption(step[2]) end
  pcall(step[3])
  vim.defer_fn(function() run(i + 1) end, step[1])
end

-- Let the UI (and the language server) start before the tour does.
vim.defer_fn(function() run(1) end, 1600)
