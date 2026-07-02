-- Layout persistence: save/restore window split arrangements.
local M = {}

local api = vim.api
local fn  = vim.fn

local SKIP_FT = { cs_filetree = true, cs_dirdash = true, cs_outline = true, cs_mdtoc = true }
local SKIP_BT = { terminal = true, nofile = true, prompt = true, quickfix = true }

local function skip(win)
  local buf = api.nvim_win_get_buf(win)
  return SKIP_FT[vim.bo[buf].filetype] or SKIP_BT[vim.bo[buf].buftype]
end

-- Serialize winlayout() tree into a JSON-safe table.
local function serialize(node)
  if node[1] == 'leaf' then
    local win = node[2]
    if skip(win) then return nil end
    local buf    = api.nvim_win_get_buf(win)
    local path   = api.nvim_buf_get_name(buf)
    local cursor = api.nvim_win_get_cursor(win)
    return {
      t      = 'l',
      path   = path,
      cursor = { cursor[1], cursor[2] },
      w      = api.nvim_win_get_width(win),
      h      = api.nvim_win_get_height(win),
    }
  end

  local kids = {}
  for _, child in ipairs(node[2]) do
    local s = serialize(child)
    if s then table.insert(kids, s) end
  end
  if #kids == 0 then return nil end
  if #kids == 1 then return kids[1] end
  return { t = node[1], kids = kids }  -- 'col' (stacked) or 'row' (side-by-side)
end

function M.save()
  return serialize(fn.winlayout())
end

-- Restore a serialized layout node in the current window.
local function restore_node(node)
  if not node then return end

  if node.t == 'l' then
    if node.path ~= '' and fn.filereadable(node.path) == 1 then
      pcall(vim.cmd, 'edit ' .. fn.fnameescape(node.path))
      pcall(api.nvim_win_set_cursor, 0, node.cursor)
    end

  elseif node.t == 'row' then   -- side-by-side (vsplit)
    restore_node(node.kids[1])
    for i = 2, #node.kids do
      vim.cmd 'vsplit'
      restore_node(node.kids[i])
      -- size hint
      if node.kids[i].w then
        pcall(api.nvim_win_set_width, 0, node.kids[i].w)
      end
    end
    vim.cmd 'wincmd h'  -- return focus to first pane

  elseif node.t == 'col' then   -- stacked (split)
    restore_node(node.kids[1])
    for i = 2, #node.kids do
      vim.cmd 'split'
      restore_node(node.kids[i])
      if node.kids[i].h then
        pcall(api.nvim_win_set_height, 0, node.kids[i].h)
      end
    end
    vim.cmd 'wincmd k'  -- return focus to first pane
  end
end

function M.restore(layout)
  if not layout then return end
  -- Focus a real editor window (skip() excludes sidebars/panels/terminals).
  for _, win in ipairs(api.nvim_list_wins()) do
    if not skip(win) then
      api.nvim_set_current_win(win)
      break
    end
  end
  -- Collapse editor windows to one. We can't use `:only` — it ignores
  -- winfixbuf and would wipe the sidebars too. Close only non-skip windows.
  local keep = api.nvim_get_current_win()
  for _, win in ipairs(api.nvim_list_wins()) do
    if win ~= keep and api.nvim_win_is_valid(win) and not skip(win) then
      pcall(api.nvim_win_close, win, false)
    end
  end
  restore_node(layout)
end

return M
