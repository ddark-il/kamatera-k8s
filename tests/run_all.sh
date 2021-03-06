#!/usr/bin/env bash

test_cluster() {
    TEST_ENVIRONMENT_NAME="${1}"
    [ -z "${TEST_ENVIRONMENT_NAME}" ] && echo "missing ENVIRONMENT_NAME" && return 1
    [ -e environments/${TEST_ENVIRONMENT_NAME} ] && echo "environment already exists" && return 1
    ./kamatera.sh server list | grep "${TEST_ENVIRONMENT_NAME}-" && echo "existing servers with environment name prefix" && return 1

    echo
    echo "Creating environment ${TEST_ENVIRONMENT_NAME}"
    echo

    ! ./kamatera.sh cluster create ${TEST_ENVIRONMENT_NAME} \
        && echo "failed to create cluster" && return 1

    echo "sleeping 30 seconds..."
    sleep 30

    ! tests/test_elasticsearch.sh ${TEST_ENVIRONMENT_NAME} && echo failed elasticsearch test && return 1

    echo "Adding worker node to the cluster"
    ! ./kamatera.sh cluster node add ${TEST_ENVIRONMENT_NAME} "2B" "2048" "30" \
        && echo "Failed to add worker node" && return 1

    echo "sleeping 30 seconds..."

    ! ./kamatera.sh cluster shell "${TEST_ENVIRONMENT_NAME}" "
        NUM_NODES="'$'"(kubectl get nodes -o json --selector=kamateranode==true | jq -r '.items[].metadata.name' | wc -l) &&\
        [ "'"${NUM_NODES}" == "2"'" ]
    " && echo not enough worker nodes && return 1

    echo
    echo "Great Success!"
    echo
    return 0
}

terminate_cluster() {
    TEST_ENVIRONMENT_NAME="${1}"
    [ -z "${TEST_ENVIRONMENT_NAME}" ] && echo "missing ENVIRONMENT_NAME" && return 1
    echo "Terminating environment ${TEST_ENVIRONMENT_NAME}"
    MASTER=`./kamatera.sh server list | grep ${TEST_ENVIRONMENT_NAME}-master`
    NODE=`./kamatera.sh server list | grep ${TEST_ENVIRONMENT_NAME}-node`
    LB=`./kamatera.sh server list | grep ${TEST_ENVIRONMENT_NAME}-lb`
    [ "${MASTER}" != "" ] && ./kamatera.sh server terminate $(echo $MASTER | cut -d" " -f2 -) $(echo $MASTER | cut -d" " -f1 -) yes
    [ "${NODE}" != "" ] && ./kamatera.sh server terminate $(echo $NODE | cut -d" " -f2 -) $(echo $NODE | cut -d" " -f1 -) yes
    [ "${LB}" != "" ] && ./kamatera.sh server terminate $(echo $LB | cut -d" " -f2 -) $(echo $LB | cut -d" " -f1 -) yes
    rm -rf environments/${TEST_ENVIRONMENT_NAME}
    return 0
}

# set env vars on travis using:
# travis env set --private VAR_NAME VALUE
if
    ! [ -z "${DO_EMAIL}" ] &&\
    ! [ -z "${DO_DOMAIN}" ] &&\
    ! [ -z "${DO_AUTH_TOKEN}" ] &&\
    ! [ -z "${DO_DOMAIN_ROOT}" ] &&\
    ! [ -z "${DO_DOMAIN_RECORD_ID}" ] &&\
    ! [ -z "${MASTER_SERVER_PASSWORD}" ] &&\
    ! [ -z "${NODE_SERVER_PASSWORD}" ] &&\
    ! [ -z "${LB_SERVER_PASSWORD}" ];
then
    echo "environment verified"
else
    echo "missing reuqired env vars"
    exit 1
fi

RES=0
( [ "${1}" == "--terminate-first" ] || [ "${1}" == "--terminate-only" ] ) && terminate_cluster "kamateratest1"
if [ "${1}" != "--terminate-only" ]; then
    test_cluster "kamateratest1"
    RES=$?; echo "RES=$RES"
    [ "${1}" != "--terminate-first" ] && terminate_cluster "kamateratest1"
fi
exit $RES
