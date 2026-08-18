# Invoked via `cmake -P`. Expects -D FILES (semicolon-separated list) and -D OUTPUT.
# Writes one path per line — a real build-time step, unlike file(GENERATE)
# which runs at configure time and can't express a dependency on outputs
# of other custom commands (like the per-header registry files here).
string(REPLACE " " ";" FILES_LIST "${FILES}")
string(REPLACE ";" "\n" MANIFEST_CONTENT "${FILES_LIST}")
file(WRITE "${OUTPUT}" "${MANIFEST_CONTENT}\n")