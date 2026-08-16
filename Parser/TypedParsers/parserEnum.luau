--!strict
--[[
	ParserEnum

	Recognizes an enum/enum class declaration and parses its full body
	(reading forward from declaration_line until the matching closing
	brace) into a list of name/value pairs, computing implicit values
	via C++ auto-increment semantics where no explicit value is given.
]]

local ParserEnum = {}
local ParserTypes = require("../../parserTypes")

local function collect_enum_body(file_lines: { string }, start_line: number): (string, number)
	local depth = 0
	local body = ""
	local line_index = start_line
	local started = false

	while line_index <= #file_lines do
		local line = file_lines[line_index]
		for char in line:gmatch(".") do
			if char == "{" then
				depth += 1
				started = true
			elseif char == "}" then
				depth -= 1
			end
		end
		body = body .. " " .. line
		line_index += 1
		if started and depth <= 0 then
			break
		end
	end

	return body, line_index - start_line
end

function ParserEnum.try_parse(context: ParserTypes.ParseContext): ParserTypes.ParsedDecl?
	local decl_str = context.decl_str

	local is_enum_class: string?, name: string?, underlying_type: string?

	is_enum_class, name, underlying_type = decl_str:match("^%s*enum%s+(class)%s+([%w_]+)%s*:%s*([%w_:]+)")
	if not name then
		is_enum_class, name = decl_str:match("^%s*enum%s+(class)%s+([%w_]+)")
	end
	if not name then
		name, underlying_type = decl_str:match("^%s*enum%s+([%w_]+)%s*:%s*([%w_:]+)")
	end
	if not name then
		name = decl_str:match("^%s*enum%s+([%w_]+)")
	end

	if not name then
		return nil
	end

	local body = decl_str
	if not decl_str:find("{") then
		local collected = collect_enum_body(context.file_lines, context.declaration_line + 1)
		body = decl_str .. " " .. collected
	end

	local braces_content = body:match("{(.*)}") or ""

	local values: { ParserTypes.EnumValueDecl } = {}
	local next_implicit_value = 0

	for entry in braces_content:gmatch("[^,]+") do
		local trimmed = entry:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			local value_name, value_expr = trimmed:match("^([%w_]+)%s*=%s*(.+)$")
			if value_name and value_expr then
				local numeric = tonumber(value_expr)
				table.insert(values, { name = value_name, value = numeric })
				if numeric then
					next_implicit_value = numeric + 1
				end
			else
				table.insert(values, { name = trimmed, value = next_implicit_value })
				next_implicit_value += 1
			end
		end
	end

    -- Register this class so other declarations can resolve references to
	-- it. Full scope = the declaration's own scope chain + this class's
	-- own name appended at the end (a class's "self scope" includes itself).
	local full_scope: { ParserTypes.ScopeDecl } = table.clone(context.scope)
	table.insert(full_scope, {
		kind = ParserTypes.ScopeKind.Enum,
		name = name,
	})

    table.insert(context.registry, {
		name = name,
		scope = full_scope,
		header = context.header_path,
		kind = ParserTypes.DeclKind.Enum,
	})

	return {
		kind = ParserTypes.DeclKind.Enum,
		name = name,
		scope = context.scope,
		["enum"] = {
			underlying_type = underlying_type,
			is_enum_class = is_enum_class ~= nil,
			values = values,
		},
	}
end

return ParserEnum