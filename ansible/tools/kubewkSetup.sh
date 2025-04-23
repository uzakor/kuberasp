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

# デフォルト値の設定
API_SVRADDR=""
API_SVRPORT="6443"
KUBEMST_TOKEN=""
KUBEMST_CACERT_HASH=""

KUBEADM_INIT_LOG="/tmp/kubeadm.log"
KUBEADM_INIT_ERR="/tmp/kubeadm-error.log"

KUBEMST_CONFIG_FILE="${HOME}/.kube/kube-token/kube-token.conf"


# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubemst-conf)
            KUBEMST_CONFIG_FILE="$2"
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
if [ "x${KUBEMST_CONFIG_FILE}" = "x" ]
then
    echo "No mandatory argument is specified. You have to specify the API server address. Please retry with the setting"
    echo "You have to specify --kubemst-conf arguments"
    exit 1
fi

#
# Re-configure netplan to make sure applying fixed IP address
#
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

#
# Read master node parameters
#
if [ ! -f ${KUBEMST_CONFIG_FILE} ]
then
    echo "No Kubernetes Master node settings file is found [${KUBEMST_CONFIG_FILE}]"
    exit 1
fi
API_SVRADDR=`jq -r .apisvr.address ${KUBEMST_CONFIG_FILE}`
API_SVRPORT=`jq -r .apisvr.port ${KUBEMST_CONFIG_FILE}`
KUBEMST_TOKEN=`jq -r .token ${KUBEMST_CONFIG_FILE}`
KUBEMST_CACERT_HASH=`jq -r .cacert_hash ${KUBEMST_CONFIG_FILE}`

if [ "x${API_SVRADDR}" = "x" ] || [ "x${API_SVRPORT}" = "x" ] || [ "x${KUBEMST_TOKEN}" = "x" ] || [ "x${KUBEMST_CACERT_HASH}" = "x" ]
then
    echo "No mandatory parameter is specified in ${KUBEMST_CONFIG_FILE}. Migth be failed during kubeadm init procedure."
    echo "   API_SVRADDR          : ${API_SVRADDR}"
    echo "   API_SVRPORT          : ${API_SVRPORT}"
    echo "   KUBEMST_TOKEN        : ${KUBEMST_TOKEN}"
    echo "   KUBEMST_CACERT_HASH  : ${KUBEMST_CACERT_HASH}"

    exit 1
fi

#
# Edits containerd configuration, changes "/run/XXX" to "/var/run/XXX"
#
CONTAINERD_CONFIG="/etc/containerd/config.toml"
CONTAINERD_CONFIG_NEWFILE="/tmp/containerd_config.toml"
CONTAINERD_CONFIG_BKUP="${CONTAINERD_CONFIG}.bak"
if [ ! -f ${CONTAINERD_CONFIG_BKUP} ]
then
    # Not yet editted containerd configuration file
    sudo mv ${CONTAINERD_CONFIG} ${CONTAINERD_CONFIG_BKUP} 1> /dev/null 2> /dev/null
    cat ${CONTAINERD_CONFIG_BKUP} | sed -e 's/\"\/run/\"\/var\/run/g' > ${CONTAINERD_CONFIG_NEWFILE}
    sudo mv ${CONTAINERD_CONFIG_NEWFILE} ${CONTAINERD_CONFIG}
    sudo systemctl restart containerd
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
# Launch Kubernetes service as a worker node
#
KUBE_ADMIN_CONF="/etc/kubernetes/admin.conf"
KUBE_USER_CONF="${HOME}/.kube/config"
KUBE_USER_USRID=$(id -u)
KUBE_USER_GRPID=$(id -g)

#
# Checks whether this node has been already set up as a Worker Node or not
#
if [ -f "/etc/kubernetes/kubelet.conf" ]
then
    echo "Already set up as a worker node. skip this process."
    echo "If you want to reinitialize this node, then execute kubeReset.sh script before this"
    exit 0
fi

sudo kubeadm join --token ${KUBEMST_TOKEN} \
    ${API_SVRADDR}:${API_SVRPORT} \
    --discovery-token-ca-cert-hash sha256:${KUBEMST_CACERT_HASH} \
    1> ${KUBEADM_INIT_LOG} 2> ${KUBEADM_INIT_ERR}

if [ $? -ne 0 ]
then
    echo "Failed to kubeadm join command. See ${KUBEADM_INIT_ERR} file"
    exit 1
fi

echo "Succeeded"

exit 0

