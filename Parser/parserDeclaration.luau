--!strict
--[[
	ParserDeclaration

	Parses a single C++-like declaration string (as captured by the tokenizer)
	into a structured ParsedDecl: function name, return type, arguments,
	attributes (e.g. nodiscard, -style tags), and modifiers (static/const).
]]

local ParserDeclaration = {}

local ParserTypes = require("../parserTypes")

--[[
	Parses a raw attribute string such as `nodiscard, deprecated="use Foo instead"`
	into a list of LuauAttr entries.

	Attributes can appear either as:
		- key="value"   -> stored with the given string value
		- key           -> a bare flag, stored as boolean `true`
]]
local function parse_attributes(attr_str: string): { ParserTypes.LuauAttr }
	local attributes: { [string]: string | boolean } = {}

	-- Step 1: collect all key="value" pairs.
	-- %w+                 - key
	-- %s*=%s*"([^"]*)"    - '=' followed by a quoted value
	-- (gmatch captures are typed as `string?` by Luau, so we narrow with `if`
	-- before writing into `attributes`, which expects non-nil string|boolean.)
	for key, val in attr_str:gmatch('(%w+)%s*=%s*"([^"]*)"') do
		if key and val then
			attributes[key] = val
		end
	end

	-- Step 2: strip out the key="value" pairs we already consumed, so that
	-- what's left can only contain bare flags (no values to accidentally
	-- match as flag names).
	local flags_str = attr_str:gsub('%w+%s*=%s*"[^"]*"', "")

	for flag in flags_str:gmatch("(%w+)") do
		if flag then
			attributes[flag] = true
		end
	end

	-- Step 3: convert the {key -> value} map into the LuauAttr array shape,
	-- resolving each key to its known LuauAttrType (or Undefined if unknown).
	local parsed_attributes: { ParserTypes.LuauAttr } = {}
	for key, value in attributes do
		local attr_type: ParserTypes.LuauAttrType = ParserTypes.LuauAttrType.Undefined

		for known_type, known_type_str: string in ParserTypes.LuauAttrType do
			if key == known_type_str then
				attr_type = known_type
				break
			end
		end

		table.insert(parsed_attributes, {
			type = attr_type,
			value = value,
		})
	end

	return parsed_attributes
end

--[[
	Resolves a raw C++ type string (e.g. "const FString&") to our internal
	ParsedArgType enum, falling back to `Nil` for anything unrecognized.
]]
local function parse_type(str: string): ParserTypes.ParsedArgType
	local trimmed = str:match("^%s*(.-)%s*$") or ""
	return ParserTypes.ArgTypeMapping[trimmed] or ParserTypes.ParsedArgType.Nil
end

--[[
	Splits a raw argument list string (the contents between the parentheses
	of a function declaration) into individual ParsedArg entries.

	A naive `,`-split would break on types containing commas themselves
	(e.g. `TMap<FString, int32>` or `TFunction<void(int32)>`), so we track
	nesting depth across '(' '<' ... ')' '>' pairs and only split on commas
	that are at depth 0.
]]
local function parse_arguments(args_str: string): { ParserTypes.ParsedArg }
	-- NOTE: explicitly typed as {string}. Without this annotation Luau would
	-- unify `args` with the function's declared return type (because of the
	-- early `return {}` below living in the same scope), turning every
	-- string pushed into it into a type error.
	local args: { string } = {}
	if args_str:match("^%s*$") then
		return {}
	end

	-- Split on top-level commas, ignoring commas nested inside () or <>.
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

	-- Parse each raw "type name[ = default]" chunk.
	local result: { ParserTypes.ParsedArg } = {}
	for _, raw_arg in ipairs(args) do
		local arg = raw_arg:match("^%s*(.-)%s*$") or raw_arg

		-- Split off the default value, if any (everything after the last '=').
		local default: string? = nil
		local before_default, def = arg:match("^(.-)%s*=%s*(.+)$")
		if before_default and def then
			arg = before_default:match("^%s*(.-)%s*$") or before_default
			default = def:match("^%s*(.-)%s*$") or def
		end

		-- The argument name is the last identifier-like word; everything
		-- before it is the type, e.g. "const FString& InName" -> type="const FString&", name="InName".
		local arg_type, arg_name = arg:match("^(.-)%s+([%w_]+)%s*$")

		if arg_type and arg_name then
			table.insert(result, {
				name = arg_name,
				type = parse_type(arg_type),
				original_type = arg_type,
				default = default,
			})
		end
	end

	return result
end

--[[
	Parses a single declaration (function or field) into a ParsedDecl.
	Strips `static`/`const` modifiers, detects whether it's a class/struct
	field (as opposed to free/namespace-scope), and-if it looks like a
	function-parses its return type, name and arguments.
]]
local function parse_declaration(decl: ParserTypes.LuauDecl): ParserTypes.ParsedDecl
	local decl_str = decl.declaration_str:gsub(";%s*$", "") -- Drop trailing semicolon, if any.

	local is_static = false
	local is_const = false
	local is_field = false

	-- Leading modifier keywords to strip from the declaration, in any order,
	-- repeated until none match. Add new keywords here as they come up
	-- (e.g. constexpr, virtual, explicit) — no other code needs to change.
	local leading_modifier_keywords: { string } = {
		"static",
		"inline",
		"constexpr",
		"virtual",
		"explicit",
	}

	local stripped = true
	while stripped do
		stripped = false
		for _, keyword in leading_modifier_keywords do
			local pattern = "^%s*" .. keyword .. "%s+"
			if decl_str:match(pattern) then
				if keyword == "static" then
					is_static = true
				end
				decl_str = decl_str:gsub(pattern, "")
				stripped = true
			end
		end
	end

	-- A declaration is a "field" (as opposed to a free function) if its
	-- innermost enclosing scope is a class or struct.
	if decl.scope and #decl.scope > 0 then
		local last_scope = decl.scope[#decl.scope]
		if last_scope.kind == ParserTypes.ScopeKind.Class or last_scope.kind == ParserTypes.ScopeKind.Struct then
			is_field = true
		end
	end

	-- Try to match a function declaration pattern: "<ret_type> <fn_name>(<args>)".
	-- Both captures are typed as `string?` by Luau; checking both together
	-- in the `if` narrows them to plain `string` inside the block.
	local ret_and_name, args_str = decl_str:match("^(.-)%s*%((.*)%)%s*$")
	if ret_and_name and args_str then
		-- e.g. ret_and_name = "RayIntersectionResult Intersects"
		local ret_type, fn_name = ret_and_name:match("^(.-)%s+([%w_:~]+)%s*$")
		if ret_type and fn_name then
			return {
				kind = ParserTypes.DeclKind.Function,
				name = fn_name,
				ret_type = parse_type(ret_type),
				ret_original_type = ret_type,
				args = parse_arguments(args_str),
				is_const = is_const,
				is_static = is_static,
				is_field = is_field,
				scope = {}, -- scope will be filled in later by the caller
			}
		end
	end

	-- Fallback: doesn't look like a function, so record it as an unknown/plain declaration.
	return {
		kind = ParserTypes.DeclKind.Unknown,
		name = decl.declaration_str,
		is_const = is_const,
		is_static = is_static,
		is_field = is_field,
		scope = {}, -- scope will be filled in later by the caller
	}
end

--[[
	Instance methods implicitly take a `self` argument. If this declaration
	is a non-static field inside a class, prepend a synthetic `self` arg
	(typed as Userdata, resolved to the fully-qualified class name) so
	downstream codegen doesn't need to special-case it.
]]
local function parse_self_arguments(parsed_decl: ParserTypes.ParsedDecl)
	if parsed_decl.is_static or not parsed_decl.is_field then
		return
	end

	if not parsed_decl.scope or #parsed_decl.scope <= 0 then
		return
	end

	local last_scope = parsed_decl.scope[#parsed_decl.scope]
	if last_scope.kind == ParserTypes.ScopeKind.Class then
		local self_arg: ParserTypes.ParsedArg = {
			name = "self",
			type = ParserTypes.ParsedArgType.Userdata,
			-- Must resolve the self type through the full scope chain,
			-- e.g. "Namespace::Namespace::Class".
			original_type = ParserTypes.concat_scope(parsed_decl.scope),
			is_self = true,
		}

		if parsed_decl.args then
			table.insert(parsed_decl.args, 1, self_arg)
		else
			parsed_decl.args = { self_arg }
		end
	end
end

--[[
	Entry point: parses a batch of raw LuauDecl entries into ParsedDecl entries,
	attaching attributes/scope and injecting the implicit `self` arg where needed.
]]
function ParserDeclaration.parse_luau_decl(file_lines: { string }, decls: { ParserTypes.LuauDecl }): { ParserTypes.ParsedDecl }
	local parsed_decls: { ParserTypes.ParsedDecl } = {}

	for _, luau_decl in ipairs(decls) do
		local parsed_decl: ParserTypes.ParsedDecl = parse_declaration(luau_decl)
		parsed_decl.attributes = parse_attributes(luau_decl.attributes_str)
		parsed_decl.scope = luau_decl.scope
		parse_self_arguments(parsed_decl)
		table.insert(parsed_decls, parsed_decl)
	end

	return parsed_decls
end

--[[
	Debug helper: pretty-prints a single ParsedDecl to stdout.
]]
function ParserDeclaration.print_parsed_decl(parsed_decl: ParserTypes.ParsedDecl)
	print("kind: " .. parsed_decl.kind)
	print("\tname: " .. parsed_decl.name)

	if parsed_decl.scope then
		print("\tscope: " .. table.concat(parsed_decl.scope, "::"))
	end

	print("\tattributes: ")
	if parsed_decl.attributes then
		for _, attr in parsed_decl.attributes do
			print("\t\t" .. attr.type .. ": " .. tostring(attr.value))
		end
	end

	if parsed_decl.ret_type then
		print("\tret_type: " .. parsed_decl.ret_type)
	end
	print("\tis_const: " .. tostring(parsed_decl.is_const))

	if parsed_decl.args then
		for i, arg in parsed_decl.args do
			print(string.format("\t\targ[%d]: %s %s%s", i, arg.type, arg.name, arg.default and (" = " .. arg.default) or ""))
		end
	end
end

return ParserDeclaration