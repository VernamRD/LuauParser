#include "LuauTypes.h"

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

    init(L);

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