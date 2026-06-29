-- DAP inline variable display.
local M = {}

local api = vim.api
local ts  = vim.treesitter
local tsq = ts.query

-- ── treesitter compatibility ────────────────────────────────────────────────

local is_in_node_range
if vim.treesitter.is_in_node_range then
  is_in_node_range = vim.treesitter.is_in_node_range
else
  local ok, utils = pcall(require, 'nvim-treesitter.ts_utils')
  is_in_node_range = ok and utils.is_in_node_range or function() return false end
end

local function get_query(lang, name)
  return (tsq.get or tsq.get_query)(lang, name)
end

-- ── module state ────────────────────────────────────────────────────────────

local NS = api.nvim_create_namespace 'cs_dap_virtual_text'
local error_set, info_set
local stopped_frame
local last_frames = {}

-- ── options ─────────────────────────────────────────────────────────────────

local options = {
  enabled                      = true,
  enable_commands              = true,
  all_frames                   = false,
  commented                    = false,
  highlight_changed_variables  = true,
  highlight_new_as_changed     = false,
  show_stop_reason             = true,
  only_first_definition        = true,
  all_references               = false,
  clear_on_continue            = false,
  text_prefix                  = '',
  separator                    = ',',
  error_prefix                 = '  ',
  info_prefix                  = '  ',
  virt_text_pos                = vim.fn.has 'nvim-0.10' == 1 and 'inline' or 'eol',
  virt_lines                   = false,
  virt_lines_above             = true,
  virt_text_win_col            = nil,
  filter_references_pattern    = '<module',
  display_callback = function(variable, _, _, _, opts)
    if opts.virt_text_pos == 'inline' then
      return ' = ' .. variable.value:gsub('%s+', ' ')
    end
    return variable.name .. ' = ' .. variable.value:gsub('%s+', ' ')
  end,
}

-- ── virtual_text internals ───────────────────────────────────────────────────

local function variables_from_scopes(scopes, lang)
  local vars = {}
  for _, s in ipairs(scopes or {}) do
    for _, v in pairs(s.variables or {}) do
      local key = lang == 'php' and v.name:gsub('^%$', '') or v.name
      if not vars[key] or vars[key].presentationHint ~= 'locals' then
        vars[key] = { value = v, presentationHint = s.presentationHint }
      end
    end
  end
  return vars
end

local function set_virtual_text(stackframe, opts)
  if not stackframe or not stackframe.scopes
      or not stackframe.source or not stackframe.source.path then return end

  local path = stackframe.source.path
  local buf  = vim.fn.bufnr(path, false)
  if buf == -1 then buf = vim.uri_to_bufnr(vim.uri_from_fname(path)) end

  local ft = vim.bo[buf].ft
  if ft == '' then ft = vim.filetype.match { buf = buf } or '' end
  if ft == '' then return end

  local lang, parser
  if ts.language and ts.language.get_lang then
    lang = ts.language.get_lang(ft)
    if not lang then return end
    local ok; ok, parser = pcall(ts.get_parser, buf, lang)
    if not ok then return end
  else
    local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
    if not ok then return end
    lang = parsers.get_buf_lang(buf)
    if not lang then return end
    local ok2; ok2, parser = pcall(parsers.get_parser, buf, lang)
    if not ok2 then return end
  end
  if not parser then return end

  local scope_nodes = {}
  local def_nodes   = {}
  parser:parse()
  parser:for_each_tree(function(tree, ltree)
    local q = get_query(ltree:lang(), 'locals')
    if not q then return end
    for _, match in q:iter_matches(tree:root(), buf, 0, -1) do
      for id, nodes in pairs(match) do
        if type(nodes) ~= 'table' then nodes = { nodes } end
        for _, node in ipairs(nodes) do
          local cap = q.captures[id]
          if cap:find('scope', 1, true) then
            table.insert(scope_nodes, node)
          elseif cap:find('definition', 1, true) or
                 (opts.all_references and cap:find('reference', 1, true)) then
            table.insert(def_nodes, node)
          end
        end
      end
    end
  end)

  local variables   = variables_from_scopes(stackframe.scopes, lang)
  local last_scopes = last_frames[stackframe.id] and last_frames[stackframe.id].scopes or {}
  local last_vars   = variables_from_scopes(last_scopes, lang)
  local inline      = opts.virt_text_pos == 'inline'
  local virt_lines  = {}
  local node_ids    = {}
  local get_text    = ts.get_node_text or ts.query.get_node_text

  for _, node in pairs(def_nodes) do
    if node then
      local name       = get_text(node, buf)
      local vl, vc     = node:start()
      local evaluated  = variables[name] and variables[name].value
      local last_value = last_vars[name]   and last_vars[name].value
      if evaluated and not (opts.filter_references_pattern
          and evaluated.value:find(opts.filter_references_pattern)) then
        local in_scope = true
        for _, scope in ipairs(scope_nodes) do
          if is_in_node_range(scope, vl, vc)
              and not is_in_node_range(scope, stackframe.line - 1, 0) then
            in_scope = false; break
          end
        end
        if in_scope then
          if opts.only_first_definition and not opts.all_references then
            variables[name] = nil
          end
          if not node_ids[node:id()] then
            node_ids[node:id()] = true
            local changed = opts.highlight_changed_variables
                and (evaluated.value ~= (last_value and last_value.value))
                and (opts.highlight_new_as_changed or last_value)
            local text = opts.display_callback(evaluated, buf, stackframe, node, opts)
            if text then
              if opts.commented then
                text = vim.o.commentstring:gsub('%%s', { ['%s'] = text })
              end
              text = opts.text_prefix .. text
              local key = node:start()
              virt_lines[key] = virt_lines[key] or {}
              table.insert(virt_lines[key], {
                text,
                changed and 'NvimDapVirtualTextChanged' or 'NvimDapVirtualText',
                node = node,
              })
            end
          end
        end
      end
    end
  end

  for line, content in pairs(virt_lines) do
    if opts.all_references then
      local seen = {}
      content = vim.tbl_filter(function(c)
        local dup = seen[c[1]]; seen[c[1]] = true; return not dup
      end, content)
    end
    if opts.virt_lines then
      for _, vt in ipairs(content) do vt.node = nil end
      api.nvim_buf_set_extmark(buf, NS, line, 0,
        { virt_lines = { content }, virt_lines_above = opts.virt_lines_above })
    else
      local line_text = api.nvim_buf_get_lines(buf, line, line + 1, true)[1]
      local win_col   = math.max(opts.virt_text_win_col or 0, #line_text + 1)
      for i, vt in ipairs(content) do
        local nr = { vt.node:range() }
        if i < #content and not inline then vt[1] = vt[1] .. opts.separator end
        vt.node = nil
        api.nvim_buf_set_extmark(buf, NS,
          nr[inline and 3 or 1], nr[inline and 4 or 2], {
            end_line = nr[3], end_col = nr[4],
            hl_mode  = 'combine',
            virt_text     = { vt },
            virt_text_pos = opts.virt_text_pos,
            virt_text_win_col = opts.virt_text_win_col and win_col,
          })
        win_col = win_col + #vt[1] + 1
      end
    end
  end

  -- Error / info overlays on stopped line
  if stopped_frame and stopped_frame.line and stopped_frame.source and stopped_frame.source.path then
    local sf_buf = vim.uri_to_bufnr(vim.uri_from_fname(stopped_frame.source.path))
    local function overlay(msg, hl)
      if opts.commented then msg = vim.o.commentstring:gsub('%%s', { ['%s'] = msg }) end
      pcall(api.nvim_buf_set_extmark, sf_buf, NS, stopped_frame.line - 1, 0, {
        hl_mode = 'combine',
        virt_text = { { msg, hl } },
        virt_text_pos = inline and 'eos' or opts.virt_text_pos,
      })
    end
    if error_set then overlay(error_set, 'NvimDapVirtualTextError') end
    if info_set  then overlay(info_set,  'NvimDapVirtualTextInfo')  end
  end
end

local function clear_virtual_text(stackframe)
  if stackframe then
    local buf = vim.uri_to_bufnr(vim.uri_from_fname(stackframe.source.path))
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  else
    for _, buf in ipairs(api.nvim_list_bufs()) do
      api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    end
  end
end

-- ── public API ───────────────────────────────────────────────────────────────

function M.refresh(session)
  session = session or require('dap').session()
  clear_virtual_text()
  if not options.enabled or not session then return end
  if options.all_frames and session.threads and session.threads[session.stopped_thread_id] then
    for _, f in pairs(session.threads[session.stopped_thread_id].frames or {}) do
      set_virtual_text(f, options)
    end
  else
    set_virtual_text(session.current_frame, options)
  end
end

function M.enable()  options.enabled = true;  M.refresh() end
function M.disable() options.enabled = false; M.refresh() end
function M.toggle()  options.enabled = not options.enabled; M.refresh() end
function M.is_enabled() return options.enabled end

function M.setup(opts)
  options = vim.tbl_deep_extend('force', options, opts or {})

  vim.cmd [[
    highlight default link NvimDapVirtualText        Comment
    highlight default link NvimDapVirtualTextChanged DiagnosticVirtualTextWarn
    highlight default link NvimDapVirtualTextError   DiagnosticVirtualTextError
    highlight default link NvimDapVirtualTextInfo    DiagnosticVirtualTextInfo
  ]]

  if options.enable_commands then
    vim.api.nvim_create_user_command('DapVirtualTextEnable',        M.enable,  {})
    vim.api.nvim_create_user_command('DapVirtualTextDisable',       M.disable, {})
    vim.api.nvim_create_user_command('DapVirtualTextToggle',        M.toggle,  {})
    vim.api.nvim_create_user_command('DapVirtualTextForceRefresh',  M.refresh, {})
  end

  local ID = 'cs_dap_virtual_text'
  local dap = require 'dap'

  local function on_continue()
    error_set = nil; info_set = nil; stopped_frame = nil
    if options.clear_on_continue then clear_virtual_text() end
  end

  local function on_exit()
    clear_virtual_text()
    last_frames = {}
  end

  dap.listeners.after.event_terminated[ID]  = on_exit
  dap.listeners.after.event_exited[ID]      = on_exit
  dap.listeners.before.event_continued[ID]  = on_continue
  dap.listeners.before.continue[ID]         = on_continue

  dap.listeners.before.event_stopped[ID] = function(session)
    for _, t in pairs(session.threads or {}) do
      for _, f in pairs(t.frames or {}) do
        if f and f.id then last_frames[f.id] = f end
      end
    end
  end

  dap.listeners.after.event_stopped[ID] = function(_, event)
    if not options.show_stop_reason or not event then return end
    if event.reason == 'exception' then
      info_set = nil
      error_set = options.error_prefix .. 'Stopped due to exception'
    elseif event.reason == 'data breakpoint' then
      error_set = nil
      info_set = options.info_prefix .. 'Stopped due to ' .. event.reason
    end
  end

  dap.listeners.after.event_stopped[ID .. '_frame'] = function(session, body)
    if not options.enabled or not body then return end
    if session.stopped_thread_id
        and session.threads[session.stopped_thread_id]
        and session.threads[session.stopped_thread_id].frames then
      local frames = vim.tbl_filter(
        function(f) return f.source and f.source.path end,
        session.threads[session.stopped_thread_id].frames)
      stopped_frame = frames[1]
    end
    if options.all_frames and body.stackFrames then
      local seen = {}
      for _, f in pairs(body.stackFrames) do
        if not seen[f.name] then
          seen[f.name] = true
          if not f.scopes or #f.scopes == 0 then
            pcall(session._request_scopes, session, f)
          end
        end
      end
    end
  end

  dap.listeners.after.variables[ID]       = M.refresh
  dap.listeners.after.stackTrace[ID]      = function(session, body, _)
    if not options.enabled then return end
    -- reuse event_stopped frame listener logic above
  end

  dap.listeners.after.exceptionInfo[ID] = function(_, _, response)
    if not options.enabled or not response then return end
    local etype = response.details and response.details.typeName
    error_set   = options.error_prefix
      .. (etype or '')
      .. (response.description and ((etype and ': ' or '') .. response.description) or '')
  end
end

return M
