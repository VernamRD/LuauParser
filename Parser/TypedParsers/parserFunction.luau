--!strict
--[[
	ParserFunction

	Recognizes a function/method declaration: "<ret_type> <name>(<args>)".
	Produces a ParsedDecl of kind Function. If the declaration is a
	non-static method of a class/struct, prepends a synthetic `self`
	argument (typed as Userdata, resolved to the fully-qualified class
	name) so downstream codegen doesn't need to special-case it.
]]

local ParserFunction = {}

local ParserTypes = require("../../parserTypes")

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
	local args: { string } = {}
	if args_str:match("^%s*$") then
		return {}
	end

	local depth = 0
	local current = ""
	for char in args_str:gmatch(".") do
		if char == "(" or char == "<" then
			depth += 1
			current ..= char
		elseif char == ")" or char == ">" then
			depth -= 1
			current ..= char
		elseif char == "," and depth == 0 then
			table.insert(args, current)
			current = ""
		else
			current ..= char
		end
	end

	if current:match("%S") then
		table.insert(args, current)
	end

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
	Instance methods implicitly take a `self` argument. If this decl is a
	non-static method inside a class/struct, prepend a synthetic `self`
	arg (typed as Userdata, resolved to the fully-qualified class name)
	so downstream codegen doesn't need to special-case it.
]]
local function prepend_self_argument(args: { ParserTypes.ParsedArg }, context): { ParserTypes.ParsedArg }
	if context.is_static or not context.is_field then
		return args
	end

	if not context.scope or #context.scope <= 0 then
		return args
	end

	local last_scope = context.scope[#context.scope]
	if last_scope.kind ~= ParserTypes.ScopeKind.Class and last_scope.kind ~= ParserTypes.ScopeKind.Struct then
		return args
	end

	local self_arg: ParserTypes.ParsedArg = {
		name = "self",
		type = ParserTypes.ParsedArgType.Userdata,
		-- Must resolve the self type through the full scope chain,
		-- e.g. "Namespace::Namespace::Class".
		original_type = ParserTypes.concat_scope(context.scope),
		is_self = true,
	}

	table.insert(args, 1, self_arg)
	return args
end

function ParserFunction.try_parse(context: ParserTypes.ParseContext): ParserTypes.ParsedDecl?
	local decl_str = context.decl_str

	-- Match "<ret_type> <fn_name>(<args>)". Both captures are typed as
	-- `string?` by Luau; checking both together narrows them to `string`.
	local ret_and_name, args_str = decl_str:match("^(.-)%s*%((.*)%)%s*$")
	if not ret_and_name or not args_str then
		return nil
	end

	-- e.g. ret_and_name = "RayIntersectionResult Intersects"
	local ret_type, fn_name = ret_and_name:match("^(.-)%s+([%w_:~]+)%s*$")
	if not ret_type or not fn_name then
		return nil
	end

	local args = parse_arguments(args_str)
	args = prepend_self_argument(args, context)

	return {
		kind = ParserTypes.DeclKind.Function,
		name = fn_name,
		scope = context.scope,
		["function"] = {
			ret_type = parse_type(ret_type),
			ret_original_type = ret_type,
			args = args,
			is_const = context.is_const,
			is_static = context.is_static,
			is_field = context.is_field,
		},
	}
end

return ParserFunction