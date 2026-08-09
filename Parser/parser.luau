assert(arg[1] == "-a", "Expected -a flag")
local out_json_file   = arg[2]
local header    = arg[3]

local ParserTypes = require("../parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserScope = require("parserScope")
local Json = require("../json")

-- Print current parse file
if ParserTypes.verbose_print then
    print ("Parse " .. header)
end

-- Read the header file
local file_content = io.readfile(header)
local file_lines: {string} = {}
for line in file_content:gmatch("[^\n]+") do
	table.insert(file_lines, line)
end

-- Find all export delcs
local luau_decls: {ParserTypes.LuauDecl} = ParserScope.parse_file(file_lines)
if ParserTypes.verbose_print then
    print(#luau_decls .. " declarations found")
    print("Parsing declarations...")
end

-- Parse all declarations
local parsed_decls: {ParserTypes.ParsedDecl} = {}
local decls = ParserDeclaration.parse_luau_decl(file_lines, luau_decls)
for _, parsed_decl in decls do
    table.insert(parsed_decls, parsed_decl)
    
    if ParserTypes.verbose_print then
        ParserDeclaration.print_parsed_decl(parsed_decl)
    end
end

io.writefile(out_json_file, Json.encode(parsed_decls))