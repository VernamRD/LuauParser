#pragma once

#include "cmake-build-debug/generated/LuauParserTest_generated.h"

void register_bindings(lua_State* L)
{
	register_internal(L);
}