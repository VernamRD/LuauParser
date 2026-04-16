local Generator = {}

local ParserTypes = require("../Parser/parserTypes")
local GeneratorFunction = require("../Generator/generatorFunction")

function Generator.generate(out_wrapper: string, out_reg: string, out_api: string, decls: {ParserTypes.ParsedDecl})
    local file_wrapper_content = ""
    local file_reg_content = ""
    local file_api_content = ""

    for _, decl in ipairs(decls) do
        if decl.kind == ParserTypes.DeclKind.Function then
            file_wrapper_content = file_wrapper_content .. GeneratorFunction.generate_function_luau_wrapper(decl) .. "\n"
            file_reg_content = file_reg_content .. GeneratorFunction.generate_function_luau_reg(decl) .. "\n"
            file_api_content = file_api_content .. GeneratorFunction.generate_function_luau_api(decl) .. "\n"
        elseif decl.kind == ParserTypes.DeclKind.Field then
            print("Generating field: " .. decl.name)
            -- Here you would generate the C++ code for the field declaration
            -- using decl.field_type and decl.attributes
        else
            print("Unknown declaration kind for: " .. decl.name)
        end
    end

    io.writefile(out_wrapper, file_wrapper_content)
    io.writefile(out_reg, file_reg_content)
    io.writefile(out_api, file_api_content)

end

return Generator