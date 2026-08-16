# =============================================================================
# LuauParser build integration
#
# Pipeline per header (only for headers containing at least one @luau marker):
#
# 1. Parse    -> luau_parser reads the header, emits <Header>_ParsedDecls.json
# 2. Check    -> if the JSON isn't empty, verify the header compiles standalone
# (-fsyntax-only), catching forward-declaration-only headers
# before we generate C++ that can't see complete types.
# 3. Build    -> luau_builder turns the JSON into:
# - <Header>_api.d.luau      (Luau type declarations)
# - <Header>_definition.h    (C wrapper function bodies)
# - <Target>_<Header>_bindings.h/.cpp
# (register_<Header>(lua_State*))
#
# All per-header .cpp files are added to the target's sources, so each header
# gets its own translation unit (parallel builds, minimal rebuild fan-out).
# A small aggregator header (luau_parser_bindings.h) exposes a single
# register_internal(lua_State*) that calls every per-header register_* fn.
# =============================================================================

set(LUAU_PARSER_EXE $<TARGET_FILE:luau_parser>)
set(LUAU_BUILDER_EXE $<TARGET_FILE:luau_builder>)
set(PARSER_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR})

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")

if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()

# Small runtime helper (register_scoped_func, etc.) needed by every
# generated *_bindings.cpp. Copied into the generated tree once per target.
set(PARSER_UTILITY_FILE_NAME "ParserRegister.h")

# -----------------------------------------------------------------------------
# register_luau_parser()
#
# Declares the two helper executables used by the pipeline:
# - luau_parser  : header -> ParsedDecls.json
# - luau_builder : ParsedDecls.json -> generated bindings
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# build_luau_bindings(TARGET_NAME header1.h [header2.h ...])
#
# Generates and attaches Luau bindings for every header in the list that
# contains at least one @luau marker. Headers without any @luau markers are
# skipped entirely (no parse, no compile) to keep the build clean and fast.
# -----------------------------------------------------------------------------
function(build_luau_bindings TARGET_NAME)
    set(HEADER_FILES_LIST ${ARGN})

    # Re-run CMake configure whenever any candidate header changes, so that
    # adding/removing @luau markers is picked up without a manual reconfigure.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${HEADER_FILES_LIST})

    # Self-containment checks should use the same C++ standard as the target
    # they're generating bindings for, to avoid false positives/negatives
    # from language features gated behind -std=.
    get_target_property(TARGET_CXX_STANDARD ${TARGET_NAME} CXX_STANDARD)

    if(NOT TARGET_CXX_STANDARD)
        set(TARGET_CXX_STANDARD 23) # fallback if the target doesn't set CXX_STANDARD explicitly
    endif()

    # --- Generated directory layout -----------------------------------------
    # generated/include/  -> public bindings headers (target include path)
    # generated/private/  -> .cpp sources + internal definition headers
    # generated/<Target>/ -> per-target intermediate cache (parsed JSON, stamps)
    # generated/api/      -> generated .d.luau type declarations
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

    # Copy ParserRegister.h into the generated tree once per target, so every
    # generated *_bindings.cpp can #include "ParserRegister.h" locally.
    add_custom_command(
        OUTPUT "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMAND ${CMAKE_COMMAND} -E copy
        "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
        DEPENDS "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMENT "Copying parser utility file to generated directory"
        VERBATIM
    )

    # Umbrella targets: depending on these builds/parses every header for
    # this target in one go (mainly useful for IDE targets / manual invocation).
    set(PARSE_TARGET "Parse_${TARGET_NAME}")
    add_custom_target(${PARSE_TARGET})

    set(BUILD_TARGET "Build_${TARGET_NAME}_luau_bindings")
    add_custom_target(${BUILD_TARGET})

    # Accumulated across the loop below, used to build the aggregator and
    # the target's source list once all headers have been processed.
    set(ALL_HEADER_BINDINGS_CPP "")
    set(ALL_HEADER_NAMES "")
    set(ALL_HEADER_API_FILES "")

    foreach(HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)

        # --- Skip headers with nothing to bind ------------------------------
        # A header with no @luau markers has no exported declarations, so
        # there's no point parsing/compiling/checking it at all.
        file(STRINGS "${HEADER}" LUAU_MARKERS REGEX "@luau")

        if(NOT LUAU_MARKERS)
            continue()
        endif()

        list(APPEND ALL_HEADER_NAMES "${HEADER_NAME}")

        # --- Step 1: parse header -> ParsedDecls.json -----------------------
        set(OUT_PARSED_DECLS "${GENERATED_PARSED_DIR}/${HEADER_NAME}_ParsedDecls.json")

        add_custom_command(
            OUTPUT "${OUT_PARSED_DECLS}"
            COMMAND ${LUAU_PARSER_EXE} "${LUAU_PARSER}" -a "${OUT_PARSED_DECLS}" ${HEADER}
            DEPENDS ${LUAU_PARSER_EXE} "${LUAU_PARSER}" ${HEADER}
            COMMENT "Parse Luau bindings for ${HEADER}..."
            VERBATIM
        )

        set(SINGLE_PARSE_TARGET "Parse_${TARGET_NAME}_${HEADER_NAME}")
        add_custom_target(${SINGLE_PARSE_TARGET} DEPENDS "${OUT_PARSED_DECLS}")
        add_dependencies(${PARSE_TARGET} ${SINGLE_PARSE_TARGET})

        # --- Step 2: self-containment check ---------------------------------
        # Compiles the header standalone (-fsyntax-only) to catch forward-decl
        # -only headers before we generate C++ that references incomplete
        # types. CheckSelfContained.cmake itself no-ops if the JSON is empty,
        # but we've already filtered those out above, so this always runs
        # for headers that reach this point.
        set(SYNTAX_CHECK_STAMP "${GENERATED_PARSED_DIR}/${HEADER_NAME}.syntax_ok")
        add_custom_command(
            OUTPUT "${SYNTAX_CHECK_STAMP}"
            COMMAND ${CMAKE_COMMAND}
            -DDECLS_JSON=${OUT_PARSED_DECLS}
            -DHEADER=${HEADER}
            -DCXX_COMPILER=${CMAKE_CXX_COMPILER}
            -DCXX_STANDARD=${TARGET_CXX_STANDARD}
            -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
            -DSTAMP=${SYNTAX_CHECK_STAMP}
            -P "${PARSER_ROOT_DIR}/CheckSelfContained.cmake"
            DEPENDS "${OUT_PARSED_DECLS}" "${PARSER_ROOT_DIR}/CheckSelfContained.cmake"
            COMMENT "Checking ${HEADER_NAME}.h is self-contained..."
            VERBATIM
        )

        # Path to the header relative to the source root, used inside the
        # generated .cpp as `#include "<HEADER_REL>"` (resolved via the
        # CMAKE_SOURCE_DIR include path added to the target below).
        file(RELATIVE_PATH HEADER_REL "${CMAKE_SOURCE_DIR}" "${HEADER}")

        # --- Step 3: build bindings for this header -------------------------
        set(HEADER_API "${GENERATED_API_DIR}/${TARGET_NAME}_${HEADER_NAME}_api.d.luau")
        set(HEADER_DEF "${GENERATED_PRIVATE_DIR}/${TARGET_NAME}_${HEADER_NAME}_definition.h")
        set(HEADER_BINDINGS_H "${GENERATED_INCLUDE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.h")
        set(HEADER_BINDINGS_CPP "${GENERATED_PRIVATE_DIR}/${TARGET_NAME}_${HEADER_NAME}_bindings.cpp")

        list(APPEND ALL_HEADER_BINDINGS_CPP "${HEADER_BINDINGS_CPP}")
        list(APPEND ALL_HEADER_API_FILES "${HEADER_API}")

        add_custom_command(
            OUTPUT "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -s "${OUT_PARSED_DECLS}" "${HEADER_REL}"
            "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}"
            DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${SINGLE_PARSE_TARGET}" "${OUT_PARSED_DECLS}"
            "${SYNTAX_CHECK_STAMP}"
            "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
            COMMENT "Build Luau bindings for ${HEADER_NAME}..."
            VERBATIM
        )

        set(SINGLE_BUILD_TARGET "Build_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${SINGLE_BUILD_TARGET} DEPENDS "${HEADER_API}" "${HEADER_DEF}" "${HEADER_BINDINGS_H}" "${HEADER_BINDINGS_CPP}")
        add_dependencies(${BUILD_TARGET} ${SINGLE_BUILD_TARGET})
    endforeach()

    # --- Aggregator ----------------------------------------------------------
    # A single stable header exposing register_internal(lua_State*), which
    # calls register_<HeaderName>() for every processed header. Generated
    # directly by CMake (not by luau_builder) since the header-name list is
    # already known at configure time — no need to round-trip through the
    # builder tool for this.
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

    # --- Wire everything into the target --------------------------------------
    add_dependencies(${TARGET_NAME} ${BUILD_TARGET})
    target_include_directories(${TARGET_NAME} PRIVATE "${GENERATED_INCLUDE_DIR}")
    target_include_directories(${TARGET_NAME} PRIVATE "${CMAKE_SOURCE_DIR}") # for HEADER_REL includes
    target_sources(${TARGET_NAME} PRIVATE ${ALL_HEADER_BINDINGS_CPP})
endfunction()