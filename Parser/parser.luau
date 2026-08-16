assert(arg[1] == "-a", "Expected -a flag")
local out_json_file   = arg[2]
local header    = arg[3]
local out_registry = arg[4]

local ParserTypes = require("../parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserLuauDecl = require("parserLuauDecl")
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
local luau_decls: {ParserTypes.LuauDecl} = ParserLuauDecl.parse_file(file_lines)
if ParserTypes.verbose_print then
    print(#luau_decls .. " declarations found")
    print("Parsing declarations...")
end

-- Parse all declarations
local parsed_decls: {ParserTypes.ParsedDecl} = {}
-- Type registry data classes, struct, enum
local registry_data: ParserTypes.TypeRegistry = {}

local decls = ParserDeclaration.parse_luau_decl(file_lines, luau_decls, registry_data, header)
for _, parsed_decl in decls do
    table.insert(parsed_decls, parsed_decl)
end

io.writefile(out_json_file, Json.encode(parsed_decls))
io.writefile(out_registry, Json.encode(registry_data))