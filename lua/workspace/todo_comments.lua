-- TODO/FIXME/HACK comment highlighting + jumping + telescope search.

-- ── Util ─────────────────────────────────────────────────────────────────────

local Util = {}

function Util.get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)
  if not ok then return end
  for _, k in ipairs { 'foreground', 'background', 'special' } do
    if hl[k] then hl[k] = ('#%06x'):format(hl[k]) end
  end
  return hl
end

local function rgb_linear(c)
  c = c / 255
  return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(c) return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b end

function Util.hex2linear_srgb(hex)
  hex = hex:gsub('#', '')
  return {
    r = rgb_linear(tonumber('0x' .. hex:sub(1, 2))),
    g = rgb_linear(tonumber('0x' .. hex:sub(3, 4))),
    b = rgb_linear(tonumber('0x' .. hex:sub(5, 6))),
  }
end

function Util.contrast_ratio(c1, c2)
  local l1, l2 = luminance(c1), luminance(c2)
  if l1 < l2 then l1, l2 = l2, l1 end
  return (l1 + 0.05) / (l2 + 0.05)
end

function Util.maximize_contrast(base, fg1, fg2)
  base = Util.hex2linear_srgb(base)
  return Util.contrast_ratio(base, Util.hex2linear_srgb(fg1))
       > Util.contrast_ratio(base, Util.hex2linear_srgb(fg2)) and fg1 or fg2
end

function Util.warn(msg)  vim.notify(msg, vim.log.levels.WARN,  { title = 'TodoComments' }) end
function Util.error(msg) vim.notify(msg, vim.log.levels.ERROR, { title = 'TodoComments' }) end

-- ── Config ────────────────────────────────────────────────────────────────────

local Config = {}
Config.keywords = {}
Config.options  = {}
Config.loaded   = false
Config.ns       = vim.api.nvim_create_namespace 'todo-comments'

local defaults = {
  signs         = true,
  sign_priority = 8,
  keywords = {
    FIX  = { icon = ' ', color = 'error',   alt = { 'FIXME', 'BUG', 'FIXIT', 'ISSUE' } },
    TODO = { icon = ' ', color = 'info' },
    HACK = { icon = ' ', color = 'warning' },
    WARN = { icon = ' ', color = 'warning', alt = { 'WARNING', 'XXX' } },
    PERF = { icon = ' ', alt = { 'OPTIM', 'PERFORMANCE', 'OPTIMIZE' } },
    NOTE = { icon = ' ', color = 'hint',    alt = { 'INFO' } },
    TEST = { icon = '⏲ ', color = 'test',   alt = { 'TESTING', 'PASSED', 'FAILED' } },
  },
  gui_style  = { fg = 'NONE', bg = 'BOLD' },
  merge_keywords = true,
  highlight = {
    multiline         = true,
    multiline_pattern = '^.',
    multiline_context = 10,
    before            = '',
    keyword           = 'wide',
    after             = 'fg',
    pattern           = [[.*<(KEYWORDS)\s*:]],
    comments_only     = true,
    max_line_len      = 400,
    exclude           = {},
    throttle          = 200,
  },
  colors = {
    error   = { 'DiagnosticError', 'ErrorMsg', '#DC2626' },
    warning = { 'DiagnosticWarn', 'WarningMsg', '#FBBF24' },
    info    = { 'DiagnosticInfo', '#2563EB' },
    hint    = { 'DiagnosticHint', '#10B981' },
    default = { 'Identifier', '#7C3AED' },
    test    = { 'Identifier', '#FF00FF' },
  },
  search = {
    command = 'rg',
    args    = { '--color=never', '--no-heading', '--with-filename', '--line-number', '--column' },
    pattern = [[\b(KEYWORDS):]],
  },
}

Config._options = nil

local Highlight  -- forward declaration (defined below)

function Config.setup(options)
  Config._options = options
  if vim.api.nvim_get_vvar('vim_did_enter') == 0 then
    vim.defer_fn(function() Config._setup() end, 0)
  else
    Config._setup()
  end
end

function Config._setup()
  Config.options = vim.tbl_deep_extend('force', {}, defaults, Config.options or {}, Config._options or {})
  if Config._options and Config._options.keywords and Config._options.merge_keywords == false then
    Config.options.keywords = Config._options.keywords
  end

  Config.keywords = {}
  for kw, opts in pairs(Config.options.keywords) do
    Config.keywords[kw] = kw
    for _, alt in pairs(opts.alt or {}) do Config.keywords[alt] = kw end
  end

  local function tags(kws)
    kws = kws or vim.tbl_keys(Config.keywords)
    table.sort(kws, function(a, b) return #b < #a end)
    return table.concat(kws, '|')
  end

  function Config.search_regex(kws) return Config.options.search.pattern:gsub('KEYWORDS', tags(kws)) end

  Config.hl_regex = {}
  local pats = Config.options.highlight.pattern
  pats = type(pats) == 'table' and pats or { pats }
  for _, p in pairs(pats) do
    table.insert(Config.hl_regex, (p:gsub('KEYWORDS', tags())))
  end

  Config.colors()
  Config.signs()
  Highlight.start()
  Config.loaded = true
end

function Config.signs()
  for kw, opts in pairs(Config.options.keywords) do
    vim.fn.sign_define('todo-sign-' .. kw, { text = opts.icon, texthl = 'TodoSign' .. kw })
  end
end

function Config.colors()
  local normal    = Util.get_hl 'Normal'
  local nfg       = normal and normal.foreground
  local nbg       = normal and normal.background
  local dark, light = '#000000', '#FFFFFF'
  if not nfg and not nbg then nfg, nbg = light, dark
  elseif not nfg then nfg = Util.maximize_contrast(nbg, dark, light)
  elseif not nbg then nbg = Util.maximize_contrast(nfg, dark, light) end

  local sign_hl  = Util.get_hl 'SignColumn'
  local sign_bg  = (sign_hl and sign_hl.background) and sign_hl.background or 'NONE'
  local fg_gui   = Config.options.gui_style.fg
  local bg_gui   = Config.options.gui_style.bg

  for kw, opts in pairs(Config.options.keywords) do
    local kc = opts.color or 'default'
    local hex
    if kc:sub(1, 1) == '#' then
      hex = kc
    else
      local colors = Config.options.colors[kc]
      colors = type(colors) == 'string' and { colors } or colors
      for _, c in pairs(colors) do
        if c:sub(1, 1) == '#' then hex = c; break end
        local h = Util.get_hl(c)
        if h and h.foreground then hex = h.foreground; break end
      end
    end
    if not hex then error('TodoComments: no color for ' .. kw) end
    local fg = Util.maximize_contrast(hex, nfg, nbg)
    vim.cmd('hi def TodoBg'   .. kw .. ' guibg=' .. hex    .. ' guifg=' .. fg      .. ' gui=' .. bg_gui)
    vim.cmd('hi def TodoFg'   .. kw .. ' guibg=NONE guifg=' .. hex .. ' gui=' .. fg_gui)
    vim.cmd('hi def TodoSign' .. kw .. ' guibg=' .. sign_bg .. ' guifg=' .. hex .. ' gui=NONE')
  end
end

-- ── Highlight ─────────────────────────────────────────────────────────────────

Highlight = {}
Highlight.enabled = false
Highlight.bufs    = {}
Highlight.wins    = {}
Highlight.state   = {}
Highlight.timer   = assert(vim.uv.new_timer())

function Highlight.match(str, pats)
  local max = Config.options and Config.options.highlight and Config.options.highlight.max_line_len
  if max and #str > max then return end
  pats = pats or Config.hl_regex
  if type(pats) ~= 'table' then pats = { pats } end
  for _, p in pairs(pats) do
    local m = vim.fn.matchlist(str, [[\v\C]] .. p)
    if #m > 1 and m[2] then
      local match = m[2]
      local kw    = m[3] ~= '' and m[3] or m[2]
      local s     = str:find(match, 1, true)
      return s, s + #match, kw
    end
  end
end

function Highlight.is_comment(buf, row, col)
  if vim.treesitter.highlighter.active[buf] then
    for _, c in ipairs(vim.treesitter.get_captures_at_pos(buf, row, col)) do
      if c.capture == 'comment' then return true end
    end
  else
    local win = vim.fn.bufwinid(buf)
    return win ~= -1 and vim.api.nvim_win_call(win, function()
      for _, i1 in ipairs(vim.fn.synstack(row + 1, col)) do
        local n1 = vim.fn.synIDattr(i1, 'name')
        local n2 = vim.fn.synIDattr(vim.fn.synIDtrans(i1), 'name')
        if n1 == 'Comment' or n2 == 'Comment' then return true end
      end
    end)
  end
end

local function add_hl(buf, line, from, to, hl)
  vim.api.nvim_buf_set_extmark(buf, Config.ns, line, from, { end_col = to, hl_group = hl, priority = 500 })
end

function Highlight.get_state(buf)
  if not Highlight.state[buf] then Highlight.state[buf] = { valid = {} } end
  return Highlight.state[buf]
end

function Highlight.invalidate(buf, first, last)
  local s = Highlight.get_state(buf)
  if first == 0 and last == -1 then
    s.valid = {}
  else
    local ctx = Config.options.highlight.multiline_context
    first = math.max(first - ctx, 0)
    last  = math.min(last + ctx, vim.api.nvim_buf_line_count(buf))
    for i = first, last do s.valid[i] = nil end
  end
  Highlight.update()
end

function Highlight.update()
  if not Highlight.timer:is_active() then
    Highlight.timer:start(Config.options.highlight.throttle, 0, vim.schedule_wrap(Highlight._update))
  end
end

function Highlight._update()
  for buf, state in pairs(Highlight.state) do
    if vim.api.nvim_buf_is_valid(buf) then
      local todo = {}
      for _, win in pairs(vim.fn.win_findbuf(buf)) do
        local f = vim.fn.line('w0', win) - 1
        local l = vim.fn.line('w$', win)
        for i = f, l do
          if not state.valid[i] then todo[i] = true end
        end
      end
      local dirty = vim.tbl_keys(todo); table.sort(dirty)
      if #dirty > 0 then
        local i = 1
        while i <= #dirty do
          local f, l = dirty[i], dirty[i]
          while dirty[i + 1] == dirty[i] + 1 do i = i + 1; l = dirty[i] end
          Highlight.highlight(buf, f, l)
          for j = f, l do state.valid[j] = true end
          i = i + 1
        end
      end
    else
      Highlight.state[buf] = nil
    end
  end
end

function Highlight.highlight(buf, first, last)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, Config.ns, first, last + 1)
  for _, sign in pairs(vim.fn.sign_getplaced(buf, { group = 'todo-signs' })[1].signs) do
    if sign.lnum - 1 >= first and sign.lnum - 1 <= last then
      vim.fn.sign_unplace('todo-signs', { buffer = buf, id = sign.id })
    end
  end
  local lines     = vim.api.nvim_buf_get_lines(buf, first, last + 1, false)
  local last_match
  for l, line in ipairs(lines) do
    local ok, s, finish, kw = pcall(Highlight.match, line)
    local lnum = first + l - 1
    if ok and s then
      if Config.options.highlight.comments_only and not Highlight.is_quickfix(buf)
          and not Highlight.is_comment(buf, lnum, s - 1) then
        kw = nil
      else
        last_match = { kw = kw, start = s }
      end
    end
    local is_ml = false
    if not kw and last_match and Config.options.highlight.multiline then
      if Highlight.is_comment(buf, lnum, last_match.start)
          and line:find(Config.options.highlight.multiline_pattern, last_match.start) then
        kw, s, finish, is_ml = last_match.kw, last_match.start, last_match.start, true
      else
        last_match = nil
      end
    end
    if kw then kw = Config.keywords[kw] or kw end
    local opts = Config.options.keywords[kw]
    if opts then
      s      = s - 1
      finish = finish - 1
      local fg_hl = 'TodoFg' .. kw
      local bg_hl = 'TodoBg' .. kw
      local hl    = Config.options.highlight
      if not is_ml then
        if hl.before == 'fg' then add_hl(buf, lnum, 0, s, fg_hl)
        elseif hl.before == 'bg' then add_hl(buf, lnum, 0, s, bg_hl) end
        if hl.keyword == 'wide' or hl.keyword == 'wide_bg' then
          add_hl(buf, lnum, math.max(s - 1, 0), finish + 1, bg_hl)
        elseif hl.keyword == 'wide_fg' then
          add_hl(buf, lnum, math.max(s - 1, 0), finish + 1, fg_hl)
        elseif hl.keyword == 'bg' then add_hl(buf, lnum, s, finish, bg_hl)
        elseif hl.keyword == 'fg' then add_hl(buf, lnum, s, finish, fg_hl) end
      end
      if hl.after == 'fg'     then add_hl(buf, lnum, finish, #line, fg_hl)
      elseif hl.after == 'bg' then add_hl(buf, lnum, finish, #line, bg_hl) end
      if not is_ml then
        local show = opts.signs ~= nil and opts.signs or Config.options.signs
        if show then
          vim.fn.sign_place(0, 'todo-signs', 'todo-sign-' .. kw, buf,
            { lnum = lnum + 1, priority = Config.options.sign_priority })
        end
      end
    end
  end
end

function Highlight.is_float(win)
  local c = vim.api.nvim_win_get_config(win)
  return c and c.relative and c.relative ~= ''
end
function Highlight.is_quickfix(buf) return vim.bo[buf].buftype == 'quickfix' end
function Highlight.is_valid_buf(buf)
  local bt = vim.bo[buf].buftype
  if bt ~= '' and bt ~= 'quickfix' then return false end
  return not vim.tbl_contains(Config.options.highlight.exclude, vim.bo[buf].filetype)
end
function Highlight.is_valid_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.fn.getcmdwintype() ~= '' then return false end
  if Highlight.is_float(win) then return false end
  return Highlight.is_valid_buf(vim.api.nvim_win_get_buf(win))
end

function Highlight.attach(win, force)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return end
  if not force and not Highlight.is_valid_win(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  Highlight.get_state(buf)
  if not Highlight.bufs[buf] then
    vim.api.nvim_buf_attach(buf, false, {
      on_reload = function()
        if not Highlight.enabled or not Highlight.is_valid_buf(buf) then return end
        Highlight.invalidate(buf, 0, -1)
      end,
      on_lines = function(_, _, _, first, _, last_new)
        if not Highlight.enabled then return true end
        if not Highlight.is_valid_buf(buf) then return true end
        Highlight.invalidate(buf, first, last_new)
      end,
      on_detach = function()
        Highlight.state[buf] = nil
        Highlight.bufs[buf]  = nil
      end,
    })
    local hl_active = require('vim.treesitter.highlighter').active[buf]
    if hl_active then
      hl_active.tree:register_cbs({
        on_bytes        = function(_, _, row) Highlight.invalidate(buf, row, row + 1) end,
        on_changedtree  = function(changes)
          for _, ch in ipairs(changes or {}) do Highlight.invalidate(buf, ch[1], ch[3] + 1) end
        end,
      })
    end
    Highlight.bufs[buf] = true
  end
  if not Highlight.wins[win] then
    Highlight.wins[win] = true
    Highlight.update()
  end
end

function Highlight.stop()
  Highlight.enabled = false
  pcall(vim.api.nvim_clear_autocmds, { group = 'Todo' })
  pcall(vim.api.nvim_del_augroup_by_name, 'Todo')
  Highlight.wins = {}
  vim.fn.sign_unplace 'todo-signs'
  for buf in pairs(Highlight.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, Config.ns, 0, -1)
    end
  end
  Highlight.bufs = {}
end

function Highlight.start()
  if Highlight.enabled then Highlight.stop() end
  Highlight.enabled = true
  local grp = vim.api.nvim_create_augroup('Todo', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinNew' }, { group = grp,
    callback = function() Highlight.attach() end })
  vim.api.nvim_create_autocmd('WinScrolled', { group = grp,
    callback = function() Highlight.update() end })
  vim.api.nvim_create_autocmd({ 'ColorScheme' }, { group = grp,
    callback = function() vim.defer_fn(Config.colors, 10) end })
  vim.api.nvim_create_autocmd('User', { group = grp, pattern = 'CSThemeApplied',
    callback = function() vim.defer_fn(Config.colors, 10) end })
  for _, win in pairs(vim.api.nvim_list_wins()) do Highlight.attach(win) end
end

-- ── Jump ──────────────────────────────────────────────────────────────────────

local Jump = {}

local function do_jump(up, opts)
  opts = opts or {}
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(win)
  local from = up and (pos[1] - 1) or (pos[1] + 1)
  local to   = up and 1 or vim.api.nvim_buf_line_count(buf)
  for l = from, to, up and -1 or 1 do
    local line = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1] or ''
    local ok, s, _, kw = pcall(Highlight.match, line)
    if ok and s then
      if Config.options.highlight.comments_only and Highlight.is_comment(buf, l - 1, s) == false then
        kw = nil
      end
    end
    if kw and opts.keywords and #opts.keywords > 0
        and not vim.tbl_contains(opts.keywords, kw) then kw = nil end
    if kw then vim.api.nvim_win_set_cursor(win, { l, s - 1 }); return end
  end
  Util.warn 'No more todo comments to jump to'
end

function Jump.next(opts) do_jump(false, opts) end
function Jump.prev(opts) do_jump(true,  opts) end

-- ── Search / Telescope ────────────────────────────────────────────────────────

local Search = {}

local function kw_filter(kws_str)
  local all = vim.tbl_keys(Config.keywords)
  if not kws_str then return all end
  local filters = vim.split(kws_str, ',')
  return vim.tbl_filter(function(k) return vim.tbl_contains(filters, k) end, all)
end

function Search.process(lines)
  local results = {}
  for _, line in pairs(lines) do
    local file, row, col, text = line:match '^(.+):(%d+):(%d+):(.*)$'
    if file then
      local item = { filename = file, lnum = tonumber(row), col = tonumber(col), line = text }
      local s, finish, kw = Highlight.match(text)
      if s then
        kw       = Config.keywords[kw] or kw
        item.tag = kw
        item.text    = vim.trim(text:sub(s))
        item.message = vim.trim(text:sub(finish + 1))
        table.insert(results, item)
      end
    end
  end
  return results
end

function Search.search(cb, opts)
  opts = opts or {}
  opts.cwd = vim.fn.fnamemodify(opts.cwd or '.', ':p')
  if not Config.loaded then Util.error "todo-comments isn't loaded. Did you run setup()?"; return end
  local cmd = Config.options.search.command
  if vim.fn.executable(cmd) ~= 1 then Util.error(cmd .. ' was not found on your path'); return end
  local ok, Job = pcall(require, 'plenary.job')
  if not ok then Util.error 'search requires plenary.nvim'; return end
  local args = {}
  vim.list_extend(args, Config.options.search.args)
  vim.list_extend(args, { Config.search_regex(kw_filter(opts.keywords)), opts.cwd })
  Job:new({
    command = cmd, args = args,
    on_exit = vim.schedule_wrap(function(j, code)
      if code == 2 then Util.error(cmd .. ' failed: ' .. table.concat(j:stderr_result(), '\n')) end
      if code == 1 and not opts.disable_not_found_warnings then Util.warn 'no todos found' end
      cb(Search.process(j:result()))
    end),
  }):start()
end

local function parse_opts(opts)
  if not opts or type(opts) ~= 'string' then return opts end
  return { keywords = opts:match 'keywords=(%S*)', cwd = opts:match 'cwd=(%S*)' }
end

function Search.setqflist(opts)  Search.setlist(opts, false) end
function Search.setloclist(opts) Search.setlist(opts, true)  end
function Search.setlist(opts, loc)
  opts = parse_opts(opts) or {}
  opts.open = (opts.open ~= nil and { opts.open } or { true })[1]
  Search.search(function(results)
    if loc then
      vim.fn.setloclist(0, {}, ' ', { title = 'Todo', id = '$', items = results })
    else
      vim.fn.setqflist({}, ' ', { title = 'Todo', id = '$', items = results })
    end
    if opts.open then vim.cmd(loc and 'lopen' or 'copen') end
    local win = vim.fn.getqflist { winid = true }
    if win.winid ~= 0 then Highlight.attach(win.winid, true) end
  end, opts)
end

-- ── Telescope extension ───────────────────────────────────────────────────────

local function register_telescope()
  local ok, telescope = pcall(require, 'telescope')
  if not ok then return end
  local make_entry = require 'telescope.make_entry'
  local pickers    = require 'telescope.builtin'

  local function todo_picker(opts)
    opts = opts or {}
    opts.vimgrep_arguments = { Config.options.search.command }
    vim.list_extend(opts.vimgrep_arguments, Config.options.search.args)
    opts.search      = Config.search_regex(kw_filter(opts.keywords))
    opts.prompt_title = 'Find Todo'
    opts.use_regex   = true
    local base_maker = make_entry.gen_from_vimgrep(opts)
    opts.entry_maker = function(line)
      local ret = base_maker(line)
      ret.display = function(entry)
        local disp = ('%s:%s:%s '):format(entry.filename, entry.lnum, entry.col)
        local text = entry.text
        local s, finish, kw = Highlight.match(text)
        local hl = {}
        if s then
          kw = Config.keywords[kw] or kw
          local icon = (Config.options.keywords[kw] or {}).icon or ' '
          disp = icon .. ' ' .. disp
          table.insert(hl, { { 0, #icon + 1 }, 'TodoFg' .. kw })
          text = vim.trim(text:sub(s))
          table.insert(hl, { { #disp, #disp + finish - s + 2 }, 'TodoBg' .. kw })
          table.insert(hl, { { #disp + finish - s + 1, #disp + finish + 1 + #text }, 'TodoFg' .. kw })
          disp = disp .. ' ' .. text
        end
        return disp, hl
      end
      return ret
    end
    pickers.grep_string(opts)
  end

  telescope.register_extension { exports = { ['todo-comments'] = todo_picker, todo = todo_picker } }
end

-- ── Public API ────────────────────────────────────────────────────────────────

local M = {}

function M.setup(opts)
  Config.setup(opts)
  register_telescope()
  -- register user commands matching the original plugin
  vim.api.nvim_create_user_command('TodoQuickFix',   function(o) Search.setqflist(o.args)  end, { nargs = '?' })
  vim.api.nvim_create_user_command('TodoLocList',    function(o) Search.setloclist(o.args) end, { nargs = '?' })
  vim.api.nvim_create_user_command('TodoTelescope',  function(o)
    require('telescope').extensions['todo-comments'].todo(parse_opts(o.args) or {})
  end, { nargs = '?' })
  vim.api.nvim_create_user_command('TodoTrouble',    function()
    require('trouble').open { mode = 'todo', focus = true }
  end, {})
  vim.api.nvim_create_user_command('WSTodos', function(o)
    M.workspace(parse_opts(o.args))
  end, { nargs = '?' })
end

M.jump_next = Jump.next
M.jump_prev = Jump.prev
M.enable    = Highlight.start
M.disable   = Highlight.stop

-- ── workspace: workspace / repo-scoped TODO listing ─────────────────────────

-- Directories to search: every repo in a multi-repo workspace, else the active
-- repo's root; falls back to the cwd when workspace.repos isn't available.
local function scope_dirs()
  local ok, repos = pcall(require, 'workspace.repos')
  if ok and repos.list then
    if repos.is_multi and repos.is_multi() then
      local dirs = {}
      for _, m in ipairs(repos.list() or {}) do
        if m.abspath then dirs[#dirs + 1] = m.abspath end
      end
      if #dirs > 0 then return dirs, true end
    end
    local a = repos.active and repos.active()
    if a and a.abspath then return { a.abspath }, false end
  end
  return { vim.fn.getcwd() }, false
end

-- Sidebar TODO panel (activity-bar slot, like the diagnostics panel): grouped
-- by file, <CR> opens the file at the TODO in the center window.
local List = {
  ns = vim.api.nvim_create_namespace 'cs_todolist',
  win = nil, buf = nil, anchor = nil, at = {}, keywords = nil,
}
local WIDTH = 44

local function rel_to(dirs, file)
  for _, d in ipairs(dirs) do
    local p = d:sub(-1) == '/' and d or (d .. '/')
    if file:sub(1, #p) == p then return file:sub(#p + 1) end
  end
  return vim.fn.fnamemodify(file, ':~')
end

local function render_list(items, dirs, title)
  local api = vim.api
  if not (List.buf and api.nvim_buf_is_valid(List.buf)) then return end
  table.sort(items, function(a, b)
    if a.filename ~= b.filename then return a.filename < b.filename end
    return a.lnum < b.lnum
  end)

  local lines, hls = {}, {}
  List.at = {}
  local function add(s) lines[#lines + 1] = s end
  local function hl(group, s, e) hls[#hls + 1] = { #lines - 1, s, e, group } end

  local last
  for _, it in ipairs(items) do
    if it.filename ~= last then
      last = it.filename
      if #lines > 0 then add '' end
      add(' ' .. vim.fn.strcharpart(rel_to(dirs, it.filename), 0, WIDTH - 2))
      hl('Directory', 0, -1)
      List.at[#lines] = { filename = it.filename, lnum = 1, col = 1 }
    end
    local kw   = it.tag or 'TODO'
    local icon = (Config.options.keywords[kw] or {}).icon or ''
    local head = '  ' .. icon .. kw
    local ln   = ' ' .. it.lnum .. '  '
    local msg  = it.message ~= '' and it.message or vim.trim(it.text or '')
    add(vim.fn.strcharpart(head .. ln .. msg, 0, WIDTH - 1))
    List.at[#lines] = it
    hl('TodoFg' .. kw, 2, #head)
    hl('NonText', #head, #head + #ln)
  end
  if #items == 0 then add ' (no todos found)'; hl('Comment', 0, -1) end

  vim.bo[List.buf].modifiable = true
  api.nvim_buf_set_lines(List.buf, 0, -1, false, lines)
  vim.bo[List.buf].modifiable = false
  api.nvim_buf_clear_namespace(List.buf, List.ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_add_highlight(List.buf, List.ns, h[4], h[1], h[2], h[3])
  end
  if List.win and api.nvim_win_is_valid(List.win) then
    vim.wo[List.win].winbar =
      ('%%#Title# %s  %d %%#CSInfo# <CR> open  r refresh  q close'):format(title, #items)
  end
end

local function search_all(cb)
  local dirs, multi = scope_dirs()
  local title = multi and 'WORKSPACE TODOS' or 'REPO TODOS'
  local all, remaining = {}, #dirs
  for _, dir in ipairs(dirs) do
    Search.search(function(results)
      vim.list_extend(all, results)
      remaining = remaining - 1
      if remaining == 0 then cb(all, dirs, title) end
    end, { cwd = dir, keywords = List.keywords, disable_not_found_warnings = true })
  end
end

local function jump_to()
  local it = List.at[vim.api.nvim_win_get_cursor(List.win)[1]]
  if not it then return end
  vim.api.nvim_set_current_win(require('workspace.shell').center())
  vim.cmd('edit ' .. vim.fn.fnameescape(it.filename))
  pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
  vim.cmd 'normal! zz'
end

function M.refresh() search_all(render_list) end

-- Shared teardown for q, :q and sidebar-driven closes: wipe the scratch buffer
-- (they'd pile up hidden otherwise) and un-mark the activity-bar icon.
local function on_panel_closed()
  List.win = nil
  if List.buf and vim.api.nvim_buf_is_valid(List.buf) then
    pcall(vim.api.nvim_buf_delete, List.buf, { force = true })
  end
  List.buf = nil
  pcall(function() require('workspace.sidebar').deactivated 'todo' end)
end

function M.close_panel()
  if List.win and vim.api.nvim_win_is_valid(List.win) then
    pcall(vim.api.nvim_win_close, List.win, true)  -- WinClosed runs the teardown
  else
    on_panel_closed()
  end
end

-- Fallback anchor when opened via keymap/command instead of the activity bar.
local function default_anchor()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'cs_activitybar' then return w end
  end
end

function M.open_panel(anchor_win, keywords)
  local api = vim.api
  List.keywords = keywords
  if List.win and api.nvim_win_is_valid(List.win) then
    api.nvim_set_current_win(List.win)
    M.refresh()
    return
  end
  List.buf = api.nvim_create_buf(false, true)
  vim.bo[List.buf].buftype   = 'nofile'
  vim.bo[List.buf].bufhidden = 'hide'
  vim.bo[List.buf].swapfile  = false
  vim.bo[List.buf].filetype  = 'cs_todolist'

  anchor_win = anchor_win or default_anchor()
  if anchor_win and api.nvim_win_is_valid(anchor_win) then List.anchor = anchor_win end
  if List.anchor and api.nvim_win_is_valid(List.anchor) then
    api.nvim_set_current_win(List.anchor)
    vim.cmd 'rightbelow vsplit'
  else
    List.anchor = nil
    vim.cmd 'topleft vsplit'
  end
  List.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(List.win, List.buf)
  api.nvim_win_set_width(List.win, WIDTH)
  local wo = vim.wo[List.win]
  wo.number = false; wo.relativenumber = false; wo.signcolumn = 'no'
  wo.wrap = false; wo.cursorline = true; wo.winfixwidth = true
  wo.winbar = '%#Title# TODOS %#CSInfo# searching…'
  -- workspace.winbar wipes nofile winbars on WinEnter unless flagged.
  pcall(api.nvim_win_set_var, List.win, 'cs_winbar', true)

  local o = { buffer = List.buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', jump_to,       o)
  vim.keymap.set('n', 'r',    M.refresh,     o)
  vim.keymap.set('n', 'q',    M.close_panel, o)

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(List.win), once = true,
    callback = vim.schedule_wrap(on_panel_closed),
  })
  M.refresh()
end

-- List TODO/FIX/HACK/… comments across the current workspace (all repos) or, in
-- a single repo, that repo's root — in the left sidebar panel.
function M.workspace(opts)
  M.open_panel(nil, opts and opts.keywords or nil)
end

return M
