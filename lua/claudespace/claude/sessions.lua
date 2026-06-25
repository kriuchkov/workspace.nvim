-- Telescope picker for Claude sessions
-- <leader>cs — fuzzy-find and switch between active sessions

local function pick_session()
  local ok_tel, telescope = pcall(require, 'telescope')
  if not ok_tel then
    vim.notify('claudespace: telescope not available', vim.log.levels.ERROR)
    return
  end

  local ok_state, state = pcall(require, 'claude-multi.state')
  if not ok_state then return end

  local sessions = state.get_sessions()
  if #sessions == 0 then
    vim.notify('claudespace: no active Claude sessions', vim.log.levels.WARN)
    return
  end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  pickers.new({}, {
    prompt_title = 'Claude Sessions',
    finder = finders.new_table {
      results = sessions,
      entry_maker = function(s)
        local active = s.id == state.get_active_session_id()
        local display = (active and '⚡ ' or '  ') .. (s.name or 'Chat')
        if s.branch then display = display .. '  [' .. s.branch .. ']' end
        if s.cwd then display = display .. '  ' .. vim.fn.fnamemodify(s.cwd, ':~') end
        return {
          value = s,
          display = display,
          ordinal = (s.name or '') .. (s.branch or '') .. (s.cwd or ''),
        }
      end,
    },
    sorter = conf.generic_sorter {},
    attach_mappings = function(prompt_buf, map_)
      -- <CR>: switch to session
      actions.select_default:replace(function()
        actions.close(prompt_buf)
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local sess = sel.value
        state.set_active_session_id(sess.id)
        require('claude-multi.terminal').open_in_current_window(sess)
      end)

      -- <C-x>: close selected session
      local function do_close()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        actions.close(prompt_buf)
        local cm = require 'claude-multi'
        cm.switch_session(sel.value.id, false)
        vim.schedule(function() cm.close_tab() end)
      end
      map_('i', '<C-x>', do_close)
      map_('n', '<C-x>', do_close)

      return true
    end,
  }):find()
end

vim.keymap.set({ 'n', 't' }, '<leader>cs', pick_session, { desc = 'Claude: pick session', silent = true })
