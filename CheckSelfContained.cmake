# Invoked via `cmake -P`. Expects -D DECLS_JSON, HEADER, CXX_COMPILER, CXX_STANDARD, SOURCE_DIR, STAMP
file(READ "${DECLS_JSON}" DECLS_CONTENT)
string(STRIP "${DECLS_CONTENT}" DECLS_CONTENT)

if(NOT DECLS_CONTENT STREQUAL "" AND NOT DECLS_CONTENT STREQUAL "[]")
    execute_process(
        COMMAND "${CXX_COMPILER}" -fsyntax-only -std=c++${CXX_STANDARD} -Wno-pragma-once-outside-header -I "${SOURCE_DIR}" "${HEADER}"
        RESULT_VARIABLE CHECK_RESULT
    )

    if(NOT CHECK_RESULT EQUAL 0)
        message(FATAL_ERROR "Header ${HEADER} is not self-contained (has exported decls but fails -fsyntax-only)")
    endif()
endif()

file(TOUCH "${STAMP}")