#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"

if [ -z "${1}" ]
then
  echo "Usage: ${SCRIPT_NAME} <access-key-id ...>"
  exit 1
fi

for access_key_id in "${@}"
do
    for aws_profile in `aws configure list-profiles | grep -v secrets`
    do
        username="$("${SCRIPT_DIR}/get-iam-user-from-access-key.sh" --aws-profile "${aws_profile}" "${access_key_id}" 2> /dev/null)"
        if [ -n "${username}" ]
        then
            echo "Found username '${username}' for access key '${access_key_id}' in account associated with AWS profile '${aws_profile}'"
            break
        fi
    done

    if [ -z "${username}" ]
    then
        echo "No username found for access key '${access_key_id}'"
    fi
done
