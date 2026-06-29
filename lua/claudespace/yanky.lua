-- Clipboard ring: cycle history, persist via shada, flash highlight on put/yank.

-- ── Config ────────────────────────────────────────────────────────────────────

local Config = {
  options = {
    ring = {
      history_length             = 100,
      storage                    = 'shada',
      sync_with_numbered_registers = true,
      ignore_registers           = { '_' },
      cancel_event               = 'update',
      update_register_on_cycle   = false,
      permanent_wrapper          = nil,
    },
    system_clipboard = { sync_with_ring = true, clipboard_register = nil },
    highlight        = { on_put = true, on_yank = true, timer = 500 },
    preserve_cursor_position = { enabled = true },
    picker = { select = { action = nil } },
  },
}

function Config.setup(opts)
  Config.options = vim.tbl_deep_extend('force', Config.options, opts or {})
end

-- ── Storage backends ──────────────────────────────────────────────────────────

local ShadaStorage = {}  -- persists via vim.g.YANKY_HISTORY → shada file

function ShadaStorage.setup() end

function ShadaStorage.push(item)
  local copy = vim.deepcopy(vim.g.YANKY_HISTORY or {})
  table.insert(copy, 1, item)
  if #copy > Config.options.ring.history_length then table.remove(copy) end
  vim.g.YANKY_HISTORY = copy
end

function ShadaStorage.get(n) return (vim.g.YANKY_HISTORY or {})[n] end
function ShadaStorage.length() return #(vim.g.YANKY_HISTORY or {}) end
function ShadaStorage.all() return vim.g.YANKY_HISTORY or {} end
function ShadaStorage.clear() vim.g.YANKY_HISTORY = {} end

function ShadaStorage.delete(index)
  local copy = vim.deepcopy(vim.g.YANKY_HISTORY or {})
  table.remove(copy, index)
  vim.g.YANKY_HISTORY = copy
end

local MemStorage = { state = {} }  -- fallback: in-process only

function MemStorage.setup() end

function MemStorage.push(item)
  table.insert(MemStorage.state, 1, item)
  if #MemStorage.state > Config.options.ring.history_length then table.remove(MemStorage.state) end
end

function MemStorage.get(n) return MemStorage.state[n] end
function MemStorage.length() return #MemStorage.state end
function MemStorage.all() return MemStorage.state end
function MemStorage.clear() MemStorage.state = {} end
function MemStorage.delete(index) table.remove(MemStorage.state, index) end

-- ── Utils ─────────────────────────────────────────────────────────────────────

local Utils = {}

function Utils.is_osc52_active()
  return vim.g.clipboard and vim.g.clipboard.name == 'OSC 52'
end

function Utils.get_default_register()
  if Utils.is_osc52_active() then return '"' end
  local flags = vim.split(vim.api.nvim_get_option_value('clipboard', {}), ',')
  local reg = '"'
  if vim.tbl_contains(flags, 'unnamed')    then reg = '*' end
  if vim.tbl_contains(flags, 'unnamedplus') then reg = '+' end
  if reg ~= '"' then
    local tool = vim.fn['provider#clipboard#Executable']()
    if not tool or tool == '' then return '"' end
  end
  return reg
end

function Utils.get_system_register()
  local flags = vim.split(vim.api.nvim_get_option_value('clipboard', {}), ',')
  return vim.tbl_contains(flags, 'unnamedplus') and '+' or '*'
end

function Utils.get_register(reg)
  reg = reg or vim.v.register
  if Utils.is_osc52_active() and (reg == '+' or reg == '*') then return '"' end
  return reg
end

function Utils.get_register_info(reg)
  local ok1, contents = pcall(vim.fn.getreg, reg)
  local ok2, regtype  = pcall(vim.fn.getregtype, reg)
  if not ok1 or not ok2 then return nil end
  return { regcontents = contents, regtype = regtype }
end

function Utils.use_temporary_register(reg, info, callback)
  local saved = Utils.get_register_info(reg)
  vim.fn.setreg(reg, info.regcontents, info.regtype)
  callback()
  vim.fn.setreg(reg, saved.regcontents, saved.regtype)
end

-- ── History ───────────────────────────────────────────────────────────────────

local History = { storage = nil, position = 1 }

function History.setup()
  if Config.options.ring.storage == 'shada' then
    History.storage = ShadaStorage
  else
    History.storage = MemStorage
  end
  History.storage.setup()
end

function History.push(item)
  if not item then return end
  local prev = History.storage.get(1)
  if prev and prev.regcontents == item.regcontents and prev.regtype == item.regtype then return end
  History.storage.push(item)
  History.sync_with_numbered_registers()
end

function History.sync_with_numbered_registers()
  if Config.options.ring.sync_with_numbered_registers then
    for i = 1, math.min(History.storage.length(), 9) do
      local reg = History.storage.get(i)
      vim.fn.setreg(i, reg.regcontents, reg.regtype)
    end
  end
end

function History.first()
  return History.storage.length() > 0 and History.storage.get(1) or nil
end

function History.skip()   History.position = History.position + 1 end
function History.reset()  History.position = 0 end
function History.all()    return History.storage.all() end

function History.next()
  local np = History.position + 1
  if np > History.storage.length() then return nil end
  History.position = np
  return History.storage.get(History.position)
end

function History.previous()
  if History.position == 1 then return nil end
  History.position = History.position - 1
  return History.storage.get(History.position)
end

function History.clear()
  History.storage.clear()
  History.position = 1
end

function History.delete(index)
  History.storage.delete(index)
end

-- ── Highlight ─────────────────────────────────────────────────────────────────

vim.hl = vim.hl or vim.highlight  -- compat Neovim <0.12

local Highlight = {}

local function hl_op(opts)
  if vim.hl.hl_op then return vim.hl.hl_op(opts) end
  return vim.hl.on_yank(opts)
end

function Highlight.setup()
  local cfg = Config.options.highlight
  if cfg.on_put then
    Highlight.ns    = vim.api.nvim_create_namespace 'yanky.put'
    Highlight.timer = vim.loop.new_timer()
    vim.api.nvim_set_hl(0, 'YankyPut', { link = 'Search', default = true })
  end
  if cfg.on_yank then
    vim.api.nvim_create_autocmd('TextYankPost', {
      pattern  = '*',
      callback = function() pcall(hl_op, { higroup = 'YankyYanked', timeout = cfg.timer }) end,
    })
    vim.api.nvim_set_hl(0, 'YankyYanked', { link = 'Search', default = true })
  end
end

function Highlight.highlight_put(state)
  if not Config.options.highlight.on_put then return end
  Highlight.timer:stop()
  vim.api.nvim_buf_clear_namespace(0, Highlight.ns, 0, -1)
  local s = vim.api.nvim_buf_get_mark(0, '[')
  local e = vim.api.nvim_buf_get_mark(0, ']')
  vim.hl.range(0, Highlight.ns, 'YankyPut',
    { s[1] - 1, s[2] }, { e[1] - 1, e[2] },
    { regtype = vim.fn.getregtype(state.register), inclusive = true })
  Highlight.timer:start(Config.options.highlight.timer, 0, vim.schedule_wrap(function()
    vim.api.nvim_buf_clear_namespace(0, Highlight.ns, 0, -1)
  end))
end

-- ── PreserveCursor ────────────────────────────────────────────────────────────

local PreserveCursor = { state = { pos = nil, win = nil } }

function PreserveCursor.setup() end

function PreserveCursor.on_yank()
  if not Config.options.preserve_cursor_position.enabled then return end
  if PreserveCursor.state.pos then
    vim.fn.setpos('.', PreserveCursor.state.pos)
    vim.fn.winrestview(PreserveCursor.state.win)
    PreserveCursor.state = { pos = nil, win = nil }
  end
end

function PreserveCursor.yank()
  if not Config.options.preserve_cursor_position.enabled then return end
  PreserveCursor.state = { pos = vim.fn.getpos('.'), win = vim.fn.winsaveview() }
  vim.api.nvim_buf_attach(0, false, {
    on_lines = function()
      PreserveCursor.state = { pos = nil, win = nil }
      return true
    end,
  })
end

-- ── SystemClipboard ───────────────────────────────────────────────────────────

local SystemClipboard = { state = { reg_on_lost = nil } }

function SystemClipboard.setup()
  local cfg = Config.options.system_clipboard
  cfg.clipboard_register = cfg.clipboard_register or Utils.get_system_register()
  if not cfg.sync_with_ring then return end

  local focused_real, focused_delayed = true, true
  local timer
  vim.api.nvim_create_autocmd({ 'FocusGained', 'FocusLost' }, {
    group = vim.api.nvim_create_augroup('YankySyncClipboard', { clear = true }),
    callback = function(ev)
      if ev.event == 'FocusLost' then
        focused_real = false
        if timer then timer:stop() end
        timer = vim.defer_fn(function()
          if not focused_real then
            SystemClipboard.on_focus_lost()
            focused_delayed = false
          end
        end, 500)
      else
        if not focused_delayed then SystemClipboard.on_focus_gained() end
        focused_real, focused_delayed = true, true
      end
    end,
  })
end

function SystemClipboard.on_focus_lost()
  SystemClipboard.state.reg_on_lost =
    Utils.get_register_info(Config.options.system_clipboard.clipboard_register)
end

function SystemClipboard.on_focus_gained()
  local new = Utils.get_register_info(Config.options.system_clipboard.clipboard_register)
  if not new then SystemClipboard.state.reg_on_lost = nil; return end
  local old = SystemClipboard.state.reg_on_lost
  if old and not vim.deep_equal(old, new) then History.push(new) end
  SystemClipboard.state.reg_on_lost = nil
end

-- ── Picker ────────────────────────────────────────────────────────────────────

local Picker = {}

function Picker.setup()
  vim.api.nvim_create_user_command('YankyClearHistory', function() History.clear() end, {})
  vim.api.nvim_create_user_command('YankyRingHistory', Picker.select_in_history, {})
end

function Picker.select_in_history()
  local M = require 'claudespace.yanky'
  local history = {}
  for idx, v in pairs(History.all()) do
    v.history_index = idx
    history[idx] = v
  end
  local action = Config.options.picker.select.action
    or function(entry)
      if not entry then return end
      Utils.use_temporary_register(Utils.get_default_register(), entry, function()
        M.put('p', false)
      end)
    end
  vim.ui.select(history, {
    prompt      = 'Ring history> ',
    format_item = function(item) return item.regcontents and item.regcontents:gsub('\n', '\\n') or '' end,
  }, action)
end

-- ── Main ──────────────────────────────────────────────────────────────────────

local M = {}

M.direction = { FORWARD = 1, BACKWARD = -1 }
M.type = {
  PUT_BEFORE     = 'P',  PUT_AFTER      = 'p',
  GPUT_BEFORE    = 'gP', GPUT_AFTER     = 'gp',
  PUT_INDENT_AFTER  = ']p', PUT_INDENT_BEFORE = '[p',
}

M.ring = { state = nil, is_cycling = false, callback = nil }

function M.setup(opts)
  Config.setup(opts)
  History.setup()
  SystemClipboard.setup()
  Highlight.setup()
  PreserveCursor.setup()
  Picker.setup()

  local grp = vim.api.nvim_create_augroup('Yanky', { clear = true })
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = grp, pattern = '*',
    callback = function() M.on_yank() end,
  })
  if vim.v.vim_did_enter == 1 then
    M.init_history()
  else
    vim.api.nvim_create_autocmd('VimEnter', { group = grp, pattern = '*', callback = M.init_history })
  end
end

function M.init_history()
  History.push(Utils.get_register_info(Utils.get_default_register()))
  History.sync_with_numbered_registers()
end

local function do_put(state, _)
  if state.is_visual then vim.cmd [[execute "normal! \<esc>"]] end
  local ok, val = pcall(vim.cmd, ('silent normal! %s"%s%s%s'):format(
    state.is_visual and 'gv' or '',
    state.register ~= '=' and state.register
      or ('=' .. vim.api.nvim_replace_termcodes('<CR>', true, false, true)),
    state.count,
    state.type
  ))
  if not ok then vim.notify(val, vim.log.levels.WARN); return end
  Highlight.highlight_put(state)
end

function M.put(type, is_visual, callback)
  if not vim.tbl_contains(vim.tbl_values(M.type), type) then
    vim.notify('Invalid type ' .. type, vim.log.levels.ERROR); return
  end
  M.ring.state     = nil
  M.ring.is_cycling = false
  M.ring.callback  = callback or do_put
  if Config.options.ring.permanent_wrapper then
    M.ring.callback = Config.options.ring.permanent_wrapper(M.ring.callback)
  end
  if vim.v.register == '=' then
    local entry = Utils.get_register_info '='
    entry.filetype = vim.bo.filetype
    History.push(entry)
  end
  M.init_ring(type, Utils.get_register(), vim.v.count, is_visual, M.ring.callback)
end

function M.clear_ring()
  if M.can_cycle() and M.ring.state.augroup then
    vim.api.nvim_clear_autocmds { group = M.ring.state.augroup }
  end
  M.ring.state     = nil
  M.ring.is_cycling = false
end

function M.attach_cancel()
  if Config.options.ring.cancel_event == 'move' then
    M.ring.state.augroup = vim.api.nvim_create_augroup('YankyRingClear', { clear = true })
    vim.schedule(function()
      vim.api.nvim_create_autocmd('CursorMoved', {
        group = M.ring.state.augroup, buffer = 0, callback = M.clear_ring,
      })
    end)
  else
    vim.api.nvim_buf_attach(0, false, {
      on_lines = function() M.clear_ring(); return true end,
    })
  end
end

function M.init_ring(type, reg, count, is_visual, callback)
  reg = (reg ~= '"' and reg ~= '_') and reg or Utils.get_default_register()
  local content = vim.fn.getreg(reg)
  if not content or content == '' then
    vim.notify(('Register "%s" is empty'):format(reg), vim.log.levels.WARN); return
  end
  local state = {
    type = type, register = reg,
    count = count > 0 and count or 1,
    is_visual = is_visual, use_repeat = callback == nil,
  }
  if callback then callback(state, do_put) end
  M.ring.state     = state
  M.ring.is_cycling = false
  M.attach_cancel()
end

function M.can_cycle() return M.ring.state ~= nil end

function M.cycle(direction)
  if not M.can_cycle() then
    vim.notify('Your last action was not put, ignoring cycle', vim.log.levels.INFO); return
  end
  direction = direction or M.direction.FORWARD
  if M.ring.state.augroup then
    vim.api.nvim_clear_autocmds { group = M.ring.state.augroup }
  end
  if not M.ring.is_cycling then
    History.reset()
    local reg = Utils.get_register_info(M.ring.state.register)
    local first = History.first()
    if first and reg.regcontents == first.regcontents and reg.regtype == first.regtype then
      History.skip()
    end
  end
  local state = M.ring.state
  local next_content
  if direction == M.direction.FORWARD then
    next_content = History.next()
    if not next_content then
      vim.notify('Reached oldest item', vim.log.levels.INFO)
      M.attach_cancel(); return
    end
  else
    next_content = History.previous()
    if not next_content then
      vim.notify('Reached first item', vim.log.levels.INFO)
      M.attach_cancel(); return
    end
  end
  M.ring.state.register = M.ring.state.register ~= '='
    and M.ring.state.register or Utils.get_default_register()
  Utils.use_temporary_register(M.ring.state.register, next_content, function()
    if state.use_repeat then
      local ok, val = pcall(vim.cmd, 'silent normal! u.')
      if not ok then vim.notify(val, vim.log.levels.WARN); M.attach_cancel(); return end
      Highlight.highlight_put(state)
    else
      local ok, val = pcall(vim.cmd, 'silent normal! u')
      if not ok then vim.notify(val, vim.log.levels.WARN); M.attach_cancel(); return end
      M.ring.callback(state, do_put)
    end
  end)
  if Config.options.ring.update_register_on_cycle then
    vim.fn.setreg(state.register, next_content.regcontents, next_content.regtype)
  end
  M.ring.is_cycling = true
  M.ring.state      = state
  M.attach_cancel()
end

function M.on_yank()
  if vim.tbl_contains(Config.options.ring.ignore_registers, vim.v.register) then return end
  if vim.v.event.visual and vim.v.event.operator == 'd' and M.ring.is_cycling then return end
  local entry = Utils.get_register_info(vim.v.event.regname)
  entry.filetype = vim.bo.filetype
  History.push(entry)
  PreserveCursor.on_yank()
end

function M.yank(opts)
  opts = opts or {}
  PreserveCursor.yank()
  return ('%sy'):format(opts.register and ('"' .. opts.register) or '')
end

function M.clear_history() History.clear() end

return M
