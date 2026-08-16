--!strict
--[[
	ParserLuauDecl

	Walks a header's source lines, tracking C++ scope structure
	(namespace/class/struct/enum blocks) and collecting every declaration
	marked with an `@luau` comment into a flat list of LuauDecl entries,
	each carrying its own attributes string, raw declaration text, and
	full scope path.

	Declaration text can span multiple lines (multi-line function
	signatures, base-class lists before '{', enum bodies). Everything
	except enum stops right before the opening '{' of its body — the
	scope-tracking logic below is responsible for pushing/popping that
	scope on subsequent lines. Enum bodies are consumed in full here,
	since enum values aren't declarations we need to walk into.
]]

local ParserLuauDecl = {}

local ParserTypes = require("../parserTypes")

type ScopeNode = {
	kind: ParserTypes.ScopeKind,
	name: string,
	children: { ScopeNode },
	parent: ScopeNode?,
	line_start: number?,
	line_end: number?,
}

-- Builds the full scope path for a node by walking up to (but excluding)
-- the root sentinel, skipping anonymous/unclassified blocks (Unknown,
-- Block) along the way — those don't correspond to a real C++ scope
-- qualifier, so they shouldn't appear in e.g. "Namespace::Class::Fn".
local function build_full_scope(node: ScopeNode): { ParserTypes.ScopeDecl }
	local decl_full_scope: { ParserTypes.ScopeDecl } = {}

	local node_it: ScopeNode? = node
	while node_it and node_it.parent do
		if node_it.kind ~= ParserTypes.ScopeKind.Unknown and node_it.kind ~= ParserTypes.ScopeKind.Block then
			table.insert(decl_full_scope, 1, { kind = node_it.kind, name = node_it.name })
		end
		node_it = node_it.parent
	end

	return decl_full_scope
end

local function is_enum_header(text: string): boolean
	return text:match("^%s*enum%s") ~= nil
end

-- Scans forward from `start_line`, tracking parenthesis depth, until it
-- finds a ';' or '{' at depth 0. Returns the accumulated text up to (but
-- not including) that character, plus its exact position.
local function scan_header(file_lines: { string }, start_line: number): (string, number, number, string?)
	local text = ""
	local paren_depth = 0
	local line_index = start_line

	while line_index <= #file_lines do
		local line = file_lines[line_index]
		for col = 1, #line do
			local char = line:sub(col, col)
			if char == "(" then
				paren_depth += 1
			elseif char == ")" then
				paren_depth -= 1
			elseif paren_depth <= 0 and (char == ";" or char == "{") then
				return text, line_index, col, char
			end
			text ..= char
		end
		text ..= " "
		line_index += 1
	end

	return text, line_index, 1, nil
end

-- Given the exact position of an opening '{' (line_index/col point AT
-- it), scans forward tracking brace depth and returns the position just
-- past the matching closing '}'.
local function scan_balanced_braces(file_lines: { string }, line_index: number, col: number): (number, number)
	local depth = 0

	while line_index <= #file_lines do
		local line = file_lines[line_index]
		while col <= #line do
			local char = line:sub(col, col)
			col += 1
			if char == "{" then
				depth += 1
			elseif char == "}" then
				depth -= 1
				if depth == 0 then
					return line_index, col
				end
			end
		end
		line_index += 1
		col = 1
	end

	return line_index, col
end

-- Collects one full declaration starting at `start_line`. Returns:
--   text                - the declaration's raw text
--   end_line             - last source line the declaration occupies
--   consumed_full_block  - true only for enums: text already includes
--                          the full body through the matching '}', and
--                          the caller should NOT run scope push/pop logic
--                          on end_line (there's nothing left to open).
--                          false for everything else: text stops right
--                          before '{' or ';', and end_line is where that
--                          stopping character was found — the caller
--                          should let normal scope-tracking process it.
local function collect_declaration(file_lines: { string }, start_line: number): (string, number, boolean)
	local header, stop_line, stop_col, stop_char = scan_header(file_lines, start_line)

	if stop_char == "{" and is_enum_header(header) then
		local end_line, end_col = scan_balanced_braces(file_lines, stop_line, stop_col)

		local body_parts: { string } = {}
		for l = stop_line, end_line do
			local line = file_lines[l] or ""
			if l == stop_line and l == end_line then
				table.insert(body_parts, line:sub(stop_col, end_col - 1))
			elseif l == stop_line then
				table.insert(body_parts, line:sub(stop_col))
			elseif l == end_line then
				table.insert(body_parts, line:sub(1, end_col - 1))
			else
				table.insert(body_parts, line)
			end
		end

		-- Join with real newlines, not spaces — downstream comment
		-- stripping (ParserEnum) needs actual line boundaries to know
		-- where a "//" comment ends, otherwise it eats the rest of the
		-- flattened body.
		return header .. " " .. table.concat(body_parts, "\n"), end_line, true
	end

	return header, stop_line, false
end

function ParserLuauDecl.parse_file(file_lines: { string }): { ParserTypes.LuauDecl }
	local decls: { ParserTypes.LuauDecl } = {}

	local root: ScopeNode = { kind = ParserTypes.ScopeKind.Unknown, name = "root", children = {}, line_start = 0 }
	local stack: { ScopeNode } = { root }
	root.line_end = #file_lines + 1

	local prev_trimmed = ""
	local line_index = 1

	while line_index <= #file_lines do
		local line = file_lines[line_index]
		local trimmed = line:match("^%s*(.-)%s*$")
		local current = stack[#stack]

		if not trimmed or trimmed == "" then
			line_index += 1
			continue
		end

		local attr_str = trimmed:match("@luau%s*(.*)")
		if attr_str then
			local attr_str_trimmed = attr_str:match("^(.-)%s*%*?/?%s*$")
			if attr_str_trimmed then
				-- Find the first non-empty line after the @luau comment —
				-- that's where the actual declaration starts.
				local decl_start = line_index + 1
				while decl_start <= #file_lines and file_lines[decl_start]:match("^%s*$") do
					decl_start += 1
				end

				if decl_start <= #file_lines then
					local decl_text, decl_end_line, consumed_full_block = collect_declaration(file_lines, decl_start)

					table.insert(decls, {
						attributes_line = line_index,
						attributes_str = attr_str_trimmed,
						declaration_line = decl_start,
						declaration_str = decl_text:match("^%s*(.-)%s*$") or decl_text,
						scope = build_full_scope(current),
					})

					if consumed_full_block then
						-- Enum: full body already consumed, including its
						-- closing brace. Nothing to scope-track — skip past it.
						line_index = decl_end_line + 1
						prev_trimmed = trimmed
						continue
					else
						-- Class/struct/function/variable: we stopped right
						-- before '{' or ';'. Re-point at that terminal line
						-- and fall through to the normal brace-tracking
						-- logic below, so this declaration's own scope (if
						-- any) gets pushed/popped exactly like a
						-- non-@luau-marked one would.
						line_index = decl_end_line
						line = file_lines[line_index]
						trimmed = line:match("^%s*(.-)%s*$") or ""
					end
				end
			end
		end

		-- { check before } to handle inline blocks correctly
		if trimmed:find("{") then
			if trimmed:find("}") then
				prev_trimmed = trimmed
				line_index += 1
				continue
			end

			local header = trimmed:gsub("{.*$", ""):match("^%s*(.-)%s*$") or ""
			if header == "" then
				header = prev_trimmed
			end

			local kind: ParserTypes.ScopeKind = ParserTypes.ScopeKind.Block
			local name = header

			if header:match("^namespace%s+") then
				kind = ParserTypes.ScopeKind.Namespace
				name = header:match("^namespace%s+(.+)$") or ""
			elseif header:match("^struct%s+") then
				kind = ParserTypes.ScopeKind.Struct
				name = header:match("^struct%s+([%w_]+)") or ""
			elseif header:match("^class%s+") then
				kind = ParserTypes.ScopeKind.Class
				name = header:match("^class%s+([%w_]+)") or ""
			elseif header:match("^enum%s+") then
				kind = ParserTypes.ScopeKind.Enum
				name = header:match("^enum%s*class%s+([%w_]+)") or header:match("^enum%s+([%w_]+)") or ""
			else
				kind = ParserTypes.ScopeKind.Unknown
			end

			local node: ScopeNode = {
				kind = kind,
				name = name or header,
				children = {},
				parent = current,
				line_start = line_index,
			}

			table.insert(stack[#stack].children, node)
			table.insert(stack, node)
		elseif trimmed:find("^}") then
			if #stack > 1 then
				current.line_end = line_index + 1
				table.remove(stack)
			end
		end

		prev_trimmed = trimmed
		line_index += 1
	end

	return decls
end

return ParserLuauDecl