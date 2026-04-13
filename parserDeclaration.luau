local ParserDeclaration = {}

local parserTypes = require("./parserTypes")
local ParserTypes = require("parserTypes")

local function parse_attributes(attr_str: string)
	local attributes = {}

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

	return attributes
end


function ParserDeclaration.parse_header(content: string)
	local result: {ParserTypes.LuauDecl} = {}

	local lines: {string} = {}
	for line in content:gmatch("[^\n]+") do
		table.insert(lines, line)
	end

	local i = 1
	while i <= #lines do
		local line = lines[i]

		local attr_str = line:match("@luau%s*(.*)")
		if attr_str then
		-- Remove trailing whitespace and optional * or / characters
			attr_str = attr_str:match("^(.-)%s*%*?/?%s*$")

			local attributes = parse_attributes(attr_str)

			-- Find declaration line after attributes
			local j = i + 1
			while j <= #lines and lines[j]:match("^%s*$") do
				j = j + 1
			end

			local decl_line = lines[j] or ""
			decl_line = decl_line:match("^%s*(.-)%s*$") -- Match function or variable declaration

			local decl: parserTypes.LuauDecl = {
				attributes_line = i,
				attributes_str = attr_str,
				declaration_line = j,
				declaration_strs = {decl_line},
				scope = nil, -- Scope parsing can be added later
			}
			table.insert(result, decl)

			-- Skip to the line after the declaration for the next iteration
			i = j
		end
		i = i + 1
	end

	return result
end

local function parse_type(str: string): string
-- Remove leading/trailing whitespace
	return str:match("^%s*(.-)%s*$")
end

local function parse_arguments(args_str: string): {{name: string, type: string, default: string?}}
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
				default = default,
			})
		end
	end

	return result
end

function parse_declaration(decl: string): PareserTypes.ParsedDecl
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
				kind     = "function",
				name     = fn_name,
				ret_type = parse_type(ret_type),
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
			kind       = "field",
			name       = field_name,
			field_type = parse_type(field_type),
			is_const   = is_const,
			is_static  = is_static,
		}
	end

	return { kind = "unknown", name = decl, is_const = is_const, is_static = is_static }
end

function ParserDeclaration.print_parsed_decl(parsed_decl: PareserTypes.ParsedDecl)
	for _, entry in ipairs(parsed_decl) do
		print("DECL: " .. entry.declaration)
		local parsed_decl = parse_declaration(entry.declaration)
		print("kind:     " .. parsed_decl.kind)
		print("name:     " .. parsed_decl.name)
		print("ret_type: " .. parsed_decl.ret_type)
		print("is_const: " .. tostring(parsed_decl.is_const))
		for i, arg in ipairs(parsed_decl.args) do
			print(string.format("  arg[%d]: %s %s%s", i, arg.type, arg.name,
				arg.default and (" = " .. arg.default) or ""))
		end


		print("ATTRS:")
		for k, v in pairs(entry.attributes) do
			print("  " .. k .. " = " .. tostring(v))
		end
	end
end

return ParserDeclaration