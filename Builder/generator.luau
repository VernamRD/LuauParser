local Generator = {}

local ParserTypes = require("../parserTypes")
local Json = require("../json")
local GeneratorFunction = require("../Generator/generatorFunction")

function Generator.generate(out_wrapper: string, out_reg: string, out_api: string, decls: {ParserTypes.ParsedDeclFunc})
    local file_wrapper_content = ""
    local file_reg_content = ""
    local file_api_content = ""

    file_reg_content = Json.encode(decls)
    

    io.writefile(out_wrapper, file_wrapper_content)
    io.writefile(out_reg, file_reg_content)
    io.writefile(out_api, file_api_content)

end

return Generator