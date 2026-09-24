steam_libraries() {
    local STEAM_ROOT_LIST=(
        "$HOME/.steam/steam"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
        "$HOME/Library/Application Support/Steam"
    )
    local STEAM_ROOT_DIRECTORY LIBRARY_MANIFEST LIBRARY_PATH
    for STEAM_ROOT_DIRECTORY in "${STEAM_ROOT_LIST[@]}"; do
        [[ -d "$STEAM_ROOT_DIRECTORY" ]] || continue
        printf '%s\n' "$STEAM_ROOT_DIRECTORY"
        LIBRARY_MANIFEST="$STEAM_ROOT_DIRECTORY/steamapps/libraryfolders.vdf"
        [[ -f "$LIBRARY_MANIFEST" ]] || continue
        while IFS= read -r LIBRARY_PATH; do
            printf '%s\n' "$LIBRARY_PATH"
        done < <(sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$LIBRARY_MANIFEST")
    done
}

find_in_libraries() {
    local DIRECTORY_NAME="$1" LIBRARY_DIRECTORY
    while IFS= read -r LIBRARY_DIRECTORY; do
        if [[ -d "$LIBRARY_DIRECTORY/steamapps/common/$DIRECTORY_NAME" ]]; then
            printf '%s\n' "$LIBRARY_DIRECTORY/steamapps/common/$DIRECTORY_NAME"
            return 0
        fi
    done < <(steam_libraries)
    return 1
}

find_x4() {
    if [[ -n "${X4_PATH:-}" ]]; then
        printf '%s\n' "$X4_PATH"
        return 0
    fi
    local LIBRARY_DIRECTORY
    while IFS= read -r LIBRARY_DIRECTORY; do
        if [[ -x "$LIBRARY_DIRECTORY/steamapps/common/X4 Foundations/X4" ]] \
            || [[ -f "$LIBRARY_DIRECTORY/steamapps/common/X4 Foundations/X4.exe" ]]; then
            printf '%s\n' "$LIBRARY_DIRECTORY/steamapps/common/X4 Foundations"
            return 0
        fi
    done < <(steam_libraries)
    return 1
}

extension_id() {
    sed -n 's/.*<content[^>]*id="\([^"]*\)".*/\1/p' "$1" | head -1
}
