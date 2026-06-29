-- Jump between function/method declarations via treesitter.
-- ]f / [f (and aliases ]m / [m) move to the next/previous function or method.
local M = {}

-- Node types that count as a "function" per treesitter language.
local FUNC_NODES = {
  go     = { function_declaration = true, method_declaration = true },
  rust   = { function_item = true },
  lua    = { function_declaration = true },
  python = { function_definition = true },
  ts     = { function_declaration = true, method_definition = true,
             generator_function_declaration = true },
}

local FT = {
  go = 'go', rust = 'rust', lua = 'lua', python = 'python',
  typescript = 'ts', typescriptreact = 'ts',
  javascript = 'ts', javascriptreact = 'ts',
}

-- Collect start positions of function nodes (prefer the name's position).
local function collect(node, want, out)
  for child in node:iter_children() do
    if want[child:type()] then
      local nm = child:field('name')[1]
      local r, c = (nm or child):start()
      out[#out + 1] = { r, c }
    end
    collect(child, want, out)
  end
end

---Move the cursor to the next (dir>0) or previous (dir<0) function/method.
function M.goto_func(dir)
  local ok, parser = pcall(vim.treesitter.get_parser)
  if not ok or not parser then return end
  local want = FUNC_NODES[FT[vim.bo.filetype] or parser:lang()]
  if not want then return end
  local tree = parser:parse()[1]
  if not tree then return end

  local pos = {}
  collect(tree:root(), want, pos)
  if #pos == 0 then return end
  table.sort(pos, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)

  local cur = vim.api.nvim_win_get_cursor(0)
  local cr, cc = cur[1] - 1, cur[2]
  local target
  if dir > 0 then
    for _, p in ipairs(pos) do
      if p[1] > cr or (p[1] == cr and p[2] > cc) then target = p; break end
    end
  else
    for i = #pos, 1, -1 do
      local p = pos[i]
      if p[1] < cr or (p[1] == cr and p[2] < cc) then target = p; break end
    end
  end
  if target then
    vim.api.nvim_win_set_cursor(0, { target[1] + 1, target[2] })
    vim.cmd 'normal! zz'
  end
end

function M.setup()
  local map = vim.keymap.set
  local o = { silent = true }
  map('n', ']f', function() M.goto_func(1) end,  vim.tbl_extend('force', o, { desc = 'Next function/method' }))
  map('n', '[f', function() M.goto_func(-1) end, vim.tbl_extend('force', o, { desc = 'Prev function/method' }))
  map('n', ']m', function() M.goto_func(1) end,  o)   -- aliases
  map('n', '[m', function() M.goto_func(-1) end, o)
end

return M
