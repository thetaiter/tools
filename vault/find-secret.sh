#!/bin/bash
# Recursively search for a value in all kv secrets in Vault

SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
AWS_SCRIPTS_DIR="$(dirname "${SCRIPT_DIR}")/aws"

unset SECRET_PATH
unset SECRET_PATTERNS
unset PARALLEL_JOBS
unset GET_USER_FROM_ACCESS_KEY

declare -a SECRET_PATTERNS
export PARALLEL_JOBS=2

usage() {
    local error_msg="${1}"

    if ! [ -z "${error_msg}" ]
    then
        echo "Error: ${error_msg}" >&2
        echo
    fi

    echo "Usage: ${SCRIPT_NAME} [options] <secret-path> <secret-pattern ...>"
    echo
    echo "Options:"
    echo "  -g|--get-user-from-access-key    Assume the secrets are AWS access keys and try to get"
    echo "                                      the username of the user associated with it them"
    echo "  -h|--help, help                  Print this help message"
    echo "  -j|--parallel-jobs <jobs>        Number of parallel jobs to run"
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
    while [ "${#}" -gt 0 ]
    do
        OPTION="${1}"
        VALUE="${2}"

        case "${OPTION}" in
            -g|--get-user-from-access-key)
                GET_USER_FROM_ACCESS_KEY=true
            ;;
            -h|--help|help)
                usage
            ;;
            -j|--parallel-jobs)
                export PARALLEL_JOBS="${VALUE}"
                shift
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
                    SECRET_PATTERNS+=( "${OPTION}" )
                else
                    usage "Unknown option '${OPTION}'"
                fi
            ;;
        esac

        shift
    done

    if [ -z "${SECRET_PATH}" ]
    then
        usage "No secret path was provided"
    elif [ -z "${SECRET_PATTERNS[*]}" ]
    then
        usage "No secret patterns were provided"
    fi

    SECRET_PATTERNS=( $(tr ' ' '\n' <<< "${SECRET_PATTERNS[@]}" | sort -u | tr '\n' ' ') )
}

check_secret() {
    local path="${1}"
    local value="${2}"

    if [[ "${path}" != */ ]]
    then
        local secret_value="$(vault kv get -format=json "${path}" | jq -r '.data.data')"

        if [[ "${secret_value}" == *"${value}"* ]]
        then
            echo "Found in secret at path ${path}"
        fi
    else
        find_secret "${path%/}" "${value}"
    fi
}
export -f check_secret

find_secret() {
    local path="${1}"
    local value="${2}"
    local secrets="$(vault kv list -format=json "${path}" | jq -r '.[]')"

    if ! [ -z "${secrets[*]}" ]
    then
        parallel -j "${PARALLEL_JOBS}" "check_secret '${path}/{}' '${value}'" ::: ${secrets}
    fi
}
export -f find_secret

main() {
    parse_args "${@}"

    if [ "${GET_USER_FROM_ACCESS_KEY}" = true ]
    then
        echo "Assuming secret are AWS keys, getting usernames associated with them"
        "${AWS_SCRIPTS_DIR}/check-profiles-for-access-keys.sh" "${SECRET_PATTERNS[@]}"
    fi

    for pattern in "${SECRET_PATTERNS[@]}"
    do
        if [ "${#SECRET_PATTERNS[@]}" -gt 1 ]
        then
            echo "Searching for pattern '${pattern}' in secret values in path '${SECRET_PATH}'..."
        fi

        find_secret "${SECRET_PATH}" "${pattern}" | sort -u
    done
}

ctrl_c() {
    echo "Caught Ctrl+C, exiting..."
    exit 1
}

trap ctrl_c INT

main "${@}"
