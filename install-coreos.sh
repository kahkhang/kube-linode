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
        "path": "/home/${USERNAME}/bootstrap.sh",
        "contents": {
          "source": "data:,%23!%2Fusr%2Fbin%2Fenv%20bash%0Aset%20-euo%20pipefail%0A%0AREMOTE_USER%3D${USERNAME}%0ACLUSTER_DIR%3D%24%7BCLUSTER_DIR%3A-cluster%7D%0ASELF_HOST_ETCD%3D%24%7BSELF_HOST_ETCD%3A-true%7D%0ACALICO_NETWORK_POLICY%3D%24%7BCALICO_NETWORK_POLICY%3A-false%7D%0ACLOUD_PROVIDER%3D%24%7BCLOUD_PROVIDER%3A-%7D%0A%0Afunction%20usage()%20%7B%0A%20%20%20%20echo%20%22USAGE%3A%22%0A%20%20%20%20echo%20%22%240%3A%20%3Cremote-host%3E%22%0A%20%20%20%20exit%201%0A%7D%0A%0Afunction%20configure_etcd()%20%7B%0A%20%20%20%20%5B%20-f%20%22%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%2F10-etcd-member.conf%22%20%5D%20%7C%7C%20%7B%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fetcd%2Ftls%0A%20%20%20%20%20%20%20%20cp%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%2Ftls%2Fetcd-*%20%2Fetc%2Fetcd%2Ftls%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fetcd%2Ftls%2Fetcd%0A%20%20%20%20%20%20%20%20cp%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%2Ftls%2Fetcd%2F*%20%2Fetc%2Fetcd%2Ftls%2Fetcd%0A%20%20%20%20%20%20%20%20chown%20-R%20etcd%3Aetcd%20%2Fetc%2Fetcd%0A%20%20%20%20%20%20%20%20chmod%20-R%20u%3DrX%2Cg%3D%2Co%3D%20%2Fetc%2Fetcd%0A%20%20%20%20%20%20%20%20mkdir%20-p%20%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%0A%20%20%20%20%20%20%20%20cat%20%3C%3C%20EOF%20%3E%20%2Fetc%2Fsystemd%2Fsystem%2Fetcd-member.service.d%2F10-etcd-member.conf%0A%5BService%5D%0AEnvironment%3D%22ETCD_IMAGE_TAG%3Dv3.1.8%22%0AEnvironment%3D%22ETCD_NAME%3Dcontroller%22%0AEnvironment%3D%22ETCD_INITIAL_CLUSTER%3Dcontroller%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2380%22%0AEnvironment%3D%22ETCD_INITIAL_ADVERTISE_PEER_URLS%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2380%22%0AEnvironment%3D%22ETCD_ADVERTISE_CLIENT_URLS%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2379%22%0AEnvironment%3D%22ETCD_LISTEN_CLIENT_URLS%3Dhttps%3A%2F%2F0.0.0.0%3A2379%22%0AEnvironment%3D%22ETCD_LISTEN_PEER_URLS%3Dhttps%3A%2F%2F0.0.0.0%3A2380%22%0AEnvironment%3D%22ETCD_SSL_DIR%3D%2Fetc%2Fetcd%2Ftls%22%0AEnvironment%3D%22ETCD_TRUSTED_CA_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver-ca.crt%22%0AEnvironment%3D%22ETCD_CERT_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver.crt%22%0AEnvironment%3D%22ETCD_KEY_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fserver.key%22%0AEnvironment%3D%22ETCD_CLIENT_CERT_AUTH%3Dtrue%22%0AEnvironment%3D%22ETCD_PEER_TRUSTED_CA_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer-ca.crt%22%0AEnvironment%3D%22ETCD_PEER_CERT_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer.crt%22%0AEnvironment%3D%22ETCD_PEER_KEY_FILE%3D%2Fetc%2Fssl%2Fcerts%2Fetcd%2Fpeer.key%22%0AEOF%0A%20%20%20%20%7D%0A%7D%0A%0A%23%20Initialize%20a%20Master%20node%0Afunction%20init_master_node()%20%7B%0A%20%20%20%20systemctl%20daemon-reload%0A%20%20%20%20systemctl%20stop%20update-engine%3B%20systemctl%20mask%20update-engine%0A%0A%20%20%20%20if%20%5B%20%22%24SELF_HOST_ETCD%22%20%3D%20true%20%5D%20%3B%20then%0A%20%20%20%20%20%20%20%20echo%20%22WARNING%3A%20THIS%20IS%20NOT%20YET%20FULLY%20WORKING%20-%20merely%20here%20to%20make%20ongoing%20testing%20easier%22%0A%20%20%20%20%20%20%20%20etcd_render_flags%3D%22--experimental-self-hosted-etcd%22%0A%20%20%20%20else%0A%20%20%20%20%20%20%20%20etcd_render_flags%3D%22--etcd-servers%3Dhttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A2379%22%0A%20%20%20%20fi%0A%0A%20%20%20%20if%20%5B%20%22%24CALICO_NETWORK_POLICY%22%20%3D%20true%20%5D%3B%20then%0A%20%20%20%20%20%20%20%20echo%20%22WARNING%3A%20THIS%20IS%20EXPERIMENTAL%20SUPPORT%20FOR%20NETWORK%20POLICY%22%0A%20%20%20%20%20%20%20%20cnp_render_flags%3D%22--experimental-calico-network-policy%22%0A%20%20%20%20else%0A%20%20%20%20%20%20%20%20cnp_render_flags%3D%22%22%0A%20%20%20%20fi%0A%0A%20%20%20%20%23%20Render%20cluster%20assets%0A%20%20%20%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fbootkube%20render%20--asset-dir%3D%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%20%24%7Betcd_render_flags%7D%20%24%7Bcnp_render_flags%7D%20%5C%0A%20%20%20%20%20%20--api-servers%3Dhttps%3A%2F%2F%24%7BCOREOS_PUBLIC_IPV4%7D%3A6443%2Chttps%3A%2F%2F%24%7BCOREOS_PRIVATE_IPV4%7D%3A6443%0A%0A%20%20%20%20%23%20Move%20the%20local%20kubeconfig%20into%20expected%20location%0A%20%20%20%20chown%20-R%20%24%7BREMOTE_USER%7D%3A%24%7BREMOTE_USER%7D%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%0A%20%20%20%20mkdir%20-p%20%2Fetc%2Fkubernetes%0A%20%20%20%20cp%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%2Fauth%2Fkubeconfig%20%2Fetc%2Fkubernetes%2F%0A%20%20%20%20cp%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%2Ftls%2Fca.crt%20%2Fetc%2Fkubernetes%2Fca.crt%0A%0A%20%20%20%20%23%20Start%20etcd.%0A%20%20%20%20if%20%5B%20%22%24SELF_HOST_ETCD%22%20%3D%20false%20%5D%20%3B%20then%0A%20%20%20%20%20%20%20%20configure_etcd%0A%20%20%20%20%20%20%20%20systemctl%20enable%20etcd-member%3B%20sudo%20systemctl%20start%20etcd-member%0A%20%20%20%20fi%0A%0A%20%20%20%20%23%20Set%20cloud%20provider%0A%20%20%20%20sed%20-i%20%22s%2Fcloud-provider%3D%2Fcloud-provider%3D%24CLOUD_PROVIDER%2F%22%20%2Fetc%2Fsystemd%2Fsystem%2Fkubelet.service%0A%0A%20%20%20%20%23%20Start%20the%20kubelet%0A%20%20%20%20systemctl%20enable%20kubelet%3B%20sudo%20systemctl%20start%20kubelet%0A%0A%20%20%20%20%23%20Start%20bootkube%20to%20launch%20a%20self-hosted%20cluster%0A%20%20%20%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fbootkube%20start%20--asset-dir%3D%2Fhome%2F%24%7BREMOTE_USER%7D%2Fassets%0A%7D%0A%0A%5B%20-d%20%22%24%7BCLUSTER_DIR%7D%22%20%5D%20%26%26%20%7B%0A%20%20%20%20echo%20%22Error%3A%20CLUSTER_DIR%3D%24%7BCLUSTER_DIR%7D%20already%20exists%22%0A%20%20%20%20exit%201%0A%7D%0A%0Awget%20-P%20%2Fhome%2F%24%7BREMOTE_USER%7D%20https%3A%2F%2Fgithub.com%2Fkahkhang%2Fkube-linode%2Fraw%2Fbootkube%2Fbootkube.tar.gz%0Atar%20-xzvf%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fbootkube.tar.gz%20-C%20%2Fhome%2F%24%7BREMOTE_USER%7D%0Achmod%20%2Bx%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fbootkube%0Asudo%20systemctl%20start%20localstorage.service%0Ainit_master_node%0A",
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
        "name": "localstorage.service",
        "enable": true,
        "contents": "[Unit]\nDescription=command\n[Service]\nType=oneshot\nRemainAfterExit=true\nExecStart=/bin/sh -c 'for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]\$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done'\n"
      },
      {
        "name": "kubelet.service",
        "enable": true,
        "contents": "[Service]\nEnvironment=KUBELET_IMAGE_URL=quay.io/coreos/hyperkube\nEnvironment=KUBELET_IMAGE_TAG=v1.7.0_coreos.0\nEnvironment=\"RKT_RUN_ARGS=\\\n--uuid-file-save=/var/cache/kubelet-pod.uuid \\\n--volume etc-resolv,kind=host,source=/etc/resolv.conf --mount volume=etc-resolv,target=/etc/resolv.conf \\\n--volume opt-cni-bin,kind=host,source=/opt/cni/bin --mount volume=opt-cni-bin,target=/opt/cni/bin \\\n--volume var-log,kind=host,source=/var/log --mount volume=var-log,target=/var/log \\\n--volume var-lib-cni,kind=host,source=/var/lib/cni --mount volume=var-lib-cni,target=/var/lib/cni \\\n--volume local-storage,kind=host,source=/mnt/disks --mount volume=local-storage,target=/mnt/disks\"\nEnvironmentFile=/etc/environment\nExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests\nExecStartPre=/bin/mkdir -p /opt/cni/bin\nExecStartPre=/bin/mkdir -p /etc/kubernetes/cni/net.d\nExecStartPre=/bin/mkdir -p /etc/kubernetes/checkpoint-secrets\nExecStartPre=/bin/mkdir -p /etc/kubernetes/inactive-manifests\nExecStartPre=/bin/mkdir -p /var/lib/cni\nExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/cache/kubelet-pod.uuid\nExecStartPre=/usr/bin/mkdir -p /mnt/disks\nExecStart=/usr/lib/coreos/kubelet-wrapper \\\n  --allow-privileged \\\n  --anonymous-auth=false \\\n  --client-ca-file=/etc/kubernetes/ca.crt \\\n  --cloud-provider= \\\n  --cluster_dns=10.3.0.10 \\\n  --cluster_domain=cluster.local \\\n  --cni-conf-dir=/etc/kubernetes/cni/net.d \\\n  --exit-on-lock-contention \\\n  --hostname-override=\${COREOS_PUBLIC_IPV4} \\\n  --kubeconfig=/etc/kubernetes/kubeconfig \\\n  --lock-file=/var/run/lock/kubelet.lock \\\n  --minimum-container-ttl-duration=3m0s \\\n  --network-plugin=cni \\\n  --node-labels=node-role.kubernetes.io/master \\\n  --pod-manifest-path=/etc/kubernetes/manifests \\\n  --register-with-taints=node-role.kubernetes.io/master=:NoSchedule \\\n  --require-kubeconfig \\\n  --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true\nExecStop=-/usr/bin/rkt stop --uuid-file=/var/cache/kubelet-pod.uuid\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n"
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
        "name": "${USERNAME}",
        "sshAuthorizedKeys": [
          "$SSH_KEY"
        ],
        "create": {
          "groups": [
            "sudo",
            "docker",
            "systemd-journal"
          ],
          "shell": "/bin/bash"
        }
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
        "path": "/home/${USERNAME}/bootstrap.sh",
        "contents": {
          "source": "data:,%23!%2Fusr%2Fbin%2Fenv%20bash%0Aset%20-euo%20pipefail%0A%0AREMOTE_PORT%3D%24%7BREMOTE_PORT%3A-22%7D%0AREMOTE_USER%3D${USERNAME}%0AIDENT%3D%24%7BIDENT%3A-%24%7BHOME%7D%2F.ssh%2Fid_rsa%7D%0ATAG_MASTER%3D%24%7BTAG_MASTER%3A-false%7D%0ACLOUD_PROVIDER%3D%24%7BCLOUD_PROVIDER%3A-%7D%0A%0A%23%20Initialize%20a%20worker%20node%0Afunction%20init_worker_node()%20%7B%0A%0A%20%20%20%20%23%20Setup%20kubeconfig%0A%20%20%20%20mkdir%20-p%20%2Fetc%2Fkubernetes%0A%20%20%20%20cp%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fkubeconfig%20%2Fetc%2Fkubernetes%2Fkubeconfig%0A%20%20%20%20%23%20Pulled%20out%20of%20the%20kubeconfig.%20Other%20installations%20should%20place%20the%20root%0A%20%20%20%20%23%20CA%20here%20manually.%0A%20%20%20%20grep%20'certificate-authority-data'%20%2Fhome%2F%24%7BREMOTE_USER%7D%2Fkubeconfig%20%7C%20awk%20'%7Bprint%20%242%7D'%20%7C%20base64%20-d%20%3E%20%2Fetc%2Fkubernetes%2Fca.crt%0A%0A%20%20%20%20%23%20Set%20cloud%20provider%0A%20%20%20%20sed%20-i%20%22s%2Fcloud-provider%3D%2Fcloud-provider%3D%24CLOUD_PROVIDER%2F%22%20%2Fetc%2Fsystemd%2Fsystem%2Fkubelet.service%0A%0A%20%20%20%20%23%20Start%20services%0A%20%20%20%20systemctl%20daemon-reload%0A%20%20%20%20systemctl%20stop%20update-engine%3B%20systemctl%20mask%20update-engine%0A%20%20%20%20systemctl%20enable%20kubelet%3B%20sudo%20systemctl%20start%20kubelet%0A%7D%0A%0Asudo%20systemctl%20start%20localstorage.service%0Ainit_worker_node%0A",
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
        "name": "localstorage.service",
        "enable": true,
        "contents": "[Unit]\nDescription=command\n[Service]\nType=oneshot\nRemainAfterExit=true\nExecStart=/bin/sh -c 'for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]\$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done'\n"
      },
      {
        "name": "kubelet.service",
        "enable": true,
        "contents": "[Service]\nEnvironment=KUBELET_IMAGE_URL=quay.io/coreos/hyperkube\nEnvironment=KUBELET_IMAGE_TAG=v1.7.0_coreos.0\nEnvironment=\"RKT_RUN_ARGS=\\\n--uuid-file-save=/var/cache/kubelet-pod.uuid \\\n--volume etc-resolv,kind=host,source=/etc/resolv.conf --mount volume=etc-resolv,target=/etc/resolv.conf \\\n--volume opt-cni-bin,kind=host,source=/opt/cni/bin --mount volume=opt-cni-bin,target=/opt/cni/bin \\\n--volume var-log,kind=host,source=/var/log --mount volume=var-log,target=/var/log \\\n--volume var-lib-cni,kind=host,source=/var/lib/cni --mount volume=var-lib-cni,target=/var/lib/cni \\\n--volume local-storage,kind=host,source=/mnt/disks --mount volume=local-storage,target=/mnt/disks\"\nEnvironmentFile=/etc/environment\nExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests\nExecStartPre=/bin/mkdir -p /opt/cni/bin\nExecStartPre=/bin/mkdir -p /etc/kubernetes/cni/net.d\nExecStartPre=/bin/mkdir -p /var/lib/cni\nExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/cache/kubelet-pod.uuid\nExecStartPre=/usr/bin/mkdir -p /mnt/disks\nExecStart=/usr/lib/coreos/kubelet-wrapper \\\n  --allow-privileged \\\n  --anonymous-auth=false \\\n  --client-ca-file=/etc/kubernetes/ca.crt \\\n  --cloud-provider= \\\n  --cluster_dns=10.3.0.10 \\\n  --cluster_domain=cluster.local \\\n  --cni-conf-dir=/etc/kubernetes/cni/net.d \\\n  --exit-on-lock-contention \\\n  --hostname-override=\${COREOS_PUBLIC_IPV4} \\\n  --kubeconfig=/etc/kubernetes/kubeconfig \\\n  --lock-file=/var/run/lock/kubelet.lock \\\n  --minimum-container-ttl-duration=3m0s \\\n  --network-plugin=cni \\\n  --pod-manifest-path=/etc/kubernetes/manifests \\\n  --require-kubeconfig \\\n  --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true\nExecStop=-/usr/bin/rkt stop --uuid-file=/var/cache/kubelet-pod.uuid\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n"
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
        "name": "${USERNAME}",
        "sshAuthorizedKeys": [
          "$SSH_KEY"
        ],
        "create": {
          "groups": [
            "sudo",
            "docker",
            "systemd-journal"
          ],
          "shell": "/bin/bash"
        }
      }
    ]
  }
}
EOF
fi

# cat >> cloud-config.yaml <<-EOF
# write_files:
#   - path: /etc/environment
#     permissions: 0644
#     content: |
#       COREOS_PUBLIC_IPV4=${ADVERTISE_IP}
#       COREOS_PRIVATE_IPV4=${ADVERTISE_IP}
#   - path: "/etc/flannel/options.env"
#     permissions: 0644
#     owner: root:root
#     content: |
#       FLANNELD_IFACE=${ADVERTISE_IP}
#       FLANNELD_ETCD_ENDPOINTS=${ETCD_ENDPOINT}
#   - path: "/etc/systemd/system/flanneld.service.d/40-ExecStartPre-symlink.conf"
#     permissions: 0644
#     owner: root:root
#     content: |
#       [Service]
#       ExecStartPre=/usr/bin/ln -sf /etc/flannel/options.env /run/flannel/options.env
#   - path: "/etc/systemd/system/docker.service.d/40-flannel.conf"
#     permissions: 0644
#     owner: root:root
#     content: |
#       [Unit]
#       Requires=flanneld.service
#       After=flanneld.service
#       [Service]
#       EnvironmentFile=/etc/kubernetes/cni/docker_opts_cni.env
#   - path: "/etc/kubernetes/cni/docker_opts_cni.env"
#     owner: root:root
#     content: |
#       DOCKER_OPT_BIP=""
#       DOCKER_OPT_IPMASQ=""
#   - path: "/etc/kubernetes/cni/net.d/10-flannel.conf"
#     owner: root:root
#     content: |
#       {
#         "name": "podnet",
#         "type": "flannel",
#         "delegate": {
#             "isDefaultGateway": true
#         }
#       }
# EOF
#
# if [ "$NODE_TYPE" = "worker" ] ; then
# cat >> cloud-config.yaml <<-EOF
#   - path: "/etc/kubernetes/ssl/worker-key.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $WORKER_KEY_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/worker.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $WORKER_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/ca.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $CA_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/manifests/kube-proxy.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Pod
#       metadata:
#         name: kube-proxy
#         namespace: kube-system
#       spec:
#         hostNetwork: true
#         containers:
#         - name: kube-proxy
#           image: quay.io/coreos/hyperkube:${K8S_VER}
#           command:
#           - /hyperkube
#           - proxy
#           - --master=https://${MASTER_IP}:6443
#           - --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml
#           - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#           securityContext:
#             privileged: true
#           volumeMounts:
#           - mountPath: /etc/ssl/certs
#             name: "ssl-certs"
#           - mountPath: /etc/kubernetes/worker-kubeconfig.yaml
#             name: "kubeconfig"
#             readOnly: true
#           - mountPath: /etc/kubernetes/ssl
#             name: "etc-kube-ssl"
#             readOnly: true
#         volumes:
#         - name: "ssl-certs"
#           hostPath:
#             path: "/usr/share/ca-certificates"
#         - name: "kubeconfig"
#           hostPath:
#             path: "/etc/kubernetes/worker-kubeconfig.yaml"
#         - name: "etc-kube-ssl"
#           hostPath:
#             path: "/etc/kubernetes/ssl"
#   - path: "/etc/kubernetes/worker-kubeconfig.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Config
#       clusters:
#       - name: local
#         cluster:
#           certificate-authority: /etc/kubernetes/ssl/ca.pem
#       users:
#       - name: kubelet
#         user:
#           client-certificate: /etc/kubernetes/ssl/worker.pem
#           client-key: /etc/kubernetes/ssl/worker-key.pem
#       contexts:
#       - context:
#           cluster: local
#           user: kubelet
#         name: kubelet-context
#       current-context: kubelet-context
#   - path: "/home/${USERNAME}/bootstrap.sh"
#     owner: ${USERNAME}:${USERNAME}
#     permissions: 0700
#     content: |
#       GREEN=\$(tput setaf 2)
#       CYAN=\$(tput setaf 6)
#       NORMAL=\$(tput sgr0)
#       BOLD=\$(tput bold)
#       YELLOW=\$(tput setaf 3)
#
#       _SPINNER_POS=0
#       _TASK_OUTPUT=""
#       spinner() {
#           _TASK_OUTPUT=""
#           local delay=0.05
#           local list=( \$(echo -e '\xe2\xa0\x8b')
#                        \$(echo -e '\xe2\xa0\x99')
#                        \$(echo -e '\xe2\xa0\xb9')
#                        \$(echo -e '\xe2\xa0\xb8')
#                        \$(echo -e '\xe2\xa0\xbc')
#                        \$(echo -e '\xe2\xa0\xb4')
#                        \$(echo -e '\xe2\xa0\xa6')
#                        \$(echo -e '\xe2\xa0\xa7')
#                        \$(echo -e '\xe2\xa0\x87')
#                        \$(echo -e '\xe2\xa0\x8f'))
#           local i=\$_SPINNER_POS
#           local tempfile
#           tempfile=\$(mktemp)
#
#           eval \$2 >> \$tempfile 2>/dev/null &
#           local pid=\$!
#
#           tput sc
#           printf "%s %s" "\${list[i]}" "\$1"
#           tput el
#           tput rc
#
#           i=\$((\$i+1))
#           i=\$((\$i%10))
#
#           while [ "\$(ps a | awk '{print \$1}' | grep \$pid)" ]; do
#               printf "%s" "\${list[i]}"
#               i=\$((\$i+1))
#               i=\$((\$i%10))
#               sleep \$delay
#               printf "\b\b\b"
#           done
#           _TASK_OUTPUT="\$(cat \$tempfile)"
#           rm \$tempfile
#           _SPINNER_POS=\$i
#
#           if [ -z \$3 ]; then :; else
#             eval \$3=\'"\$_TASK_OUTPUT"\'
#           fi
#       }
#
#       start_flannel() {
#         sudo systemctl daemon-reload
#
#         while ! sudo systemctl start flanneld >/dev/null 2>&1; do sleep 5 ; done
#         sudo systemctl enable flanneld >/dev/null 2>&1
#       }
#
#       start_kubelet() {
#         sudo systemctl start kubelet >/dev/null
#         sudo systemctl enable kubelet >/dev/null 2>&1
#       }
#
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Starting flannel (might take a while)" start_flannel
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Starting kubelet" start_kubelet
#       exit 0
# EOF
#
# cat >> cloud-config.yaml <<-EOF
# coreos:
#   units:
#   - name: localstorage.service
#     command: start
#     content: |
#        [Unit]
#        Description=command
#        [Service]
#        Type=oneshot
#        RemainAfterExit=true
#        ExecStart=/bin/sh -c "for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done"
#   - name: kubelet.service
#     command: start
#     content: |
#       [Service]
#       Environment=KUBELET_IMAGE_TAG=${K8S_VER}
#       Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
#         --volume dns,kind=host,source=/etc/resolv.conf \
#         --mount volume=dns,target=/etc/resolv.conf \
#         --volume var-log,kind=host,source=/var/log \
#         --mount volume=var-log,target=/var/log \
#         --volume local-storage,kind=host,source=/mnt/disks \
#         --mount volume=local-storage,target=/mnt/disks"
#       ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
#       ExecStartPre=/usr/bin/mkdir -p /var/log/containers
#       ExecStartPre=/usr/bin/mkdir -p /mnt/disks
#       ExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/run/kubelet-pod.uuid
#       ExecStart=/usr/lib/coreos/kubelet-wrapper \
#         --api-servers=https://${MASTER_IP}:6443 \
#         --cni-conf-dir=/etc/kubernetes/cni/net.d \
#         --network-plugin=cni \
#         --container-runtime=docker \
#         --register-node=true \
#         --allow-privileged=true \
#         --pod-manifest-path=/etc/kubernetes/manifests \
#         --hostname-override=${ADVERTISE_IP} \
#         --cluster_dns=${DNS_SERVICE_IP} \
#         --cluster_domain=cluster.local \
#         --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml \
#         --tls-cert-file=/etc/kubernetes/ssl/worker.pem \
#         --tls-private-key-file=/etc/kubernetes/ssl/worker-key.pem \
#         --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#       ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
#       Restart=always
#       RestartSec=10
#
#       [Install]
#       WantedBy=multi-user.target
# EOF
#
# fi
#
# if [ "$NODE_TYPE" = "master" ] ; then
# cat >> cloud-config.yaml <<-EOF
#   - path: "/etc/systemd/system/etcd2.service.d/40-listen-address.conf"
#     permissions: 0644
#     owner: root:root
#     content: |
#       [Service]
#       Environment=ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
#       Environment=ETCD_ADVERTISE_CLIENT_URLS=${ETCD_ENDPOINT}
#   - path: "/etc/traefik/acme/acme.json"
#     permissions: 0600
#     owner: root:root
#     content: |
#   - path: "/etc/kubernetes/ssl/admin-key.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $ADMIN_KEY_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/admin.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $ADMIN_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/apiserver-key.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $APISERVER_KEY_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/apiserver.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $APISERVER_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/ca-key.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $CA_KEY_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/ssl/ca.pem"
#     permissions: 0600
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $CA_CERT | base64 --decode | sed 's/^/      /' )
#   - path: "/etc/kubernetes/manifests/kube-apiserver.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Pod
#       metadata:
#         name: kube-apiserver
#         namespace: kube-system
#       spec:
#         hostNetwork: true
#         containers:
#         - name: kube-apiserver
#           image: quay.io/coreos/hyperkube:${K8S_VER}
#           command:
#           - /hyperkube
#           - apiserver
#           - --bind-address=0.0.0.0
#           - --etcd-servers=${ETCD_ENDPOINT}
#           - --allow-privileged=true
#           - --service-cluster-ip-range=${SERVICE_IP_RANGE}
#           - --advertise-address=${ADVERTISE_IP}
#           - --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota
#           - --tls-cert-file=/etc/kubernetes/ssl/apiserver.pem
#           - --tls-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem
#           - --client-ca-file=/etc/kubernetes/ssl/ca.pem
#           - --service-account-key-file=/etc/kubernetes/ssl/apiserver-key.pem
#           - --runtime-config=extensions/v1beta1/networkpolicies=true
#           - --anonymous-auth=false
#           - --storage-backend=etcd2
#           - --storage-media-type=application/json
#           - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#           livenessProbe:
#             httpGet:
#               host: 127.0.0.1
#               port: 8080
#               path: /healthz
#             initialDelaySeconds: 15
#             timeoutSeconds: 15
#           ports:
#           - containerPort: 6443
#             hostPort: 6443
#             name: https
#           - containerPort: 8080
#             hostPort: 8080
#             name: local
#           volumeMounts:
#           - mountPath: /etc/kubernetes/ssl
#             name: ssl-certs-kubernetes
#             readOnly: true
#           - mountPath: /etc/ssl/certs
#             name: ssl-certs-host
#             readOnly: true
#         volumes:
#         - hostPath:
#             path: /etc/kubernetes/ssl
#           name: ssl-certs-kubernetes
#         - hostPath:
#             path: /usr/share/ca-certificates
#           name: ssl-certs-host
#   - path: "/etc/kubernetes/manifests/kube-proxy.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Pod
#       metadata:
#         name: kube-proxy
#         namespace: kube-system
#       spec:
#         hostNetwork: true
#         containers:
#         - name: kube-proxy
#           image: quay.io/coreos/hyperkube:${K8S_VER}
#           command:
#           - /hyperkube
#           - proxy
#           - --master=http://127.0.0.1:8080
#           - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#           securityContext:
#             privileged: true
#           volumeMounts:
#           - mountPath: /etc/ssl/certs
#             name: ssl-certs-host
#             readOnly: true
#         volumes:
#         - hostPath:
#             path: /usr/share/ca-certificates
#           name: ssl-certs-host
#   - path: "/etc/kubernetes/manifests/kube-controller-manager.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Pod
#       metadata:
#         name: kube-controller-manager
#         namespace: kube-system
#       spec:
#         hostNetwork: true
#         containers:
#         - name: kube-controller-manager
#           image: quay.io/coreos/hyperkube:${K8S_VER}
#           command:
#           - /hyperkube
#           - controller-manager
#           - --master=http://127.0.0.1:8080
#           - --leader-elect=true
#           - --service-account-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem
#           - --root-ca-file=/etc/kubernetes/ssl/ca.pem
#           - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#           resources:
#             requests:
#               cpu: 200m
#           livenessProbe:
#             httpGet:
#               host: 127.0.0.1
#               path: /healthz
#               port: 10252
#             initialDelaySeconds: 15
#             timeoutSeconds: 15
#           volumeMounts:
#           - mountPath: /etc/kubernetes/ssl
#             name: ssl-certs-kubernetes
#             readOnly: true
#           - mountPath: /etc/ssl/certs
#             name: ssl-certs-host
#             readOnly: true
#         volumes:
#         - hostPath:
#             path: /etc/kubernetes/ssl
#           name: ssl-certs-kubernetes
#         - hostPath:
#             path: /usr/share/ca-certificates
#           name: ssl-certs-host
#   - path: "/etc/kubernetes/manifests/kube-scheduler.yaml"
#     owner: root:root
#     content: |
#       apiVersion: v1
#       kind: Pod
#       metadata:
#         name: kube-scheduler
#         namespace: kube-system
#       spec:
#         hostNetwork: true
#         containers:
#         - name: kube-scheduler
#           image: quay.io/coreos/hyperkube:${K8S_VER}
#           command:
#           - /hyperkube
#           - scheduler
#           - --master=http://127.0.0.1:8080
#           - --leader-elect=true
#           - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#           resources:
#             requests:
#               cpu: 100m
#           livenessProbe:
#             httpGet:
#               host: 127.0.0.1
#               path: /healthz
#               port: 10251
#             initialDelaySeconds: 15
#             timeoutSeconds: 15
#   - path: "/home/${USERNAME}/kube-dns.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: v1
#       kind: Service
#       metadata:
#         name: kube-dns
#         namespace: kube-system
#         labels:
#           k8s-app: kube-dns
#           kubernetes.io/cluster-service: "true"
#           kubernetes.io/name: "KubeDNS"
#       spec:
#         selector:
#           k8s-app: kube-dns
#         clusterIP: ${DNS_SERVICE_IP}
#         ports:
#         - name: dns
#           port: 53
#           protocol: UDP
#         - name: dns-tcp
#           port: 53
#           protocol: TCP
#       ---
#       apiVersion: v1
#       kind: ReplicationController
#       metadata:
#         name: kube-dns-v20
#         namespace: kube-system
#         labels:
#           k8s-app: kube-dns
#           version: v20
#           kubernetes.io/cluster-service: "true"
#       spec:
#         replicas: 1
#         selector:
#           k8s-app: kube-dns
#           version: v20
#         template:
#           metadata:
#             labels:
#               k8s-app: kube-dns
#               version: v20
#             annotations:
#               scheduler.alpha.kubernetes.io/critical-pod: ''
#               scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
#           spec:
#             containers:
#             - name: kubedns
#               image: gcr.io/google_containers/kubedns-amd64:1.8
#               resources:
#                 limits:
#                   memory: 170Mi
#                 requests:
#                   cpu: 100m
#                   memory: 70Mi
#               livenessProbe:
#                 httpGet:
#                   path: /healthz-kubedns
#                   port: 8080
#                   scheme: HTTP
#                 initialDelaySeconds: 60
#                 timeoutSeconds: 5
#                 successThreshold: 1
#                 failureThreshold: 5
#               readinessProbe:
#                 httpGet:
#                   path: /readiness
#                   port: 8081
#                   scheme: HTTP
#                 initialDelaySeconds: 3
#                 timeoutSeconds: 5
#               args:
#               - --domain=cluster.local.
#               - --dns-port=10053
#               ports:
#               - containerPort: 10053
#                 name: dns-local
#                 protocol: UDP
#               - containerPort: 10053
#                 name: dns-tcp-local
#                 protocol: TCP
#             - name: dnsmasq
#               image: gcr.io/google_containers/kube-dnsmasq-amd64:1.4
#               livenessProbe:
#                 httpGet:
#                   path: /healthz-dnsmasq
#                   port: 8080
#                   scheme: HTTP
#                 initialDelaySeconds: 60
#                 timeoutSeconds: 5
#                 successThreshold: 1
#                 failureThreshold: 5
#               args:
#               - --cache-size=1000
#               - --no-resolv
#               - --server=127.0.0.1#10053
#               - --log-facility=-
#               ports:
#               - containerPort: 53
#                 name: dns
#                 protocol: UDP
#               - containerPort: 53
#                 name: dns-tcp
#                 protocol: TCP
#             - name: healthz
#               image: gcr.io/google_containers/exechealthz-amd64:1.2
#               resources:
#                 limits:
#                   memory: 50Mi
#                 requests:
#                   cpu: 10m
#                   memory: 50Mi
#               args:
#               - --cmd=nslookup kubernetes.default.svc.cluster.local 127.0.0.1 >/dev/null
#               - --url=/healthz-dnsmasq
#               - --cmd=nslookup kubernetes.default.svc.cluster.local 127.0.0.1:10053 >/dev/null
#               - --url=/healthz-kubedns
#               - --port=8080
#               - --quiet
#               ports:
#               - containerPort: 8080
#                 protocol: TCP
#             dnsPolicy: Default
#   - path: "/home/${USERNAME}/heapster.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: extensions/v1beta1
#       kind: Deployment
#       metadata:
#         name: heapster
#         namespace: kube-system
#       spec:
#         replicas: 1
#         template:
#           metadata:
#             labels:
#               task: monitoring
#               k8s-app: heapster
#           spec:
#             serviceAccountName: heapster
#             containers:
#             - name: heapster
#               image: gcr.io/google_containers/heapster-amd64:v1.3.0
#               imagePullPolicy: IfNotPresent
#               command:
#               - /heapster
#               - --source=kubernetes:https://kubernetes.default
#       ---
#       apiVersion: v1
#       kind: Service
#       metadata:
#         labels:
#           task: monitoring
#           # For use as a Cluster add-on (https://github.com/kubernetes/kubernetes/tree/master/cluster/addons)
#           # If you are NOT using this as an addon, you should comment out this line.
#           kubernetes.io/cluster-service: 'true'
#           kubernetes.io/name: Heapster
#         name: heapster
#         namespace: kube-system
#       spec:
#         ports:
#         - port: 80
#           targetPort: 8082
#         selector:
#           k8s-app: heapster
#       ---
#       apiVersion: v1
#       kind: ServiceAccount
#       metadata:
#         name: heapster
#         namespace: kube-system
#   - path: "/home/${USERNAME}/kube-dashboard.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: v1
#       kind: ReplicationController
#       metadata:
#         name: kubernetes-dashboard-v1.6.1
#         namespace: kube-system
#         labels:
#           k8s-app: kubernetes-dashboard
#           version: v1.6.1
#           kubernetes.io/cluster-service: "true"
#       spec:
#         replicas: 1
#         selector:
#           k8s-app: kubernetes-dashboard
#         template:
#           metadata:
#             labels:
#               k8s-app: kubernetes-dashboard
#               version: v1.6.1
#               kubernetes.io/cluster-service: "true"
#             annotations:
#               scheduler.alpha.kubernetes.io/critical-pod: ''
#               scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
#           spec:
#             containers:
#             - name: kubernetes-dashboard
#               image: gcr.io/google_containers/kubernetes-dashboard-amd64:v1.6.1
#               resources:
#                 limits:
#                   cpu: 100m
#                   memory: 50Mi
#                 requests:
#                   cpu: 100m
#                   memory: 50Mi
#               ports:
#               - containerPort: 9090
#               livenessProbe:
#                 httpGet:
#                   path: /
#                   port: 9090
#                 initialDelaySeconds: 30
#                 timeoutSeconds: 30
#       ---
#       apiVersion: extensions/v1beta1
#       kind: Ingress
#       metadata:
#         name: dashboard-ingress
#         namespace: kube-system
#         annotations:
#           kubernetes.io/ingress.class: "traefik"
#           ingress.kubernetes.io/auth-type: "basic"
#           ingress.kubernetes.io/auth-secret: "kubesecret"
#       spec:
#         rules:
#           - host: kube.${DOMAIN}
#             http:
#               paths:
#                 - backend:
#                     serviceName: kubernetes-dashboard
#                     servicePort: 80
#           - host: traefik.${DOMAIN}
#             http:
#               paths:
#                 - backend:
#                     serviceName: traefik-console
#                     servicePort: webui
#       ---
#       apiVersion: v1
#       kind: Service
#       metadata:
#         name: kubernetes-dashboard
#         namespace: kube-system
#         labels:
#           k8s-app: kubernetes-dashboard
#           kubernetes.io/cluster-service: "true"
#       spec:
#         selector:
#           k8s-app: kubernetes-dashboard
#         ports:
#         - port: 80
#           targetPort: 9090
#   - path: "/home/${USERNAME}/traefik.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: v1
#       kind: Service
#       metadata:
#         name: traefik
#         namespace: kube-system
#         labels:
#           k8s-app: traefik-ingress-lb
#       spec:
#         selector:
#           k8s-app: traefik-ingress-lb
#         ports:
#           - port: 80
#             name: http
#           - port: 443
#             name: https
#         externalIPs:
#           - ${MASTER_IP}
#       ---
#       apiVersion: v1
#       kind: Service
#       metadata:
#         name: traefik-console
#         namespace: kube-system
#         labels:
#           k8s-app: traefik-ingress-lb
#       spec:
#         selector:
#           k8s-app: traefik-ingress-lb
#         ports:
#           - port: 8080
#             name: webui
#       ---
#       apiVersion: v1
#       kind: ConfigMap
#       metadata:
#         name: traefik-conf
#         namespace: kube-system
#       data:
#         traefik.toml: |
#           # traefik.toml
#           defaultEntryPoints = ["http","https"]
#           [entryPoints]
#             [entryPoints.http]
#             address = ":80"
#             [entryPoints.http.redirect]
#             entryPoint = "https"
#             [entryPoints.https]
#             address = ":443"
#             [entryPoints.https.tls]
#           [acme]
#           email = "$EMAIL"
#           storageFile = "/acme/acme.json"
#           entryPoint = "https"
#           onDemand = true
#           onHostRule = true
#           caServer = "https://acme-v01.api.letsencrypt.org/directory"
#           [[acme.domains]]
#           main = "${DOMAIN}"
#       ---
#       apiVersion: extensions/v1beta1
#       kind: Deployment
#       metadata:
#         name: traefik-ingress-controller
#         namespace: kube-system
#         labels:
#           k8s-app: traefik-ingress-lb
#       spec:
#         replicas: 1
#         revisionHistoryLimit: 0
#         template:
#           metadata:
#             labels:
#               k8s-app: traefik-ingress-lb
#               name: traefik-ingress-lb
#           spec:
#             terminationGracePeriodSeconds: 60
#             volumes:
#               - name: config
#                 configMap:
#                   name: traefik-conf
#               - name: acme
#                 hostPath:
#                   path: /etc/traefik/acme/acme.json
#             containers:
#               - image: containous/traefik:experimental
#                 name: traefik-ingress-lb
#                 imagePullPolicy: Always
#                 volumeMounts:
#                   - mountPath: "/config"
#                     name: "config"
#                   - mountPath: "/acme/acme.json"
#                     name: "acme"
#                 ports:
#                   - containerPort: 80
#                     hostPort: 80
#                   - containerPort: 443
#                     hostPort: 443
#                   - containerPort: 8080
#                 args:
#                   - --configfile=/config/traefik.toml
#                   - --web
#                   - --kubernetes
#                   - --logLevel=DEBUG
#   - path: "/home/${USERNAME}/local-storage-admin.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: v1
#       kind: ServiceAccount
#       metadata:
#         name: local-storage-admin
#         namespace: kube-system
#       ---
#       apiVersion: rbac.authorization.k8s.io/v1beta1
#       kind: ClusterRoleBinding
#       metadata:
#         name: local-storage-provisioner-pv-binding
#         namespace: kube-system
#       subjects:
#       - kind: ServiceAccount
#         name: local-storage-admin
#         namespace: kube-system
#       roleRef:
#         kind: ClusterRole
#         name: system:persistent-volume-provisioner
#         apiGroup: rbac.authorization.k8s.io
#       ---
#       apiVersion: rbac.authorization.k8s.io/v1beta1
#       kind: ClusterRoleBinding
#       metadata:
#         name: local-storage-provisioner-node-binding
#         namespace: kube-system
#       subjects:
#       - kind: ServiceAccount
#         name: local-storage-admin
#         namespace: kube-system
#       roleRef:
#         kind: ClusterRole
#         name: system:node
#         apiGroup: rbac.authorization.k8s.io
#   - path: "/home/${USERNAME}/local-storage-provisioner.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       apiVersion: extensions/v1beta1
#       kind: DaemonSet
#       metadata:
#         name: local-volume-provisioner
#         namespace: kube-system
#       spec:
#         template:
#           metadata:
#             labels:
#               app: local-volume-provisioner
#           spec:
#             containers:
#             - name: provisioner
#               image: "quay.io/external_storage/local-volume-provisioner:latest"
#               imagePullPolicy: Always
#               securityContext:
#                 privileged: true
#               volumeMounts:
#               - name: discovery-vol
#                 mountPath: "/local-disks"
#               env:
#               - name: MY_NODE_NAME
#                 valueFrom:
#                   fieldRef:
#                     fieldPath: spec.nodeName
#             volumes:
#             - name: discovery-vol
#               hostPath:
#                 path: "/mnt/disks"
#             serviceAccount: local-storage-admin
#   - path: "/home/${USERNAME}/local-storage-class.yaml"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
#       kind: StorageClass
#       apiVersion: storage.k8s.io/v1
#       metadata:
#         name: local-storage
#         annotations:
#           storageclass.kubernetes.io/is-default-class: "true"
#       provisioner: "local-storage"
#   - path: "/home/${USERNAME}/auth"
#     owner: ${USERNAME}:${USERNAME}
#     content: |
# $( echo $AUTH | base64 --decode | sed 's/^/      /' )
#   - path: "/home/${USERNAME}/bootstrap.sh"
#     owner: ${USERNAME}:${USERNAME}
#     permissions: 0700
#     content: |
#       GREEN=\$(tput setaf 2)
#       CYAN=\$(tput setaf 6)
#       NORMAL=\$(tput sgr0)
#       BOLD=\$(tput bold)
#       YELLOW=\$(tput setaf 3)
#
#       _SPINNER_POS=0
#       _TASK_OUTPUT=""
#       spinner() {
#           _TASK_OUTPUT=""
#           local delay=0.05
#           local list=( \$(echo -e '\xe2\xa0\x8b')
#                        \$(echo -e '\xe2\xa0\x99')
#                        \$(echo -e '\xe2\xa0\xb9')
#                        \$(echo -e '\xe2\xa0\xb8')
#                        \$(echo -e '\xe2\xa0\xbc')
#                        \$(echo -e '\xe2\xa0\xb4')
#                        \$(echo -e '\xe2\xa0\xa6')
#                        \$(echo -e '\xe2\xa0\xa7')
#                        \$(echo -e '\xe2\xa0\x87')
#                        \$(echo -e '\xe2\xa0\x8f'))
#           local i=\$_SPINNER_POS
#           local tempfile
#           tempfile=\$(mktemp)
#
#           eval \$2 >> \$tempfile 2>/dev/null &
#           local pid=\$!
#
#           tput sc
#           printf "%s %s" "\${list[i]}" "\$1"
#           tput el
#           tput rc
#
#           i=\$((\$i+1))
#           i=\$((\$i%10))
#
#           while [ "\$(ps a | awk '{print \$1}' | grep \$pid)" ]; do
#               printf "%s" "\${list[i]}"
#               i=\$((\$i+1))
#               i=\$((\$i%10))
#               sleep \$delay
#               printf "\b\b\b"
#           done
#           _TASK_OUTPUT="\$(cat \$tempfile)"
#           rm \$tempfile
#           _SPINNER_POS=\$i
#
#           if [ -z \$3 ]; then :; else
#             eval \$3=\'"\$_TASK_OUTPUT"\'
#           fi
#       }
#
#       install_kubectl() {
#         wget -q https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
#         chmod +x kubectl
#         sudo mkdir -p /opt/bin
#         sudo mv kubectl /opt/bin/kubectl
#         export PATH=\$PATH:/opt/bin
#       }
#
#       start_etcd() {
#         sudo systemctl start etcd2 >/dev/null
#         sudo systemctl enable etcd2 >/dev/null 2>&1
#         sudo systemctl daemon-reload >/dev/null
#         while ! curl -s -X PUT -d "value={\"Network\":\"10.2.0.0/16\",\"Backend\":{\"Type\":\"vxlan\"}}" "${ETCD_ENDPOINT}/v2/keys/coreos.com/network/config" >/dev/null ; do sleep 5 ; done
#       }
#
#       start_flannel() {
#         while ! sudo systemctl start flanneld >/dev/null 2>&1; do sleep 5 ; done
#         sudo systemctl enable flanneld >/dev/null 2>&1
#       }
#
#       set_kubectl_defaults() {
#         kubectl config set-cluster ${USERNAME}-cluster --server=https://${MASTER_IP}:6443 --certificate-authority=/etc/kubernetes/ssl/ca.pem >/dev/null
#         kubectl config set-credentials ${USERNAME} --certificate-authority=/etc/kubernetes/ssl/ca.pem --client-key=/etc/kubernetes/ssl/admin-key.pem --client-certificate=/etc/kubernetes/ssl/admin.pem >/dev/null
#         kubectl config set-context default-context --cluster=${USERNAME}-cluster --user=${USERNAME} >/dev/null
#         kubectl config use-context default-context >/dev/null
#       }
#
#       start_kubelet() {
#         sudo systemctl start kubelet >/dev/null
#         sudo systemctl enable kubelet >/dev/null 2>&1
#         while ! curl -s http://127.0.0.1:8080/version >/dev/null 2>&1; do sleep 5 ; done
#         sleep 20
#       }
#
#       start_kube_dns() {
#         kubectl create -f kube-dns.yaml >/dev/null 2>&1
#         while ! kubectl get pods --namespace=kube-system | grep kube-dns | grep Running >/dev/null 2>&1; do sleep 5 ; done
#         sleep 10
#       }
#
#       create_kube_secret() {
#         kubectl --namespace=kube-system create secret generic kubesecret --from-file /home/${USERNAME}/auth >/dev/null
#       }
#
#       install_traefik() {
#         kubectl create -f /home/${USERNAME}/traefik.yaml >/dev/null 2>&1
#         while ! kubectl get pods --namespace=kube-system | grep traefik | grep Running >/dev/null 2>&1; do sleep 5 ; done
#         sleep 10
#       }
#
#       install_heapster() {
#         kubectl create -f heapster.yaml >/dev/null 2>&1
#         while ! kubectl get pods --namespace=kube-system | grep heapster | grep Running >/dev/null 2>&1; do sleep 5 ; done
#       }
#
#       install_kube_dashboard() {
#         kubectl create -f kube-dashboard.yaml >/dev/null 2>&1
#         while ! kubectl get pods --namespace=kube-system | grep dashboard | grep Running >/dev/null 2>&1; do sleep 5 ; done
#       }
#
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing kubectl" install_kubectl
#       export PATH=\$PATH:/opt/bin
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Starting etcd" start_etcd
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Starting flannel (might take a while)" start_flannel
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Setting defaults for kubectl" set_kubectl_defaults
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Starting kubelet (might take a while)" start_kubelet
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing kube-dns" start_kube_dns
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Creating kube-secret" create_kube_secret
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing traefik" install_traefik
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing heapster" install_heapster
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing kube-dashboard" install_kube_dashboard
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing local storage class" "kubectl create -f local-storage-class.yaml >/dev/null 2>&1"
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Creating local storage admin" "kubectl create -f local-storage-admin.yaml >/dev/null 2>&1"
#       spinner "\${CYAN}[$LINODE_ID]\${NORMAL} Installing local storage provisioner" "kubectl create -f local-storage-provisioner.yaml >/dev/null 2>&1"
#       exit 0
# EOF
#
# cat >> cloud-config.yaml <<-EOF
# coreos:
#   units:
#   - name: localstorage.service
#     command: start
#     content: |
#        [Unit]
#        Description=command
#        [Service]
#        Type=oneshot
#        RemainAfterExit=true
#        ExecStart=/bin/sh -c "for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done"
#   - name: kubelet.service
#     command: start
#     content: |
#       [Service]
#       Environment=KUBELET_IMAGE_TAG=${K8S_VER}
#       Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
#         --volume var-log,kind=host,source=/var/log \
#         --mount volume=var-log,target=/var/log \
#         --volume dns,kind=host,source=/etc/resolv.conf \
#         --mount volume=dns,target=/etc/resolv.conf \
#         --volume local-storage,kind=host,source=/mnt/disks \
#         --mount volume=local-storage,target=/mnt/disks"
#       ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
#       ExecStartPre=/usr/bin/mkdir -p /var/log/containers
#       ExecStartPre=/usr/bin/mkdir -p /mnt/disks
#       ExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/run/kubelet-pod.uuid
#       ExecStart=/usr/lib/coreos/kubelet-wrapper \
#       --api-servers=http://127.0.0.1:8080 \
#       --register-schedulable=true \
#       --cni-conf-dir=/etc/kubernetes/cni/net.d \
#       --network-plugin=cni \
#       --container-runtime=docker \
#       --allow-privileged=true \
#       --pod-manifest-path=/etc/kubernetes/manifests \
#       --hostname-override=${ADVERTISE_IP} \
#       --cluster_dns=${DNS_SERVICE_IP} \
#       --cluster_domain=cluster.local \
#       --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
#       ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
#       Restart=always
#       RestartSec=10
#
#       [Install]
#       WantedBy=multi-user.target
# EOF
# fi

apt-get -y install gawk
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
chmod u+x coreos-install
./coreos-install -d /dev/sda -i container-linux-config.json
reboot
