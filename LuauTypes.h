#pragma once

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

#include "lua.h"
#include "luacode.h"
#include "lualib.h"

namespace fs = std::filesystem;
// Directory for resolve relative paths
static fs::path g_script_dir;

static std::string read_file(const char* path)
{
    std::ifstream f(path, std::ios::binary);
    if (!f) return "";
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

#pragma region io
static int io_readfile(lua_State* L)
{
    const char* path = luaL_checkstring(L, 1);
    std::ifstream f(path, std::ios::binary);
    if (!f)
    {
        lua_pushnil(L);
        lua_pushstring(L, "cannot open file");
        return 2;
    }
    std::ostringstream ss;
    ss << f.rdbuf();
    std::string content = ss.str();
    lua_pushlstring(L, content.c_str(), content.size());
    return 1;
}

static int io_writefile(lua_State* L)
{
    const char* path = luaL_checkstring(L, 1);
    size_t len = 0;
    const char* content = luaL_checklstring(L, 2, &len);
    std::ofstream f(path, std::ios::binary);
    if (!f)
    {
        lua_pushnil(L);
        lua_pushstring(L, "cannot open file for writing");
        return 2;
    }
    f.write(content, static_cast<std::streamsize>(len));
    lua_pushboolean(L, 1);
    return 1;
}

static int io_appendfile(lua_State* L)
{
    const char* path = luaL_checkstring(L, 1);
    size_t len = 0;
    const char* content = luaL_checklstring(L, 2, &len);
    std::ofstream f(path, std::ios::binary | std::ios::app);
    if (!f)
    {
        lua_pushnil(L);
        lua_pushstring(L, "cannot open file for appending");
        return 2;
    }
    f.write(content, static_cast<std::streamsize>(len));
    lua_pushboolean(L, 1);
    return 1;
}

static int io_source_directory(lua_State* L)
{
    lua_pushstring(L, g_script_dir.c_str());
    return 1;
}

static const luaL_Reg io_lib[] = {
    {"readfile", io_readfile}, {"writefile", io_writefile}, {"appendfile", io_appendfile}, {"source_directory", io_source_directory}, {nullptr, nullptr}};
#pragma endregion io

#pragma region require
static int lua_require(lua_State *L)
{
    const char *modname = luaL_checkstring(L, 1);

    // package.loaded[modname]
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_getfield(L, -1, modname);

    if (!lua_isnil(L, -1))
    {
        // Already loaded.
        // Stack: package, loaded, module
        lua_remove(L, -3); // remove package
        lua_remove(L, -2); // remove loaded

        return 1;
    }

    // Remove nil, loaded, package.
    lua_pop(L, 3);

    // ------------------------------------------------------------
    // Resolve module path
    // ------------------------------------------------------------

    std::string modpath = modname;

    const bool is_relative = modpath.starts_with("./") || modpath.starts_with("../");

    if (!is_relative)
    {
        // Lua module syntax:
        //
        // Foo.Bar
        //
        // ->
        //
        // Foo/Bar
        for (char &c : modpath)
        {
            if (c == '.')
                c = '/';
        }
    }

    modpath += ".luau";

    // Resolve relative to the currently executing module.
    fs::path fullpath = (g_script_dir / modpath).lexically_normal();

    // ------------------------------------------------------------
    // Read source
    // ------------------------------------------------------------

    std::string source = read_file(fullpath.string().c_str());

    if (source.empty())
    {
        luaL_error(L, "Module '%s', not found (tried: %s)", modname, fullpath.string().c_str());

        return 0;
    }

    // ------------------------------------------------------------
    // Compile
    // ------------------------------------------------------------

    size_t bytecode_size = 0;

    char *bytecode = luau_compile(source.c_str(), source.length(), nullptr, &bytecode_size);

    if (!bytecode)
    {
        luaL_error(L, "Failed to compile module '%s'", modname);

        return 0;
    }

    // ------------------------------------------------------------
    // Load
    // ------------------------------------------------------------

    std::string chunkname = "@" + fullpath.string();

    if (luau_load(L, chunkname.c_str(), bytecode, bytecode_size, 0) != LUA_OK)
    {
        std::string error = lua_tostring(L, -1) ? lua_tostring(L, -1) : "unknown error";

        free(bytecode);

        luaL_error(L, "Error loading module '%s': %s", modname, error.c_str());

        return 0;
    }

    free(bytecode);

    // ------------------------------------------------------------
    // Execute module
    //
    // require() inside this module must resolve relative to
    // this module's directory.
    // ------------------------------------------------------------

    fs::path previous_script_dir = g_script_dir;

    g_script_dir = fullpath.parent_path();

    const int result = lua_pcall(L, 0, 1, 0);

    // ALWAYS restore the parent directory.
    g_script_dir = previous_script_dir;

    if (result != LUA_OK)
    {
        const char *error = lua_tostring(L, -1);

        luaL_error(L, "Error running module '%s': %s", modname, error ? error : "unknown error");

        return 0;
    }

    // ------------------------------------------------------------
    // Lua require semantics:
    //
    // module returning nil -> true
    // ------------------------------------------------------------

    if (lua_isnil(L, -1))
    {
        lua_pop(L, 1);
        lua_pushboolean(L, 1);
    }

    // ------------------------------------------------------------
    // package.loaded[modname] = result
    // ------------------------------------------------------------

    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");

    // Stack:
    //
    // result
    // package
    // loaded
    //
    // Copy result.
    lua_pushvalue(L, -3);

    lua_setfield(L, -2, modname);

    // Remove package and loaded.
    lua_pop(L, 2);

    // Stack now contains:
    //
    // result
    //
    return 1;
}

void init(lua_State* L)
{
    // Register io
    lua_newtable(L);
    luaL_register(L, nullptr, io_lib);
    lua_setglobal(L, "io");

    // Register require
    lua_newtable(L);  // package
    lua_newtable(L);  // package.loaded
    lua_setfield(L, -2, "loaded");
    lua_setglobal(L, "package");
    
    lua_pushcfunction(L, lua_require, "require");
    lua_setglobal(L, "require");
}

#pragma endregion require