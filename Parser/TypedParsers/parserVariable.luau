--!strict
--[[
	ParserVariable

	Recognizes a plain variable or class/struct field declaration:
	"<type> <name>[ = <default>]". This is the fallback sub-parser — it
	should be tried after ParserClass/ParserEnum/ParserFunction, since
	those all recognize more specific shapes first.
]]

local ParserVariable = {}

local ParserTypes = require("../../parserTypes")

local function parse_type(str: string): ParserTypes.ParsedArgType
	local trimmed = str:match("^%s*(.-)%s*$") or ""
	return ParserTypes.ArgTypeMapping[trimmed] or ParserTypes.ParsedArgType.Nil
end

function ParserVariable.try_parse(context: ParserTypes.ParseContext): ParserTypes.ParsedDecl?
	local decl_str = context.decl_str

	-- Reject anything that looks like a function call/signature — a
	-- trailing "(...)" means this isn't a plain variable declaration.
	if decl_str:match("^%s*[%w_:~%[%]%*&%s]+%s*%(%s*.*%s*%)%s*$") then
		return nil
	end

	-- Split off the default value/initializer, if any.
	local before_default, raw_default = decl_str:match("^(.-)%s*=%s*(.+)$")
	local core_str = before_default or decl_str

	local default: string? = nil
	if raw_default then
		default = raw_default:match("^%s*(.-)%s*$") or raw_default
	end

	-- Everything before the last identifier-like word is the type,
	-- e.g. "const std::string& Name" -> type="const std::string&", name="Name".
	local raw_type, raw_name = core_str:match("^(.-)%s+([%w_]+)%s*$")
	if not raw_type or not raw_name then
		return nil
	end

	-- Explicit non-optional locals: narrows string? -> string for the
	-- table constructor below, which some Luau versions don't infer
	-- automatically when the value flows into a table field.
	local var_type: string = raw_type
	local var_name: string = raw_name

	if var_type == var_name then
		return nil
	end

	return {
		kind = ParserTypes.DeclKind.Variable,
		name = var_name,
		scope = context.scope,
		variable = {
			var_type = parse_type(var_type),
			var_original_type = var_type,
			is_const = context.is_const,
			is_static = context.is_static,
			is_field = context.is_field,
			default = default,
		},
	}
end

return ParserVariable