--!strict
--[[
	ParserDeclaration

	Parses a single C++-like declaration string (as captured by the tokenizer)
	into a structured ParsedDecl: function name, return type, arguments,
	attributes (e.g. nodiscard, -style tags), and modifiers (static/const).
]]

local ParserDeclaration = {}

local ParserTypes = require("../parserTypes")
local ParserFunction = require("TypedParsers/parserFunction")
local ParserVariable = require("TypedParsers/parserVariable")
local ParserClass = require("TypedParsers/parserClass")
local ParserEnum = require("TypedParsers/parserEnum")

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
	Parses a single declaration (function or field) into a ParsedDecl.
	Strips `static`/`const` modifiers, detects whether it's a class/struct
	field (as opposed to free/namespace-scope), and-if it looks like a
	function-parses its return type, name and arguments.
]]
local function strip_trailing_qualifiers(str: string): string
	local result = str
	local qualifiers: { string } = { "const", "noexcept", "override", "final", "volatile" }

	local changed = true
	while changed do
		changed = false
		for _, qualifier in ipairs(qualifiers) do
			local next_result = result:gsub("%s+" .. qualifier .. "%s*$", "")
			if next_result ~= result then
				result = next_result
				changed = true
			end
		end
	end

	return result
end

--[[
	Strips trailing qualifiers (const, noexcept, override, final, volatile)
	and leading modifiers (static, inline, constexpr, virtual, explicit),
	returning the cleaned text plus the flags that were found. Shared by
	every sub-parser so each one only deals with the "core" declaration.
]]
local function strip_qualifiers(decl_str: string): (string, boolean, boolean)
	local result = decl_str:gsub(";%s*$", "")

	local trailing_qualifiers: { string } = { "const", "noexcept", "override", "final", "volatile" }
	local is_const = false
	local trailing_changed = true
	while trailing_changed do
		trailing_changed = false
		for _, qualifier in ipairs(trailing_qualifiers) do
			local next_result = result:gsub("%s+" .. qualifier .. "%s*$", "")
			if next_result ~= result then
				if qualifier == "const" then
					is_const = true
				end
				result = next_result
				trailing_changed = true
			end
		end
	end

	local leading_modifiers: { string } = { "static", "inline", "constexpr", "virtual", "explicit" }
	local is_static = false
	local leading_changed = true
	while leading_changed do
		leading_changed = false
		for _, keyword in leading_modifiers do
			local pattern = "^%s*" .. keyword .. "%s+"
			if result:match(pattern) then
				if keyword == "static" then
					is_static = true
				end
				result = result:gsub(pattern, "")
				leading_changed = true
			end
		end
	end

	return result, is_static, is_const
end

--[[
	Entry point: parses a batch of raw LuauDecl entries into ParsedDecl entries,
	attaching attributes/scope and injecting the implicit `self` arg where needed.
]]
function ParserDeclaration.parse_luau_decl(file_lines: { string }, decls: { ParserTypes.LuauDecl }, registry: ParserTypes.TypeRegistry, header_path: string): { ParserTypes.ParsedDecl }
	local parsed_decls: { ParserTypes.ParsedDecl } = {}

	for _, luau_decl in ipairs(decls) do
		local decl_str, is_static, is_const = strip_qualifiers(luau_decl.declaration_str)
		local is_field = false
		if luau_decl.scope and #luau_decl.scope > 0 then
			local last_scope = luau_decl.scope[#luau_decl.scope]
			if last_scope.kind == ParserTypes.ScopeKind.Class or last_scope.kind == ParserTypes.ScopeKind.Struct then
				is_field = true
			end
		end

		local context: ParserTypes.ParseContext = {
			decl_str = decl_str,
			is_static = is_static,
			is_const = is_const,
			is_field = is_field,
			scope = luau_decl.scope,
			file_lines = file_lines,
			declaration_line = luau_decl.declaration_line,
			header_path = header_path,
			registry = registry,
		}

		-- Try each sub-parser in order; first one that recognizes the
		-- shape wins. Class/enum checked first (unambiguous keywords),
		-- then function (has "(...)"), then variable as the fallback.
		local parsed_decl: ParserTypes.ParsedDecl? =
			ParserClass.try_parse(context)
			or ParserEnum.try_parse(context)
			or ParserFunction.try_parse(context)
			or ParserVariable.try_parse(context)

		if not parsed_decl then
			parsed_decl = {
				kind = ParserTypes.DeclKind.Unknown,
				name = luau_decl.declaration_str,
				scope = luau_decl.scope,
			}
		end

		if parsed_decl then 
			parsed_decl.attributes = parse_attributes(luau_decl.attributes_str)
			parsed_decl.scope = luau_decl.scope
			table.insert(parsed_decls, parsed_decl)
		end
	end

	return parsed_decls
end

return ParserDeclaration