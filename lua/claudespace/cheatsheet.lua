-- Live keymap cheatsheet: reads the actual registered <leader> maps so it can
-- never drift from what is really bound. Grouped by the first key after <leader>.
local M = {}

-- Group headers keyed by the first key after <leader>. Mirrors the which-key
-- groups in plugins/ui.lua; anything unlisted falls under "General".
local GROUPS = {
  c = 'Claude', g = 'Git', f = 'Find/Files', l = 'LSP', t = 'Tabs/Terminal',
  x = 'Diagnostics/Panels', s = 'Search/Replace', w = 'Workspace',
  d = 'Debug', r = 'Run/Test', m = 'Marks', u = 'Toggles',
  _general = 'General',
}
local GROUP_ORDER = { 'c', 'g', 'f', 'l', 't', 'x', 's', 'w', 'r', 'd', 'm', 'u', '_general' }

local function collect()
  local leader = vim.g.mapleader or '\\'
  local seen, groups = {}, {}
  for _, mode in ipairs { 'n', 'x' } do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.lhs:sub(1, #leader) == leader and m.desc and m.desc ~= '' then
        local suffix = vim.fn.keytrans(m.lhs:sub(#leader + 1))
        if suffix ~= '' then
          local lhs = '<leader>' .. suffix
          local key = lhs .. (mode == 'x' and ' (v)' or '')
          if not seen[key] then
            seen[key] = true
            local g = suffix:sub(1, 1):lower()
            if not GROUPS[g] then g = '_general' end
            groups[g] = groups[g] or {}
            table.insert(groups[g], { lhs = key, desc = m.desc })
          end
        end
      end
    end
  end
  return groups
end

function M.show()
  local groups = collect()

  -- Widest lhs sets the description column, so descriptions line up.
  local pad = 0
  for _, items in pairs(groups) do
    for _, it in ipairs(items) do pad = math.max(pad, #it.lhs) end
  end

  local order = {}
  for _, g in ipairs(GROUP_ORDER) do order[#order + 1] = g end
  for g in pairs(groups) do
    if not GROUPS[g] then order[#order + 1] = g end -- ungrouped, keep after known
  end

  local lines, done = {}, {}
  local function emit_group(g)
    local items = groups[g]
    if not items or done[g] then return end
    done[g] = true
    table.sort(items, function(a, b) return a.lhs < b.lhs end)
    lines[#lines + 1] = (GROUPS[g] or ('<leader>' .. g)) .. ':'
    for _, it in ipairs(items) do
      lines[#lines + 1] = string.format('  %-' .. (pad + 2) .. 's%s', it.lhs, it.desc)
    end
    lines[#lines + 1] = ''
  end

  for _, g in ipairs(order) do emit_group(g) end
  if #lines == 0 then lines = { 'No <leader> mappings with descriptions found.' } end

  lines[#lines + 1] = 'Tip: :WhichKey for the live popup · ? inside the file tree'
  require('claudespace.claude.util').read_float(lines, ' Keymaps ')
end

return M
