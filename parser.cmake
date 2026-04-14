set(LUAU_PARSER_EXE $<TARGET_FILE:luau_parser>)
set(LUAU_BUILDER_EXE $<TARGET_FILE:luau_builder>)
set(PARSER_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR})

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()
set(GENERATED_DEF "${CMAKE_BINARY_DIR}/generated/generated.h")
set(GENERATED_DECL "${CMAKE_BINARY_DIR}/generated/api.d.luau")

set(MANIFEST_GENERATED_DEF "${GENERATED_DIR}/generated_definition.txt")
set(MANIFEST_GENERATED_DECL "${GENERATED_DIR}/generated_declaration.txt")

function(register_luau_parser)
    add_executable (luau_parser "${PARSER_ROOT_DIR}/LuauParser.cpp")
    target_link_libraries(luau_parser PRIVATE Luau.VM Luau.Compiler Luau.Ast)

    add_executable (luau_builder "${PARSER_ROOT_DIR}/LuauBuilder.cpp")
    target_link_libraries(luau_builder PRIVATE Luau.VM Luau.Compiler Luau.Ast)
endfunction()

set(LUAU_PARSER "${CMAKE_CURRENT_LIST_DIR}/parser.luau")
set(LUAU_BUILDER "${CMAKE_CURRENT_LIST_DIR}/builder.luau")

function(add_luau_bindings TARGET_NAME)
    set(HEADER_FILES_LIST ${ARGN})
    
    set(ALL_GEN_CPP "")
    set(ALL_GEN_TYPES "")

    foreach (HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)
        set(OUT_CPP "${GENERATED_DIR}/bindings_${TARGET_NAME}_${HEADER_NAME}.cpp")
        set(OUT_TYPES "${GENERATED_DIR}/api_${TARGET_NAME}_${HEADER_NAME}.d.luau")
        
        list(APPEND ALL_GEN_CPP "${OUT_CPP}")
        list(APPEND ALL_GEN_TYPES "${OUT_TYPES}")
        
        add_custom_command(
                OUTPUT "${OUT_CPP}" "${OUT_TYPES}"
                COMMAND ${LUAU_PARSER_EXE} "${LUAU_PARSER}" -a "${OUT_CPP}" "${OUT_TYPES}" ${HEADER}
                DEPENDS ${LUAU_PARSER_EXE} "${LUAU_PARSER}" ${HEADER}
                COMMENT "Generating Luau bindings for ${HEADER}..."
                VERBATIM
        )
        
        set(GEN_TARGET "generate_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${GEN_TARGET} DEPENDS "${OUT_CPP}" "${OUT_TYPES}")
        add_dependencies(${TARGET_NAME} ${GEN_TARGET})
    endforeach()

    string(REPLACE ";" "\n" MANIFEST_DEF_CONTENT "${ALL_GEN_CPP}")
    string(REPLACE ";" "\n" MANIFEST_DECL_CONTENT "${ALL_GEN_TYPES}")
    file(GENERATE OUTPUT "${MANIFEST_GENERATED_DEF}" CONTENT "${MANIFEST_DEF_CONTENT}")
    file(GENERATE OUTPUT "${MANIFEST_GENERATED_DECL}" CONTENT "${MANIFEST_DECL_CONTENT}")
    
    add_custom_command(
            OUTPUT "${GENERATED_DEF}" "${GENERATED_DECL}"
            COMMAND ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" -a "${MANIFEST_GENERATED_DEF}" "${MANIFEST_GENERATED_DECL}" "${GENERATED_DEF}" "${GENERATED_DECL}"
            DEPENDS ${LUAU_BUILDER_EXE} "${LUAU_BUILDER}" "${ALL_GEN_CPP}" "${ALL_GEN_TYPES}"
            COMMENT "Build Luau bindings..."
            VERBATIM
    )
    set(BUILD_TARGET "build_${TARGET_NAME}_bindings")
    add_custom_target(${BUILD_TARGET} DEPENDS "${GENERATED_DECL}")
    add_dependencies(${TARGET_NAME} ${BUILD_TARGET})
    
endfunction()