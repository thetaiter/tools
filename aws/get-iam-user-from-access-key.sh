#!/bin/bash -e

SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"
AWS_PROFILE="${AWS_PROFILE:-default}"

usage() {
    local error_msg="${1}"

    if ! [ -z "${error_msg}" ]
    then
        echo "${error_msg}" >&2
        echo
    fi

    echo "Usage: ${SCRIPT_NAME} [--aws-profile <aws-profile>] <access-key-id>"

    if ! [ -z "${error_msg}" ]
    then
        exit 1
    else
        exit
    fi
}

while [ "${#}" -gt 0 ]
do
    OPTION="${1}"
    VALUE="${2}"

    case "${OPTION}" in
        -h|--help|help)
            usage
        ;;
        -p|--aws-profile)
            export AWS_PROFILE="${VALUE}"
            shift
        ;;
        *)
            if [ -z "${ACCESS_KEY_ID}" ]
            then
                ACCESS_KEY_ID="${OPTION}"
            else
                usage "Unknown option '${OPTION}'"
            fi
        ;;
    esac

    shift
done

if [ -z "${ACCESS_KEY_ID}" ]
then
    usage "No access key ID was provided"
fi

aws-vault exec "${AWS_PROFILE}" --no-session -- aws iam get-access-key-last-used --access-key-id "${ACCESS_KEY_ID}" --output json | jq -j .UserName
