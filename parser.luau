assert(arg[1] == "-a", "Expected -a flag")
local out_cpp   = arg[2]
local out_types = arg[3]
local header    = arg[4]

print ("Generate " .. header)

local ParserTypes = require("parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserScope = require("parserScope")

local file_content = io.readfile(header)
local file_lines: {string} = {}
for line in file_content:gmatch("[^\n]+") do
	table.insert(file_lines, line)
end

local root = ParserScope.parse_blocks(file_lines)
ParserScope.print_tree(root, 1)

print("Parsing declarations...")
local decls: {ParserTypes.ParsedDecl} = {}
local scopes_with_decl = ParserScope.build_scope_arr_with_decl(root)
print(#scopes_with_decl .. " scopes with @luau declarations found")

for _, scope in scopes_with_decl do
    local parsed_decls = ParserDeclaration.parse_scope(file_lines, scope)
    for _, decl in parsed_decls do
        table.insert(decls, decl)
        ParserDeclaration.print_parsed_decl(decl)
    end
end