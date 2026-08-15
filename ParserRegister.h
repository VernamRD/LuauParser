#pragma once

#include "lua.h"
#include "luacode.h"
#include "lualib.h"

#include <string>
#include <vector>

// Walks/creates nested tables in _G along `scope`, then sets func under `name`.
// scope should NOT include "root". No-op if a non-table value blocks the path.
inline void register_scoped_func(lua_State *L, const std::vector<std::string> &scope, const std::string &name,
                                 lua_CFunction func)
{
    lua_getglobal(L, "_G");

    for (const std::string &part : scope)
    {
        lua_getfield(L, -1, part.c_str());
        if (lua_isnil(L, -1))
        {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_setfield(L, -3, part.c_str());
        }
        else if (!lua_istable(L, -1))
        {
            lua_pop(L, (int)scope.size() + 1);
            return;
        }
        lua_remove(L, -2);
    }

    lua_pushcfunction(L, func, name.c_str());
    lua_setfield(L, -2, name.c_str());

    lua_pop(L, 1);
}

// Mirrors one entry of the declaration JSON. Fill `scope` from the "scope" array,
// skipping the "root" element (its "kind" doesn't matter for registration).
struct LuauFuncDecl
{
    std::string name;
    std::vector<std::string> scope;
};

inline void register_func(lua_State *L, const LuauFuncDecl &decl, lua_CFunction func)
{
    register_scoped_func(L, decl.scope, decl.name, func);
}

// Bulk registration table: pairs a declaration with its C implementation.
struct LuauFuncBinding
{
    LuauFuncDecl decl;
    lua_CFunction impl;
};

inline void register_all(lua_State *L, const std::vector<LuauFuncBinding> &bindings)
{
    for (const LuauFuncBinding &b : bindings)
        register_func(L, b.decl, b.impl);
}