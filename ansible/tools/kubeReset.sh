#!/usr/bin/env bash

# kubeadm resetコマンドを実行して、Kubernetesの設定をリセットします。
sudo kubeadm reset --force

# 全てのKubernetes関連プロセスを停止
sudo systemctl stop kubelet
sudo systemctl stop docker
sudo systemctl stop kubelet

# コンテナの削除
sudo docker stop $(sudo docker ps -aq)
sudo docker rm $(sudo docker ps -aq)
sudo docker rmi $(sudo docker images -q)

# Stops services
SERVICE_LIST="docker docker.socket containerd"
for SERVICE_NAME in ${SERVICE_LIST}
do
    sudo systemctl stop ${SERVICE_NAME}
    if [ ${SERVICE_NAME} = "docker" ]
    then
        sudo /lib/systemd/systemd-sysv-install disable ${SERVICE_NAME}
    fi
    sudo systemctl disable ${SERVICE_NAME}
done

# containerdの削除
sudo apt-get remove containerd containerd.io docker-ce kubelet kubeadm kubectl -y
sudo apt-get autoremove -y


# 手動で古い設定ファイルやディレクトリを削除します。
sudo rm -rf /etc/kubernetes
sudo rm -rf /etc/containerd
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/containerd
sudo rm -rf /var/lib/docker
sudo rm -rf /var/run/containerd

# iptablesのクリーンアップ
sudo iptables -F

# kubernetes configファイルの削除
rm $HOME/.kube/config

# containerd更新時に作成したバックアップファイルの削除
sudo rm /etc/containerd/config.toml.bak

# ポート10250が使用中でないことを確認し、問題があれば該当プロセスを停止
echo -n "Check whether port 10250 has been already released or not : "
sudo lsof -i :10250 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]
then
    echo "Already released"
else
    echo "Still bound the port 10250. Check and recover this situation manually"
    exit 1
fi

exit 0

