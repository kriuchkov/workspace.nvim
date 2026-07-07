-- nvim-cmp LSP source.
-- Registers per-client sources on InsertEnter.
local M = {}

M.client_source_map = {}

-- ── source ────────────────────────────────────────────────────────────────────

local source = {}

local IS_011 = vim.fn.has 'nvim-0.11' == 1
local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients

-- Neovim 0.11+ made these client methods (self-first); older versions call them
-- bare. Never use `a and b or c` here: is_stopped() returns a boolean, so a false
-- result would fall through to the deprecated bare call.
local function client_call(client, method, ...)
  local fn = client[method]
  if IS_011 then
    return fn(client, ...)
  end
  return fn(...)
end

function source.new(client)
  return setmetatable({ client = client, request_ids = {} }, { __index = source })
end

function source:get_debug_name()
  return 'nvim_lsp:' .. self.client.name
end

function source:is_available()
  if client_call(self.client, 'is_stopped') then return false end
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.tbl_isempty(get_clients { bufnr = bufnr, id = self.client.id }) then return false end
  if not (self.client.server_capabilities or {}).completionProvider then return false end
  return true
end

function source:get_position_encoding_kind()
  local caps = self.client.server_capabilities or {}
  return caps.positionEncoding or self.client.offset_encoding or 'utf-16'
end

function source:get_trigger_characters()
  local caps = self.client.server_capabilities or {}
  return (caps.completionProvider or {}).triggerCharacters or {}
end

function source:get_keyword_pattern(params)
  local opt = (params.option or {})[self.client.name] or {}
  return opt.keyword_pattern or require('cmp').get_config().completion.keyword_pattern
end

function source:complete(params, callback)
  local lsp_params = vim.lsp.util.make_position_params(0, self.client.offset_encoding)
  lsp_params.context = {
    triggerKind      = params.completion_context.triggerKind,
    triggerCharacter = params.completion_context.triggerCharacter,
  }
  self:_request('textDocument/completion', lsp_params, function(_, response)
    callback(response)
  end)
end

function source:resolve(item, callback)
  if client_call(self.client, 'is_stopped') then return callback() end
  local caps = self.client.server_capabilities or {}
  if not ((caps.completionProvider or {}).resolveProvider) then return callback() end
  self:_request('completionItem/resolve', item, function(_, response)
    callback(response or item)
  end)
end

function source:execute(item, callback)
  if client_call(self.client, 'is_stopped') then return callback() end
  if not item.command then return callback() end
  self:_request('workspace/executeCommand', item.command, function() callback() end)
end

function source:_request(method, params, callback)
  if self.request_ids[method] then
    client_call(self.client, 'cancel_request', self.request_ids[method])
    self.request_ids[method] = nil
  end
  local _, req_id = client_call(self.client, 'request', method, params,
    function(arg1, arg2, arg3)
      if self.request_ids[method] ~= req_id then return end
      self.request_ids[method] = nil
      if arg1 and arg1.code == -32801 then
        self:_request(method, params, callback); return
      end
      callback(arg1, method == arg2 and arg3 or arg2)
    end)
  self.request_ids[method] = req_id
end

-- ── capabilities ──────────────────────────────────────────────────────────────

function M.default_capabilities(override)
  override = override or {}
  local function d(v, default) return v == nil and default or v end
  return {
    textDocument = {
      completion = {
        dynamicRegistration = d(override.dynamicRegistration, false),
        completionItem = {
          snippetSupport            = d(override.snippetSupport,            true),
          commitCharactersSupport   = d(override.commitCharactersSupport,   true),
          deprecatedSupport         = d(override.deprecatedSupport,         true),
          preselectSupport          = d(override.preselectSupport,          true),
          insertReplaceSupport      = d(override.insertReplaceSupport,      true),
          labelDetailsSupport       = d(override.labelDetailsSupport,       true),
          tagSupport                = d(override.tagSupport,                { valueSet = { 1 } }),
          resolveSupport            = d(override.resolveSupport,            {
            properties = { 'documentation', 'additionalTextEdits',
                           'insertTextFormat', 'insertTextMode', 'command' },
          }),
          insertTextModeSupport     = d(override.insertTextModeSupport,     { valueSet = { 1, 2 } }),
        },
        contextSupport  = d(override.contextSupport,  true),
        insertTextMode  = d(override.insertTextMode,  1),
        completionList  = d(override.completionList,  {
          itemDefaults = { 'commitCharacters', 'editRange',
                           'insertTextFormat', 'insertTextMode', 'data' },
        }),
      },
    },
  }
end

-- ── registration ──────────────────────────────────────────────────────────────

function M.setup()
  vim.api.nvim_create_autocmd('InsertEnter', {
    group   = vim.api.nvim_create_augroup('cs_cmp_nvim_lsp', { clear = true }),
    pattern = '*',
    callback = function()
      local cmp     = require 'cmp'
      local allowed = {}
      for _, client in ipairs(get_clients()) do
        allowed[client.id] = client
        if not M.client_source_map[client.id] then
          local s = source.new(client)
          if s:is_available() then
            M.client_source_map[client.id] = cmp.register_source('nvim_lsp', s)
          end
        end
      end
      for _, client in ipairs(get_clients { bufnr = 0 }) do
        allowed[client.id] = client
        if not M.client_source_map[client.id] then
          local s = source.new(client)
          if s:is_available() then
            M.client_source_map[client.id] = cmp.register_source('nvim_lsp', s)
          end
        end
      end
      for client_id, source_id in pairs(M.client_source_map) do
        if not allowed[client_id] or allowed[client_id]:is_stopped() then
          cmp.unregister_source(source_id)
          M.client_source_map[client_id] = nil
        end
      end
    end,
  })
end

return M
