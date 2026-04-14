local ParserDeclaration = {}

local ParserTypes = require("parserTypes")

local function parse_attributes(attr_str: string): { ParserTypes.LuauAttr }	
	local attributes: { [string]: string | boolean } = {}

	-- Search pattern: key, then either ="value" or nothing
	-- %w+ - key
	-- %s*=%s*"([^"]*)" - optional part with the value in quotes
	for key, val in attr_str:gmatch('(%w+)%s*=%s*"([^"]*)"') do
		attributes[key] = val
	end

	-- To correctly handle flags without touching values,
	-- it's easiest to remove already-found key="val" pairs from the string
	local flags_str = attr_str:gsub('%w+%s*=%s*"[^"]*"', "")

	for flag in flags_str:gmatch('(%w+)') do
		attributes[flag] = true
	end

	local parsed_attributes: { ParserTypes.LuauAttr } = {}
	for key, flag in attributes do
		local type: ParserTypes.LuauAttrType = ParserTypes.LuauAttrType.Undefined

		for known_type, known_type_str: string in ParserTypes.LuauAttrType do
			if key == known_type_str then
				type = known_type
				break
			end
		end

		table.insert(parsed_attributes, {
			type = type,
			value = flag
		})
	end


	return parsed_attributes
end

local function parse_type(str: string): ParserTypes.ParsedArgType
	local trimmed = str:match("^%s*(.-)%s*$") or "???"
	if trimmed then
        return (ParserTypes.ArgTypeMapping[trimmed] or ParserTypes.ParsedArgType.Nil)
    end

	return ParserTypes.ParsedArgType.Nil
end

local function parse_arguments(args_str: string): {ParserTypes.ParsedArg}
	local args = {}
	if args_str:match("^%s*$") then
		return args
	end

	local depth = 0
	local current = ""
	for char in args_str:gmatch(".") do
		if char == "(" or char == "<" then
			depth += 1
			current = current .. char
		elseif char == ")" or char == ">" then
			depth -= 1
			current = current .. char
		elseif char == "," and depth == 0 then
			table.insert(args, current)
			current = ""
		else
			current = current .. char
		end
	end

	if current:match("%S") then
		table.insert(args, current)
	end

	local result = {}
	for _, arg in ipairs(args) do
		arg = arg:match("^%s*(.-)%s*$")

		local default = nil
		-- Trim default value if it exists
		local before_default, def = arg:match("^(.-)%s*=%s*(.+)$")
		if before_default then
			arg = before_default:match("^%s*(.-)%s*$")
			default = def:match("^%s*(.-)%s*$")
		end

		-- Arg name is the last word before the default value
		-- Type is everything before the name
		local arg_type, arg_name = arg:match("^(.-)%s+([%w_]+)%s*$")

		if arg_name then
			table.insert(result, {
				name    = arg_name,
				type    = parse_type(arg_type),
				original_type = arg_type,
				default = default,
			})
		end
	end

	return result
end

local function parse_declaration(decl: string): ParserTypes.ParsedDecl
	decl = decl:gsub(";%s*$", "") -- Remove trailing semicolon

	local is_static = false
	local is_const = false

	-- Remove "static" keyword if it exists
	if decl:match("^%s*static%s+") then
		is_static = true
		decl = decl:gsub("^%s*static%s+", "")
	end

	-- Remove "const" keyword if it exists
	if decl:match("%s+const%s*$") then
		is_const = true
		decl = decl:gsub("%s+const%s*$", "")
	end

	-- Try to match function declaration pattern: "ret_type fn_name(args)"
	local ret_and_name, args_str = decl:match("^(.-)%s*%((.*)%)%s*$")
	if ret_and_name then
	-- ret_and_name = "RayIntersectionResult Intersects"
		local ret_type, fn_name = ret_and_name:match("^(.-)%s+([%w_:~]+)%s*$")
		if fn_name then
			return {
				kind     = ParserTypes.DeclKind.Function,
				name     = fn_name,
				ret_type = parse_type(ret_type),
				ret_original_type = ret_type,
				args     = parse_arguments(args_str),
				is_const = is_const,
				is_static = is_static,
			}
		end
	end

	local field_decl = decl:gsub("%s*=.*$", "") -- убираем = value
	local field_type, field_name = field_decl:match("^(.-)%s+([%w_]+)%s*$")
	if field_name then
		return {
			kind       = ParserTypes.DeclKind.Field,
			name       = field_name,
			field_type = parse_type(field_type),
			is_const   = is_const,
			is_static  = is_static,
		}
	end

	return { kind = ParserTypes.DeclKind.Unknown, name = decl, is_const = is_const, is_static = is_static }
end

function ParserDeclaration.parse_luau_decl(file_lines: {string}, decls: {ParserTypes.LuauDecl}): {ParserTypes.ParsedDecl}
	local parsed_decls: {ParserTypes.ParsedDecl} = {}
	for _, luau_decl in pairs(decls) do
		local parsed_decl: ParserTypes.ParsedDecl = parse_declaration(luau_decl.declaration_str)
		parsed_decl.attributes = parse_attributes(luau_decl.attributes_str)
		parsed_decl.scope = luau_decl.scope
		table.insert(parsed_decls, parsed_decl)
	end

	return parsed_decls
end

function ParserDeclaration.print_parsed_decl(parsed_decl: ParserTypes.ParsedDecl)
	print("kind: " .. parsed_decl.kind)
	print("\tname: " .. parsed_decl.name)
	if parsed_decl.scope then
		print("\tscope: " .. table.concat(parsed_decl.scope, "::"))
	end

	print("\tattributes: ")
	if parsed_decl.attributes then
		for _, attr in pairs(parsed_decl.attributes) do
			print("\t\t" .. attr.type .. ": " .. tostring(attr.value))
		end
	end

	if parsed_decl.ret_type then
		print("\tret_type: " .. parsed_decl.ret_type)
	end
	print("\tis_const: " .. tostring(parsed_decl.is_const))

	if parsed_decl.args then
		for i, arg in parsed_decl.args do
			print(string.format("\t\targ[%d]: %s %s%s", i, arg.type, arg.name,
			arg.default and (" = " .. arg.default) or ""))
		end
	end
end

return ParserDeclaration