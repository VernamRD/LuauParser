#include "lua.h"
#include "luacode.h"
#include "lualib.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;

// Директория главного скрипта — для резолва относительных путей
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
    std::cout << path;
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

static const luaL_Reg io_lib[] = {
    {"readfile", io_readfile}, {"writefile", io_writefile}, {"appendfile", io_appendfile}, {nullptr, nullptr}};
#pragma endregion io

#pragma region require
static int lua_require(lua_State* L)
{
    const char* modname = luaL_checkstring(L, 1);

    // Check cache: package.loaded[modname]
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_getfield(L, -1, modname);
    if (!lua_isnil(L, -1))
    {
        // Alredy loaded, return cached value
        return 1;
    }

    // Remove nil, loaded, package
    lua_pop(L, 3);

    std::string modpath = modname;
    for (char& c : modpath)
    {
        if (c == '.') c = '/';
    }
    modpath += ".luau";

    fs::path fullpath = g_script_dir / modpath;
    std::string source = read_file(fullpath.string().c_str());

    if (source.empty())
    {
        fullpath = g_script_dir / (std::string(modname) + ".luau");
        source = read_file(fullpath.string().c_str());
    }

    if (source.empty())
    {
        luaL_error(L, "Module '%s', not found (tried: %s)", modname, fullpath.string().c_str());
        return 0;
    }

    size_t bytecode_size = 0;
    char* bytecode = luau_compile(source.c_str(), source.length(), nullptr, &bytecode_size);

    std::string chunkname = "@" + fullpath.string();
    if (luau_load(L, chunkname.c_str(), bytecode, bytecode_size, 0) != LUA_OK)
    {
        free(bytecode);
        luaL_error(L, "Error loading module '%s' : %s", modname, lua_tostring(L, -1));
        return 0;
    }
    free(bytecode);

    if (lua_pcall(L, 0, 1, 0) != LUA_OK)
    {
        luaL_error(L, "Error running module '%s' : %s", modname, lua_tostring(L, -1));
        return 0;
    }

    if (lua_isnil(L, -1))
    {
        lua_pop(L, 1);
        lua_pushboolean(L, 1);
    }

    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_pushvalue(L, -3);
    lua_setfield(L, -2, modname);
    lua_pop(L, 2);

    return 1;
}
#pragma endregion require

int main(int argc, char** argv)
{
    if (argc < 2)
    {
        printf("Usage: luau_host <script.luau> [args...]\n");
        return 1;
    }

    // Cache path
    g_script_dir = fs::absolute(fs::path(argv[1])).parent_path();

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);

    // Регистрируем io
    lua_newtable(L);
    luaL_register(L, nullptr, io_lib);
    lua_setglobal(L, "io");

    lua_newtable(L);  // package
    lua_newtable(L);  // package.loaded
    lua_setfield(L, -2, "loaded");
    lua_setglobal(L, "package");
    
    lua_pushcfunction(L, lua_require, "require");
    lua_setglobal(L, "require");

    // Передаём все аргументы после имени скрипта в глобальную таблицу arg
    // arg[0] = script path, arg[1] = первый аргумент, и т.д.
    lua_newtable(L);
    lua_pushstring(L, argv[1]);
    lua_rawseti(L, -2, 0);
    for (int i = 2; i < argc; i++)
    {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i - 1);  // arg[1], arg[2], ...
    }
    lua_setglobal(L, "arg");

    std::ifstream file(argv[1], std::ios::binary);
    if (!file)
    {
        printf("Cannot open script: %s\n", argv[1]);
        lua_close(L);
        return 1;
    }
    std::string source((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source.c_str(), source.length(), nullptr, &bytecodeSize);

    if (luau_load(L, argv[1], bytecode, bytecodeSize, 0) != LUA_OK)
    {
        printf("Error loading: %s\n", lua_tostring(L, -1));
        free(bytecode);
        lua_close(L);
        return 1;
    }
    free(bytecode);

    if (lua_pcall(L, 0, 0, 0) != LUA_OK)
    {
        printf("Runtime Error: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}