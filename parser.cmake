set(LUAU_PARSER_EXE $<TARGET_FILE:luau_parser>)
set(LUAU_BUILDER_EXE $<TARGET_FILE:luau_builder>)
set(PARSER_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR})

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()

function(register_luau_parser)
    add_executable (luau_parser "${PARSER_ROOT_DIR}/LuauParser.cpp")
    target_link_libraries(luau_parser PRIVATE Luau.VM Luau.Compiler Luau.Ast)

    add_executable (luau_builder "${PARSER_ROOT_DIR}/LuauBuilder.cpp")
    target_link_libraries(luau_builder PRIVATE Luau.VM Luau.Compiler Luau.Ast)
endfunction()

set(LUAU_PARSER "${CMAKE_CURRENT_LIST_DIR}/parser.luau")
set(LUAU_BUILDER "${CMAKE_CURRENT_LIST_DIR}/builder.luau")

function(build_luau_bindings TARGET_NAME)
    set(HEADER_FILES_LIST ${ARGN})

    # Function registration
    set(GENERATED_REG "${GENERATED_DIR}/${TARGET_NAME}_generated.h")
    # Luau function declaration
    set(GENERATED_API "${GENERATED_DIR}/${TARGET_NAME}_api.d.luau")

    # Function registration
    set(OUTPUT_INCLUDE "${PARSER_ROOT_DIR}/include/luau_parser_bindings.h")
    
    set(MANIFEST_GENERATED_WRAPPERS "${GENERATED_DIR}/${TARGET_NAME}_generated_wrappers.manifest")
    if(NOT EXISTS "${MANIFEST_GENERATED_WRAPPERS}")
        file(WRITE "${MANIFEST_GENERATED_WRAPPERS}")
    endif()
    
    set(MANIFEST_GENERATED_REG "${GENERATED_DIR}/${TARGET_NAME}_generated_reg.manifest")
    if(NOT EXISTS "${MANIFEST_GENERATED_REG}")
        file(WRITE "${MANIFEST_GENERATED_REG}")
    endif()
    
    set(MANIFEST_GENERATED_API "${GENERATED_DIR}/${TARGET_NAME}_generated_api.manifest")
    if(NOT EXISTS "${MANIFEST_GENERATED_API}")
        file(WRITE "${MANIFEST_GENERATED_API}")
    endif()

    set(ALL_GEN_WRAPPERS "")
    set(ALL_GEN_REG "")
    set(ALL_GEN_API "")
    
    # Parse each header
    foreach (HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)
        set(OUT_WRAPPERS "${GENERATED_DIR}/wrapper_${TARGET_NAME}_${HEADER_NAME}.h")
        set(OUT_REG "${GENERATED_DIR}/reg_${TARGET_NAME}_${HEADER_NAME}.h")
        set(OUT_APIS "${GENERATED_DIR}/api_${TARGET_NAME}_${HEADER_NAME}.d.luau")
        
        list(APPEND ALL_GEN_WRAPPERS "${OUT_WRAPPERS}")
        list(APPEND ALL_GEN_REG "${OUT_REG}")
        list(APPEND ALL_GEN_API "${OUT_APIS}")
        
        add_custom_command(
                OUTPUT "${OUT_WRAPPERS}" "${OUT_REG}" "${OUT_APIS}"
                COMMAND ${LUAU_PARSER_EXE} "${LUAU_PARSER}" -a "${OUT_WRAPPERS}" "${OUT_REG}" "${OUT_APIS}" ${HEADER}
                DEPENDS ${LUAU_PARSER_EXE} "${LUAU_PARSER}" ${HEADER}
                COMMENT "Generating Luau bindings for ${HEADER}..."
                VERBATIM
        )
        
        set(GEN_TARGET "generate_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${GEN_TARGET} DEPENDS "${OUT_WRAPPERS}" "${OUT_REG}" "${OUT_APIS}")
        add_dependencies(${TARGET_NAME} ${GEN_TARGET})
    endforeach()

    string(REPLACE ";" "\n" MANIFEST_WRAPPERS_CONTENT "${ALL_GEN_WRAPPERS}")
    string(REPLACE ";" "\n" MANIFEST_REG_CONTENT "${ALL_GEN_REG}")
    string(REPLACE ";" "\n" MANIFEST_APIS_CONTENT "${ALL_GEN_API}")
    file(GENERATE OUTPUT "${MANIFEST_GENERATED_WRAPPERS}" CONTENT "${MANIFEST_WRAPPERS_CONTENT}")
    file(GENERATE OUTPUT "${MANIFEST_GENERATED_REG}" CONTENT "${MANIFEST_REG_CONTENT}")
    file(GENERATE OUTPUT "${MANIFEST_GENERATED_API}" CONTENT "${MANIFEST_APIS_CONTENT}")
    
    # Build single file
    add_custom_command(
            OUTPUT "${GENERATED_REG}" "${GENERATED_API}" "${OUTPUT_INCLUDE}"
            COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -a "${MANIFEST_GENERATED_WRAPPERS}" "${MANIFEST_GENERATED_REG}" "${MANIFEST_GENERATED_API}" "${GENERATED_REG}" "${GENERATED_API}" "${OUTPUT_INCLUDE}"
            DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${ALL_GEN_WRAPPERS}" "${ALL_GEN_API}"
            COMMENT "Build Luau bindings..."
            VERBATIM
    )
    
    set(PARSER_UTILITY_FILE_NAME "ParserRegister.h")
    # Copy ParserRegister.h to generated folder
    add_custom_command(
            OUTPUT "${GENERATED_DIR}/${PARSER_UTILITY_FILE_NAME}"
            COMMAND ${CMAKE_COMMAND} -E copy
            "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
            "${GENERATED_DIR}/${PARSER_UTILITY_FILE_NAME}"
            DEPENDS "${PARSER_ROOT_DIR}/${PARSER_UTILITY_FILE_NAME}"
            COMMENT "Copying parser utility file to generated directory"
            VERBATIM
    )
    
    set(BUILD_TARGET "build_${TARGET_NAME}_bindings")
    add_custom_target(${BUILD_TARGET} DEPENDS "${GENERATED_REG}" "${GENERATED_API}" "${OUTPUT_INCLUDE}" "${GENERATED_DIR}/${PARSER_UTILITY_FILE_NAME}")
    add_dependencies(${TARGET_NAME} ${BUILD_TARGET})
endfunction()