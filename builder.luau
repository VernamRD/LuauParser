assert(arg[1] == "-a", "Expected -a flag")
local manifest_def   = arg[2]
local manifest_decl = arg[3]
local generated_def = arg[4]
local generated_decl = arg[5]

function generate_def()
    local manifest_def_content = io.readfile(manifest_def)
    local manifest_def_lines: {string} = {}
    for line in manifest_def_content:gmatch("[^\n]+") do
        table.insert(manifest_def_lines, line)
    end

    for _, def_file in manifest_def_lines do
        local def_content = io.readfile(def_file)
        io.appendfile(generated_def, def_content .. "\n")
    end
end

function generate_decl()
    local manifest_decl_content = io.readfile(manifest_decl)
    local manifest_decl_lines: {string} = {}
    for line in manifest_decl_content:gmatch("[^\n]+") do
        table.insert(manifest_decl_lines, line)
    end

    for _, decl_file in manifest_decl_lines do
        local decl_content = io.readfile(decl_file)
        io.appendfile(generated_decl, decl_content .. "\n")
    end
end

-- Clear the generated definition file before appending new content
io.writefile(generated_def, "")
generate_def()

-- Clear the generated declaration file before appending new content
io.writefile(generated_decl, "")
generate_decl()
