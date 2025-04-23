#!/usr/bin/env bash

#
# Options:
#   --apisvr:       API server advertising address
#   --podnet:       Pod network address
#   --token-ttl:    Token TTL
#
CMDNAME=$0

#
# Checks necessary package installation
#
REQ_CMDLIST="jq"
NO_CMDLIST=""
for REQ_CMDNAME in ${REQ_CMDLIST}
do
    which ${REQ_CMDNAME} 1> /dev/null 2> /dev/null
    if [ $? -ne 0 ]
    then
        NO_CMDLIST="${NO_CMDLIST} ${REQ_CMD}"
    fi
done
if [ "x${NO_CMDLIST}" != "x" ]
then
    echo "Some necessary packages seems to be installed... [Not found commands: ${NO_CMDLIST}]"
    exit 1
fi
        
#
# Checks executing user to avoid by admin user execution
#
if [ `id -u` = "0" ]
then
    echo "Do not execute this script by super user"
    exit 1
fi

KUBE_UID=`id -u`
KUBE_GID=`id -g`

# デフォルト値の設定
API_SVRADDR=""
API_SVRPORT="6443"
POD_NETADDR="10.225.0.0/16"
TOKEN_TTL="87600h"
KUBEADM_INIT_LOG="/tmp/kubeadm.log"
KUBEADM_INIT_ERR="/tmp/kubeadm-error.log"

KUBE_USER_DIR="${HOME}/.kube"
KUBE_MSTSETTING_FILE="${KUBE_USER_DIR}/kube-token/kube-token.conf"


# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apisvr)
            API_SVRADDR="$2"
            shift 2
            ;;
        --apisvr-port)
            API_SVRPORT="$2"
            shift 2
            ;;
        --podnet)
            POD_NETADDR="$2"
            shift 2
            ;;
        --token-ttl)
            TOKEN_TTL="$2"
            shift 2
            ;;
        --store-token-file)
            KUBE_MSTSETTING_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unrecognized argument is specified: $1"
            exit 1
            ;;
    esac
done

#
# Checks whether mandatory arguments is set or not
#
if [ "x${API_SVRADDR}" = "x" ]
then
    echo "No API server address is specified. You have to specify the API server address. Please retry with the setting"
    exit 1
fi

#
# Make sure to check /etc/hosts file in name service functionality
#
HOST_CONF_FILE="/etc/host.conf"
REQUIRED_RESOLVA_ORDER="order hosts,bind"
TEMP_HOST_CONF_FILE="/tmp/host.conf"
egrep -v order ${HOST_CONF_FILE} > ${TEMP_HOST_CONF_FILE}
echo ${REQUIRED_RESOLVA_ORDER} >> ${TEMP_HOST_CONF_FILE}
sudo mv ${HOST_CONF_FILE} ${HOST_CONF_FILE}.bak
sudo mv ${TEMP_HOST_CONF_FILE} ${HOST_CONF_FILE}
sudo chown root:root ${HOST_CONF_FILE}

#
# Launch Kubernetes service as a master node
#
KUBE_ADMIN_CONF="/etc/kubernetes/admin.conf"
KUBE_USER_CONF="${HOME}/.kube/config"
KUBE_USER_USRID=$(id -u)
KUBE_USER_GRPID=$(id -g)

ifconfig | grep ${API_SVRADDR} 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]
then
    sudo netplan apply
    if [ $? -ne 0 ]
    then
        echo "Cannot apply netplan"
        exit 1
    fi
fi

KUBE_MSTSETTING_FILE_DIR=`dirname ${KUBE_MSTSETTING_FILE}`
if [ ! -d ${KUBE_MSTSETTING_FILE_DIR} ]
then
    # No directory to store setting file --> create it
    mkdir -p ${KUBE_MSTSETTING_FILE_DIR} 1> /dev/null 2> /dev/null
fi
sudo chown -R ${KUBE_UID}:${KUBE_GID} ${KUBE_USER_DIR}

if [ -f ${KUBE_ADMIN_CONF} ]
then
    # Seems to have been already set up
    KUBE_TOKEN=`kubeadm token list | tail -1 | cut -d' ' -f1`
    if [ "x${KUBE_TOKEN}" = "x" ]
    then
        echo "Kuernetes environment seems to be in failure status"
        exit 1
    fi

    if [ -f ${KUBE_MSTSETTING_FILE} ]
    then
        STORED_KUBE_TOKEN=`cat ${KUBE_MSTSETTING_FILE} | jq -r .token`
        if [ "x${KUBE_TOKEN}" = "x${STORED_KUBE_TOKEN}" ]
        then
            # Previous setting is still alive
            echo "Previous settings is still alive"
            exit 0
        fi
    fi
    # This is a case to be token unmatch between previous setting and current environment
    # It is necessary to keep following procedures
else
    sudo kubeadm init \
        --apiserver-advertise-address=${API_SVRADDR} \
        --apiserver-bind-port=${API_SVRPORT} \
        --pod-network-cidr=${POD_NETADDR} \
        --token-ttl ${TOKEN_TTL} 1> ${KUBEADM_INIT_LOG} 2> ${KUBEADM_INIT_ERR}
    if [ $? -ne 0 ]
    then
        echo "Failed to initialize kubernetes environment of master node"
        exit 1
    fi
    KUBE_TOKEN=`grep "Using token" ${KUBEADM_INIT_LOG} | cut -d: -f2 | sed -e "s/ //g"`

    # copy kubernetes configuration file
    sudo cp ${KUBE_ADMIN_CONF} ${KUBE_USER_CONF}
    sudo chown ${KUBE_USER_USRID}:${KUBE_USER_GRPID} ${KUBE_USER_CONF}
fi

CACERT_HASH=`openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
        openssl rsa -pubin -outform der 2>/dev/null | \
        openssl dgst -sha256 -hex | \
        cut -d" " -f2`

#
# Stores initialized system parameter settings onto ${KUBE_MSTSETTING_FILE}
#

if [ -f "${KUBE_MSTSETTING_FILE}" ]
then
    # Backup old kubernetes token file, at least 5 generation
    for GEN_INDEX in 3 2 1 0
    do
        if [ -f "${KUBE_MSTSETTING_FILE}.${GEN_INDEX}" ]
        then
            let PREV_GEN_INDEX=GEN_INDEX+1
            mv ${KUBE_MSTSETTING_FILE}.${GEN_INDEX} ${KUBE_MSTSETTING_FILE}.${PREV_GEN_INDEX}
        fi
    done

    mv ${KUBE_MSTSETTING_FILE} ${KUBE_MSTSETTING_FILE}.0
fi

echo "{
    \"apisvr\": {
        \"address\": \"${API_SVRADDR}\",
        \"port\": \"${API_SVRPORT}\"
    },
    \"podnet\": \"${POD_NETADDR}\",
    \"token_ttl\": \"${TOKEN_TTL}\",
    \"token\": \"${KUBE_TOKEN}\",
    \"cacert_hash\": \"${CACERT_HASH}\"
}" > ${KUBE_MSTSETTING_FILE}

#
# Copy $HOME/.kube/config from /etc/kubernetes/admin.conf
#
KUBE_USER_DIR="${HOME}/.kube"
if [ ! -d ${KUBE_USER_DIR} ]
then
    mkdir -p ${KUBE_USER_DIR} 1> /dev/null
    if [ $? -ne 0 ]
    then
        echo "Failed to create ${KUBE_USER_DIR} directory"
        exit 1
    fi
    sudo chown ${KUBE_UID}:${KUBE_GID} ${KUBE_USER_DIR}
fi

KUBE_ADMIN_CONF="/etc/kubernetes/admin.conf"
KUBE_CONFIG_FILE="${KUBE_USER_DIR}/config"
if [ -f ${KUBE_CONFIG_FILE} ]
then
    mv ${KUBE_CONFIG_FILE} ${KUBE_CONFIG_FILE}.bak
fi
sudo cp ${KUBE_ADMIN_CONF} ${KUBE_CONFIG_FILE}
sudo chown ${KUBE_UID}:${KUBE_GID} ${KUBE_CONFIG_FILE}

echo "Succeeded"

exit 0

