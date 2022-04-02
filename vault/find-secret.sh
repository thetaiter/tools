#!/bin/bash
# Recursively search for a value in all kv secrets in Vault

SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"

usage() {
    local error_msg="${1}"

    if ! [ -z "${error_msg}" ]
    then
        echo "${error_msg}" >&2
        echo
    fi

    echo "Usage: ${SCRIPT_NAME} <secret-path> <secret-pattern>"
    echo
    echo "<secret-path> is the base path in Vault to start searching in"
    echo "<secret-pattern> is the pattern to search for in secret values"

    if ! [ -z "${error_msg}" ]
    then
        exit 1
    else
        exit
    fi
}

parse_args() {
    unset SECRET_PATH
    unset SECRET_VOLUME

    while [ "${#}" -gt 0 ]
    do
        OPTION="${1}"
        VALUE="${2}"

        case "${OPTION}" in
            -h|--help|help)
                usage
            ;;
            -*)
                usage "Unknown option '${OPTION}'"
            ;;
            *)
                if [ -z "${SECRET_PATH}" ]
                then
                    SECRET_PATH="${OPTION}"
                elif [ -z "${SECRET_PATTERN}" ]
                then
                    SECRET_PATTERN="${OPTION}"
                else
                    usage "Unknown option '${OPTION}'"
                fi
            ;;
        esac

        shift
    done
}

check_secret() {
    local path="${1}"
    local value="${2}"

    if [[ "${path}" != */ ]]
    then
        local secret_value="$(vault kv get -format=json "${path}" 2> /dev/null | jq -r '.data.data')"

        if [[ "${secret_value}" == *"${value}"* ]]
        then
            echo "${path}"
        fi
    else
        find_secret "${path%/}" "${value}"
    fi
}
export -f check_secret

find_secret() {
    local path="${1}"
    local value="${2}"
    local secrets="$(vault kv list -format=json "${path}" 2> /dev/null | jq -r '.[]')"

    if ! [ -z "${secrets[*]}" ]
    then
        parallel "check_secret '${path}/{}' '${value}'" ::: ${secrets}
    fi
}
export -f find_secret

main() {
    parse_args "${@}"
    find_secret "${SECRET_PATH}" "${SECRET_PATTERN}" | sort -u
}

main "${@}"
