# =============================================================================
# LuauParser build integration
#
# Pipeline (only for headers containing at least one @luau marker):
#
# Pass 1 — Parse: every header is parsed independently and in parallel,
# producing <Header>_ParsedDecls.json and a per-header type registry
# fragment.
#
# Merge — all per-header registry fragments are combined into one
# manifest. This step depends on EVERY header's parse output, so it
# can't start until parsing has fully finished for the whole target.
#
# Pass 2 — Build: luau_builder turns each header's ParsedDecls.json PLUS
# the fully-merged registry manifest into:
# - <Header>_api.d.luau      (Luau type declarations)
# - <Header>_definition.h    (C wrapper function bodies)
# - <Target>_<Header>_bindings.h/.cpp (register_<Header>(lua_State*))
#
# Each build step depends on the MERGED manifest (not just its own
# header's registry fragment), guaranteeing every header's exported
# types are resolvable regardless of which header they were declared
# in or which order headers happen to build in.
#
# All per-header .cpp files are added to the target's sources, so each
# header gets its own translation unit (parallel builds, minimal rebuild
# fan-out). A small aggregator header (luau_parser_bindings.h) exposes a
# single register_internal(lua_State*) that calls every per-header
# register_* fn.
# =============================================================================

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

    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${HEADER_FILES_LIST})

    get_target_property(TARGET_CXX_STANDARD ${TARGET_NAME} CXX_STANDARD)

    if(NOT TARGET_CXX_STANDARD)
        set(TARGET_CXX_STANDARD 23)
    endif()

    set(GENERATED_CACHE_DIR "${GENERATED_DIR}/${TARGET_NAME}")
    set(GENERATED_PARSED_DIR "${GENERATED_DIR}/${TARGET_NAME}/parsed")
    set(GENERATED_INCLUDE_DIR "${GENERATED_CACHE_DIR}/include")
    set(GENERATED_PRIVATE_DIR "${GENERATED_CACHE_DIR}/private")
    set(GENERATED_API_DIR "${GENERATED_CACHE_DIR}/api")

    foreach(DIR "${GENERATED_INCLUDE_DIR}" "${GENERATED_PRIVATE_DIR}" "${GENERATED_CACHE_DIR}" "${GENERATED_PARSED_DIR}" "${GENERATED_API_DIR}")
        if(NOT EXISTS "${DIR}")
            file(MAKE_DIRECTORY "${DIR}")
        endif()
    endforeach()

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

    # Populated in Pass 1, consumed by the merge step and Pass 2.
    set(VALID_HEADER_NAMES "")
    set(VALID_HEADERS "")
    set(ALL_PARSED_DECLS_FILES "")
    set(ALL_TYPE_REGISTRY_FILES "")

    # =========================================================================
    # Pass 1 — parse every header independently. No header's parse step
    # depends on any other header, so these all run in parallel.
    # =========================================================================
    foreach(HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)

        file(STRINGS "${HEADER}" LUAU_MARKERS REGEX "@luau")

        if(NOT LUAU_MARKERS)
            continue()
        endif()

        list(APPEND VALID_HEADER_NAMES "${HEADER_NAME}")
        list(APPEND VALID_HEADERS "${HEADER}")

        set(OUT_PARSED_DECLS "${GENERATED_PARSED_DIR}/${HEADER_NAME}_ParsedDecls.json")
        set(OUT_TYPE_REGISTRY "${GENERATED_PARSED_DIR}/${TARGET_NAME}_${HEADER_NAME}_registry.json")

        list(APPEND ALL_PARSED_DECLS_FILES "${OUT_PARSED_DECLS}")
        list(APPEND ALL_TYPE_REGISTRY_FILES "${OUT_TYPE_REGISTRY}")

        add_custom_command(
            OUTPUT "${OUT_PARSED_DECLS}" "${OUT_TYPE_REGISTRY}"
            COMMAND ${LUAU_PARSER_EXE} "${LUAU_PARSER}" -a "${OUT_PARSED_DECLS}" "${HEADER}" "${OUT_TYPE_REGISTRY}"
            DEPENDS ${LUAU_PARSER_EXE} "${LUAU_PARSER}" ${HEADER}
            COMMENT "Parse Luau bindings for ${HEADER}..."
            VERBATIM
        )

        set(SINGLE_PARSE_TARGET "Parse_${TARGET_NAME}_${HEADER_NAME}")
        add_custom_target(${SINGLE_PARSE_TARGET} DEPENDS "${OUT_PARSED_DECLS}" "${OUT_TYPE_REGISTRY}")
        add_dependencies(${PARSE_TARGET} ${SINGLE_PARSE_TARGET})
    endforeach()

    # =========================================================================
    # Merge — combine every header's registry fragment into one manifest.
    # This is a REAL build-time step (add_custom_command, not
    # file(GENERATE), which runs at configure time and can't depend on
    # outputs that don't exist yet). Depending on ALL_TYPE_REGISTRY_FILES
    # here is what forces every header to finish parsing before any
    # header's build step can start.
    # =========================================================================
    set(TYPE_REGISTRY_MANIFEST "${GENERATED_PARSED_DIR}/${TARGET_NAME}_registry.manifest")

    add_custom_command(
        OUTPUT "${TYPE_REGISTRY_MANIFEST}"
        COMMAND ${CMAKE_COMMAND}
        -DFILES=${ALL_TYPE_REGISTRY_FILES}
        -DOUTPUT=${TYPE_REGISTRY_MANIFEST}
        -P "${PARSER_ROOT_DIR}/WriteManifest.cmake"
        DEPENDS ${ALL_TYPE_REGISTRY_FILES} "${PARSER_ROOT_DIR}/WriteManifest.cmake"
        COMMENT "Merging type registry for ${TARGET_NAME}..."
        VERBATIM
    )

    set(MERGE_TARGET "Merge_${TARGET_NAME}_type_registry")
    add_custom_target(${MERGE_TARGET} DEPENDS "${TYPE_REGISTRY_MANIFEST}")
    add_dependencies(${MERGE_TARGET} ${PARSE_TARGET})

    # =========================================================================
    # Pass 2 — build bindings for every header. Each one depends on the
    # MERGED manifest (which transitively depends on every header's parse
    # step), so no build step can see a partial/empty type registry.
    # =========================================================================
    set(ALL_HEADER_BINDINGS_CPP "")

    list(LENGTH VALID_HEADER_NAMES VALID_COUNT)
    math(EXPR LAST_INDEX "${VALID_COUNT} - 1")

    foreach(INDEX RANGE ${LAST_INDEX})
        list(GET VALID_HEADER_NAMES ${INDEX} HEADER_NAME)
        list(GET VALID_HEADERS ${INDEX} HEADER)
        list(GET ALL_PARSED_DECLS_FILES ${INDEX} OUT_PARSED_DECLS)

        file(RELATIVE_PATH HEADER_REL "${CMAKE_SOURCE_DIR}" "${HEADER}")

        set(HEADER_API "${GENERATED_API_DIR}/${TARGET_NAME}_${HEADER_NAME}_api.d.luau")
        set(HEADER_DEF "${GENERATED_PRIVATE_DIR}/${TARGET_NAME}_${HEADER_NAME}_definition.h")
        set(HEADER_BINDINGS_H "${GENERATED_INCLUDE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.h")
        set(HEADER_BINDINGS_CPP "${GENERATED_PRIVATE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.cpp")

        list(APPEND ALL_HEADER_BINDINGS_CPP "${HEADER_BINDINGS_CPP}")

        add_custom_command(
            OUTPUT "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -s "${OUT_PARSED_DECLS}" "${TYPE_REGISTRY_MANIFEST}" "${HEADER_REL}"
            "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${OUT_PARSED_DECLS}" "${TYPE_REGISTRY_MANIFEST}"
            "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
            COMMENT "Build Luau bindings for ${HEADER_NAME}..."
            VERBATIM
        )

        set(SINGLE_BUILD_TARGET "Build_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${SINGLE_BUILD_TARGET} DEPENDS "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}")
        add_dependencies(${SINGLE_BUILD_TARGET} ${MERGE_TARGET})
        add_dependencies(${BUILD_TARGET} ${SINGLE_BUILD_TARGET})
    endforeach()

    # --- Aggregator ----------------------------------------------------------
    set(OUTPUT_INCLUDE "${GENERATED_INCLUDE_DIR}/luau_parser_bindings.h")
    set(AGGREGATOR_CONTENT "#pragma once\n\n#include \"lua.h\"\n\n")

    foreach(HEADER_NAME ${VALID_HEADER_NAMES})
        string(APPEND AGGREGATOR_CONTENT "void register_${HEADER_NAME}(lua_State* L);\n")
    endforeach()

    string(APPEND AGGREGATOR_CONTENT "\ninline void register_internal(lua_State* L)\n{\n")

    foreach(HEADER_NAME ${VALID_HEADER_NAMES})
        string(APPEND AGGREGATOR_CONTENT "    register_${HEADER_NAME}(L);\n")
    endforeach()

    string(APPEND AGGREGATOR_CONTENT "}\n")

    file(GENERATE OUTPUT "${OUTPUT_INCLUDE}" CONTENT "${AGGREGATOR_CONTENT}")

    # --- Wire everything into the target --------------------------------------
    add_dependencies(${TARGET_NAME} ${BUILD_TARGET})
    target_include_directories(${TARGET_NAME} PRIVATE "${GENERATED_INCLUDE_DIR}")
    target_include_directories(${TARGET_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
    target_sources(${TARGET_NAME} PRIVATE ${ALL_HEADER_BINDINGS_CPP})
endfunction()