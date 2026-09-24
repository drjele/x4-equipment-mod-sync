#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_ROOT/lib/find_x4.sh"

WORKSHOP_ID_FILE="$REPO_ROOT/steam/workshop-id"

die() {
    echo "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'USAGE'
usage:
  ./publish.sh publish                          first upload of the extension
  ./publish.sh update "what changed" [option]   update the published item

update options:
  --minor      the version attribute has not changed since the last upload
  --namedesc   also push the name and description of content.xml to Steam
  --readback   overwrite the local content.xml name and description with
               the ones currently on Steam, instead of uploading anything
USAGE
    exit 2
}

MINOR=""
NAMEDESC=""
COMMAND="${1:-}"
case "$COMMAND" in
    publish)
        [[ 1 -eq $# ]] || usage
        [[ -f "$WORKSHOP_ID_FILE" ]] \
            && die "$WORKSHOP_ID_FILE already exists - the item is published, use: ./publish.sh update \"...\""
        ;;
    update)
        [[ 2 -le $# && -n "${2:-}" ]] || usage
        CHANGENOTE="$2"
        shift 2
        while [[ 0 -lt $# ]]; do
            case "$1" in
                --minor) MINOR="-minor" ;;
                --namedesc) NAMEDESC="up" ;;
                --readback) NAMEDESC="down" ;;
                *) usage ;;
            esac
            shift
        done
        [[ -f "$WORKSHOP_ID_FILE" ]] \
            || die "no $WORKSHOP_ID_FILE - nothing has been published yet, use: ./publish.sh publish"
        ;;
    *) usage ;;
esac

find_workshop_tool() {
    local TOOL_CANDIDATE
    if [[ -n "${X_TOOLS_PATH:-}" ]]; then
        if [[ -f "$X_TOOLS_PATH" ]]; then
            printf '%s\n' "$X_TOOLS_PATH"
            return 0
        fi
        TOOL_CANDIDATE="$X_TOOLS_PATH/WorkshopTool.exe"
        [[ -f "$TOOL_CANDIDATE" ]] || return 1
        printf '%s\n' "$TOOL_CANDIDATE"
        return 0
    fi
    local TOOL_DIRECTORY
    TOOL_DIRECTORY="$(find_in_libraries "X Tools")" || return 1
    TOOL_CANDIDATE="$(find "$TOOL_DIRECTORY" -maxdepth 2 -iname 'WorkshopTool.exe' -print -quit)"
    [[ -n "$TOOL_CANDIDATE" ]] || return 1
    printf '%s\n' "$TOOL_CANDIDATE"
}

find_proton() {
    if [[ -n "${PROTON_PATH:-}" ]]; then
        [[ -x "$PROTON_PATH/proton" ]] || return 1
        printf '%s\n' "$PROTON_PATH"
        return 0
    fi
    local LIBRARY_DIRECTORY PROTON_CANDIDATE=""
    while IFS= read -r LIBRARY_DIRECTORY; do
        local TOOL_DIRECTORY
        for TOOL_DIRECTORY in "$LIBRARY_DIRECTORY"/steamapps/common/Proton*; do
            [[ -x "$TOOL_DIRECTORY/proton" ]] || continue
            PROTON_CANDIDATE="$TOOL_DIRECTORY"
            [[ "$TOOL_DIRECTORY" == *Experimental* ]] && {
                printf '%s\n' "$TOOL_DIRECTORY"
                return 0
            }
        done
    done < <(steam_libraries)
    [[ -n "$PROTON_CANDIDATE" ]] || return 1
    printf '%s\n' "$PROTON_CANDIDATE"
}

steam_root() {
    local LIBRARY_DIRECTORY
    while IFS= read -r LIBRARY_DIRECTORY; do
        printf '%s\n' "$LIBRARY_DIRECTORY"
        return 0
    done < <(steam_libraries)
    return 1
}

win_path() {
    printf 'Z:%s\n' "${1//\//\\}"
}

GAME_PATH="$(find_x4)" || {
    die "could not find an X4: Foundations installation - set X4_PATH to point at it"
}
[[ -d "$GAME_PATH/extensions" ]] || die "no extensions directory at $GAME_PATH/extensions"

TOOL="$(find_workshop_tool)" || {
    die "could not find WorkshopTool.exe - install the X Tools package (steam://install/282160),
or set X_TOOLS_PATH to the directory holding it"
}

EXTENSION_ID="$(extension_id "$REPO_ROOT/extension/content.xml")"
[[ -n "$EXTENSION_ID" ]] || die "could not read the extension id out of extension/content.xml"
STAGE="$GAME_PATH/extensions/$EXTENSION_ID"
[[ -f "$REPO_ROOT/extension/preview.jpg" ]] || die "extension/preview.jpg is missing"

echo "game:  $GAME_PATH"
echo "tool:  $TOOL"
echo "stage: $STAGE"

# whatever happens from here on, the local install must not be left holding the
# staged copy with the Workshop id in it
restore_local_install() {
    "$REPO_ROOT/install.sh" >/dev/null && echo "local install restored to id=$EXTENSION_ID"
}
trap restore_local_install EXIT

rm -rf -- "$STAGE"
mkdir -p -- "$STAGE"
cp -r -- "$REPO_ROOT/extension/." "$STAGE/"

if [[ -f "$WORKSHOP_ID_FILE" ]]; then
    WORKSHOP_ID="$(tr -cd '0-9' <"$WORKSHOP_ID_FILE")"
    [[ -n "$WORKSHOP_ID" ]] || die "$WORKSHOP_ID_FILE holds no digits"
    sed -i "s/id=\"$EXTENSION_ID\"/id=\"ws_$WORKSHOP_ID\"/" "$STAGE/content.xml"
    echo "item:  ws_$WORKSHOP_ID"
fi

# the tool is a Windows console application: launched through Proton it gets no
# console of its own and everything it prints is lost, so it is wrapped in a
# batch file that redirects both streams to a log we can show afterwards
write_batch_file() {
    local BATCH_FILE="$1" LOG_FILE="$2"
    shift 2
    local LINE ARGUMENT
    LINE="\"$(win_path "$TOOL")\""
    for ARGUMENT in "$@"; do
        ARGUMENT="${ARGUMENT//%/%%}"
        case "$ARGUMENT" in
            *[[:space:]]*) LINE="$LINE \"$ARGUMENT\"" ;;
            *) LINE="$LINE $ARGUMENT" ;;
        esac
    done
    {
        printf '@echo off\r\n'
        printf 'cd /d "%s"\r\n' "$(win_path "$(dirname "$TOOL")")"
        printf '%s > "%s" 2>&1\r\n' "$LINE" "$(win_path "$LOG_FILE")"
        printf 'exit /b %%ERRORLEVEL%%\r\n'
    } >"$BATCH_FILE"
}

# the Steam snap runs with a private /tmp, so the Steam IPC that the tool needs
# to talk to the client is only reachable from inside the snap mount namespace
uses_snap_steam() {
    [[ "$1" == "$HOME/snap/steam/"* ]] && command -v snap >/dev/null 2>&1
}

run_tool() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN* | Windows_NT)
            (cd "$(dirname "$TOOL")" && ./"$(basename "$TOOL")" "$@")
            ;;
        *)
            local PROTON_DIRECTORY STEAM_DIRECTORY COMPATIBILITY_DIRECTORY
            PROTON_DIRECTORY="$(find_proton)" \
                || die "could not find Proton - install any Proton version from Steam, or set PROTON_PATH"
            STEAM_DIRECTORY="$(steam_root)"
            COMPATIBILITY_DIRECTORY="$(dirname "$(dirname "$TOOL")")/../compatdata/282160"
            mkdir -p -- "$COMPATIBILITY_DIRECTORY"
            COMPATIBILITY_DIRECTORY="$(cd "$COMPATIBILITY_DIRECTORY" && pwd)"
            echo "proton: $PROTON_DIRECTORY"

            local BATCH_FILE="$COMPATIBILITY_DIRECTORY/workshoptool.bat"
            local LOG_FILE="$COMPATIBILITY_DIRECTORY/workshoptool.log"
            rm -f -- "$LOG_FILE"
            write_batch_file "$BATCH_FILE" "$LOG_FILE" "$@"

            # Proton discards the exit code of the Windows process and the
            # wrapper's own status says nothing about it either, so the log the
            # batch file leaves behind is the only report we get
            local STATUS=0
            if uses_snap_steam "$STEAM_DIRECTORY"; then
                echo "steam:  snap - running the tool inside the snap namespace"
                local SNAP_SCRIPT
                SNAP_SCRIPT="$(printf 'export STEAM_COMPAT_CLIENT_INSTALL_PATH=%q\nexport STEAM_COMPAT_DATA_PATH=%q\ncd %q || exit 1\nexec %q run cmd.exe /c %q </dev/null\n' \
                    "$STEAM_DIRECTORY" "$COMPATIBILITY_DIRECTORY" "$(dirname "$TOOL")" \
                    "$PROTON_DIRECTORY/proton" "$(win_path "$BATCH_FILE")")"
                printf '%s' "$SNAP_SCRIPT" | snap run --shell steam >/dev/null 2>&1 || true
            else
                (
                    cd "$(dirname "$TOOL")" || exit 1
                    STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_DIRECTORY" \
                        STEAM_COMPAT_DATA_PATH="$COMPATIBILITY_DIRECTORY" \
                        "$PROTON_DIRECTORY/proton" run cmd.exe /c "$(win_path "$BATCH_FILE")" </dev/null
                ) >/dev/null 2>&1 || true
            fi

            echo
            if [[ -s "$LOG_FILE" ]]; then
                cat -- "$LOG_FILE"
                grep -q '^ERROR' -- "$LOG_FILE" && STATUS=1
            else
                echo "the tool produced no output - it could not be started" >&2
                STATUS=1
            fi
            rm -f -- "$BATCH_FILE" "$LOG_FILE"
            return "$STATUS"
            ;;
    esac
}

STAGE_WIN="$(win_path "$STAGE")"
case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN* | Windows_NT) STAGE_WIN="$STAGE" ;;
esac

if [[ "publish" == "$COMMAND" ]]; then
    run_tool publishx4 -path "$STAGE_WIN" -preview "$STAGE_WIN\\preview.jpg" -buildcat -batchmode \
        || die "the upload failed - see the tool output above"
else
    run_tool update -path "$STAGE_WIN" -preview "$STAGE_WIN\\preview.jpg" -buildcat \
        -batchmode ${MINOR:+"$MINOR"} ${NAMEDESC:+-namedesc} ${NAMEDESC:+"$NAMEDESC"} \
        -changenote "$CHANGENOTE" \
        || die "the update failed - see the tool output above"
    if [[ "down" == "$NAMEDESC" ]]; then
        cp -- "$STAGE/content.xml" "$REPO_ROOT/content.xml.steam"
        echo "steam name and description written to content.xml.steam"
    fi
fi

NEW_ID="$(extension_id "$STAGE/content.xml" | tr -cd '0-9')"
if [[ "publish" == "$COMMAND" ]]; then
    [[ -n "$NEW_ID" ]] || die "the tool did not write a Workshop id into $STAGE/content.xml - upload failed?"
    mkdir -p -- "$(dirname "$WORKSHOP_ID_FILE")"
    printf '%s\n' "$NEW_ID" >"$WORKSHOP_ID_FILE"
    echo
    echo "published as https://steamcommunity.com/sharedfiles/filedetails/?id=$NEW_ID"
    echo "the item is hidden until you open that page, accept the Steam Workshop Legal Agreement"
    echo "and set the visibility to public"
    echo
    echo "commit the new $WORKSHOP_ID_FILE - ./publish.sh update needs it"
fi
