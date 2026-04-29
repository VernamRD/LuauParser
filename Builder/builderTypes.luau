--!strict

local BuilderTypes = {}

export type BuilderAttrType = "scope" | "field" | "undefined"
BuilderTypes.BuilderAttrType = table.freeze({
    Scope = "scope" :: BuilderAttrType,
	Field = "field" :: BuilderAttrType,
    Undefined = "undefined" :: BuilderAttrType
})
export type BuilderAttr = {
    type: BuilderAttrType,
    value: string | boolean,
}

function BuilderTypes.has_attr(attrs: {BuilderAttr}?, attr_type: BuilderAttrType): boolean?
    if not attrs then
        return false
    end
    
    for _, attr in attrs do
        if attr.type == attr_type then
            return true
        end
    end

    return false
end

function BuilderTypes.try_get_attributes(str: string): string?
    return str:match("^%s*%-%-%s*(.-)%s*%-%-%s*$")
end

function BuilderTypes.parse_attributes(attr_str: string): { BuilderAttr }	
	local attributes: { [string]: string | boolean } = {}

	for block in attr_str:gmatch("@([^@]+)") do
        -- Убираем лишние пробелы в конце блока
        block = block:gsub("%s+$", "")

        -- Пробуем вытащить ключ и значение в кавычках
        local key, val = block:match('^([%w_]+)%s*=%s*"([^"]*)"')
        
        if key and val then
            attributes[key] = val
        else
            -- Если не нашли конструкцию со значением, 
            -- берем первое слово как флаг
            local flag = block:match("^([%w_]+)")
            if flag then
                attributes[flag] = true
            end
        end
    end

    local parsed_attributes: { BuilderAttr } = {}
    for key, flag in pairs(attributes) do
        local attr_type: BuilderAttrType = BuilderTypes.BuilderAttrType.Undefined

        -- Поиск соответствия ключа типу
        for known_type, known_type_str in pairs(BuilderTypes.BuilderAttrType) do
            if key == known_type_str then
                attr_type = known_type_str
                break
            end
        end

        table.insert(parsed_attributes, {
            type = attr_type,
            value = flag
        })
    end


	return parsed_attributes
end

function BuilderTypes.print_attributes(attrs: {BuilderAttr}): string
    local result = "--"

    for _, attr in attrs do
        if type(attr.value) == "string" then 
            result ..= " @" .. attr.type .. "=\"" .. attr.value .. "\""
        else
            result ..= " @" .. attr.type
        end
    end

    return result .. "--"
end

export type BuilderDecl = {
    decl: string,
    attrs: {BuilderAttr}?,
}

export type BuilderDeclTree = {
    decls: {BuilderDecl}?,
    is_class: boolean?,
    [string]: BuilderDeclTree,
}

return BuilderTypes