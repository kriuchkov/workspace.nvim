local M = {}

-- Cached executable checks
local _has_claude = nil
local _has_recall = nil

---Check if claude CLI is available (cached)
---@return boolean
function M.has_claude()
  if _has_claude == nil then
    _has_claude = vim.fn.executable("claude") == 1
  end
  return _has_claude
end

---Check if recall CLI is available (cached)
---@return boolean
function M.has_recall()
  if _has_recall == nil then
    _has_recall = vim.fn.executable("recall") == 1
  end
  return _has_recall
end

function M.check()
  vim.health.start("claude-multi.nvim")

  -- Check for claude CLI
  if vim.fn.executable("claude") == 1 then
    vim.health.ok("claude CLI is installed")
  else
    vim.health.error("claude CLI is not installed", {
      "Install Claude Code: https://docs.anthropic.com/en/docs/claude-code",
      "Required for all functionality",
    })
  end

  -- Check for recall CLI (optional)
  if vim.fn.executable("recall") == 1 then
    vim.health.ok("recall CLI is installed")
  else
    vim.health.warn("recall CLI is not installed (optional)", {
      "Install recall: https://github.com/hrishioa/recall",
      "Enables browsing conversation history with :ClaudeRecall",
      "Without it, :ClaudeToggle will open a new session instead",
    })
  end
end

return M
