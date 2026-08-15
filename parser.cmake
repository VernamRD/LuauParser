set(LUAU_PARSER_EXE $<TARGET_FILE:luau_parser>)
set(LUAU_BUILDER_EXE $<TARGET_FILE:luau_builder>)
set(PARSER_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR})

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")

if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()

set(PARSER_UTILITY_FILE_NAME "ParserRegister.h")

function(register_luau_parser)
    add_executable(luau_parser "${PARSER_ROOT_DIR}/Parser/LuauParser.cpp")
    target_link_libraries(luau_parser PRIVATE Luau.VM Luau.Compiler Luau.Ast)
    target_include_directories(luau_parser PRIVATE
        "${CMAKE_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/LuauParser"
    )

    add_executable(luau_builder "${PARSER_ROOT_DIR}/Builder/LuauBuilder.cpp")
    target_link_libraries(luau_builder PRIVATE Luau.VM Luau.Compiler Luau.Ast)
    target_include_directories(luau_builder PRIVATE
        "${CMAKE_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/LuauParser"
    )
endfunction()

set(LUAU_PARSER "${CMAKE_CURRENT_LIST_DIR}/Parser/parser.luau")
set(LUAU_BUILDER "${CMAKE_CURRENT_LIST_DIR}/Builder/builder.luau")

function(build_luau_bindings TARGET_NAME)
    set(HEADER_FILES_LIST ${ARGN})

    set(GENERATED_INCLUDE_DIR "${GENERATED_DIR}/include")
    set(GENERATED_PRIVATE_DIR "${GENERATED_DIR}/private")
    set(GENERATED_CACHE_DIR "${GENERATED_DIR}/${TARGET_NAME}")
    set(GENERATED_API_DIR "${GENERATED_DIR}/api")

    foreach(DIR "${GENERATED_INCLUDE_DIR}" "${GENERATED_PRIVATE_DIR}" "${GENERATED_CACHE_DIR}" "${GENERATED_API_DIR}")
        if(NOT EXISTS "${DIR}")
            file(MAKE_DIRECTORY "${DIR}")
        endif()
    endforeach()

    # Copy ParserRegister.h to generated folder (target-wide, not per-header)
    add_custom_command(
        OUTPUT "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMAND ${CMAKE_COMMAND} -E copy
        "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
        DEPENDS "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMENT "Copying parser utility file to generated directory"
        VERBATIM
    )

    set(PARSE_TARGET "Parse_${TARGET_NAME}")
    add_custom_target(${PARSE_TARGET})

    set(BUILD_TARGET "Build_${TARGET_NAME}_luau_bindings")
    add_custom_target(${BUILD_TARGET})

    set(ALL_HEADER_BINDINGS_CPP "")
    set(ALL_HEADER_NAMES "")
    set(ALL_HEADER_API_FILES "")

    # --- Per-header: parse, then build its own isolated .cpp/.h/.d.luau ---
    foreach(HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)
        list(APPEND ALL_HEADER_NAMES "${HEADER_NAME}")

        # 1) Self-containment check: fail fast if HEADER doesn't compile standalone
        # (catches forward-decl-only headers before we generate broken bindings)
        set(SYNTAX_CHECK_STAMP "${GENERATED_CACHE_DIR}/${HEADER_NAME}.syntax_ok")
        add_custom_command(
            OUTPUT "${SYNTAX_CHECK_STAMP}"
            COMMAND ${CMAKE_CXX_COMPILER} -fsyntax-only -std=c++23 -I "${CMAKE_SOURCE_DIR}" "${HEADER}"
            COMMAND ${CMAKE_COMMAND} -E touch "${SYNTAX_CHECK_STAMP}"
            DEPENDS "${HEADER}"
            COMMENT "Checking ${HEADER_NAME}.h is self-contained..."
            VERBATIM
        )

        # 2) Parse header -> single JSON of declarations
        set(OUT_PARSED_DECLS "${GENERATED_CACHE_DIR}/${HEADER_NAME}_ParsedDecls.json")
        add_custom_command(
            OUTPUT "${OUT_PARSED_DECLS}"
            COMMAND ${LUAU_PARSER_EXE} "${LUAU_PARSER}" -a "${OUT_PARSED_DECLS}" ${HEADER}
            DEPENDS ${LUAU_PARSER_EXE} "${LUAU_PARSER}" ${HEADER} "${SYNTAX_CHECK_STAMP}"
            COMMENT "Parse Luau bindings for ${HEADER}..."
            VERBATIM
        )

        set(SINGLE_PARSE_TARGET "Parse_${TARGET_NAME}_${HEADER_NAME}")
        add_custom_target(${SINGLE_PARSE_TARGET} DEPENDS "${OUT_PARSED_DECLS}")
        add_dependencies(${PARSE_TARGET} ${SINGLE_PARSE_TARGET})

        # 3) Build isolated outputs for this header only
        set(HEADER_API "${GENERATED_API_DIR}/${TARGET_NAME}_${HEADER_NAME}_api.d.luau")
        set(HEADER_DEF "${GENERATED_PRIVATE_DIR}/${HEADER_NAME}_definition.h")
        set(HEADER_BINDINGS_H "${GENERATED_INCLUDE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.h")
        set(HEADER_BINDINGS_CPP "${GENERATED_PRIVATE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.cpp")

        list(APPEND ALL_HEADER_BINDINGS_CPP "${HEADER_BINDINGS_CPP}")

        file(RELATIVE_PATH HEADER_REL "${CMAKE_SOURCE_DIR}" "${HEADER}")

        add_custom_command(
            OUTPUT "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -s "${OUT_PARSED_DECLS}" "${HEADER_REL}"
            "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${SINGLE_PARSE_TARGET}" "${OUT_PARSED_DECLS}"
            "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
            COMMENT "Build Luau bindings for ${HEADER_NAME}..."
            VERBATIM
        )

        set(SINGLE_BUILD_TARGET "Build_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${SINGLE_BUILD_TARGET} DEPENDS "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}")
        add_dependencies(${BUILD_TARGET} ${SINGLE_BUILD_TARGET})
    endforeach()

    # --- Aggregator: stable, tiny, doesn't grow/change per binding count ---
    set(OUTPUT_INCLUDE "${GENERATED_INCLUDE_DIR}/luau_parser_bindings.h")
    set(AGGREGATOR_CONTENT "#pragma once\n\n#include \"lua.h\"\n\n")

    foreach(HEADER_NAME ${ALL_HEADER_NAMES})
        string(APPEND AGGREGATOR_CONTENT "void register_${HEADER_NAME}(lua_State* L);\n")
    endforeach()

    string(APPEND AGGREGATOR_CONTENT "\ninline void register_internal(lua_State* L)\n{\n")

    foreach(HEADER_NAME ${ALL_HEADER_NAMES})
        string(APPEND AGGREGATOR_CONTENT "    register_${HEADER_NAME}(L);\n")
    endforeach()

    string(APPEND AGGREGATOR_CONTENT "}\n")

    file(GENERATE OUTPUT "${OUTPUT_INCLUDE}" CONTENT "${AGGREGATOR_CONTENT}")

    add_custom_target(${BUILD_TARGET}_aggregator DEPENDS "${BUILD_TARGET}")

    add_dependencies(${TARGET_NAME} ${BUILD_TARGET})
    target_include_directories(${TARGET_NAME} PRIVATE "${GENERATED_INCLUDE_DIR}")
    target_include_directories(${TARGET_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
    target_sources(${TARGET_NAME} PRIVATE ${ALL_HEADER_BINDINGS_CPP})
endfunction()