--!strict
--[[
	ParserEnum

	Recognizes an enum/enum class declaration and parses its full body
	(reading forward from declaration_line until the matching closing
	brace) into a list of name/value pairs, computing implicit values
	via C++ auto-increment semantics where no explicit value is given.

	Values whose initializer is a bare reference to another member of the
	SAME enum (e.g. `GAMEPAD_BUTTON_XBOX_A = GAMEPAD_BUTTON_2`) are
	resolved by lookup, including chains of aliases (A = B, B = C, C = 5).
	Anything else non-numeric (arbitrary expressions, external constants,
	bitwise combinations, etc.) is left as `value = nil` — we deliberately
	don't evaluate C++ expressions here.
]]

local ParserEnum = {}
local ParserTypes = require("../../parserTypes")

--[[
	Strips "//" line comments from enum body text. Must run before
	splitting into individual entries, since a comment can otherwise
	swallow the comma that separates two real entries once the body has
	been joined across multiple source lines into one string.
]]
local function strip_line_comments(text: string): string
	local result = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local comment_start = line:find("//", 1, true)
		if comment_start then
			line = line:sub(1, comment_start - 1)
		end
		table.insert(result, line)
	end
	return table.concat(result, " ")
end

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
		body ..= line .. "\n"
		line_index += 1
		if started and depth <= 0 then
			break
		end
	end

	return body, line_index - start_line
end

-- Raw entry collected in the first pass: name plus its unresolved
-- initializer expression (nil if implicit / no "=" at all).
type RawEntry = {
	name: string,
	expr: string?,
}

--[[
	First pass: split the (comment-stripped) enum body into individual
	entries, without resolving anything yet. Just records each name and
	its raw right-hand-side text, if any.
]]
local function collect_raw_entries(braces_content: string): { RawEntry }
	local raw_entries: { RawEntry } = {}

	for entry in braces_content:gmatch("[^,]+") do
		local trimmed = entry:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			local value_name, value_expr = trimmed:match("^([%a_][%w_]*)%s*=%s*(.+)$")
			if value_name then
				table.insert(raw_entries, { name = value_name, expr = value_expr })
			else
				local plain_name = trimmed:match("^([%a_][%w_]*)$")
				if plain_name then
					table.insert(raw_entries, { name = plain_name, expr = nil })
				end
			end
		end
	end

	return raw_entries
end

--[[
	Second pass: walks the raw entries in order, computing each one's
	final numeric value:
	  - no expr             -> previous value + 1 (or 0 for the first entry),
	                           unless the running counter has gone "unknown"
	                           (see below), in which case also nil.
	  - expr is a number     -> that number directly.
	  - expr is the name of  -> that entry's OWN resolved value (following
	    an earlier entry in     chains transitively, e.g. A = B, B = C = 5
	    the same enum            resolves A to 5). Cycles are guarded
	                             against and resolve to nil.
	  - expr is a left-shift  -> evaluated directly, e.g. "1 << 4" -> 16.
	    of two resolvable        Common for bitflag enums. Either side can
	    operands                 itself be a number or a reference to an
	                              earlier member of this same enum.
	  - anything else         -> nil (arbitrary C++ expression, not resolved).

	Whenever a value can't be resolved, the auto-increment counter for
	subsequent implicit entries also becomes unknown, until the next
	explicit numeric literal resets it — this matches real C++ semantics
	(you can't auto-increment from an unknown value).
]]
local function resolve_entries(raw_entries: { RawEntry }): { ParserTypes.EnumValueDecl }
	local resolved_by_name: { [string]: number? } = {}
	local values: { ParserTypes.EnumValueDecl } = {}
	local next_implicit_value: number? = 0

	-- Resolves a single operand of an expression: either a numeric
	-- literal, or a bare reference to an earlier member of this enum.
	local function resolve_operand(operand: string, seen: { [string]: boolean }): number?
		local trimmed = operand:match("^%s*(.-)%s*$") or operand

		local numeric = tonumber(trimmed)
		if numeric then
			return numeric
		end

		local ref_name = trimmed:match("^([%a_][%w_]*)$")
		if not ref_name or seen[ref_name] then
			return nil
		end

		return resolved_by_name[ref_name]
	end

	local function resolve_expr(expr: string, seen: { [string]: boolean }): number?
		local numeric = tonumber(expr)
		if numeric then
			return numeric
		end

		-- Left-shift, e.g. "1 << 4" or "SOME_FLAG << 2". Only the single
		-- most common bitflag pattern is handled — no operator precedence,
		-- no other operators, no parentheses.
		local shift_lhs, shift_rhs = expr:match("^%s*(.-)%s*<<%s*(.-)%s*$")
		if shift_lhs and shift_rhs then
			local lhs_value = resolve_operand(shift_lhs, seen)
			local rhs_value = resolve_operand(shift_rhs, seen)
			if lhs_value and rhs_value then
				return lhs_value * (2 ^ rhs_value)
			end
			return nil
		end

		local ref_name = expr:match("^%s*([%a_][%w_]*)%s*$")
		if not ref_name or seen[ref_name] then
			return nil -- not a simple reference or shift, or a cycle — give up
		end

		local cached = resolved_by_name[ref_name]
		if cached ~= nil then
			return cached
		end

		return nil
	end

	for _, raw in raw_entries do
		local value: number?

		if raw.expr then
			value = resolve_expr(raw.expr, { [raw.name] = true })
		else
			value = next_implicit_value
		end

		table.insert(values, { name = raw.name, value = value })
		resolved_by_name[raw.name] = value
		next_implicit_value = if value then value + 1 else nil
	end

	return values
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
		body = decl_str .. "\n" .. collected
	end

	local braces_content = body:match("{(.*)}") or ""
	braces_content = strip_line_comments(braces_content)

	local raw_entries = collect_raw_entries(braces_content)
	local values = resolve_entries(raw_entries)

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