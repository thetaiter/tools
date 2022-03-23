#!/bin/bash -e

DESCRIPTION="Get all resources in the given context(s) and namespace(s)"

unset CONTEXTS
unset NAMESPACES
unset RESOURCE_FILTER
unset CONTEXT_FILTER_SET
unset EXCLUDE_RESOURCE_PATTERN

YES=false
PID="${$}"
JOBS="$(sysctl -n hw.ncpu)"
RESOURCE_TYPE='pod'
declare -a NAMESPACES
DELETE_RESOURCES=false
CONTEXT_FILTER_SET=false
CONTEXT_FILTER='gke|eks'
EXCLUDE_CONTEXT_PATTERN='-sec-'
SCRIPT_NAME="$(basename "$(test -L "${0}" && readlink "${0}" || echo "${0}")")"

usage() {
    local error_msg="${1}"

    if [ -z "${error_msg}" ]
    then
        printf "${DESCRIPTION}\n\n"
    fi

    if ! [ -z "${error_msg}" ]
    then
        printf "Error: ${error_msg}\n" >&2
    fi

    printf "Usage: ${SCRIPT_NAME} [options] <namespace1> [namespace2 ...]\n\n"
    printf "Options:\n"
    printf "    -c|--contexts <contexts>          Comma separated list of contexts to query\n"
    printf "    -D|--delete                       Delete all of the resources that are found\n"
    printf "    -e|--exclude-resources <pattern>  Resources matching this pattern will be excluded\n"
    printf "    -E|--exclude-contexts <pattern>   Contexts matching this pattern will be excluded from query (default is '${EXCLUDE_CONTEXT_PATTERN}')\n"
    printf "    -f|--resource-filter <pattern>    Only resources matching this pattern will be included\n"
    printf "    -F|--context-filter <pattern>     Only contexts matching this pattern will be queried (default is '${CONTEXT_FILTER}')\n"
    printf "    -h|--help|help                    Print this usage information\n"
    printf "    -j|--jobs <num>                   Number of jobs to run in parallel (default is ${JOBS})\n"
    printf "    -r|--resource-type <resource>     Kubernetes resources type to get (default is '${RESOURCE_TYPE}')\n"
    printf "    -y|--yes                          Answer yes to all prompts (USE WITH CAUTION, THIS COULD BE DESTRUCTIVE)\n\n"

    if [ -z "${error_msg}" ]
    then
        exit
    else
        exit 1
    fi
}

cleanup() {
    rm -f /tmp/get_namespaces_*_${PID}.out /tmp/*get_resources_*${PID}.out
}

trap cleanup INT

while [ "${#}" -gt 0 ]
do
    OPTION="${1}"
    VALUE="${2}"

    case "${OPTION}" in
        -c|--contexts)
            CONTEXTS="${VALUE}"
            shift
        ;;
        -D|--delete)
            DELETE_RESOURCES=true
        ;;
        -e|--exclude-resources)
            EXCLUDE_RESOURCE_PATTERN="${VALUE}"
            shift
        ;;
        -E|--exclude_contexts)
            EXCLUDE_CONTEXT_PATTERN="${VALUE}"
            CONTEXT_FILTER_SET=true
            shift
        ;;
        -f|--resource-filter)
            RESOURCE_FILTER="${VALUE}"
            shift
        ;;
        -F|--context-filter)
            CONTEXT_FILTER="${VALUE}"
            CONTEXT_FILTER_SET=true
            shift
        ;;
        -h|--help|help)
            usage
        ;;
        -j|--jobs)
            JOBS="${VALUE}"
            shift
        ;;
        -r|--resource-type)
            RESOURCE_TYPE="${VALUE}"
            shift
        ;;
        -y|--yes)
            YES=true
        ;;
        -*)
            usage "Unknown option '${1}'"
        ;;
        *)
            NAMESPACES+=( "${OPTION}" )
        ;;
    esac

    shift
done

if [ -z "${NAMESPACES[*]}" ]
then
    usage "No namespace was provided"
fi

if [ -z "${CONTEXTS}" ]
then
    CONTEXTS=( $(kubectl config get-contexts | sed 's/*//' | grep -E -- "${CONTEXT_FILTER}" | grep -Ev -- "${EXCLUDE_CONTEXT_PATTERN}" | awk '{print $1}') )
elif [ "${CONTEXT_FILTER_SET}" = true ]
then
    usage "It does not make sense to use -c with -e or -f"
else
    IFS=',' read -r -a CONTEXTS <<< "${CONTEXTS}"
fi

get_namespaces() {
    local c="${1}"
    local log="/tmp/get_namespaces_${c}_${PID}.out"
    kubectl --context "${c}" get namespaces 2>&1 | tail -n +2 2>&1 | awk -v context="${c}" '{print context":"$1}' > "${log}" 2>&1
}

export PID
export -f get_namespaces
parallel -j "${JOBS}" "get_namespaces '{}'" ::: "${CONTEXTS[@]}"

get_resources() {
    local c="${1}"
    local n="${2}"
    local log="/tmp/get_resources_${c}_${n}_${PID}.out"

    if cat /tmp/get_namespaces_*_${PID}.out | grep "${c}:${n}" > /dev/null 2>&1
    then
        kubectl --context "${c}" --namespace "${n}" get "${RESOURCE_TYPE}" 2>&1 | grep -v "No resources" 2>&1 | sed "s/^/${c} ${n} /g" > "${log}" 2>&1
    fi
}

export RESOURCE_TYPE
export -f get_resources
parallel -j "${JOBS}" --plus "get_resources '{1}' '{2}'" ::: "${CONTEXTS[@]}" ::: "${NAMESPACES[@]}"

files=( /tmp/get_resources_*_${PID}.out )
printf "CONTEXT NAMESPACE $(head -1 "${files[0]}" | cut -d' ' -f3-)\n" > "/tmp/get_resources_1_${PID}.out"

sed -i.bak '1d' "${files[@]}"
rm -f /tmp/get_resources_*_${PID}.out.bak

if ! [ -z "${RESOURCE_FILTER}" ]
then
    if ! [ -z "${EXCLUDE_RESOURCE_PATTERN}" ]
    then
        column -t -s' ' /tmp/get_resources_*_${PID}.out | grep -E -- "CONTEXT|${RESOURCE_FILTER}" | grep -Ev -- "${EXCLUDE_RESOURCE_PATTERN}" > "/tmp/final_get_resources_${PID}.out"
    else
        column -t -s' ' /tmp/get_resources_*_${PID}.out | grep -E -- "CONTEXT|${RESOURCE_FILTER}" > "/tmp/final_get_resources_${PID}.out"
    fi
elif ! [ -z "${EXCLUDE_RESOURCE_PATTERN}" ]
then
    column -t -s' ' /tmp/get_resources_*_${PID}.out | grep -Ev -- "${EXCLUDE_RESOURCE_PATTERN}" > "/tmp/final_get_resources_${PID}.out"
else
    column -t -s' ' /tmp/get_resources_*_${PID}.out > "/tmp/final_get_resources_${PID}.out"
fi

if [[ "$(wc -l < "/tmp/final_get_resources_${PID}.out")" -le 1 ]]
then
    echo "No resources found."
    cleanup
    exit
fi

cat "/tmp/final_get_resources_${PID}.out"

delete_resource() {
    local resourcecontext="${1}"
    local context="${resourcecontext%%:*}"
    local resource="${resourcecontext##*:}"
    local namespace="${resourcecontext#*:}"
    local namespace="${namespace%:*}"
    kubectl --context "${context}" --namespace "${namespace}" delete "${RESOURCE_TYPE}" "${resource}"
}

if [ "${DELETE_RESOURCES}" = true ]
then
    unset ANSWER

    if [ "${YES}" = false ]
    then
        printf "\nWARNING: You are about to delete all of the above resources.\n"
        read -p "Are you sure you want to proceed? (yes/no) [no]: " ANSWER
        ANSWER="$(echo "${ANSWER}" | tr '[:upper:]' '[:lower:]')"
    else
        printf -- "\nSkipping prompts due to -y|--yes option"
        ANSWER='yes'
    fi

    if [ "${ANSWER}" == 'yes' ]
    then
        printf "\nDeleting resources...\n"
        unset RESOURCES
        RESOURCES=( $(cat "/tmp/final_get_resources_${PID}.out" | grep -v 'CONTEXT' | awk '{print $1":"$2":"$3}') )

        export RESOURCE_TYPE
        export -f delete_resource
        parallel -j "${JOBS}" "delete_resource '{}'" ::: "${RESOURCES[@]}"
    else
        printf "Aborting.\n"
        exit 1
    fi
fi

cleanup
