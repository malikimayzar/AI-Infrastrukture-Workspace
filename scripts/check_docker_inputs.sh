#!/usr/bin/env bash
# Fail when a Dockerfile depends on build inputs that a clean clone cannot
# provide: files missing from the build context, files that are not tracked in
# git, or the gitignored `hf-cache/` directory.
#
# Usage:
#   scripts/check_docker_inputs.sh                  # scan the project Dockerfiles
#   scripts/check_docker_inputs.sh path/to/Dockerfile [...]
#
# Sources using `--from=<stage>` are skipped because they resolve inside the
# build. The whole-context source `.` is allowed by definition.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if (( $# > 0 )); then
    dockerfiles=("$@")
else
    dockerfiles=(
        "rag-research/Dockerfile"
        "arxiv-research-assistant/python-ml/Dockerfile"
    )
fi

status=0
problem() {
    printf 'check_docker_inputs: FAIL: %s\n' "$*" >&2
    status=1
}

check_source() {
    local dockerfile=$1
    local context=$2
    local source=$3
    local rel=${source#./}

    [[ $rel == */ ]] && rel=${rel%/}

    if [[ ! -e "$context/$rel" ]]; then
        problem "$dockerfile: source '$source' does not exist in build context '$context'"
        return
    fi

    if ! git -C "$context" rev-parse --show-toplevel >/dev/null 2>&1; then
        problem "$dockerfile: build context '$context' is not a git repository; cannot verify '$source' is tracked"
        return
    fi

    if [[ -d "$context/$rel" ]]; then
        if [[ -z "$(git -C "$context" ls-files -- "$rel" 2>/dev/null)" ]]; then
            problem "$dockerfile: source directory '$source' has no tracked files in git"
        fi
    elif ! git -C "$context" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        problem "$dockerfile: source file '$source' is not tracked in git"
    fi
}

process_instruction() {
    local dockerfile=$1
    local context=$2
    local raw=$3
    local line=${raw#"${raw%%[![:space:]]*}"}

    [[ -z $line ]] && return
    [[ $line == \#* ]] && return

    local keyword=${line%%[[:space:]]*}
    keyword=${keyword^^}
    if [[ $keyword != COPY && $keyword != ADD ]]; then
        return
    fi

    local rest=${line:${#keyword}}
    rest=${rest#"${rest%%[![:space:]]*}"}

    local -a fields=()
    if [[ $rest == \[* ]]; then
        # JSON array form: COPY ["src", "dest"]
        local json=${rest%%\]*}
        json=${json#\[}
        local IFS=,
        local item
        for item in $json; do
            item=${item#"${item%%[![:space:]]*}"}
            item=${item%"${item##*[![:space:]]}"}
            item=${item#\"}
            item=${item%\"}
            fields+=("$item")
        done
    else
        read -r -a fields <<< "$rest"
    fi

    local from_stage=0
    local skip_next=0
    local -a positional=()
    local field
    for field in "${fields[@]}"; do
        if (( skip_next )); then
            skip_next=0
            continue
        fi
        case $field in
            --from=*) from_stage=1 ;;
            --from) from_stage=1; skip_next=1 ;;
            --) ;;
            --*) ;;
            *) positional+=("$field") ;;
        esac
    done

    if (( ${#positional[@]} < 2 )); then
        problem "$dockerfile: cannot parse COPY/ADD instruction: $raw"
        return
    fi

    local i source
    for ((i = 0; i < ${#positional[@]} - 1; i++)); do
        source=${positional[i]}

        if [[ $source == *hf-cache* ]]; then
            problem "$dockerfile: source '$source' references the gitignored hf-cache directory"
            continue
        fi

        if (( from_stage )); then
            continue
        fi

        if [[ $source == "." || $source == "./" ]]; then
            continue
        fi

        check_source "$dockerfile" "$context" "$source"
    done
}

process_dockerfile() {
    local dockerfile=$1

    if [[ ! -f $dockerfile ]]; then
        problem "Dockerfile not found: $dockerfile"
        return
    fi

    local context
    context=$(cd "$(dirname "$dockerfile")" && pwd)

    local buffer=""
    local line
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ \\[[:space:]]*$ ]]; then
            line=${line%\\*}
            buffer+="$line "
            continue
        fi

        buffer+="$line"
        process_instruction "$dockerfile" "$context" "$buffer"
        buffer=""
    done < "$dockerfile"

    if [[ -n $buffer ]]; then
        process_instruction "$dockerfile" "$context" "$buffer"
    fi
}

for dockerfile in "${dockerfiles[@]}"; do
    process_dockerfile "$dockerfile"
done

if (( status != 0 )); then
    printf 'check_docker_inputs: checked %d Dockerfile(s); problems found\n' "${#dockerfiles[@]}" >&2
    exit 1
fi

printf 'check_docker_inputs: OK (%d Dockerfile(s))\n' "${#dockerfiles[@]}"
