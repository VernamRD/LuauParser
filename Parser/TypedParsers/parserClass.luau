--!strict
--[[
	ParserClass

	Recognizes a class/struct declaration line and produces a ParsedDecl
	of kind Class. If the declaration carries `@luau export` (checked by
	the caller via attributes, but we register unconditionally here and
	let the caller decide what to keep — see note below), it also records
	an entry in the shared class registry so other declarations (function
	args/return types) can later resolve "MyClass" to its scope + header.
]]

local ParserClass = {}
local ParserTypes = require("../../parserTypes")

function ParserClass.try_parse(context: ParserTypes.ParseContext): ParserTypes.ParsedDecl?
	local decl_str = context.decl_str

	-- e.g. "class MyClass : public Base" or "struct MyClass"
	local keyword, name, base = decl_str:match("^%s*(class)%s+([%w_]+)%s*:%s*public%s+([%w_:]+)")
	if not keyword then
		keyword, name = decl_str:match("^%s*(class)%s+([%w_]+)%s*$")
	end
	if not keyword then
		keyword, name, base = decl_str:match("^%s*(struct)%s+([%w_]+)%s*:%s*public%s+([%w_:]+)")
	end
	if not keyword then
		keyword, name = decl_str:match("^%s*(struct)%s+([%w_]+)%s*$")
	end

	if not keyword or not name then
		return nil
	end

	local is_struct = keyword == "struct"

	-- Register this class so other declarations can resolve references to
	-- it. Full scope = the declaration's own scope chain + this class's
	-- own name appended at the end (a class's "self scope" includes itself).
	local full_scope: { ParserTypes.ScopeDecl } = table.clone(context.scope)
	table.insert(full_scope, {
		kind = if is_struct then ParserTypes.ScopeKind.Struct else ParserTypes.ScopeKind.Class,
		name = name,
	})

	table.insert(context.registry, {
		name = name,
		scope = full_scope,
		header = context.header_path,
		kind = if is_struct then ParserTypes.DeclKind.Struct else ParserTypes.DeclKind.Struct,
		base = base,
	})

	return {
		kind = ParserTypes.DeclKind.Class,
		name = name,
		scope = context.scope,
		["class"] = {
			is_struct = is_struct,
			base = base,
		},
	}
end

return ParserClass