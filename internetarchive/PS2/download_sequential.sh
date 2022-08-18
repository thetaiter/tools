#!/bin/bash

declare -a IDENTIFIER_LIST=( $(cat "${1:-./identifiers.txt}") )
INCLUDE_BLOB='*USA*.zip|*En,*.zip'

function urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

for identifier in "${IDENTIFIER_LIST[@]}"
do
    # Generate ewxclude blob
    EXCLUDE_BLOB='* Demo *|*(Proto)*|*Demo Disk*|*Demo 1*|*Demo 2*|*Bonus Demo*|*(Beta)*|*Demo Disc*|*Demo)*|*Beta 1*|*Beta 2*|*Beta 3*|*Dance Factory*|*Dynasty Warriors 2*|*Gran Turismo 4*|*Guitar Hero - Van Halen*|*Operation WinBack*|*Poinie'"'"'s Poin*'
    FILES=( $(ia download --search "identifier:${identifier}" --glob "${INCLUDE_BLOB}" --exclude "${EXCLUDE_BLOB}" --no-directories --dry-run) )

    oIFS="${IFS}"
    IFS=$'\n'
    PROPER_FILES=( $(
        for file in "${FILES[@]}"
        do
            urldecode "${file}"
        done | sort -u
    ) )

    USA_FILES=( $(
        for file in "${PROPER_FILES[@]}"
        do
            echo "${file}"
        done | grep '(USA)'
    ) )

    NON_USA_FILES=( $(
        for file in "${PROPER_FILES[@]}"
        do
            echo "${file}"
        done | grep -v '(USA)'
    ) )
    IFS="${oIFS}"

    for file in "${NON_USA_FILES[@]}"
    do
        FILE_NAME="$(echo "${file}" | cut -d\/ -f6)"
        GAME_NAME="$(echo "${FILE_NAME}" | cut -d\( -f1 | awk '{$1=$1};1')"
        if [[ " ${USA_FILES[@]} " =~ "/${GAME_NAME} (USA)" ]]
        then
            EXCLUDE_BLOB="${EXCLUDE_BLOB}|${FILE_NAME}"
        fi
    done

    for file in "${PROPER_FILES[@]}"
    do
        FILE_NAME="$(echo "${file}" | cut -d\/ -f6)"
        GAME_NAME="$(echo "${FILE_NAME}" | cut -d\( -f1 | awk '{$1=$1};1')"
        if [ -f "${FILE_NAME}" ] || [ -f "${FILE_NAME/.zip/.tar.gz}" ]
        then
            EXCLUDE_BLOB="${EXCLUDE_BLOB}|${FILE_NAME}"
        fi
    done

    echo "Downloading files from identifier ${identifier}"
    ia download --search "identifier:${identifier}" --glob "${INCLUDE_BLOB}" --exclude "${EXCLUDE_BLOB}" --no-directories
    printf -- "Finished downloading files from ${identifier}."
    if [ "${1}" == '-w' ]
    then
        read -p " Press enter to continue..."
    else
        echo
    fi
done
