#pragma once

#include "lua.h"
#include "luacode.h"
#include "lualib.h"

#include <string>
#include <vector>
#include <sstream>

void register_nested_func(lua_State* L, const char* path, lua_CFunction func)
{
    std::vector<std::string> scope_arr;
    std::string s(path);
    std::string scope;
    std::stringstream ss(s);

    while (std::getline(ss, scope, '.'))
    {
        scope_arr.push_back(scope);
    }

    if (scope_arr.empty()) return;

    lua_getglobal(L, "_G");

    for (size_t i = 0; i < parts.size() - 1; ++i) {
        lua_getfield(L, -1, parts[i].c_str());
        
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_setfield(L, -3, parts[i].c_str());
        } else if (!lua_istable(L, -1)) {
            lua_pop(L, parts.size() + 1); 
            return;
        }
        lua_remove(L, -2);
    }
    
    lua_pushcfunction(L, func, parts.back().c_str());
    lua_setfield(L, -2, parts.back().c_str());

    lua_pop(L, 1);
}
