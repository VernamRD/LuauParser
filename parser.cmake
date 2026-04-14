set(LUAU_PARSER_EXE $<TARGET_FILE:luau_host>)

function(register_luau_parser)
    add_executable (luau_host "${CMAKE_CURRENT_SOURCE_DIR}/LuauParser/LuauParser.cpp")
    target_link_libraries(luau_host PRIVATE Luau.VM Luau.Compiler Luau.Ast)
endfunction()

set(GENERATED_DIR ${CMAKE_BINARY_DIR}/generated)
if(NOT EXISTS "${GENERATED_DIR}")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
endif()

set(LUAU_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/LuauParser/parser.luau")

function(add_luau_bindings TARGET_NAME)
    set(HEADER_FILES_LIST ${ARGN})

    foreach (HEADER ${HEADER_FILES_LIST})
        get_filename_component(HEADER_NAME ${HEADER} NAME_WE)
        set(OUT_CPP "${GENERATED_DIR}/bindings_${TARGET_NAME}_${HEADER_NAME}.cpp")
        set(OUT_TYPES "${GENERATED_DIR}/api_${TARGET_NAME}_${HEADER_NAME}.d.luau")
        
        add_custom_command(
                OUTPUT "${OUT_CPP}" "${OUT_TYPES}"
                COMMAND ${LUAU_PARSER_EXE} "${LUAU_SCRIPT}" -a "${OUT_CPP}" "${OUT_TYPES}" ${HEADER}
                DEPENDS ${LUAU_PARSER_EXE} "${LUAU_SCRIPT}" ${HEADER}
                COMMENT "Generating Luau bindings for ${HEADER}..."
                VERBATIM
        )

        set(GEN_TARGET "generate_${TARGET_NAME}_${HEADER_NAME}_bindings")
        add_custom_target(${GEN_TARGET} DEPENDS "${OUT_CPP}" "${OUT_TYPES}")
        add_dependencies(${TARGET_NAME} ${GEN_TARGET})
    endforeach()
endfunction()