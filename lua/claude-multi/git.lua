local M = {}

--- Get branch name for directory
---@param dir string
---@return string|nil branch name or nil if not a git repo
function M.get_branch(dir)
  local result = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(dir) .. " symbolic-ref --short HEAD 2>/dev/null"
  )
  if vim.v.shell_error == 0 and result[1] then
    return result[1]
  end
  return nil
end

--- Create worktree or return existing path
---@param path string worktree directory path
---@param branch string branch name
---@param on_complete? function callback when done (receives success boolean, path string)
function M.create_worktree(path, branch, on_complete)
  -- Check if worktree already exists at this path
  if vim.fn.isdirectory(path) == 1 then
    -- Already exists, just use it
    if on_complete then on_complete(true, path) end
    return
  end

  -- Ensure parent directory exists
  local parent_dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(parent_dir, "p")

  -- Build git worktree add command
  -- -b creates the branch if it doesn't exist
  local cmd = string.format(
    "git worktree add -b %s %s 2>&1",
    vim.fn.shellescape(branch),
    vim.fn.shellescape(path)
  )

  -- Run async to avoid blocking
  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          if on_complete then on_complete(true, path) end
        else
          -- Branch might already exist, try without -b
          local cmd_existing = string.format(
            "git worktree add %s %s 2>&1",
            vim.fn.shellescape(path),
            vim.fn.shellescape(branch)
          )
          vim.fn.jobstart(cmd_existing, {
            on_exit = function(_, exit_code2)
              vim.schedule(function()
                if exit_code2 == 0 then
                  if on_complete then on_complete(true, path) end
                else
                  vim.notify("claude-multi: Failed to create worktree for " .. branch, vim.log.levels.ERROR)
                  if on_complete then on_complete(false, nil) end
                end
              end)
            end,
          })
        end
      end)
    end,
  })
end

--- Get worktree path for a branch (convention-based)
--- Creates path as sibling directory: ~/code/project-worktrees/branch-name
---@param branch string
---@return string path
function M.get_worktree_path(branch)
  local cwd = vim.fn.getcwd()
  local parent = vim.fn.fnamemodify(cwd, ":h")
  local repo_name = vim.fn.fnamemodify(cwd, ":t")
  local safe_branch = branch:gsub("/", "-")
  return parent .. "/" .. repo_name .. "-worktrees/" .. safe_branch
end

--- List all worktrees for current repo
---@return table[] list of {path, branch}
function M.list_worktrees()
  local result = vim.fn.systemlist("git worktree list --porcelain 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local worktrees = {}
  local current = {}

  for _, line in ipairs(result) do
    if line:match("^worktree ") then
      current.path = line:sub(10)
    elseif line:match("^branch ") then
      -- Extract branch name from refs/heads/...
      local ref = line:sub(8)
      current.branch = ref:gsub("^refs/heads/", "")
    elseif line == "" and current.path then
      table.insert(worktrees, current)
      current = {}
    end
  end

  -- Don't forget the last one
  if current.path then
    table.insert(worktrees, current)
  end

  return worktrees
end

return M
