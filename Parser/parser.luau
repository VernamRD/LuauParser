assert(arg[1] == "-a", "Expected -a flag")
local out_wrapper   = arg[2]
local out_reg = arg[3]
local out_api = arg[4]
local header    = arg[5]

local ParserTypes = require("parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserScope = require("parserScope")

if ParserTypes.verbose_print then
    print ("Parse " .. header)
end

local file_content = io.readfile(header)
local file_lines: {string} = {}
for line in file_content:gmatch("[^\n]+") do
	table.insert(file_lines, line)
end

local luau_decls = ParserScope.parse_file(file_lines)
if ParserTypes.verbose_print then
    print(#luau_decls .. " declarations found")
    print("Parsing declarations...")
end

local parsed_decls: {ParserTypes.ParsedDecl} = {}
local decls = ParserDeclaration.parse_luau_decl(file_lines, luau_decls)
for _, parsed_decl in decls do
    table.insert(parsed_decls, parsed_decl)
    
    if ParserTypes.verbose_print then
        ParserDeclaration.print_parsed_decl(parsed_decl)
    end
end

local Generator = require("../Generator/generator")
Generator.generate(out_wrapper, out_reg, out_api, parsed_decls)