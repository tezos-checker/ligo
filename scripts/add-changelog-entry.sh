#!/usr/bin/env bash

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."

set -euo pipefail

THIS="$0 $@"

if command -v nix-shell > /dev/null && [[ -z "${IN_NIX_SHELL-}" ]]; then
    nix-shell -p envsubst --run "$THIS"
    exit $?
fi

usage() {
    echo "Usage: $0 '<TYPE>' <MERGE_REQUEST> '<AUTHOR>' <TITLE> ..."
    echo "where"
    echo "  TYPE is one of added, fixed, changed, deprecated, removed, performance, other"
    echo "  MERGE_REQUEST is a merge request ID like !123"
    echo "  AUTHOR is your name"
    echo "  TITLE is a concise one-line description of your changes. All arguments after that are added to title"
}

help() {
    echo "$0: Generate a new changelog entry"
    usage
}

if [[ $# -eq 0 ]] || [[  "$1" == "--help" ]]; then
    help
    exit 0
fi

if [[ $# -lt 4 ]]; then
    echo "Wrong number of arguments: expected 4 or more, got $#"
    usage
    exit 1
fi

case "$1" in
    added|fixed|changed|deprecated|removed|performance|other) TYPE="$1" ;;
    *) echo "Wrong TYPE"; usage; exit 1
esac
shift

MERGE_REQUEST="$1"
shift

AUTHOR="$1"
shift

TITLE="$@"

LAST="$(ls "$ROOT/changelog" | sort -n | tail -1)"

THIS=$(( LAST + 1 ))

export TYPE MERGE_REQUEST AUTHOR TITLE

envsubst -i "$ROOT/scripts/changelog-template.yaml" -o "$ROOT/changelog/$THIS"
