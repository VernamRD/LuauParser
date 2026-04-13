assert(arg[1] == "-a", "Expected -a flag")
local out_cpp   = arg[2]
local out_types = arg[3]
local header    = arg[4]

print ("Generate " .. header)

local ParserTypes = require("parserTypes")
local ParserDeclaration = require("parserDeclaration")
local ParserScope = require("parserScope")

local file_content = io.readfile(header)
local root = ParserScope.parse_blocks(file_content)
ParserScope.print_tree(root, 1)