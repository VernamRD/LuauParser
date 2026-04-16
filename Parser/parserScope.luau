local ParserScope = {}

local ParserTypes = require("parserTypes")

-- Build full scope path for the declaration, e.g. {"Namespace", "Class"}
function build_full_scope(node: ParserTypes.ScopeNode): {string}
	local decl_full_scope: {string} = {}

	local node_it = node
	while node_it and not (node_it.name == "") do
		table.insert(decl_full_scope, 1, node_it.name)
		node_it = node_it.parent or nil
	end

    return decl_full_scope
end

function parse_decl(node: ParserTypes.ScopeNode, attr_str: string, line_index: number, lines: {string}): {decl: ParserTypes.LuauDecl, line_offset: number}
    -- Remove trailing whitespace and optional * or / characters
	attr_str_trimmed = attr_str:match("^(.-)%s*%*?/?%s*$")

	-- Find declaration line after attributes
	local j = line_index + 1
	while j <= #lines and lines[j]:match("^%s*$") do
		j = j + 1
	end
	local decl_line = lines[j] or ""
	decl_line = decl_line:match("^%s*(.-)%s*$") -- Match function or variable declaration
	local decl: ParserTypes.LuauDecl = {
		attributes_line = line_index,
		attributes_str = attr_str_trimmed,
		declaration_line = j,
		declaration_str = decl_line,
		scope = build_full_scope(node),
	}
	
	return {
        decl = decl,
        line_offset = j - line_index
    }
end

local function print_tree(node: ParserTypes.ScopeNode, indent: number)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    print(prefix .. "[" .. node.kind .. "] " .. (node.name or "?") .. " " .. (node.line_start or "?") .. "-" .. (node.line_end or "?"))

    for _, child in ipairs(node.children) do
        print_tree(child, indent + 1)
    end
end


function ParserScope.parse_file(file_lines: {string}) : {ParserTypes.LuauDecl}
    local decls: {ParserTypes.LuauDecl} = {}

    local root: ParserTypes.ScopeNode = { kind = ParserTypes.ScopeKind.Root, name = "", children = {}, body = "", line_start = 0}
    local stack = { root }

    root.line_end = #file_lines + 1

    local prev_trimmed = ""  -- previous non-empty line

    local line_index: number = 1
    while line_index <= #file_lines do
        local line = file_lines[line_index]
        local trimmed = line:match("^%s*(.-)%s*$")
        local current = stack[#stack]

        -- Skip empty lines but remember context
        if trimmed == "" then
            line_index += 1
            continue
        end

        -- Try catch @luau decl
        local attr_str = trimmed:match("@luau%s*(.*)")
        if attr_str then
            local result = parse_decl(current, attr_str, line_index, file_lines)
            table.insert(decls, result.decl)
            line_index += result.line_offset
        end

        -- { check before } to handle inline blocks correctly
        if trimmed:find("{") then
            -- inline and { } on the same line - skip
            if trimmed:find("}") then
                prev_trimmed = trimmed
                line_index += 1
                continue
            end

            -- Block header: either on this line before {, or it was prev_trimmed
            local header = trimmed:gsub("{.*$", ""):match("^%s*(.-)%s*$")
            if header == "" then
                -- { placed separately - header is the previous line
                header = prev_trimmed
            end

            local kind: ParserTypes.ScopeKind = ParserTypes.ScopeKind.Block
            local name = header

            if header:match("^namespace%s+") then
                kind = ParserTypes.ScopeKind.Namespace
                name = header:match("^namespace%s+(.+)$")
            elseif header:match("^struct%s+") then
                kind = ParserTypes.ScopeKind.Struct
                name = header:match("^struct%s+([%w_]+)")
            elseif header:match("^class%s+") then
                kind = ParserTypes.ScopeKind.Class
                name = header:match("^class%s+([%w_]+)")
            elseif header:match("^enum%s+") then
                kind = ParserTypes.ScopeKind.Enum
                name = header:match("^enum%s*class%s+([%w_]+)") 
                    or header:match("^enum%s+([%w_]+)")
            end

            local node: ParserTypes.ScopeNode = {
                kind       = kind,
                name       = name or header,
                children   = {},
                parent     = current,
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

    if ParserTypes.verbose_print then
        print_tree(root, 1)
    end

    return decls
end

return ParserScope