local M = {}

local git = require("claude-multi.git")
local health = require("claude-multi.health")

---Pick an existing worktree or create a new one.
---Uses vim.ui.select (no snacks dependency; overridden by telescope/fzf-lua automatically).
---@param callback function Called with (path) when worktree is ready
---@param prompt? string Custom prompt text
function M.pick(callback, prompt)
  local worktrees = git.list_worktrees()

  -- "New…" sentinel always first so the user can create without typing
  local items = { { text = '+ New worktree…', path = nil } }
  for _, wt in ipairs(worktrees) do
    table.insert(items, { text = wt.branch or 'detached', path = wt.path })
  end

  vim.ui.select(items, {
    prompt = prompt or 'Worktree',
    format_item = function(item) return item.text end,
  }, function(item)
    if not item then return end
    if not item.path then
      vim.ui.input({ prompt = 'New branch name: ' }, function(branch)
        if not branch or branch == '' then return end
        local path = git.get_worktree_path(branch)
        git.create_worktree(path, branch, function(success)
          if success then callback(path) end
        end)
      end)
    else
      callback(item.path)
    end
  end)
end

---Open new session with worktree picker
---@param new_session_fn function Function to create new session (receives cwd)
function M.new_session(new_session_fn)
  M.pick(function(path)
    new_session_fn(path)
  end, "Select worktree for new session:")
end

---Open recall with worktree picker
---@param open_recall_fn function Function to open recall (receives cwd)
function M.open_recall(open_recall_fn)
  if not health.has_recall() then
    vim.notify("claude-multi: 'recall' CLI not found. Install from https://github.com/hrishioa/recall", vim.log.levels.ERROR)
    return
  end

  M.pick(function(path)
    open_recall_fn(path)
  end, "Select worktree for recall:")
end

return M
