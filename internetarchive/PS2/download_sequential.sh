#!/bin/bash

SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

unset IDENTIFIERS_FILE
unset INCLUDE_BLOB
unset EXCLUDE_BLOB
unset WAIT

IDENTIFIERS_FILE_DEFAULT='./identifiers.txt'
INCLUDE_BLOB_DEFAULT='*'
EXCLUDE_BLOB_DEFAULT=''
WAIT_DEFAULT=false

usage() {
    local error_msg="${1}"

    if ! [ -z "${error_msg}" ]
    then
        echo "Error: ${error_msg}" >&2
        echo
    fi

    echo "Usage: ${SCRIPT_NAME} [options] <identifiers-file>"
    echo
    echo "Options:"
    echo "  -i|--include        Blob pattern for files to include in the download (Default = '${INCLUDE_BLOB_DEFAULT}')"
    echo "  -e|--exclude        Blob pattern for files to exclude from the download (Default = '${EXCLUDE_BLOB_DEFAULT}')"
    echo "  -h|--help|help      Print this help message"
    echo "  -w|--wait           Wait for user input after downloading all matching files from each identifier (Default = ${WAIT_DEFAULT})"
    echo
    echo "Arguments:"
    echo "  <identifiers-file>  Path to a file containing a list of identifiers to download from"
    echo "                      Default: ${IDENTIFIERS_FILE_DEFAULT}"

    if ! [ -z "${error_msg}" ]
    then
        exit 1
    else
        exit
    fi
}

function urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

while [ "${#}" -gt 0 ]
do
    OPTION="${1}"
    VALUE="${2}"

    case "${OPTION}" in
        -i|--include)
            INCLUDE_BLOB="${VALUE}"
            shift
        ;;
        -e|--exclude)
            EXCLUDE_BLOB="${VALUE}"
            shift
        ;;
        -h|--help|help)
            usage
        ;;
        -w|--wait)
            WAIT=true
        ;;
        -*)
            usage "Unknown option '${OPTION}'"
        ;;
        *)
            if [ -z "${IDENTIFIERS_FILE}" ]
            then
                IDENTIFIERS_FILE="${OPTION}"
            else
                usage "Unknown argument '${OPTION}'"
            fi
        ;;
    esac

    shift
done

if [ -z "${IDENTIFIERS_FILE}" ]
then
    IDENTIFIERS_FILE="${IDENTIFIERS_FILE_DEFAULT}"
fi

if [ -z "${INCLUDE_BLOB}" ]
then
    INCLUDE_BLOB="${INCLUDE_BLOB_DEFAULT}"
fi

if [ -z "${EXCLUDE_BLOB}" ]
then
    EXCLUDE_BLOB="${EXCLUDE_BLOB_DEFAULT}"
fi

if [ -z "${WAIT}" ]
then
    WAIT="${WAIT_DEFAULT}"
fi

if ! [ -f "${IDENTIFIERS_FILE}" ]
then
    echo "Error: Identifiers file '${IDENTIFIERS_FILE}' does not exist." >&2
    exit 2
fi

declare -a IDENTIFIER_LIST=( $(cat "${IDENTIFIERS_FILE}") )

for identifier in "${IDENTIFIER_LIST[@]}"
do
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

    if [ "${WAIT}" == true ]
    then
        read -p " Press enter to continue..."
    else
        echo
    fi
done

