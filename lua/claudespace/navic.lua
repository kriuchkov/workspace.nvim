-- LSP breadcrumb context for the winbar.

-- ── lib ─────────────────────────────────────────────

local lib = {}

local function symbol_relation(symbol, other)
	local s = symbol.scope
	local o = other.scope
	if
		o["end"].line < s["start"].line
		or (o["end"].line == s["start"].line and o["end"].character <= s["start"].character)
	then
		return "before"
	end
	if
		o["start"].line > s["end"].line
		or (o["start"].line == s["end"].line and o["start"].character >= s["end"].character)
	then
		return "after"
	end
	if
		(
			o["start"].line < s["start"].line
			or (o["start"].line == s["start"].line and o["start"].character <= s["start"].character)
		)
		and (
			o["end"].line > s["end"].line
			or (o["end"].line == s["end"].line and o["end"].character >= s["end"].character)
		)
	then
		return "around"
	end
	return "within"
end

local function symbolInfo_treemaker(symbols, root_node)
	for _, node in ipairs(symbols) do
		node.scope = node.location.range
		node.scope["start"].line = node.scope["start"].line + 1
		node.scope["end"].line = node.scope["end"].line + 1
		node.location = nil
		node.name_range = node.scope
		node.containerName = nil
	end

	table.sort(symbols, function(a, b)
		local loc = symbol_relation(a, b)
		if loc == "after" or loc == "within" then
			return true
		end
		return false
	end)

	root_node.children = {}
	local stack = {}

	table.insert(root_node.children, symbols[1])
	symbols[1].parent = root_node
	table.insert(stack, root_node)

	for i = 2, #symbols, 1 do
		local prev_chain_node_relation = symbol_relation(symbols[i], symbols[i - 1])
		local stack_top_node_relation = symbol_relation(symbols[i], stack[#stack])

		if prev_chain_node_relation == "around" then
			table.insert(stack, symbols[i - 1])
			if not symbols[i - 1].children then
				symbols[i - 1].children = {}
			end
			table.insert(symbols[i - 1].children, symbols[i])
			symbols[i].parent = symbols[i - 1]
		elseif prev_chain_node_relation == "before" and stack_top_node_relation == "around" then
			table.insert(stack[#stack].children, symbols[i])
			symbols[i].parent = stack[#stack]
		elseif stack_top_node_relation == "before" then
			while symbol_relation(symbols[i], stack[#stack]) ~= "around" do
				stack[#stack] = nil
			end
			table.insert(stack[#stack].children, symbols[i])
			symbols[i].parent = stack[#stack]
		end
	end

	local function dfs_index(node)
		if node.children == nil then return end
		for i = 1, #node.children, 1 do
			node.children[i].index = i
			dfs_index(node.children[i])
		end
		for i = 1, #node.children, 1 do
			local curr_node = node.children[i]
			if i ~= 1 then
				local prev_node = node.children[i - 1]
				prev_node.next = curr_node
				curr_node.prev = prev_node
			end
			if node.children[i + 1] ~= nil then
				local next_node = node.children[i + 1]
				next_node.prev = curr_node
				curr_node.next = next_node
			end
		end
	end

	dfs_index(root_node)
end

local function dfs(curr_symbol_layer, parent_node)
	if #curr_symbol_layer == 0 then return end
	parent_node.children = {}
	for _, val in ipairs(curr_symbol_layer) do
		local scope = val.range
		scope["start"].line = scope["start"].line + 1
		scope["end"].line = scope["end"].line + 1
		local name_range = val.selectionRange
		name_range["start"].line = name_range["start"].line + 1
		name_range["end"].line = name_range["end"].line + 1
		local curr_parsed_symbol = {
			name = val.name or "<???>",
			scope = scope,
			name_range = name_range,
			kind = val.kind or 0,
			parent = parent_node,
		}
		if val.children then
			dfs(val.children, curr_parsed_symbol)
		end
		table.insert(parent_node.children, curr_parsed_symbol)
	end
	table.sort(parent_node.children, function(a, b)
		if b.scope.start.line == a.scope.start.line then
			return b.scope.start.character > a.scope.start.character
		end
		return b.scope.start.line > a.scope.start.line
	end)
	for i = 1, #parent_node.children, 1 do
		parent_node.children[i].prev = parent_node.children[i - 1]
		parent_node.children[i].next = parent_node.children[i + 1]
		parent_node.children[i].index = i
	end
end

local function in_range(cursor_pos, range)
	local line = cursor_pos[1]
	local char = cursor_pos[2]
	if line < range["start"].line then return -1
	elseif line > range["end"].line then return 1
	end
	if line == range["start"].line and char < range["start"].character then return -1
	elseif line == range["end"].line and char > range["end"].character then return 1
	end
	return 0
end

function lib.parse(symbols)
	local root_node = {
		is_root = true,
		index = 1,
		scope = {
			start = { line = -10, character = 0 },
			["end"] = { line = 2147483640, character = 0 },
		},
	}
	if #symbols >= 1 and symbols[1].range == nil then
		symbolInfo_treemaker(symbols, root_node)
	else
		dfs(symbols, root_node)
	end
	return root_node
end

function lib.request_symbol(for_buf, handler, client, file_uri, retry_count)
	local textDocument_argument = vim.lsp.util.make_text_document_params()
	if retry_count == nil then
		retry_count = 10
	elseif retry_count == 0 then
		handler(for_buf, {})
		return
	end
	if file_uri ~= nil then
		textDocument_argument = { textDocument = { uri = file_uri } }
	end
	if not vim.api.nvim_buf_is_loaded(for_buf) then return end
	local function request(...)
		if vim.fn.has("nvim-0.11") == 1 then
			client:request(...)
		else
			client.request(...)
		end
	end
	request("textDocument/documentSymbol", { textDocument = textDocument_argument }, function(err, symbols, _)
		if err ~= nil then
			if vim.api.nvim_buf_is_valid(for_buf) then
				vim.defer_fn(function()
					lib.request_symbol(for_buf, handler, client, file_uri, retry_count - 1)
				end, 750)
			end
		elseif symbols == nil then
			if vim.api.nvim_buf_is_valid(for_buf) then
				handler(for_buf, {})
			end
		elseif symbols ~= nil then
			if vim.api.nvim_buf_is_loaded(for_buf) then
				handler(for_buf, symbols)
			end
		end
	end, for_buf)
end

local navic_symbols = {}
local navic_context_data = {}

function lib.get_tree(bufnr) return navic_symbols[bufnr] end
function lib.get_context_data(bufnr) return navic_context_data[bufnr] end

function lib.clear_buffer_data(bufnr)
	navic_context_data[bufnr] = nil
	navic_symbols[bufnr] = nil
end

function lib.update_data(for_buf, symbols)
	navic_symbols[for_buf] = lib.parse(symbols)
end

function lib.update_context(for_buf, arg_cursor_pos)
	local cursor_pos = arg_cursor_pos ~= nil and arg_cursor_pos or vim.api.nvim_win_get_cursor(0)
	if navic_context_data[for_buf] == nil then
		navic_context_data[for_buf] = {}
	end
	local old_context_data = navic_context_data[for_buf]
	local new_context_data = {}
	local curr = navic_symbols[for_buf]
	if curr == nil then return end
	if curr.is_root then
		table.insert(new_context_data, curr)
	end
	for _, context in ipairs(old_context_data) do
		if curr == nil then break end
		if
			in_range(cursor_pos, context.scope) == 0
			and curr.children ~= nil
			and curr.children[context.index] ~= nil
			and context.name == curr.children[context.index].name
			and context.kind == curr.children[context.index].kind
		then
			table.insert(new_context_data, curr.children[context.index])
			curr = curr.children[context.index]
		else
			break
		end
	end
	while curr.children ~= nil do
		local go_deeper = false
		local l = 1
		local h = #curr.children
		while l <= h do
			local m = bit.rshift(l + h, 1)
			local comp = in_range(cursor_pos, curr.children[m].scope)
			if comp == -1 then
				h = m - 1
			elseif comp == 1 then
				l = m + 1
			else
				table.insert(new_context_data, curr.children[m])
				curr = curr.children[m]
				go_deeper = true
				break
			end
		end
		if not go_deeper then break end
	end
	navic_context_data[for_buf] = new_context_data
end

-- stylua: ignore
local lsp_str_to_num = {
	File = 1, Module = 2, Namespace = 3, Package = 4, Class = 5,
	Method = 6, Property = 7, Field = 8, Constructor = 9, Enum = 10,
	Interface = 11, Function = 12, Variable = 13, Constant = 14,
	String = 15, Number = 16, Boolean = 17, Array = 18, Object = 19,
	Key = 20, Null = 21, EnumMember = 22, Struct = 23, Event = 24,
	Operator = 25, TypeParameter = 26,
}
setmetatable(lsp_str_to_num, { __index = function() return 0 end })

-- stylua: ignore
local lsp_num_to_str = {
	[1]="File",[2]="Module",[3]="Namespace",[4]="Package",[5]="Class",
	[6]="Method",[7]="Property",[8]="Field",[9]="Constructor",[10]="Enum",
	[11]="Interface",[12]="Function",[13]="Variable",[14]="Constant",
	[15]="String",[16]="Number",[17]="Boolean",[18]="Array",[19]="Object",
	[20]="Key",[21]="Null",[22]="EnumMember",[23]="Struct",[24]="Event",
	[25]="Operator",[26]="TypeParameter",
}
setmetatable(lsp_num_to_str, { __index = function() return "Text" end })

function lib.adapt_lsp_str_to_num(s) return lsp_str_to_num[s] end
function lib.adapt_lsp_num_to_str(n) return lsp_num_to_str[n] end

-- ── public API ────────────────────────────────────────────────────────────────

local M = {}

local config = {
	icons = {
		enabled = true,
		[1]  = "󰈙 ", [2]  = " ",  [3]  = "󰌗 ", [4]  = " ",  [5]  = "󰌗 ",
		[6]  = "󰆧 ", [7]  = " ",  [8]  = " ",  [9]  = " ",  [10] = "󰕘 ",
		[11] = "󰕘 ", [12] = "󰊕 ", [13] = "󰆧 ", [14] = "󰏿 ", [15] = "󰀬 ",
		[16] = "󰎠 ", [17] = "◩ ", [18] = "󰅪 ", [19] = "󰅩 ", [20] = "󰌋 ",
		[21] = "󰟢 ", [22] = " ",  [23] = "󰌗 ", [24] = " ",  [25] = "󰆕 ",
		[26] = "󰊄 ", [255] = "󰉨 ",
	},
	highlight = false,
	separator = " > ",
	depth_limit = 0,
	depth_limit_indicator = "..",
	safe_output = true,
	lazy_update_context = false,
	click = false,
	lsp = { auto_attach = false, preference = nil },
	format_text = function(a) return a end,
}
setmetatable(config.icons, { __index = function() return "? " end })

local function setup_auto_attach(opts)
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client.server_capabilities.documentSymbolProvider then return end
			local prev_client = vim.b[args.buf].navic_client_name
			if not prev_client or prev_client == client.name then
				return M.attach(client, args.buf)
			end
			if not opts.lsp.preference then
				return vim.notify(
					"nvim-navic: Trying to attach " .. client.name
					.. " for current buffer. Already attached to " .. prev_client
					.. ". Please use the preference option to set a higher preference for one of the servers",
					vim.log.levels.WARN
				)
			end
			for _, preferred_lsp in ipairs(opts.lsp.preference) do
				if preferred_lsp == client.name then
					vim.b[args.buf].navic_client_id = nil
					vim.b[args.buf].navic_client_name = nil
					return M.attach(client, args.buf)
				elseif preferred_lsp == prev_client then
					return
				end
			end
		end,
	})
end

function M.setup(opts)
	if opts == nil then return end
	if opts.lsp ~= nil and opts.lsp.auto_attach then
		setup_auto_attach(opts)
	end
	if opts.icons ~= nil then
		for k, v in pairs(opts.icons) do
			if lib.adapt_lsp_str_to_num(k) then
				config.icons[lib.adapt_lsp_str_to_num(k)] = v
			end
		end
		if opts.icons.enabled ~= nil then config.icons.enabled = opts.icons.enabled end
	end
	if opts.separator ~= nil then config.separator = opts.separator end
	if opts.depth_limit ~= nil then config.depth_limit = opts.depth_limit end
	if opts.depth_limit_indicator ~= nil then config.depth_limit_indicator = opts.depth_limit_indicator end
	if opts.highlight ~= nil then config.highlight = opts.highlight end
	if opts.safe_output ~= nil then config.safe_output = opts.safe_output end
	if opts.lazy_update_context then config.lazy_update_context = opts.lazy_update_context end
	if opts.click then config.click = opts.click end
	if opts.format_text then
		vim.validate({ format_text = { opts.format_text, "f" } })
		config.format_text = opts.format_text
	end
end

function M.get_data(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local context_data = lib.get_context_data(bufnr)
	if context_data == nil then return nil end
	local ret = {}
	for i, v in ipairs(context_data) do
		if i ~= 1 then
			table.insert(ret, {
				kind  = v.kind,
				type  = lib.adapt_lsp_num_to_str(v.kind),
				name  = v.name,
				icon  = config.icons[v.kind],
				scope = v.scope,
			})
		end
	end
	return ret
end

function M.is_available(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	return vim.b[bufnr].navic_client_id ~= nil
end

function M.format_data(data, opts)
	if data == nil then return "" end
	local local_config
	if opts ~= nil then
		local_config = vim.deepcopy(config)
		if opts.icons ~= nil then
			for k, v in pairs(opts.icons) do
				if lib.adapt_lsp_str_to_num(k) then
					local_config.icons[lib.adapt_lsp_str_to_num(k)] = v
				end
			end
			if opts.icons.enabled ~= nil then local_config.icons.enabled = opts.icons.enabled end
		end
		if opts.separator ~= nil then local_config.separator = opts.separator end
		if opts.depth_limit ~= nil then local_config.depth_limit = opts.depth_limit end
		if opts.depth_limit_indicator ~= nil then local_config.depth_limit_indicator = opts.depth_limit_indicator end
		if opts.highlight ~= nil then local_config.highlight = opts.highlight end
		if opts.safe_output ~= nil then local_config.safe_output = opts.safe_output end
		if opts.click ~= nil then local_config.click = opts.click end
	else
		local_config = config
	end

	local location = {}

	local function add_hl(kind, name)
		local icon_part = ""
		if local_config.icons.enabled then
			icon_part = "%#NavicIcons"
				.. lib.adapt_lsp_num_to_str(kind)
				.. "#"
				.. local_config.icons[kind]
				.. "%*"
		end
		return icon_part .. "%#NavicText#" .. config.format_text(name) .. "%*"
	end

	if local_config.click then
		_G.navic_click_handler = function(minwid, cnt, _, _)
			vim.cmd("normal! m'")
			vim.api.nvim_win_set_cursor(0, {
				data[minwid].scope["start"].line,
				data[minwid].scope["start"].character,
			})
			if cnt > 1 then
				local ok, navbuddy = pcall(require, "nvim-navbuddy")
				if ok then
					navbuddy.open()
				else
					vim.notify("nvim-navic: Double click requires nvim-navbuddy to be installed.", vim.log.levels.WARN)
				end
			end
		end
	end

	local function add_click(level, component)
		return "%" .. level .. "@v:lua.navic_click_handler@" .. component .. "%X"
	end

	for i, v in ipairs(data) do
		local name = ""
		if local_config.safe_output then
			name = string.gsub(v.name, "%%", "%%%%")
			name = string.gsub(name, "\n", " ")
		else
			name = v.name
		end

		local component
		if local_config.highlight then
			component = add_hl(v.kind, name)
		else
			if local_config.icons.enabled then
				component = v.icon .. name
			else
				component = name
			end
		end

		if local_config.click then
			component = add_click(i, component)
		end

		table.insert(location, component)
	end

	if local_config.depth_limit ~= 0 and #location > local_config.depth_limit then
		location = vim.list_slice(location, #location - local_config.depth_limit + 1, #location)
		if local_config.highlight then
			table.insert(location, 1, "%#NavicSeparator#" .. local_config.depth_limit_indicator .. "%*")
		else
			table.insert(location, 1, local_config.depth_limit_indicator)
		end
	end

	if local_config.highlight then
		return table.concat(location, "%#NavicSeparator#" .. local_config.separator .. "%*")
	else
		return table.concat(location, local_config.separator)
	end
end

function M.get_location(opts, bufnr)
	return M.format_data(M.get_data(bufnr), opts)
end

local awaiting_lsp_response = {}

local function lsp_callback(for_buf, symbols)
	awaiting_lsp_response[for_buf] = false
	lib.update_data(for_buf, symbols)
end

function M.attach(client, bufnr)
	if not client.server_capabilities.documentSymbolProvider then
		if not vim.g.navic_silence then
			vim.notify(
				'nvim-navic: Server "' .. client.name .. '" does not support documentSymbols.',
				vim.log.levels.ERROR
			)
		end
		return
	end

	if vim.b[bufnr].navic_client_id ~= nil and vim.b[bufnr].navic_client_name ~= client.name then
		local prev_client = vim.b[bufnr].navic_client_name
		if not vim.g.navic_silence then
			vim.notify(
				"nvim-navic: Failed to attach to " .. client.name
				.. " for current buffer. Already attached to " .. prev_client,
				vim.log.levels.WARN
			)
		end
		return
	end

	vim.b[bufnr].navic_client_id   = client.id
	vim.b[bufnr].navic_client_name = client.name
	local changedtick = 0

	local navic_augroup = vim.api.nvim_create_augroup("navic", { clear = false })
	vim.api.nvim_clear_autocmds({ buffer = bufnr, group = navic_augroup })

	vim.api.nvim_create_autocmd({ "InsertLeave", "BufEnter", "CursorHold" }, {
		callback = function()
			if not awaiting_lsp_response[bufnr] and changedtick < vim.b[bufnr].changedtick then
				awaiting_lsp_response[bufnr] = true
				changedtick = vim.b[bufnr].changedtick
				lib.request_symbol(bufnr, lsp_callback, client)
			end
		end,
		group = navic_augroup,
		buffer = bufnr,
	})

	vim.api.nvim_create_autocmd("CursorHold", {
		callback = function() lib.update_context(bufnr) end,
		group = navic_augroup,
		buffer = bufnr,
	})

	if not config.lazy_update_context then
		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			callback = function()
				if vim.b.navic_lazy_update_context ~= true then
					lib.update_context(bufnr)
				end
			end,
			group = navic_augroup,
			buffer = bufnr,
		})
	end

	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function() lib.clear_buffer_data(bufnr) end,
		group = navic_augroup,
		buffer = bufnr,
	})

	vim.b[bufnr].navic_awaiting_lsp_response = true
	lib.request_symbol(bufnr, lsp_callback, client)
end

return M
