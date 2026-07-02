-- Custom statusline — owns every pixel, no lualine dependency.
local M = {}

local MODES = {
  n  = { 'NORMAL',   'CSModeN' },
  i  = { 'INSERT',   'CSModeI' },
  v  = { 'VISUAL',   'CSModeV' },
  V  = { 'V-LINE',   'CSModeV' },
  ['\22'] = { 'V-BLOCK', 'CSModeV' },
  c  = { 'COMMAND',  'CSModeC' },
  R  = { 'REPLACE',  'CSModeR' },
  t  = { 'TERMINAL', 'CSModeT' },
  s  = { 'SELECT',   'CSModeV' },
  S  = { 'S-LINE',   'CSModeV' },
  no = { 'OP',       'CSModeN' },
}

local function hl(t, group, text)
  t[#t+1] = '%#' .. group .. '#' .. text
end

function M.render()
  -- Skip for special buffers (keep them minimal)
  local bt = vim.bo.buftype
  local ft = vim.bo.filetype
  if ft == 'cs_filetree' then
    return '%#StatusLine# Files%=%#StatusLine# '
  end

  local mode_info = MODES[vim.api.nvim_get_mode().mode] or MODES['n']
  local t = {}

  -- ── Left ──────────────────────────────────────────────────
  hl(t, mode_info[2], ' ' .. mode_info[1] .. ' ')
  hl(t, 'StatusLine', ' ')

  -- Git branch (populated by gitsigns)
  local branch = vim.b.gitsigns_head or ''
  if branch ~= '' then
    hl(t, 'CSGit', ' ' .. branch)
    hl(t, 'StatusLine', '  ')
  end

  -- Filename + flags
  local fname = bt == 'terminal' and vim.b.term_title or vim.fn.expand '%:t'
  if fname == '' then fname = '[No Name]' end
  hl(t, 'CSFile', fname)
  if vim.bo.modified  then hl(t, 'CSMod',  ' ●') end
  if vim.bo.readonly  then hl(t, 'CSInfo', ' ') end
  hl(t, 'StatusLine', ' ')

  -- Diagnostics (only for normal files)
  if bt == '' then
    local ok, diag = pcall(vim.diagnostic.get, 0)
    if ok then
      local counts = { 0, 0, 0, 0 }  -- error, warn, info, hint
      for _, d in ipairs(diag) do
        counts[d.severity] = (counts[d.severity] or 0) + 1
      end
      if counts[1] > 0 then hl(t, 'CSErr',  ' ' .. counts[1]) end
      if counts[2] > 0 then hl(t, 'CSWarn', '  ' .. counts[2]) end
      if counts[1] > 0 or counts[2] > 0 then hl(t, 'StatusLine', '  ') end
    end
  end

  -- DAP status (shown when debugging)
  local ok_dap, dap = pcall(require, 'dap')
  if ok_dap then
    local session = dap.session()
    if session then
      local status = require('dap').status()
      hl(t, 'CSDebug', '  ' .. (status ~= '' and status or 'Debugging') .. '  ')
    end
  end

  -- ── Right ─────────────────────────────────────────────────
  t[#t+1] = '%='

  -- Workspace name
  local ok_ws, ws = pcall(require, 'claudespace.workspace')
  if ok_ws and ws._current then
    hl(t, 'CSWorkspace', '⬡ ' .. ws._current .. '  ')
  end

  -- neotest status (running/failed count)
  local ok_nt, nt = pcall(require, 'neotest')
  if ok_nt then
    local ok_state, state = pcall(function() return nt.state() end)
    if ok_state and state then
      local running = 0
      for _, s in pairs(state) do
        if s == 'running' then running = running + 1 end
      end
      if running > 0 then hl(t, 'CSInfo', '◌ ' .. running .. '  ') end
    end
  end

  -- Claude sessions + connection
  local ok_cs, cs = pcall(require, 'claudespace.claude.status')
  if ok_cs then
    local s = cs.component()
    if s ~= '' then hl(t, 'CSClaude', s .. '  ') end
  end

  -- Filetype
  if ft ~= '' then hl(t, 'CSInfo', ft .. '  ') end

  -- LSP server(s)
  if bt == '' then
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    local names = {}
    for _, c in ipairs(clients) do
      if c.name ~= 'null-ls' and c.name ~= 'copilot' then
        table.insert(names, c.name)
      end
    end
    if #names == 1 then
      hl(t, 'CSLsp', '◆ ' .. names[1] .. '  ')
    elseif #names > 1 then
      hl(t, 'CSLsp', '◆ ' .. names[1] .. '+' .. (#names - 1) .. '  ')
    end
  end

  -- Encoding / line endings (only show when non-default)
  local enc = vim.bo.fileencoding
  if enc ~= '' and enc ~= 'utf-8' then hl(t, 'CSInfo', enc .. '  ') end

  -- Location
  if bt ~= 'terminal' then
    local line  = vim.fn.line '.'
    local total = vim.fn.line '$'
    local col   = vim.fn.virtcol '.'
    local pct   = total == 0 and 0 or math.floor(line / total * 100)
    hl(t, 'CSInfo', pct .. '%%  ')
    hl(t, mode_info[2], ' ' .. line .. ':' .. col .. ' ')
  end

  return table.concat(t)
end

local function setup_highlights()
  local hi = vim.api.nvim_set_hl
  local c  = require('claudespace.theme').colors()
  -- Mode pills — coloured background, palette-bg text for contrast in both themes.
  hi(0, 'CSModeN', { bg = c.blue,   fg = c.bg, bold = true })
  hi(0, 'CSModeI', { bg = c.green,  fg = c.bg, bold = true })
  hi(0, 'CSModeV', { bg = c.purple, fg = c.bg, bold = true })
  hi(0, 'CSModeC', { bg = c.yellow, fg = c.bg, bold = true })
  hi(0, 'CSModeR', { bg = c.red,    fg = c.bg, bold = true })
  hi(0, 'CSModeT', { bg = c.cyan,   fg = c.bg, bold = true })
  -- Statusline segments
  hi(0, 'CSGit',    { fg = c.git_change })
  hi(0, 'CSFile',   { fg = c.fg, bold = true })
  hi(0, 'CSMod',    { fg = c.red })
  hi(0, 'CSErr',    { fg = c.error })
  hi(0, 'CSWarn',   { fg = c.warn })
  hi(0, 'CSWorkspace', { fg = c.purple, bold = true })
  hi(0, 'CSClaude', { fg = c.blue })
  hi(0, 'CSLsp',    { fg = c.cyan })
  hi(0, 'CSInfo',   { fg = c.fg_dim })
  hi(0, 'CSDebug',  { fg = c.orange, bold = true })
end

function M.setup()
  setup_highlights()
  vim.o.statusline = '%!v:lua.require("claudespace.statusline").render()'
  -- Re-tint when the theme (dark/light) is (re-)applied.
  vim.api.nvim_create_autocmd('User', { pattern = 'CSThemeApplied', callback = setup_highlights })
end

return M
