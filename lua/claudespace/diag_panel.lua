-- Workspace diagnostics panel (sidebar slot). Lists all diagnostics across open
-- buffers; <CR> jumps. Lives to the right of the activity bar when anchored.
local M = {}

local api = vim.api
local S = { win = nil, buf = nil, anchor = nil, items = {} }
local ns = api.nvim_create_namespace 'cs_diagpanel'

local SEV = {
  [vim.diagnostic.severity.ERROR] = { ic = vim.fn.nr2char(0xf057), hl = 'DiagnosticError' },
  [vim.diagnostic.severity.WARN]  = { ic = vim.fn.nr2char(0xf071), hl = 'DiagnosticWarn' },
  [vim.diagnostic.severity.INFO]  = { ic = vim.fn.nr2char(0xf05a), hl = 'DiagnosticInfo' },
  [vim.diagnostic.severity.HINT]  = { ic = vim.fn.nr2char(0xf059), hl = 'DiagnosticHint' },
}

local function render()
  if not (S.buf and api.nvim_buf_is_valid(S.buf)) then return end
  local all = vim.diagnostic.get(nil)
  table.sort(all, function(a, b)
    if a.bufnr ~= b.bufnr then return a.bufnr < b.bufnr end
    return a.lnum < b.lnum
  end)
  local lines, hls = {}, {}
  S.items = {}
  if #all == 0 then
    lines = { '  No diagnostics' }
  else
    for _, d in ipairs(all) do
      local sev  = SEV[d.severity] or SEV[vim.diagnostic.severity.INFO]
      local file = vim.fn.fnamemodify(api.nvim_buf_get_name(d.bufnr), ':t')
      local msg  = (d.message or ''):gsub('%s*\n%s*', ' ')
      lines[#lines + 1] = string.format('%s %s:%d  %s', sev.ic, file, d.lnum + 1, msg)
      hls[#lines]       = { hl = sev.hl, w = #sev.ic }
      S.items[#lines]   = { bufnr = d.bufnr, lnum = d.lnum, col = d.col }
    end
  end
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for i, h in pairs(hls) do
    api.nvim_buf_add_highlight(S.buf, ns, h.hl, i - 1, 0, h.w)
  end
end

local function editor_win()
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if api.nvim_win_get_config(w).relative == '' and vim.bo[b].buftype == ''
      and not vim.bo[b].filetype:match '^cs_' then
      return w
    end
  end
end

local function jump()
  local it = S.items[api.nvim_win_get_cursor(S.win)[1]]
  if not it or not api.nvim_buf_is_valid(it.bufnr) then return end
  local w = editor_win()
  if w then api.nvim_set_current_win(w) else vim.cmd 'wincmd l' end
  pcall(api.nvim_win_set_buf, 0, it.bufnr)
  pcall(api.nvim_win_set_cursor, 0, { it.lnum + 1, it.col })
  vim.cmd 'normal! zz'
end

function M.open(anchor_win)
  if S.win and api.nvim_win_is_valid(S.win) then api.nvim_set_current_win(S.win); return end
  S.buf = api.nvim_create_buf(false, true)
  vim.bo[S.buf].buftype   = 'nofile'
  vim.bo[S.buf].bufhidden = 'hide'
  vim.bo[S.buf].swapfile  = false
  vim.bo[S.buf].filetype  = 'cs_diagpanel'

  if anchor_win and api.nvim_win_is_valid(anchor_win) then S.anchor = anchor_win end
  if S.anchor and api.nvim_win_is_valid(S.anchor) then
    api.nvim_set_current_win(S.anchor)
    vim.cmd 'rightbelow vsplit'
  else
    S.anchor = nil
    vim.cmd 'botright vsplit'
  end
  S.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.win, S.buf)
  api.nvim_win_set_width(S.win, 50)
  local wo = vim.wo[S.win]
  wo.number = false; wo.relativenumber = false; wo.signcolumn = 'no'
  wo.wrap = false; wo.cursorline = true; wo.winfixwidth = true
  wo.winbar = '%#Title# Diagnostics'

  local o = { buffer = S.buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', jump,    o)
  vim.keymap.set('n', 'q',    M.close, o)
  vim.keymap.set('n', 'r',    render,  o)

  api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(S.win), once = true,
    callback = function() S.win = nil end,
  })
  render()
end

function M.close()
  if S.win and api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  S.win = nil
end

-- Live refresh while the panel is open.
api.nvim_create_autocmd('DiagnosticChanged', {
  group = api.nvim_create_augroup('cs_diagpanel', { clear = true }),
  callback = function()
    if S.win and api.nvim_win_is_valid(S.win) then render() end
  end,
})

return M
