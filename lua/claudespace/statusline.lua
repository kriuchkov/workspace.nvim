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
  -- Mode pills — colours from tokyonight palette, work on any dark theme
  hi(0, 'CSModeN', { bg = '#7aa2f7', fg = '#1a1b26', bold = true })
  hi(0, 'CSModeI', { bg = '#9ece6a', fg = '#1a1b26', bold = true })
  hi(0, 'CSModeV', { bg = '#bb9af7', fg = '#1a1b26', bold = true })
  hi(0, 'CSModeC', { bg = '#e0af68', fg = '#1a1b26', bold = true })
  hi(0, 'CSModeR', { bg = '#f7768e', fg = '#1a1b26', bold = true })
  hi(0, 'CSModeT', { bg = '#73daca', fg = '#1a1b26', bold = true })
  -- Statusline segments
  hi(0, 'CSGit',    { fg = '#e0af68' })
  hi(0, 'CSFile',   { fg = '#c0caf5', bold = true })
  hi(0, 'CSMod',    { fg = '#f7768e' })
  hi(0, 'CSErr',    { fg = '#f7768e' })
  hi(0, 'CSWarn',   { fg = '#e0af68' })
  hi(0, 'CSWorkspace', { fg = '#bb9af7', bold = true })
  hi(0, 'CSClaude', { fg = '#7aa2f7' })
  hi(0, 'CSLsp',    { fg = '#73daca' })
  hi(0, 'CSInfo',   { fg = '#565f89' })
  hi(0, 'CSDebug',  { fg = '#ff9e64', bold = true })
end

function M.setup()
  setup_highlights()
  vim.o.statusline = '%!v:lua.require("claudespace.statusline").render()'
  -- Re-apply after colorscheme changes
  vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_highlights })
end

return M
