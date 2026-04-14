assert(arg[1] == "-a", "Expected -a flag")
local out_cpp   = arg[2]
local out_types = arg[3]
local header    = arg[4]

local ParserTypes = require("parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserScope = require("parserScope")

if ParserTypes.verbose_print then
    print ("Generate " .. header)
end

local file_content = io.readfile(header)
local file_lines: {string} = {}
for line in file_content:gmatch("[^\n]+") do
	table.insert(file_lines, line)
end

local root = ParserScope.parse_blocks(file_lines)
if ParserTypes.verbose_print then
    ParserScope.print_tree(root, 1)
end

local scopes_with_decl = ParserScope.build_scope_arr_with_decl(root)
if ParserTypes.verbose_print then
    print(#scopes_with_decl .. " scopes with @luau declarations found")
    print("Parsing declarations...")
end

local decls: {ParserTypes.ParsedDecl} = {}
for _, scope in scopes_with_decl do
    local parsed_decls = ParserDeclaration.parse_scope(file_lines, scope)
    for _, decl in parsed_decls do
        table.insert(decls, decl)
        
        if ParserTypes.verbose_print then
            ParserDeclaration.print_parsed_decl(decl)
        end
    end
end

local Generator = require("generator")
Generator.generate(out_cpp, out_types, decls)