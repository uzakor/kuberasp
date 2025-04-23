#!/usr/bin/env bash

# Executing mode
#IS_ANSI_PB_DRY_RUN="true"

#
# Analyze executing directory
#
CMDNAME="$0"
CMDPATH=`dirname ${CMDNAME}`
if [ ${CMDPATH} = "." ]
then
    # No additional path info
    EXEC_ROOTDIR=`pwd`
else
    EXEC_ROOTDIR="`pwd`/${CMDPATH}"
fi

#
# Initializes some constant variables
#
ANSIPB_CONFIG_FILE="kube-ansible.conf"
ANSIPB_EXEC_PATHNAME="exec_tmp"
ANSIPB_PLAYBOOK_FILE="k8s-setup.yaml"

ANSIBLE_DEBUG_OPTION="-vv"

#
# Generate executing environment
#
EXEC_PATH="${EXEC_ROOTDIR}/${ANSIPB_EXEC_PATHNAME}"
LOCAL_TMP_PATH="${EXEC_ROOTDIR}/local_tmp"

ANSIPB_CONFIG="${EXEC_PATH}/${ANSIPB_CONFIG_FILE}"
ANSIPB_PLAYBOOK="${EXEC_ROOTDIR}/${ANSIPB_PLAYBOOK_FILE}"

FORCE_PKGDL="false"

#
# Analyzes specified arguments
#
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ansible-pb-config)
            ANSIPB_CONFIG="$2"
            shift 2
            ;;

        --ansible-pb-file)
            ANSIPB_PLAYBOOK="$2"
            shift 2
            ;;

        --force-download-packages)
            FORCE_PKGDL="true"
            shift 1
            ;;

        *)
            echo "Unknown argument is specified [$1]"
            exit 1
            ;;
    esac
done

#
# Subroutine to create directory
#
function createDirectory ( ) {
    GEN_DIRNAME=$1
    if [ ! -d ${GEN_DIRNAME} ]
    then
        mkdir -p ${GEN_DIRNAME} 1> /dev/null
        if [ $? -ne 0 ]
        then
            echo "Failed to create executing directory [${GEN_DIRNAME}]"
            exit 1
        fi
    fi
}

createDirectory ${EXEC_PATH}
createDirectory ${LOCAL_TMP_PATH}

#
# Generate Ansible Playbook with specified configuration
#
function genSedFile ( ) {
    SED_FILENAME="$1"
    JQ_PICK_MODE="$2"
    ANSIPB_CONFIG="$3"
    if [ -f ${SED_FILENAME} ]
    then
        mv ${SED_FILENAME} ${SED_FILENAME}.bak
    fi

    case "${JQ_PICK_MODE}" in
        "general")
            TOP_KEYNAME=".general_settings"
            CONV_KEYLIST=`jq -r '.general_settings | keys[]' ${ANSIPB_CONFIG}`
            ;;

        "master")
            TOP_KEYNAME=".master_node"
            CONV_KEYLIST=`jq -r '.master_node | keys[]' ${ANSIPB_CONFIG}`
            ;;

        "worker")
            WKNODE_INDEX="$4"
            TOP_KEYNAME=".worker_node[${WKNODE_INDEX}]"
            CONV_KEYLIST=`jq -r '.worker_node[0] | keys[]' ${ANSIPB_CONFIG}`
            ;;

        *)
            echo "Unknown jq picking up mode name [${JQ_PICK_MODE}]"
            exit 1
    esac

    for CONV_KEY in ${CONV_KEYLIST}
    do
        CONV_VALUE=`jq -r ${TOP_KEYNAME}.${CONV_KEY} ${ANSIPB_CONFIG}`
        echo "s/%%${CONV_KEY}%%/${CONV_VALUE}/g" >> ${SED_FILENAME}
    done
}

echo "Generate sed file for general settings"
# Backup inventory.ini file if existed
INVENTORY_FILENAME="${EXEC_PATH}/inventory.ini"
if [ -f ${INVENTORY_FILENAME} ]
then
    mv ${INVENTORY_FILENAME} ${INVENTORY_FILENAME}.bak
fi
EXEC_DATETIME=`date`
echo "# Generating date/time: ${EXEC_DATETIME}" > ${INVENTORY_FILENAME}

# Generate master node setting
MSTNODE_CONF_SED_FILENAME=${EXEC_PATH}/applyMstNodeConf.sed
MASTER_NODE_SETTING_TEMPLATE="%%hostname%% ansible_host=%%address%% ansible_ssh_private_key_file=~/.ssh/%%ssh_pkey_filename%% net_ip=%%fixed_ipv4_addr%% netmask=%%fixed_ipv4_netmasklen%%"

genSedFile ${MSTNODE_CONF_SED_FILENAME} master ${ANSIPB_CONFIG}

echo "[master]" >> ${INVENTORY_FILENAME}
echo "${MASTER_NODE_SETTING_TEMPLATE}" \
    | sed -f ${MSTNODE_CONF_SED_FILENAME} >> ${INVENTORY_FILENAME}
echo >> ${INVENTORY_FILENAME}

# Removes sed file
rm -f ${MSTNODE_CONF_SED_FILENAME}

# Generate worker node setting
WKNODE_CONF_SED_FILENAME=${EXEC_PATH}/applyWkrNodeConf.sed
WORKER_NODE_SETTING_TEMPLATE="%%hostname%% ansible_host=%%address%% ansible_ssh_private_key_file=~/.ssh/%%ssh_pkey_filename%% net_ip=%%fixed_ipv4_addr%% netmask=%%fixed_ipv4_netmasklen%%"

WORKER_NODE_INDEXES=`jq '.worker_node | keys[]' ${ANSIPB_CONFIG}`
echo "[workers]" >> ${INVENTORY_FILENAME}
for WORKER_NODE_INDEX in ${WORKER_NODE_INDEXES}
do
    genSedFile ${WKNODE_CONF_SED_FILENAME} worker ${ANSIPB_CONFIG} ${WORKER_NODE_INDEX}
    echo "${WORKER_NODE_SETTING_TEMPLATE}" \
        | sed -f ${WKNODE_CONF_SED_FILENAME} >> ${INVENTORY_FILENAME}

    # Removes sed file
    rm -f ${WKNODE_CONF_SED_FILENAME}
done
echo >> ${INVENTORY_FILENAME}

# Generate parameter setting
GENERAL_SETTING_CONF_SED_FILENAME="${EXEC_PATH}/applyGenVarConf.sed"
GENERAL_SETTING_TEMPLATE="[all:vars]
ansible_ssh_user=%%ssh_username%%
ansible_user=%%ansible_user%%
ansible_group=%%ansible_group%%
ansible_python_interpreter=/usr/bin/python3
kube_bashrc=/home/%%ansible_user%%/.bash_kubevars
kube_master_node_addr=%%master_server_addr%%
kube_master_server_port=%%master_server_port%%
gateway=%%default_gateway_addr%%
dns_server=%%dns_server_addr%%
store_directory=/usr/local/bin
store_config_directory=/tmp
kube_config=/home/%%ansible_user%%/.kube/kube-token/kube-token.conf
local_tmpdir=local_tmp
reset_kube_env=%%do_reset_kube_env%%
cni_name=%%cni_name%%
flannel_version=%%flannel_version%%
calico_version=%%calico_version%%
pv_mount_path=%%pv_mount_path%%
"

genSedFile ${GENERAL_SETTING_CONF_SED_FILENAME} general ${ANSIPB_CONFIG}
echo "${GENERAL_SETTING_TEMPLATE}" \
    | sed -f ${GENERAL_SETTING_CONF_SED_FILENAME} >> ${INVENTORY_FILENAME}

# Removes sed file
#rm -f ${GENERAL_SETTING_CONF_SED_FILENAME}

#
# Download extra packages in advanced
#
ARCH_NAME=`jq -r .extra_pkginfo.arch_name ${ANSIPB_CONFIG}`
OS_NAME=`jq -r .extra_pkginfo.os_name ${ANSIPB_CONFIG}`
HELM_VERSION=`jq -r .extra_pkginfo.helm_version ${ANSIPB_CONFIG}`
HELM_DLURL=`jq -r .extra_pkginfo.helm_dlurl ${ANSIPB_CONFIG}`
GOLANG_ARCHNAME=`jq -r .extra_pkginfo.golang_archname ${ANSIPB_CONFIG}`
GOLANG_VERSION=`jq -r .extra_pkginfo.golang_version ${ANSIPB_CONFIG}`
GOLANG_DLURL=`jq -r .extra_pkginfo.golang_dlurl ${ANSIPB_CONFIG}`
CONTAINERD_VERSION=`jq -r .extra_pkginfo.containerd_version ${ANSIPB_CONFIG}`
RUNC_VERSION=`jq -r .extra_pkginfo.runc_version ${ANSIPB_CONFIG}`
CNI_PLUGIN_VERSION=`jq -r .extra_pkginfo.cni_plugin_version ${ANSIPB_CONFIG}`
CONTAINERD_DLURL=`jq -r .extra_pkginfo.containerd_dlurl ${ANSIPB_CONFIG} `
RUNC_DLURL=`jq -r .extra_pkginfo.runc_dlurl ${ANSIPB_CONFIG}`
CNI_PLUGIN_DLURL=`jq -r .extra_pkginfo.cni_plugin_dlurl ${ANSIPB_CONFIG}`

# Generates SED data to convert Download URL
EXTRA_PKG_CONV_SEDFILE="${LOCAL_TMP_PATH}/extra_pkgconv.sed"
cat << EOD_PKGCONV_SED > ${EXTRA_PKG_CONV_SEDFILE}
s/%%arch_name%%/${ARCH_NAME}/g
s/%%os_name%%/${OS_NAME}/g
s/%%helm_version%%/${HELM_VERSION}/g
s/%%golang_archname%%/${GOLANG_ARCHNAME}/g
s/%%golang_version%%/${GOLANG_VERSION}/g
s/%%containerd_version%%/${CONTAINERD_VERSION}/g
s/%%runc_version%%/${RUNC_VERSION}/g
s/%%cni_plugin_version%%/${CNI_PLUGIN_VERSION}/g
EOD_PKGCONV_SED

# Adds extra package information onto inventory.ini file
EXTRA_PKGINFO_SETTING_TEMPLATE="arch_name=%%arch_name%%
os_name=%%os_name%%
helm_version=%%helm_version%%
golang_archname=%%golang_archname%%
golang_version=%%golang_version%%
containerd_version=%%containerd_version%%
runc_version=%%runc_version%%
cni_plugin_version=%%cni_plugin_version%%
"
echo "${EXTRA_PKGINFO_SETTING_TEMPLATE}" \
    | sed -f ${EXTRA_PKG_CONV_SEDFILE} >> ${INVENTORY_FILENAME}

# Do download necessary packages
HELM_PKGURL=`echo ${HELM_DLURL} | sed -f ${EXTRA_PKG_CONV_SEDFILE}`
HELM_PKGNAME="${LOCAL_TMP_PATH}/helm-${OS_NAME}-${ARCH_NAME}-${HELM_VERSION}.tgz"
if [ ${FORCE_PKGDL} = "true" ] || [ ! -f ${HELM_PKGNAME} ]
then
    echo "Download helm package file [${HELM_PKGNAME}]"
    wget -O "${HELM_PKGNAME}" "${HELM_PKGURL}"
    if [ $? -ne 0 ]
    then
        echo "Failed to download ${HELM_PKGNAME}"
        rm -f ${HELM_PKGNAME}
        exit 1
    fi
fi
echo "helm_pkgfile=${HELM_PKGNAME}" >> ${INVENTORY_FILENAME}

GOLANG_PKGURL=`echo ${GOLANG_DLURL} | sed -f ${EXTRA_PKG_CONV_SEDFILE}`
GOLANG_PKGNAME="${LOCAL_TMP_PATH}/golang-${OS_NAME}-${ARCH_NAME}-${GOLANG_VERSION}.tgz"
if [ ${FORCE_PKGDL} = "true" ] || [ ! -f ${GOLANG_PKGNAME} ]
then
    echo "Download containerd package file [${GOLANG_PKGNAME}]"
    wget -O "${GOLANG_PKGNAME}" "${GOLANG_PKGURL}"
    if [ $? -ne 0 ]
    then
        echo "Failed to download ${GOLANG_PKGNAME}"
        rm -f ${GOLANG_PKGNAME}
        exit 1
    fi
fi
echo "golang_pkgfile=${GOLANG_PKGNAME}" >> ${INVENTORY_FILENAME}

CONTAINERD_PKGURL=`echo ${CONTAINERD_DLURL} | sed -f ${EXTRA_PKG_CONV_SEDFILE}`
CONTAINERD_PKGNAME="${LOCAL_TMP_PATH}/containerd-${OS_NAME}-${ARCH_NAME}-${CONTAINERD_VERSION}.tgz"
if [ ${FORCE_PKGDL} = "true" ] || [ ! -f ${CONTAINERD_PKGNAME} ]
then
    echo "Download containerd package file [${CONTAINERD_PKGNAME}]"
    wget -O "${CONTAINERD_PKGNAME}" "${CONTAINERD_PKGURL}"
    if [ $? -ne 0 ]
    then
        echo "Failed to download ${CONTAINERD_PKGNAME}"
        rm -f ${CONTAINERD_PKGNAME}
        exit 1
    fi
fi
echo "containerd_pkgfile=${CONTAINERD_PKGNAME}" >> ${INVENTORY_FILENAME}

RUNC_PKGURL=`echo ${RUNC_DLURL} | sed -f ${EXTRA_PKG_CONV_SEDFILE}`
RUNC_PKGNAME="${LOCAL_TMP_PATH}/runc-${RUNC_VERSION}-${OS_NAME}-${ARCH_NAME}"
if [ ${FORCE_PKGDL} = "true" ] || [ ! -f ${RUNC_PKGNAME} ]
then
    echo "Download containerd package file [${RUNC_PKGNAME}]"
    wget -O "${RUNC_PKGNAME}" "${RUNC_PKGURL}"
    if [ $? -ne 0 ]
    then
        echo "Failed to download ${RUNC_PKGNAME}"
        rm -f ${RUNC_PKGNAME}
        exit 1
    fi
fi
echo "runc_pkgfile=${RUNC_PKGNAME}" >> ${INVENTORY_FILENAME}

CNI_PLUGIN_PKGURL=`echo ${CNI_PLUGIN_DLURL} | sed -f ${EXTRA_PKG_CONV_SEDFILE}`
CNI_PLUGIN_PKGNAME="${LOCAL_TMP_PATH}/cni-plugins-${OS_NAME}-${ARCH_NAME}-${CNI_PLUGIN_VERSION}.tgz"
if [ ${FORCE_PKGDL} = "true" ] || [ ! -f ${CNI_PLUGIN_PKGNAME} ]
then
    echo "Download containerd package file [${CNI_PLUGIN_PKGNAME}]"
    wget -O "${CNI_PLUGIN_PKGNAME}" "${CNI_PLUGIN_PKGURL}"
    if [ $? -ne 0 ]
    then
        echo "Failed to download ${CNI_PLUGIN_PKGNAME}"
        rm -f ${CNI_PLUGIN_PKGNAME}
        exit 1
    fi
fi
echo "cni_plugins_pkgfile=${CNI_PLUGIN_PKGNAME}" >> ${INVENTORY_FILENAME}

# Adds package storing directory on all kubernetes nodes
echo "kube_pkgdirname=.kube/extra_packages" >> ${INVENTORY_FILENAME}

#
# Executes applying Ansible Playbook
#
if [ "x${IS_ANSI_PB_DRY_RUN}" != "xtrue" ]
then
    echo "Start applying Ansible Playbook"
    ansible-playbook -i ${INVENTORY_FILENAME} ${ANSIPB_PLAYBOOK} ${ANSIBLE_DEBUG_OPTION}
    if [ $? -ne 0 ]
    then
        echo "Failed to construct kubernetes system"
        exit 1
    fi
    echo "Finished applying Ansible Playbook"
fi

#
# Generate "/etc/hosts" file
#
echo "Start applying '/etc/hosts' file with associating kubernetes nodes"

KUBE_HOST_COMMENT_BEGIN_MARK="#### Kubernetes hosts added ####"
KUBE_HOST_COMMENT_END_MARK="#### Kubernetes hosts added till here ####"

# Puts beginning marker
KUBE_HOST_LIST="${KUBE_HOST_COMMENT_BEGIN_MARK}\n"

KUBE_HOSTNAMES=""

# For master node
KUBE_HOST_NAME=`jq -r '.master_node.hostname' ${ANSIPB_CONFIG}`
KUBE_HOST_ADDR=`jq -r '.master_node.fixed_ipv4_addr' ${ANSIPB_CONFIG}`
KUBE_HOST_LIST+="# Master node\n${KUBE_HOST_ADDR} ${KUBE_HOST_NAME}\n"
KUBE_HOSTNAMES="${KUBE_HOST_NAME}"

KUBE_MASTER_NODE_NAME=${KUBE_HOST_NAME}     # Save master node name to use later process

# For worker node
WORKER_NODE_INDEXES=`jq '.worker_node | keys[]' ${ANSIPB_CONFIG}`
KUBE_HOST_LIST+="# Worker nodes\n"
for WORKER_NODE_INDEX in ${WORKER_NODE_INDEXES}
do
    KUBE_HOST_NAME=`jq -r ".worker_node[${WORKER_NODE_INDEX}].hostname" ${ANSIPB_CONFIG}`
    KUBE_HOST_ADDR=`jq -r ".worker_node[${WORKER_NODE_INDEX}].fixed_ipv4_addr" ${ANSIPB_CONFIG}`
    KUBE_HOST_LIST+="${KUBE_HOST_ADDR} ${KUBE_HOST_NAME}\n"
    KUBE_HOSTNAMES+=" ${KUBE_HOST_NAME}"
done

# For Storage node
KUBE_HOST_NAME=`jq -r '.nfssvr_node.hostname' ${ANSIPB_CONFIG}`
KUBE_HOST_ADDR=`jq -r '.nfssvr_node.fixed_ipv4_addr' ${ANSIPB_CONFIG}`
KUBE_HOST_LIST+="# Storage(NFS Server) node\n${KUBE_HOST_ADDR} ${KUBE_HOST_NAME}\n"
KUBE_HOSTNAMES+=" ${KUBE_HOST_NAME}"

# Puts end marker
KUBE_HOST_LIST+="\n${KUBE_HOST_COMMENT_END_MARK}"

#
# Adds kubernetes host addresses into "/etc/hosts" file on each node
#
function rmOldSetting ( ) {
    LOCAL_HOSTFILE=$1
    OUTPUT_HOSTFILE=$2
    shift 2
    KUBE_HOSTINFO_BEGIN_LINE=`grep -n "${KUBE_HOST_COMMENT_BEGIN_MARK}" ${LOCAL_HOSTFILE} | head -1 | cut -d: -f1`
    KUBE_HOSTINFO_END_LINE=`grep -n "${KUBE_HOST_COMMENT_END_MARK}" ${LOCAL_HOSTFILE} | tail -1 | cut -d: -f1`
    if [ "x${KUBE_HOSTINFO_BEGIN_LINE}" != "x" ] && [ "x${KUBE_HOSTINFO_END_LINE}" != "x" ]
    then
        # Removes blocks of kubernetes host information
        sed "${KUBE_HOSTINFO_BEGIN_LINE},${KUBE_HOSTINFO_END_LINE}d" ${LOCAL_HOSTFILE} > ${OUTPUT_HOSTFILE}
        cp ${OUTPUT_HOSTFILE} ${LOCAL_HOSTFILE}
    else
        echo "Seems to be editted by user. Gives up removing comment lines. Just removing host defnitions"
    fi
    for KUBE_HOST_NAME in "$@"
    do
        grep -v ${KUBE_HOST_NAME} ${LOCAL_HOSTFILE} > ${OUTPUT_HOSTFILE}
        cp ${OUTPUT_HOSTFILE} ${LOCAL_HOSTFILE}
    done
}
TEMP_HOSTFILE="${LOCAL_TMP_PATH}/hosts"
for KUBE_HOST in ${KUBE_HOSTNAMES}
do
    HOSTS_FILENAME=${TEMP_HOSTFILE}.${KUBE_HOST}
    scp ${KUBE_HOST}:/etc/hosts ${TEMP_HOSTFILE}
    if [ $? -ne 0 ]
    then
        echo "Failed to obtain hosts file from ${KUBE_HOST}"
        exit 1
    fi
    rm -f ${HOSTS_FILENAME} 1> /dev/null 2> /dev/null

    rmOldSetting ${TEMP_HOSTFILE} ${HOSTS_FILENAME} ${KUBE_HOSTNAMES}
    echo -e "127.0.0.1 ${KUBE_HOST}" >> ${HOSTS_FILENAME}
    echo -e ${KUBE_HOST_LIST} >> ${HOSTS_FILENAME}

    scp ${HOSTS_FILENAME} ${KUBE_HOST}:/tmp/hosts
    ssh ${KUBE_HOST} sudo mv /tmp/hosts /etc/hosts
done
echo "Finished applying '/etc/hosts' files to all kubernetes nodes"

echo "Start applying NFS provisioner to support PV on NFS environment"

NFS_PROVISIONER_MANIFEST_TEMPL_FILE="${EXEC_ROOTDIR}/nfs-provisioner-templ.yaml"
TEMP_SED_FILENAME="${LOCAL_TMP_PATH}/nfsProvManifest.sed"
NFS_PROVISIONER_MANIFEST_FILE="${EXEC_PATH}/nfsProv-value.yaml"
if [ -f ${NFS_PROVISIONER_MANIFEST_FILE} ]
then
    mv ${NFS_PROVISIONER_MANIFEST_FILE} ${NFS_PROVISIONER_MANIFEST_FILE}.bak
fi

#
# Analyzing NFS Provisioner configuration parameters and then
# generating manifest file for NFS Provisioner
#
NFS_SERVER_HOSTNAME=`jq -r ".nfssvr_node.hostname" ${ANSIPB_CONFIG}`
DOMAIN_NAME=`jq -r ".domain_name" ${ANSIPB_CONFIG}`
KUBE_PV_MOUNT_PATH=`jq -r ".nfssvr_node.kube_mount_pathname" ${ANSIPB_CONFIG}`
NFS_PROV_NAMESPACE=`jq -r ".nfssvr_node.namespace" ${ANSIPB_CONFIG}`
NFS_PROV_HELM_REPO_NAME="nfs-subdir-external-provisioner"
NFS_PROV_HELM_CHART_NAME="nfs-subdir-external-provisioner"
NFS_PROV_NS=`jq -r ".nfssvr_node.namespace" ${ANSIPB_CONFIG}`

ssh ${KUBE_MASTER_NODE_NAME} sudo mkdir -p ${KUBE_PV_MOUNT_PATH}
ssh ${KUBE_MASTER_NODE_NAME} helm repo add ${NFS_PROV_HELM_CHART_NAME} https://kubernetes-sigs.github.io/${NFS_PROV_HELM_REPO_NAME}/
ssh ${KUBE_MASTER_NODE_NAME} helm repo update

NFS_EXPORTEDFS_INDEXES=`jq ".nfssvr_node.exported_dirname_list | keys[]" ${ANSIPB_CONFIG}`
REMOTE_NFS_PROV_VALUES_FILENAME="/tmp/nfsProv-value.yaml"
for INDEX in ${NFS_EXPORTEDFS_INDEXES}
do
    NFS_EXPORTED_PATHNAME=`jq -r ".nfssvr_node.exported_dirname_list[${INDEX}].exported_pathname" ${ANSIPB_CONFIG}`
    PROVISIONER_NAME=`jq -r ".nfssvr_node.exported_dirname_list[${INDEX}].provisioner_name" ${ANSIPB_CONFIG}`
    STORAGE_CLASS_NAME=`jq -r ".nfssvr_node.exported_dirname_list[${INDEX}].storage_class_name" ${ANSIPB_CONFIG}`
    RECLAIM_POLICY=`jq -r ".nfssvr_node.exported_dirname_list[${INDEX}].reclaim_policy" ${ANSIPB_CONFIG}`

    # Generates SED file to generate a NFS Provisioner manifest file
    echo "s/%%nfs_server_hostname%%/${NFS_SERVER_HOSTNAME}/g" > ${TEMP_SED_FILENAME}    # to make sure to re-create a file
    echo "s/%%domain_name%%/${DOMAIN_NAME}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%nfs_server_exportfs_name%%/${NFS_EXPORTED_PATHNAME}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%kube_pv_mount_path%%/${KUBE_PV_MOUNT_PATH}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%provisioner_name%%/${PROVISIONER_NAME}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%storage_class_name%%/${STORAGE_CLASS_NAME}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%namespace%%/${NFS_PROV_NAMESPACE}/g" >> ${TEMP_SED_FILENAME}
    echo "s/%%reclaim_policy%%/${RECLAIM_POLICY}/g" >> ${TEMP_SED_FILENAME}

    cat ${NFS_PROVISIONER_MANIFEST_TEMPL_FILE} | sed -f ${TEMP_SED_FILENAME} > ${NFS_PROVISIONER_MANIFEST_FILE}

    scp ${NFS_PROVISIONER_MANIFEST_FILE} ${KUBE_MASTER_NODE_NAME}:${REMOTE_NFS_PROV_VALUES_FILENAME}
    if [ "x${IS_ANSI_PB_DRY_RUN}" != "xtrue" ]
    then
        ssh ${KUBE_MASTER_NODE_NAME} helm install ${PROVISIONER_NAME} \
                                    -f ${REMOTE_NFS_PROV_VALUES_FILENAME} \
                                    --namespace ${NFS_PROV_NS} --create-namespace \
                                    ${NFS_PROV_HELM_REPO_NAME}/${NFS_PROV_HELM_CHART_NAME}
    fi
done

echo "Finished applying NFS provisioner"

echo "All procedures have been done."

exit 0


