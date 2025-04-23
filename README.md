# Kubernetes build-up script with Raspberry pi 5

## Terminology

In this document, below keywords are defined. Please refer them before reading this document.

| Keyword | Meaning |
| - | - |
| ${PRJROOT} | top directory name of this project without "kuberasp" directory name |


## Purpose

This project aims to build up kubernetes environment with at least 3-units Raspberry pi 5 to learn kubernetes feature, operation, capability, or others. Assumed hardware and network topology is below.

このプロジェクトは安価なRaspberry pi 5 (少なくとも３台で構成) で構築し、Kubernetesの機能や使い方などについて習得することを目的としています。想定しているシステム構成などについては後述の記事をご参照ください。

## System topology

![System topology](imgs/sys-arch.drawio.svg)

### Roles of each equipment

| Equipment name | Auto-build | Description |
| --- | --- | --- |
| Ansible executor | No | External computing resource to execute Ansible process. See XXX section about steps to install.<br>Ansibleを実行するためのPC環境。構築手順は後述のXXX節をご参照ください  |
| Storage node | No | External NFS service node. On this environment, this storage node is applied on Raspberry pi 4 and 2 USB memories for exporting filesystem.<br>Kubernetes上に構築するサービスが利用するストレージ(PV)用のストレージ環境を提供するためのノードで、NFSサーバ機能を提供するノードです。本プロジェクトではRaspberry pi 4に2本のUSBメモリを実装して作成しています。 |
| Master node | Yes | Master node of kubernetes system. <br>Kubernetesのマスタノード |
| Worker node | Yes | Worker node of kubernetes system. <br>Kubernetesのワーカノード |


### Network topology

This system has 2 networks to handle both deploying by Ansible Playbook and processing some services on this kubernetes infrastructure. The network for processing some services on kubernetes is automatically deployed by this IaC implementation, however, another network for deploying this system is NOT built up automatically. The network for deploying is necessary to be deployed in advanced.<br>
このシステムではAnsible Playbookによりデプロイ操作を行うネットワークとKubernetes環境で使用するネットワークの２つのネットワークを利用しています。Ansible Playbookによるデプロイ操作を行う際に利用するネットワークは事前に設定されていることを前提としており、[System topology](#system-topology) 図にあるWi-Fiネットワークを介してそれぞれの装置への到達性が事前に設定されていなければなりません。

## System parameter configuration

This script uses a configuration file to specify system parameters. Below is a specifications<br>
本スクリプトは構築するシステムパラメータを指定するための設定ファイルがあります。下記にその設定ファイルの仕様について記載します。

### Configuration file

```
${PRJROOT}/ansible/exec_tmp/kube-ansible.conf
```

_This file is NOT managed by Git. Please generate this file yourself with copying template file, ``${PRJROOT}/ansible/kube_ansible.conf.templ``_ <br>
_上記ファイルはGit制御下には存在しません。``${PRJROOT}/ansible/kube_ansible.conf.templ``ファイルをコピーして作成してください_

### Configuration parameter list (general_settings)

  | Parameter name | Default value | Description |
  | - | - | - |
  | ssh_username | username | Username for ssh login<br>sshでログイン時に使用するユーザ名 |
  | ansible_user | username | Username for Ansible user<br>Ansible Playbookが使用するユーザ名 |
  | ansible_group | groupname | Group name for Ansible user<br>Ansible Playbookが使用するグループ名 |
  | default_gateway_addr | 192.168.0.1 | (Unused) Default gateway address for kubernetes network<br>Kubernetesネットワークに指定するデフォルトゲートウェイ (未使用)
  | dns_server_addr | 192.168.0.1 | DNS server address for kubernetes network<br>Kubernetesネットワークに指定するDNSサーバアドレス |
  | master_server_addr | 192.168.100.2 | Master node IP address<br>マスタノードに割り当てるIPアドレス |
  | master_server_port | 6443 | Server port of kubelet service on a master node<br>マスタノードで起動されるkubeletサービスのサーバポート |
  | do_reset_kube_env | false | Configuration parameter to specify whether current kubernetes environment is reset or not. If this parameter was set as "true", current Kubernetes environment is reset at once. And then re-generate Kubernetes environment.<br>Ansible playbookを起動する際にKubernetes環境をリセットするかどうかを示す設定。"true"が指定されるとKubernetes環境をいったん削除してから再構築する |
  | cni_name | - | Setting parameter to specify CNI module, "calico" or "flannel".<br>CNIとして使用するモジュールを"calico"もしくは"flannel"のいずれかから指定する |
  | flannel_version | v0.25.2 | Flannel version if "cni_name" is set with "flannel".<br>"cni_name"で"flannel"を指定した場合にFlannelバージョンを指定する |
  | calico_version | v3.27.0 | Calico version if "cni_name" is set with "calico".<br>"cni_name"で"calico"を指定した場合に Calico バージョンを指定する |
  | domain_name | inhouse.local | Specify domain name of Kubernetes network<br>Kubernetesネットワークに割り当てるドメイン名 |
  | pv_mount_path | kubedata | Mount point name of PV<br>PVで使用するストレージのマウントポイント名 |

### Configuration parameter list (extra_pkginfo)

  | Parameter name | Default value | Description |
  | - | - | - |
  | arch_name | arm64 | Architecture name of Kubernetes nodes. All nodes MUST be same architecture<br>Kubernetesノードのアーキテクチャを指定する。すべてのノードは同じアーキテクチャでなければならない |
  | os_name | linux | OS name of Kubernetes nodes. All nodes MUST be same OS name<br>KubernetesノードのOS名を指定する。すべてのノードのOS名は同一でなければならない |
  | helm_version | v3.17.3 | Version information of Helm package<br>Helm 環境のバージョン |
  | golang_version | 1.22.4 | Version information of Golang package<br>Golang 環境のバージョン |
  | golang_archname | armv6l | Architecture name for Golang package<br>Golangパッケージ用のアーキテクチャ名 |
  | containerd_version | 2.0.5 | Version information of containerd package<br>containerd 環境のバージョン |
  | runc_version | v1.2.6 | Version information of runc package<br>runc 環境のバージョン |
  | cni_plugin_version | v1.6.2 | Version information of cni_plugin package<br>cni_plugin 環境のバージョン |
  | helm_dlurl | https://get.helm.sh/helm-%%helm_version%%-%%os_name%%-%%arch_name%%.tar.gz | URL for Helm package download<br>Helm パッケージのダウンロードサイトのURL |
  | golang_dlurl | https://go.dev/dl/go%%golang_version%%.%%os_name%%-%%arch_name%%.tar.gz | URL for Golang package download<br>Golang パッケージのダウンロードサイトのURL |
  | containerd_dlurl | https://github.com/containerd/containerd/releases/download/v%%containerd_version%%/containerd-%%containerd_version%%-%%os_name%%-%%arch_name%%.tar.gz | URL for containerd package download<br>containerd パッケージのダウンロードサイトのURL |
  | runc_dlurl | https://github.com/opencontainers/runc/releases/download/%%runc_version%%/runc.%%arch_name%% | URL for runc package download<br>runc パッケージのダウンロードサイトのURL |
  | cni_plugin_dlurl | https://github.com/containernetworking/plugins/releases/download/%%cni_plugin_version%%/cni-plugins-%%os_name%%-%%arch_name%%-%%cni_plugin_version%%.tgz | URL for cni_plugin package download<br>cni_plugin パッケージのダウンロードサイトのURL |

### Configuration parameter list (master_node)

  | Parameter name | Default value | Description |
  | - | - | - |
  | hostname | kubemst | Host name of master node<br>マスタノードのホスト名 |
  | address | 240f:79:b193:1:2f0f:c90d:2147:4a38 | IP address to be accessed by Ansible node<br>Ansibleノードからアクセスに利用するIPアドレス |
  | ssh_pkey_filename | kubemst.key | Secret key file for master node<br>マスタノードログイン用の秘密鍵ファイル名 |
  | fixed_ipv4_addr | 192.168.100.2 | Fixed IP address for master node on Kubernetes network<br>Kubernetesネットワーク側に割り当てるマスタノードの固定IPアドレス |
  | fixed_ipv4_netmasklen | 24 | Netmask length of kubemst fixed interface address<br>kubemstノードに割り当てる固定IPアドレスのネットマスクビット長 |

### Configuration parameter list (worker_node)

_Worker node element is specifed as arrayed parameter. If you want to join more worker node, you can add additional nodes you want._<br>
_ワーカノードは配列指定となっており、もしさらにワーカノードを追加したい場合は、要素として追加すればワーカノードを追加することが可能_

  | Parameter name | Default value | Description |
  | - | - | - |
  | hostname | - | Host name of worker node<br>ワーカノードのホスト名 |
  | address | - | IP address to be accessed by Ansible node<br>Ansibleノードからアクセスに利用するIPアドレス |
  | ssh_pkey_filename | - | Secret key file for worker node<br>ワーカノードログイン用の秘密鍵ファイル名 |
  | fixed_ipv4_addr | - | Fixed IP address for worker node on Kubernetes network<br>Kubernetesネットワーク側に割り当てるワーカノードの固定IPアドレス |
  | fixed_ipv4_netmasklen | - | Netmask length of this node fixed interface address<br>ノードに割り当てる固定IPアドレスのネットマスクビット長 |

### Configuration parameter list (nfssvr_node)

  | Parameter name | Default value | Description |
  | - | - | - |
  | hostname | kubestorage | Host name of NFS server node<br>NFSサーバノードのホスト名 |
  | address | 240f:79:b193:1:a75a:ef3:30ae:f444 | IP address of NFS server node<br>NFSサーバノードのIPアドレス |
  | ssh_pkey_filename | - | Secret key file for NFS server node<br>NFSサーバノードログイン用の秘密鍵ファイル名 |
  | fixed_ipv4_addr | - | Fixed IP address for NFS server node on Kubernetes network<br>Kubernetesネットワーク側に割り当てるNFSサーバノードの固定IPアドレス |
  | fixed_ipv4_netmasklen | - | Netmask length of this node fixed interface address<br>ノードに割り当てる固定IPアドレスのネットマスクビット長 |
  | namespace | nfs-provisioner | Namespace name for NFS Provisioner Pod<br>NFS Provisionerポッドを起動するNamespace名 |
  | kube_mount_pathname | kubedata | Root directory name of NFS mount point on Kubernetes nodes. This parameter MUST be JUST one hierarchy. DO NOT SPECIFY MULTIPLE DIRECTORY DEPTH.<br>KubernetesノードにおいてNFSでマウントする際のRootディレクトリ名。本パラメータは１階層のみ指定が可能です。複数階層となるディレクトリを指定しないでください |
  | exported_dirname_list | - | Exported file system name on NFS server node. This parameters have multiple settings. Detail setting parameters are defined next section.<br>NFSサーバノードで公開しているファイルシステムのディレクトリ情報。本パラメータは複数の公開ファイルシステムの指定が可能です。詳細設定は次節で示します。 |

### Configuration parameter list (exported_dirname_list)

  | Parameter name | Default value | Description |
  | - | - | - |
  | exported_pathname | - | Path name of exported file system path<br>NFSで公開しているファイルシステムのディレクトリ名 |
  | provisioner_name | - | Provisioner name used as pod name<br>Provisionerポッドに使用するProvisioner名を指定する |
  | reclaim_policy | - | Specify reclaim policy for PV<br>PVに設定するRe-claimポリシ名を指定する |
  | storage_class_name | - | Specify storage class name<br>Storage class名を指定する |

## Pre-configuration steps

### PKI authenticating SSH login

Ansible assumes login to target nodes without password input. To achieve this requirement, PKI authentication environment must be configured in advanced. Steps to configure PKI authenticating environment are below.<br>
Ansibleでは構成定義対象となるノードにはパスワードなしでログインできる必要があります。そのため、事前にPKI認証でログインできるよう設定しておく必要があります。下記にPKI認証環境を構築するための手順を記載します。

1. Installs SSH server and enables it / SSHサーバインストールと有効化

   Install SSH server package and enables it with below command.<br>
   下記コマンドを実行してSSHサーバパッケージのインストールとSSHサーバの有効化を行います。

   ```
   sudo apt-get install -y openssh-server
   sudo systemctl enable --now ssh
   ```

1. Generates PKI keys / PKI鍵一式を作成します

   Generate PKI keys with below command / 下記コマンドを実行してPKI鍵一式を作成します

   ```
   ssh-keygen -t rsa -b 4096
   ```

   _You can use another encryption algorithm if you want. Above is JUST sample command._<br>
   _上記ではRSAを指定していますが、ほかのアルゴリズムに変更することも可能です。上記はあくまでサンプルです_

   実行時の例: __DO NOT SPECIFY ENCRYPTION KEY for secret key__ / __秘密鍵の秘匿用の鍵は設定しないでください__

   ```
   $ ssh-keygen -t rsa -b 4096
   Generating public/private rsa key pair.
   Enter file in which to save the key (/home/hoge/.ssh/id_rsa):
   Enter passphrase (empty for no passphrase):
   Enter same passphrase again:
   Your identification has been saved in /home/hoge/.ssh/id_rsa
   Your public key has been saved in /home/hoge/.ssh/id_rsa.pub
   The key fingerprint is:
   SHA256:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX hoge@host
   The key's randomart image is:
   +---[RSA 4096]----+
   |        ..       |
   |        o..      |
   |       ..=..     |
   |   .  ooo.+.o    |
   |    o .oS+o+ .   |
   |.  o o  o=* .    |
   | ++   .o+=Eo     |
   |+.=.+. ++.+      |
   |.ooO+o. o=.      |
   +----[SHA256]-----+
   ```

1. Enabling PKI key / 全ステップで作成したPKI鍵の有効化

   To enabling key generated by previous step, generate "authorized_keys" file. <br>
   前ステップで作成した鍵を有効にするため、"authorized_keys"ファイルを作成します。

   ```
   cp $HOME/.ssh/id_rsa.pub $HOME/.ssh/authorized_keys
   ```

   _Above step assumes that the PKI key was generated with RSA algorithm and default file name is used. If it was other case, you need to specify appropriate public key filename._<br>
   _上記コマンドはRSAを選択し、デフォルトのオプションで生成したときのサンプルになります。変更した場合は公開鍵ファイルのファイル名を適切に指定してください_

1. Coying secret key onto accessor system / 秘密鍵ファイルをアクセス元のシステムにコピー

   You need to copy the secret key file generated in previous step on accessor system. You have to execute below steps on accessor system.<br>
   前ステップで生成した秘密鍵情報をアクセス元のシステムにコピーします。下記ステップをアクセス元のシステムで実行してください。

   ```
   cd $HOME/.ssh
   scp <username>@<SSH server address>:.ssh/id_rsa $HOME/.ssh/<hostname>.key
     ... Operate with appropriate reaction against shown prompt like password or others
   chmod 600 $HOME/.ssh/<hostname>.key
   ```

1. (Option) Register host information / (任意) ホスト情報の登録

   If you want to operate with ssh server host name, you can register the host name and other relating information on a SSH configuration file. If you want to do this, see below steps.<br>
   今後の操作でSSHサーバのホスト名でログインできるようにしたい場合は、設定ファイルにホスト情報を登録することで名前でアクセスできるようにできます。もし、設定したい場合は下記ステップに従い設定してください。

   ```
   vi $HOME/.ssh/config
   ```

   You need to add below information with appropriate setting parameters. / 下記に示す情報を適切な設定パラメータを指定して登録してください。

   ```
   Host <hostname>
     HostName <SSH server host name or address>
     Port 22
     User <Username>>
     IdentityFile ~/.ssh/<Secret key filename for the SSH server host>
     ServerAliveInterval 60
   ```


### Steps to install ansible packages

This kuberasp script assumes some packages installation. To achieve the assumption, please operate with following steps.<br>
本kuberaspスクリプトを実行するにはいくつかの依存パッケージが事前にインストールされていることを前提としています。下記ステップに沿ってパッケージインストールを実行してください。

```
sudo apt-get update
sudo apt-get install -y ansible jq openssl git
```

### Steps to install NFS server

You can enable NFS server to use as PV of this kubernetes. Below steps assumes to have 2 USB memories on Raspberry pi (Debian linux) and the USB memories has been mounted on /export and /export2 mount points.<br>
下記ステップでKubernetes環境のPVとして利用できるストレージ環境をNFSとして提供が可能です。下記構築ステップではRaspberry pi 4 (Debian linux) に２本のUSBメモリが挿入されており、それぞれ/export, /export2にマウントされていることを前提にしています。

```
sudo systemctl enable --now nfs-server
cat <<EOD > /tmp/exports
# /etc/exports: the access control list for filesystems which may be exported
#               to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#
/export         *(rw,sync,no_root_squash,subtree_check)
/export2        *(rw,sync,no_root_squash,subtree_check)
EOD
sudo mv /tmp/exports /etc/exports
sudo exportfs -a
```

To check whether the configuration steps have been applied, execute below command. If you can see both "/export" and "/export2", this steps have been done.<br>
本設定ステップが完了しているかどうかについて下記コマンドを実行して確認します。"/export"および"/export2"が表示されれば正しく設定できたことが確認できます。

```
sudo exportfs
```

[Shown message sample]
```
/export         <world>
/export2        <world>
```

## Executing playbook

Some preparing processes are implemented by bash script (ansiplay.sh). You MUST execute the bash script to launch Ansible playbook. Command syntax is defined in below.<br>
事前設定のいくつかはBashスクリプトで実装しているため、Kubernetes環境構築のためにAnsible Playbookを起動する場合はこのBashスクリプト経由で起動しなければならない。コマンド仕様は後述します。

### Command syntax of "ansiplay.sh"

1. __Command name__

   ansiplay.sh [options]

1. __Command options__

   | Option                    | Default | Description |
   | -                         | - | - |
   | --ansible-pb-config       | ${PRJROOT}/ansible/exec_tmp/kube-ansble.conf | System parameter configuration file name for this Kubernetes system<br>Kubernetes構築用のシステムパラメータ設定ファイル名 |
   | --ansible-pb-file         | ${PRJROOT}/ansible/k8s-setup.yaml            | Ansible Playbook file name<br>Ansible Playbookファイル名 |
   | --force-download-packages | -                                            | Specify force download packages even though the package file is found<br>常にパッケージファイルをダウンロードするよう指定するオプション |

1. __Example__

   ```
   bash ${PRJROOT}/ansible/ansiplay.sh
   ```

---
[Last page]
