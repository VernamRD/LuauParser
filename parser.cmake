set(LUAU_PARSER_EXE $<TARGET_FILE:luau_parser>)
set(LUAU_BUILDER_EXE $<TARGET_FILE:luau_builder>)
set(PARSER_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR})

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()

set(PARSER_UTILITY_FILE_NAME "ParserRegister.h")

function(register_luau_parser)
    add_executable (luau_parser "${PARSER_ROOT_DIR}/Parser/LuauParser.cpp")
    target_link_libraries(luau_parser PRIVATE Luau.VM Luau.Compiler Luau.Ast)
    target_include_directories(luau_parser PRIVATE
            "${CMAKE_SOURCE_DIR}"
            "${CMAKE_SOURCE_DIR}/LuauParser"
    )
    
    add_executable (luau_builder "${PARSER_ROOT_DIR}/Builder/LuauBuilder.cpp")
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

    if(NOT EXISTS "${GENERATED_INCLUDE_DIR}")
        file(MAKE_DIRECTORY "${GENERATED_INCLUDE_DIR}")
    endif()

    if(NOT EXISTS "${GENERATED_PRIVATE_DIR}")
        file(MAKE_DIRECTORY "${GENERATED_PRIVATE_DIR}")
    endif()

    if(NOT EXISTS "${GENERATED_CACHE_DIR}")
        file(MAKE_DIRECTORY "${GENERATED_CACHE_DIR}")
    endif()

    # Luau function declaration
    set(GENERATED_API "${GENERATED_DIR}/${TARGET_NAME}_api.d.luau")
    # Function realisaztion
    set(GENERATED_DEF "${GENERATED_DIR}/${TARGET_NAME}_definition.h")

    # Function registration
    set(OUTPUT_INCLUDE "${GENERATED_INCLUDE_DIR}/luau_parser_bindings.h")

    # Function registration
    set(OUTPUT_CPP "${GENERATED_PRIVATE_DIR}/luau_parser_bindings.cpp")

    set(MANIFEST_PARSED_DECLS "${GENERATED_CACHE_DIR}/parsed_decls.manifest")
    if(NOT EXISTS "${MANIFEST_PARSED_DECLS}")
        file(WRITE "${MANIFEST_PARSED_DECLS}")
    endif()
    set(ALL_PARSED_DECLS "")

    set(PARSE_TARGET "Parse_${TARGET_NAME}")
    add_custom_target(${PARSE_TARGET})

    # Parse each header
    foreach (HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)
        set(OUT_PARSED_DECLS "${GENERATED_CACHE_DIR}/${HEADER_NAME}_ParsedDecls.json")

        list(APPEND ALL_PARSED_DECLS "${OUT_PARSED_DECLS}")

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
    endforeach()

    # Format the manifest file with newlines
    string(REPLACE ";" "\n" MANIFEST_PARSED_DECLS_CONTENT "${ALL_PARSED_DECLS}")
    file(GENERATE OUTPUT "${MANIFEST_PARSED_DECLS}" CONTENT "${MANIFEST_PARSED_DECLS_CONTENT}")

    # Copy ParserRegister.h to generated folder
    add_custom_command(
        OUTPUT "${GENERATED_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMAND ${CMAKE_COMMAND} -E copy
        "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        "${GENERATED_PRIVATE_DIR}/${PARSER_UTILITY_FILE_NAME}"
        DEPENDS "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
        COMMENT "Copying parser utility file to generated directory"
        VERBATIM
    )

    # Build single file
    add_custom_command(
        OUTPUT "${GENERATED_API}" "${GENERATED_DEF}" "${OUTPUT_INCLUDE}" "${OUTPUT_CPP}"
        COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -a "${MANIFEST_PARSED_DECLS}" "${GENERATED_API}" "${GENERATED_DEF}" "${OUTPUT_INCLUDE}" "${OUTPUT_CPP}"
        DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${PARSE_TARGET}" "${MANIFEST_PARSED_DECLS}"
        COMMENT "Build Luau bindings ${OUTPUT_CPP} and API ${GENERATED_API}... "
        VERBATIM
    )
    set(PARSER_BUILD_TARGET "Build_${TARGET_NAME}_luau_bindings")
    add_custom_target(${PARSER_BUILD_TARGET} DEPENDS "${GENERATED_DIR}/${PARSER_UTILITY_FILE_NAME}" "${GENERATED_API}" "${GENERATED_DEF}" "${OUTPUT_CPP}" "${OUTPUT_INCLUDE}")

    add_dependencies(${TARGET_NAME} ${PARSER_BUILD_TARGET})
    target_include_directories(${TARGET_NAME} PRIVATE "${GENERATED_DIR}/include")
    target_sources(${TARGET_NAME} PRIVATE "${OUTPUT_CPP}")
endfunction()