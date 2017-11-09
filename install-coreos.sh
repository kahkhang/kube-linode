#!/bin/bash
cd root || exit
exec >install.out 2>&1
if [ "$NODE_TYPE" = "master" ] ; then
cat > container-linux-config.json <<-EOF
{
  "ignition": {
    "version": "2.0.0",
    "config": {}
  },
  "storage": {
    "files": [
      {
        "filesystem": "root",
        "path": "/etc/traefik/acme/acme.json",
        "contents": {
          "source": "data:,",
          "verification": {}
        },
        "mode": 384,
        "user": {},
        "group": {}
      },
      {
        "filesystem": "root",
        "path": "/etc/environment",
        "contents": {
          "source": "data:,COREOS_PUBLIC_IPV4%3D${PUBLIC_IP}%0ACOREOS_PRIVATE_IPV4%3D${PRIVATE_IP}%0A",
          "verification": {}
        },
        "mode": 420,
        "user": {},
        "group": {}
      },
      {
        "filesystem": "root",
        "path": "/home/core/bootstrap.sh",
        "contents": {
          "source": "data:,%23!%2Fusr%2Fbin%2Fenv%20bash%0Aset%20-euo%20pipefail%0A%0ACLUSTER_DIR%3D%24%7BCLUSTER_DIR%3A-cluster%7D%0ASELF_HOST_ETCD%3D%24%7BSELF_HOST_ETCD%3A-false%7D%0ACLOUD_PROVIDER%3D%24%7BCLOUD_PROVIDER%3A-%7D%0ANETWORK_PROVIDER%3D%24%7BNETWORK_PROVIDER%3A-flannel%7D%0A%0Afunction%20usage()%20%7B%0A%20%20%20%20echo%20%22USAGE%3A%22%0A%20%20%20%20echo%20%22%240%3A%20%3Cremote-host%3E%22%0A%20%20%20%20exit%201%0A%7D%0A%0Afunction%20configure_etcd()%20%7B%0A%20%20%20%20%5B%20-f%20%22%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%2F10-etcd-member.conf%22%20%5D%20%7C%7C%20%7B%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fetcd%2Ftls%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20cp%20%2Fhome%2Fcore%2Fassets%2Ftls%2Fetcd-*%20%2Fetc%2Fetcd%2Ftls%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fetcd%2Ftls%2Fetcd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20cp%20%2Fhome%2Fcore%2Fassets%2Ftls%2Fetcd%2F*%20%2Fetc%2Fetcd%2Ftls%2Fetcd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20chown%20-R%20etcd%3Aetcd%20%2Fetc%2Fetcd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20chmod%20-R%20u%3DrX%2Cg%3D%2Co%3D%20%2Fetc%2Fetcd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20%20%20%20%20cat%20%3C%3C%20EOF%20%3E%20%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%2F10-etcd-member.conf%0A%5BService%5D%0AEnvironment%3D%22ETCD_IMAGE_TAG%3Dv3.1.8%22%0AEnvironment%3D%22ETCD_NAME%3Dcontroller%22%0AEnvironment%3D%22ETCD_INITIAL_CLUSTER%3Dcontroller%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2380%22%0AEnvironment%3D%22ETCD_INITIAL_ADVERTISE_PEER_URLS%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2380%22%0AEnvironment%3D%22ETCD_ADVERTISE_CLIENT_URLS%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2379%22%0AEnvironment%3D%22ETCD_LISTEN_CLIENT_URLS%3Dhttps%3A%2F%2F0.0.0.0%3A2379%22%0AEnvironment%3D%22ETCD_LISTEN_PEER_URLS%3Dhttps%3A%2F%2F0.0.0.0%3A2380%22%0AEnvironment%3D%22ETCD_SSL_DIR%3D%2Fetc%2Fetcd%2Ftls%22%0AEnvironment%3D%22ETCD_TRUSTED_CA_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver-ca.crt%22%0AEnvironment%3D%22ETCD_CERT_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver.crt%22%0AEnvironment%3D%22ETCD_KEY_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver.key%22%0AEnvironment%3D%22ETCD_CLIENT_CERT_AUTH%3Dtrue%22%0AEnvironment%3D%22ETCD_PEER_TRUSTED_CA_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer-ca.crt%22%0AEnvironment%3D%22ETCD_PEER_CERT_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer.crt%22%0AEnvironment%3D%22ETCD_PEER_KEY_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer.key%22%0AEOF%0A%20%20%20%20%7D%0A%7D%0A%0A%23%20Initialize%20a%20Master%20node%0Afunction%20init_master_node()%20%7B%0A%20%20%20%20systemctl%20daemon-reload%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20systemctl%20stop%20locksmithd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%3B%20systemctl%20mask%20locksmithd%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%0A%20%20%20%20if%20%5B%20%22%24SELF_HOST_ETCD%22%20%3D%20true%20%5D%20%3B%20then%0A%20%20%20%20%20%20%20%20echo%20%22WARNING%3A%20THIS%20IS%20NOT%20YET%20FULLY%20WORKING%20-%20merely%20here%20to%20make%20ongoing%20testing%20easier%22%0A%20%20%20%20%20%20%20%20etcd_render_flags%3D%22--experimental-self-hosted-etcd%22%0A%20%20%20%20else%0A%20%20%20%20%20%20%20%20etcd_render_flags%3D%22--etcd-servers%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2379%22%0A%20%20%20%20fi%0A%0A%20%20%20%20if%20%5B%20%22%24NETWORK_PROVIDER%22%20%3D%20%22canal%22%20%5D%3B%20then%0A%20%20%20%20%20%20%20%20network_provider_flags%3D%22--network-provider%3Dexperimental-canal%22%0A%20%20%20%20elif%20%5B%20%22%24NETWORK_PROVIDER%22%20%3D%20%22calico%22%20%5D%3B%20then%0A%20%20%20%20%20%20%20%20network_provider_flags%3D%22--network-provider%3Dexperimental-calico%22%0A%20%20%20%20else%0A%20%20%20%20%20%20%20%20network_provider_flags%3D%22--network-provider%3Dflannel%22%0A%20%20%20%20fi%0A%0A%20%20%20%20%23%20Render%20cluster%20assets%0A%20%20%20%20%2Fhome%2Fcore%2Fbootkube%20render%20--asset-dir%3D%2Fhome%2Fcore%2Fassets%20%24%7Betcd_render_flags%7D%20%24%7Bnetwork_provider_flags%7D%20%5C%0A%20%20%20%20%20%20--api-servers%3Dhttps%3A%2F%2F%24%7BCOREOS_PUBLIC_IPV4%7D%3A443%2Chttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A443%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%0A%20%20%20%20%23%20Move%20the%20local%20kubeconfig%20into%20expected%20location%0A%20%20%20%20chown%20-R%20core%3Acore%20%2Fhome%2Fcore%2Fassets%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20mkdir%20-p%20%2Fetc%2Fkubernetes%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20cp%20%2Fhome%2Fcore%2Fassets%2Fauth%2Fkubeconfig%20%2Fetc%2Fkubernetes%2F%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20cp%20%2Fhome%2Fcore%2Fassets%2Ftls%2Fca.crt%20%2Fetc%2Fkubernetes%2Fca.crt%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%0A%20%20%20%20%23%20Start%20etcd.%0A%20%20%20%20if%20%5B%20%22%24SELF_HOST_ETCD%22%20%3D%20false%20%5D%20%3B%20then%0A%20%20%20%20%20%20%20%20configure_etcd%0A%20%20%20%20%20%20%20%20systemctl%20enable%20etcd-member%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%3B%20sudo%20systemctl%20start%20etcd-member%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%20%20%20%20fi%0A%0A%20%20%20%20%23%20Set%20cloud%20provider%0A%20%20%20%20sed%20-i%20%22s%2Fcloud-provider%3D%2Fcloud-provider%3D%24CLOUD_PROVIDER%2F%22%20%2Fetc%2Fsystemd%2Fsystem%2Fkubelet.service%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%0A%20%20%20%20%23%20Start%20the%20kubelet%0A%20%20%20%20systemctl%20enable%20kubelet%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%3B%20sudo%20systemctl%20start%20kubelet%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%0A%20%20%20%20%23%20Start%20bootkube%20to%20launch%20a%20self-hosted%20cluster%0A%20%20%20%20%2Fhome%2Fcore%2Fbootkube%20start%20--asset-dir%3D%2Fhome%2Fcore%2Fassets%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0A%7D%0A%0A%5B%20-d%20%22%24%7BCLUSTER_DIR%7D%22%20%5D%20%26%26%20%7B%0A%20%20%20%20echo%20%22Error%3A%20CLUSTER_DIR%3D%24%7BCLUSTER_DIR%7D%20already%20exists%22%0A%20%20%20%20exit%201%0A%7D%0A%0Awget%20-P%20%2Fhome%2Fcore%20https%3A%2F%2Fgithub.com%2Fkubernetes-incubator%2Fbootkube%2Freleases%2Fdownload%2Fv0.8.1%2Fbootkube.tar.gz%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0Atar%20-xzvf%20%2Fhome%2Fcore%2Fbootkube.tar.gz%20-C%20%2Fhome%2Fcore%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0Amv%20%2Fhome%2Fcore%2Fbin%2Flinux%2Fbootkube%20.%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0Achmod%20%2Bx%20%2Fhome%2Fcore%2Fbootkube%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0Arm%20-rf%20%2Fhome%2Fcore%2Fbin%202%3E%2Fdev%2Fnull%20%3E%2Fdev%2Fnull%0Ainit_master_node%0A",
          "verification": {}
        },
        "mode": 448,
        "user": {},
        "group": {}
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "kubelet.service",
        "enable": true,
        "contents": "[Service]\nEnvironment=KUBELET_IMAGE_URL=docker://gcr.io/google_containers/hyperkube\nEnvironment=KUBELET_IMAGE_TAG=v1.8.2\nEnvironment=\"RKT_RUN_ARGS=--uuid-file-save=/var/cache/kubelet-pod.uuid --volume etc-resolv,kind=host,source=/etc/resolv.conf --mount volume=etc-resolv,target=/etc/resolv.conf --volume opt-cni-bin,kind=host,source=/opt/cni/bin --mount volume=opt-cni-bin,target=/opt/cni/bin --volume var-log,kind=host,source=/var/log --mount volume=var-log,target=/var/log --volume var-lib-cni,kind=host,source=/var/lib/cni --mount volume=var-lib-cni,target=/var/lib/cni --insecure-options=image\"\nEnvironmentFile=/etc/environment\nExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests\nExecStartPre=/bin/mkdir -p /opt/cni/bin\nExecStartPre=/bin/mkdir -p /etc/kubernetes/cni/net.d\nExecStartPre=/bin/mkdir -p /etc/kubernetes/checkpoint-secrets\nExecStartPre=/bin/mkdir -p /etc/kubernetes/inactive-manifests\nExecStartPre=/bin/mkdir -p /var/lib/cni\nExecStartPre=/bin/mkdir -p /var/lib/kubelet/volumeplugins\nExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/cache/kubelet-pod.uuid\nExecStart=/usr/lib/coreos/kubelet-wrapper   --allow-privileged   --anonymous-auth=false   --client-ca-file=/etc/kubernetes/ca.crt   --cloud-provider=   --cluster_dns=10.3.0.10   --cluster_domain=cluster.local   --cni-conf-dir=/etc/kubernetes/cni/net.d   --exit-on-lock-contention   --hostname-override=\${COREOS_PUBLIC_IPV4}   --kubeconfig=/etc/kubernetes/kubeconfig   --lock-file=/var/run/lock/kubelet.lock   --minimum-container-ttl-duration=3m0s   --network-plugin=cni   --node-labels=node-role.kubernetes.io/master   --pod-manifest-path=/etc/kubernetes/manifests   --register-with-taints=node-role.kubernetes.io/master=:NoSchedule   --volume-plugin-dir=/var/lib/kubelet/volumeplugins\nExecStop=-/usr/bin/rkt stop --uuid-file=/var/cache/kubelet-pod.uuid\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n"
      }
    ]
  },
  "networkd": {
    "units": [
      {
        "name": "00-eth0.network",
        "contents": "[Match]\nName=eth0\n\n[Network]\nDHCP=no\nDNS= $(cat /etc/resolv.conf | awk '/^nameserver /{ print $0 }' | sed 's/nameserver //g' | tr '\n' ' ')\nDomains=members.linode.com\nIPv6PrivacyExtensions=false\nGateway=${PUBLIC_IP%.*}.1\nAddress=${PUBLIC_IP}/24\nAddress=${PRIVATE_IP}/17\n"
      }
    ]
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "$SSH_KEY"
        ]
      }
    ]
  }
}
EOF
fi

if [ "$NODE_TYPE" = "worker" ] ; then
cat > container-linux-config.json <<-EOF
{
  "ignition": {
    "version": "2.0.0",
    "config": {}
  },
  "storage": {
    "files": [
      {
        "filesystem": "root",
        "path": "/etc/environment",
        "contents": {
          "source": "data:,COREOS_PUBLIC_IPV4%3D${PUBLIC_IP}%0ACOREOS_PRIVATE_IPV4%3D${PRIVATE_IP}%0A",
          "verification": {}
        },
        "mode": 420,
        "user": {},
        "group": {}
      },
      {
        "filesystem": "root",
        "path": "/home/core/bootstrap.sh",
        "contents": {
          "source": "data:,%23!%2Fusr%2Fbin%2Fenv%20bash%0Aset%20-euo%20pipefail%0A%0AREMOTE_PORT%3D%24%7BREMOTE_PORT%3A-22%7D%0AIDENT%3D%24%7BIDENT%3A-%24%7BHOME%7D%2F.ssh%2Fid_rsa%7D%0ATAG_MASTER%3D%24%7BTAG_MASTER%3A-false%7D%0ACLOUD_PROVIDER%3D%24%7BCLOUD_PROVIDER%3A-%7D%0A%0A%23%20Initialize%20a%20worker%20node%0Afunction%20init_worker_node()%20%7B%0A%0A%20%20%20%20%23%20Setup%20kubeconfig%0A%20%20%20%20mkdir%20-p%20%2Fetc%2Fkubernetes%0A%20%20%20%20cp%20%2Fhome%2Fcore%2Fkubeconfig%20%2Fetc%2Fkubernetes%2Fkubeconfig%0A%20%20%20%20%23%20Pulled%20out%20of%20the%20kubeconfig.%20Other%20installations%20should%20place%20the%20root%0A%20%20%20%20%23%20CA%20here%20manually.%0A%20%20%20%20grep%20'certificate-authority-data'%20%2Fhome%2Fcore%2Fkubeconfig%20%7C%20awk%20'%7Bprint%20%242%7D'%20%7C%20base64%20-d%20%3E%20%2Fetc%2Fkubernetes%2Fca.crt%0A%0A%20%20%20%20%23%20Set%20cloud%20provider%0A%20%20%20%20sed%20-i%20%22s%2Fcloud-provider%3D%2Fcloud-provider%3D%24CLOUD_PROVIDER%2F%22%20%2Fetc%2Fsystemd%2Fsystem%2Fkubelet.service%0A%0A%20%20%20%20%23%20Start%20services%0A%20%20%20%20systemctl%20daemon-reload%20%3E%2Fdev%2Fnull%202%3E%2Fdev%2Fnull%0A%20%20%20%20systemctl%20stop%20update-engine%20%3E%2Fdev%2Fnull%202%3E%2Fdev%2Fnull%0A%20%20%20%20systemctl%20mask%20update-engine%20%3E%2Fdev%2Fnull%202%3E%2Fdev%2Fnull%0A%20%20%20%20systemctl%20enable%20kubelet%20%3E%2Fdev%2Fnull%202%3E%2Fdev%2Fnull%0A%20%20%20%20sudo%20systemctl%20start%20kubelet%20%3E%2Fdev%2Fnull%202%3E%2Fdev%2Fnull%0A%7D%0A%0Ainit_worker_node%0A",
          "verification": {}
        },
        "mode": 448,
        "user": {},
        "group": {}
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "kubelet.service",
        "enable": true,
        "contents": "[Service]\nEnvironment=KUBELET_IMAGE_URL=docker://gcr.io/google_containers/hyperkube\nEnvironment=KUBELET_IMAGE_TAG=v1.8.2\nEnvironment=\"RKT_RUN_ARGS=--uuid-file-save=/var/cache/kubelet-pod.uuid --volume etc-resolv,kind=host,source=/etc/resolv.conf --mount volume=etc-resolv,target=/etc/resolv.conf --volume opt-cni-bin,kind=host,source=/opt/cni/bin --mount volume=opt-cni-bin,target=/opt/cni/bin --volume var-log,kind=host,source=/var/log --mount volume=var-log,target=/var/log --volume var-lib-cni,kind=host,source=/var/lib/cni --mount volume=var-lib-cni,target=/var/lib/cni --insecure-options=image\"\nEnvironmentFile=/etc/environment\nExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests\nExecStartPre=/bin/mkdir -p /opt/cni/bin\nExecStartPre=/bin/mkdir -p /etc/kubernetes/cni/net.d\nExecStartPre=/bin/mkdir -p /var/lib/cni\nExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/cache/kubelet-pod.uuid\nExecStartPre=/bin/mkdir -p /var/lib/kubelet/volumeplugins\nExecStart=/usr/lib/coreos/kubelet-wrapper   --allow-privileged   --anonymous-auth=false   --client-ca-file=/etc/kubernetes/ca.crt   --cloud-provider=   --cluster_dns=10.3.0.10   --cluster_domain=cluster.local   --cni-conf-dir=/etc/kubernetes/cni/net.d   --exit-on-lock-contention   --hostname-override=\${COREOS_PUBLIC_IPV4}   --kubeconfig=/etc/kubernetes/kubeconfig   --lock-file=/var/run/lock/kubelet.lock   --minimum-container-ttl-duration=3m0s   --network-plugin=cni   --pod-manifest-path=/etc/kubernetes/manifests   --require-kubeconfig   --volume-plugin-dir=/var/lib/kubelet/volumeplugins\nExecStop=-/usr/bin/rkt stop --uuid-file=/var/cache/kubelet-pod.uuid\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n"
      }
    ]
  },
  "networkd": {
    "units": [
      {
        "name": "00-eth0.network",
        "contents": "[Match]\nName=eth0\n\n[Network]\nDHCP=no\nDNS= $(cat /etc/resolv.conf | awk '/^nameserver /{ print $0 }' | sed 's/nameserver //g' | tr '\n' ' ')\nDomains=members.linode.com\nIPv6PrivacyExtensions=false\nGateway=${PUBLIC_IP%.*}.1\nAddress=${PUBLIC_IP}/24\nAddress=${PRIVATE_IP}/17\n"
      }
    ]
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "$SSH_KEY"
        ]
      }
    ]
  }
}
EOF
fi

apt-get -y install gawk
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
chmod u+x coreos-install
./coreos-install -d /dev/sda -i container-linux-config.json
reboot
