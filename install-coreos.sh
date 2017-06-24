#!/bin/bash
cd root || exit
exec >install.out 2>&1
cat > cloud-config.yaml <<-EOF
#cloud-config
users:
  - name: ${USERNAME}
    ssh-authorized-keys:
      - "$SSH_KEY"
    groups:
      - "sudo"
      - "docker"
      - "systemd-journal"
    shell: /bin/bash
EOF

cat >> cloud-config.yaml <<-EOF
write_files:
  - path: "/etc/flannel/options.env"
    permissions: 0644
    owner: root:root
    content: |
      FLANNELD_IFACE=${ADVERTISE_IP}
      FLANNELD_ETCD_ENDPOINTS=${ETCD_ENDPOINT}
  - path: "/etc/systemd/system/flanneld.service.d/40-ExecStartPre-symlink.conf"
    permissions: 0644
    owner: root:root
    content: |
      [Service]
      ExecStartPre=/usr/bin/ln -sf /etc/flannel/options.env /run/flannel/options.env
  - path: "/etc/systemd/system/docker.service.d/40-flannel.conf"
    permissions: 0644
    owner: root:root
    content: |
      [Unit]
      Requires=flanneld.service
      After=flanneld.service
      [Service]
      EnvironmentFile=/etc/kubernetes/cni/docker_opts_cni.env
  - path: "/etc/kubernetes/cni/docker_opts_cni.env"
    owner: root:root
    content: |
      DOCKER_OPT_BIP=""
      DOCKER_OPT_IPMASQ=""
  - path: "/etc/kubernetes/cni/net.d/10-flannel.conf"
    owner: root:root
    content: |
      {
        "name": "podnet",
        "type": "flannel",
        "delegate": {
            "isDefaultGateway": true
        }
      }
EOF

if [ "$NODE_TYPE" = "worker" ] ; then
cat >> cloud-config.yaml <<-EOF
  - path: "/etc/kubernetes/ssl/worker-key.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $WORKER_KEY_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/worker.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $WORKER_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/ca.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $CA_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/manifests/kube-proxy.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-proxy
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-proxy
          image: quay.io/coreos/hyperkube:${K8S_VER}
          command:
          - /hyperkube
          - proxy
          - --master=https://${MASTER_IP}:6443
          - --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml
          - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
          securityContext:
            privileged: true
          volumeMounts:
          - mountPath: /etc/ssl/certs
            name: "ssl-certs"
          - mountPath: /etc/kubernetes/worker-kubeconfig.yaml
            name: "kubeconfig"
            readOnly: true
          - mountPath: /etc/kubernetes/ssl
            name: "etc-kube-ssl"
            readOnly: true
        volumes:
        - name: "ssl-certs"
          hostPath:
            path: "/usr/share/ca-certificates"
        - name: "kubeconfig"
          hostPath:
            path: "/etc/kubernetes/worker-kubeconfig.yaml"
        - name: "etc-kube-ssl"
          hostPath:
            path: "/etc/kubernetes/ssl"
  - path: "/etc/kubernetes/worker-kubeconfig.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Config
      clusters:
      - name: local
        cluster:
          certificate-authority: /etc/kubernetes/ssl/ca.pem
      users:
      - name: kubelet
        user:
          client-certificate: /etc/kubernetes/ssl/worker.pem
          client-key: /etc/kubernetes/ssl/worker-key.pem
      contexts:
      - context:
          cluster: local
          user: kubelet
        name: kubelet-context
      current-context: kubelet-context
  - path: "/home/${USERNAME}/bootstrap.sh"
    owner: ${USERNAME}:${USERNAME}
    permissions: 0700
    content: |
      GREEN=\$(tput setaf 2)
      CYAN=\$(tput setaf 6)
      NORMAL=\$(tput sgr0)
      BOLD=\$(tput bold)
      YELLOW=\$(tput setaf 3)

      _spinner() {
          local on_success=" Completed "
          local on_fail="  Failed   "
          local green
          local red
          green="\$(tput setaf 2)"
          red="\$(tput setaf 5)"
          nc="\$(tput sgr0)"
          case \$1 in
              start)
                  let column=\$(tput cols)-\${#2}+10
                  echo -ne \${2}
                  printf "%\${column}s"
                  i=0
                  sp=( "[\$(echo -e '\xE2\x97\x8F')          ]"
                       "[ \$(echo -e '\xE2\x97\x8F')         ]"
                       "[  \$(echo -e '\xE2\x97\x8F')        ]"
                       "[   \$(echo -e '\xE2\x97\x8F')       ]"
                       "[    \$(echo -e '\xE2\x97\x8F')      ]"
                       "[     \$(echo -e '\xE2\x97\x8F')     ]"
                       "[      \$(echo -e '\xE2\x97\x8F')    ]"
                       "[       \$(echo -e '\xE2\x97\x8F')   ]"
                       "[        \$(echo -e '\xE2\x97\x8F')  ]"
                       "[         \$(echo -e '\xE2\x97\x8F') ]"
                       "[          \$(echo -e '\xE2\x97\x8F')]"
                       "[         \$(echo -e '\xE2\x97\x8F') ]"
                       "[        \$(echo -e '\xE2\x97\x8F')  ]"
                       "[       \$(echo -e '\xE2\x97\x8F')   ]"
                       "[      \$(echo -e '\xE2\x97\x8F')    ]"
                       "[     \$(echo -e '\xE2\x97\x8F')     ]"
                       "[    \$(echo -e '\xE2\x97\x8F')      ]"
                       "[   \$(echo -e '\xE2\x97\x8F')       ]"
                       "[  \$(echo -e '\xE2\x97\x8F')        ]"
                       "[ \$(echo -e '\xE2\x97\x8F')         ]"
                       "[\$(echo -e '\xE2\x97\x8F')          ]")
                  delay=0.04

                  while :
                  do
                      printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\${sp[i]}"
                      i=\$((i+1))
                      i=\$((i%20))
                      sleep \$delay
                  done
                  ;;
              stop)
                  if [[ -z \${3} ]]; then
                      echo "spinner is not running.."
                      exit 1
                  fi

                  kill \$3 > /dev/null 2>&1
                  echo -ne "\r"
                  echo -ne "\${4}"
                  let column=\$(tput cols)-\${#4}+10
                  printf "%\${column}s"
                  # inform the user uppon success or failure
                  echo -en "\b\b\b\b\b\b\b\b\b\b\b\b\b["
                  if [[ \$2 -eq 0 ]]; then
                      echo -en "\${green}\${on_success}\${nc}"
                  else
                      echo -en "\${red}\${on_fail}\${nc}"
                  fi
                  echo -e "]"
                  ;;
              update)
                  if [[ -z \${3} ]]; then
                      echo "spinner is not running.."
                      exit 1
                  fi
                  kill \$3 > /dev/null 2>&1
                  echo -ne "\r"
                  ;;
              *)
                  echo "invalid argument, try {start/stop}"
                  exit 1
                  ;;
          esac
      }

      start_spinner() {
          _spinner "start" "\${1}" &
          _sp_pid=\$!
          disown
      }

      stop_spinner() {
          _spinner "stop" 0 \$_sp_pid "\$1"
          unset _sp_pid
      }

      update_spinner() {
          _spinner "update" 0 \$_sp_pid
          unset _sp_pid
          start_spinner "\${1}"
      }

      echo_pending() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        start_spinner "\$str"
      }

      echo_update() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        update_spinner "\$str"
      }

      echo_completed() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        stop_spinner "\$str"
      }

      sudo systemctl daemon-reload
      echo_pending "Starting flannel (might take a while)"
      while ! sudo systemctl start flanneld >/dev/null 2>&1; do sleep 5 ; done
      sudo systemctl enable flanneld >/dev/null 2>&1

      echo_update "Starting kubelet"
      sudo systemctl start kubelet >/dev/null
      sudo systemctl enable kubelet >/dev/null 2>&1
      echo_completed "Provisioned worker node"
      exit 0
EOF

cat >> cloud-config.yaml <<-EOF
coreos:
  units:
  - name: localstorage.service
    command: start
    content: |
       [Unit]
       Description=command
       [Service]
       Type=oneshot
       RemainAfterExit=true
       ExecStart=/bin/sh -c "for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done"
  - name: kubelet.service
    command: start
    content: |
      [Service]
      Environment=KUBELET_IMAGE_TAG=${K8S_VER}
      Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
        --volume dns,kind=host,source=/etc/resolv.conf \
        --mount volume=dns,target=/etc/resolv.conf \
        --volume var-log,kind=host,source=/var/log \
        --mount volume=var-log,target=/var/log \
        --volume local-storage,kind=host,source=/mnt/disks \
        --mount volume=local-storage,target=/mnt/disks"
      ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
      ExecStartPre=/usr/bin/mkdir -p /var/log/containers
      ExecStartPre=/usr/bin/mkdir -p /mnt/disks
      ExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/run/kubelet-pod.uuid
      ExecStart=/usr/lib/coreos/kubelet-wrapper \
        --api-servers=https://${MASTER_IP}:6443 \
        --cni-conf-dir=/etc/kubernetes/cni/net.d \
        --network-plugin=cni \
        --container-runtime=docker \
        --register-node=true \
        --allow-privileged=true \
        --pod-manifest-path=/etc/kubernetes/manifests \
        --hostname-override=${ADVERTISE_IP} \
        --cluster_dns=${DNS_SERVICE_IP} \
        --cluster_domain=cluster.local \
        --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml \
        --tls-cert-file=/etc/kubernetes/ssl/worker.pem \
        --tls-private-key-file=/etc/kubernetes/ssl/worker-key.pem \
        --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
      ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
EOF

fi

if [ "$NODE_TYPE" = "master" ] ; then
cat >> cloud-config.yaml <<-EOF
  - path: "/etc/systemd/system/etcd2.service.d/40-listen-address.conf"
    permissions: 0644
    owner: root:root
    content: |
      [Service]
      Environment=ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      Environment=ETCD_ADVERTISE_CLIENT_URLS=${ETCD_ENDPOINT}
  - path: "/etc/traefik/acme/acme.json"
    permissions: 0600
    owner: root:root
    content: |
  - path: "/etc/kubernetes/ssl/admin-key.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $ADMIN_KEY_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/admin.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $ADMIN_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/apiserver-key.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $APISERVER_KEY_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/apiserver.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $APISERVER_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/ca-key.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $CA_KEY_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/ssl/ca.pem"
    permissions: 0600
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $CA_CERT | base64 --decode | sed 's/^/      /' )
  - path: "/etc/kubernetes/manifests/kube-apiserver.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-apiserver
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-apiserver
          image: quay.io/coreos/hyperkube:${K8S_VER}
          command:
          - /hyperkube
          - apiserver
          - --bind-address=0.0.0.0
          - --etcd-servers=${ETCD_ENDPOINT}
          - --allow-privileged=true
          - --service-cluster-ip-range=${SERVICE_IP_RANGE}
          - --advertise-address=${ADVERTISE_IP}
          - --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota
          - --tls-cert-file=/etc/kubernetes/ssl/apiserver.pem
          - --tls-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem
          - --client-ca-file=/etc/kubernetes/ssl/ca.pem
          - --service-account-key-file=/etc/kubernetes/ssl/apiserver-key.pem
          - --runtime-config=extensions/v1beta1/networkpolicies=true
          - --anonymous-auth=false
          - --storage-backend=etcd2
          - --storage-media-type=application/json
          - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              port: 8080
              path: /healthz
            initialDelaySeconds: 15
            timeoutSeconds: 15
          ports:
          - containerPort: 6443
            hostPort: 6443
            name: https
          - containerPort: 8080
            hostPort: 8080
            name: local
          volumeMounts:
          - mountPath: /etc/kubernetes/ssl
            name: ssl-certs-kubernetes
            readOnly: true
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /etc/kubernetes/ssl
          name: ssl-certs-kubernetes
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host
  - path: "/etc/kubernetes/manifests/kube-proxy.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-proxy
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-proxy
          image: quay.io/coreos/hyperkube:${K8S_VER}
          command:
          - /hyperkube
          - proxy
          - --master=http://127.0.0.1:8080
          - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
          securityContext:
            privileged: true
          volumeMounts:
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host
  - path: "/etc/kubernetes/manifests/kube-controller-manager.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-controller-manager
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-controller-manager
          image: quay.io/coreos/hyperkube:${K8S_VER}
          command:
          - /hyperkube
          - controller-manager
          - --master=http://127.0.0.1:8080
          - --leader-elect=true
          - --service-account-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem
          - --root-ca-file=/etc/kubernetes/ssl/ca.pem
          - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
          resources:
            requests:
              cpu: 200m
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              path: /healthz
              port: 10252
            initialDelaySeconds: 15
            timeoutSeconds: 15
          volumeMounts:
          - mountPath: /etc/kubernetes/ssl
            name: ssl-certs-kubernetes
            readOnly: true
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /etc/kubernetes/ssl
          name: ssl-certs-kubernetes
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host
  - path: "/etc/kubernetes/manifests/kube-scheduler.yaml"
    owner: root:root
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-scheduler
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-scheduler
          image: quay.io/coreos/hyperkube:${K8S_VER}
          command:
          - /hyperkube
          - scheduler
          - --master=http://127.0.0.1:8080
          - --leader-elect=true
          - --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
          resources:
            requests:
              cpu: 100m
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              path: /healthz
              port: 10251
            initialDelaySeconds: 15
            timeoutSeconds: 15
  - path: "/home/${USERNAME}/kube-dns.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: v1
      kind: Service
      metadata:
        name: kube-dns
        namespace: kube-system
        labels:
          k8s-app: kube-dns
          kubernetes.io/cluster-service: "true"
          kubernetes.io/name: "KubeDNS"
      spec:
        selector:
          k8s-app: kube-dns
        clusterIP: ${DNS_SERVICE_IP}
        ports:
        - name: dns
          port: 53
          protocol: UDP
        - name: dns-tcp
          port: 53
          protocol: TCP
      ---
      apiVersion: v1
      kind: ReplicationController
      metadata:
        name: kube-dns-v20
        namespace: kube-system
        labels:
          k8s-app: kube-dns
          version: v20
          kubernetes.io/cluster-service: "true"
      spec:
        replicas: 1
        selector:
          k8s-app: kube-dns
          version: v20
        template:
          metadata:
            labels:
              k8s-app: kube-dns
              version: v20
            annotations:
              scheduler.alpha.kubernetes.io/critical-pod: ''
              scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
          spec:
            containers:
            - name: kubedns
              image: gcr.io/google_containers/kubedns-amd64:1.8
              resources:
                limits:
                  memory: 170Mi
                requests:
                  cpu: 100m
                  memory: 70Mi
              livenessProbe:
                httpGet:
                  path: /healthz-kubedns
                  port: 8080
                  scheme: HTTP
                initialDelaySeconds: 60
                timeoutSeconds: 5
                successThreshold: 1
                failureThreshold: 5
              readinessProbe:
                httpGet:
                  path: /readiness
                  port: 8081
                  scheme: HTTP
                initialDelaySeconds: 3
                timeoutSeconds: 5
              args:
              - --domain=cluster.local.
              - --dns-port=10053
              ports:
              - containerPort: 10053
                name: dns-local
                protocol: UDP
              - containerPort: 10053
                name: dns-tcp-local
                protocol: TCP
            - name: dnsmasq
              image: gcr.io/google_containers/kube-dnsmasq-amd64:1.4
              livenessProbe:
                httpGet:
                  path: /healthz-dnsmasq
                  port: 8080
                  scheme: HTTP
                initialDelaySeconds: 60
                timeoutSeconds: 5
                successThreshold: 1
                failureThreshold: 5
              args:
              - --cache-size=1000
              - --no-resolv
              - --server=127.0.0.1#10053
              - --log-facility=-
              ports:
              - containerPort: 53
                name: dns
                protocol: UDP
              - containerPort: 53
                name: dns-tcp
                protocol: TCP
            - name: healthz
              image: gcr.io/google_containers/exechealthz-amd64:1.2
              resources:
                limits:
                  memory: 50Mi
                requests:
                  cpu: 10m
                  memory: 50Mi
              args:
              - --cmd=nslookup kubernetes.default.svc.cluster.local 127.0.0.1 >/dev/null
              - --url=/healthz-dnsmasq
              - --cmd=nslookup kubernetes.default.svc.cluster.local 127.0.0.1:10053 >/dev/null
              - --url=/healthz-kubedns
              - --port=8080
              - --quiet
              ports:
              - containerPort: 8080
                protocol: TCP
            dnsPolicy: Default
  - path: "/home/${USERNAME}/heapster.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: extensions/v1beta1
      kind: Deployment
      metadata:
        name: heapster
        namespace: kube-system
      spec:
        replicas: 1
        template:
          metadata:
            labels:
              task: monitoring
              k8s-app: heapster
          spec:
            serviceAccountName: heapster
            containers:
            - name: heapster
              image: gcr.io/google_containers/heapster-amd64:v1.3.0
              imagePullPolicy: IfNotPresent
              command:
              - /heapster
              - --source=kubernetes:https://kubernetes.default
      ---
      apiVersion: v1
      kind: Service
      metadata:
        labels:
          task: monitoring
          # For use as a Cluster add-on (https://github.com/kubernetes/kubernetes/tree/master/cluster/addons)
          # If you are NOT using this as an addon, you should comment out this line.
          kubernetes.io/cluster-service: 'true'
          kubernetes.io/name: Heapster
        name: heapster
        namespace: kube-system
      spec:
        ports:
        - port: 80
          targetPort: 8082
        selector:
          k8s-app: heapster
      ---
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: heapster
        namespace: kube-system
  - path: "/home/${USERNAME}/kube-dashboard.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: v1
      kind: ReplicationController
      metadata:
        name: kubernetes-dashboard-v1.6.1
        namespace: kube-system
        labels:
          k8s-app: kubernetes-dashboard
          version: v1.6.1
          kubernetes.io/cluster-service: "true"
      spec:
        replicas: 1
        selector:
          k8s-app: kubernetes-dashboard
        template:
          metadata:
            labels:
              k8s-app: kubernetes-dashboard
              version: v1.6.1
              kubernetes.io/cluster-service: "true"
            annotations:
              scheduler.alpha.kubernetes.io/critical-pod: ''
              scheduler.alpha.kubernetes.io/tolerations: '[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
          spec:
            containers:
            - name: kubernetes-dashboard
              image: gcr.io/google_containers/kubernetes-dashboard-amd64:v1.6.1
              resources:
                limits:
                  cpu: 100m
                  memory: 50Mi
                requests:
                  cpu: 100m
                  memory: 50Mi
              ports:
              - containerPort: 9090
              livenessProbe:
                httpGet:
                  path: /
                  port: 9090
                initialDelaySeconds: 30
                timeoutSeconds: 30
      ---
      apiVersion: extensions/v1beta1
      kind: Ingress
      metadata:
        name: dashboard-ingress
        namespace: kube-system
        annotations:
          kubernetes.io/ingress.class: "traefik"
          ingress.kubernetes.io/auth-type: "basic"
          ingress.kubernetes.io/auth-secret: "kubesecret"
      spec:
        rules:
          - host: kube.${DOMAIN}
            http:
              paths:
                - backend:
                    serviceName: kubernetes-dashboard
                    servicePort: 80
          - host: traefik.${DOMAIN}
            http:
              paths:
                - backend:
                    serviceName: traefik-console
                    servicePort: webui
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: kubernetes-dashboard
        namespace: kube-system
        labels:
          k8s-app: kubernetes-dashboard
          kubernetes.io/cluster-service: "true"
      spec:
        selector:
          k8s-app: kubernetes-dashboard
        ports:
        - port: 80
          targetPort: 9090
  - path: "/home/${USERNAME}/traefik.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: v1
      kind: Service
      metadata:
        name: traefik
        namespace: kube-system
        labels:
          k8s-app: traefik-ingress-lb
      spec:
        selector:
          k8s-app: traefik-ingress-lb
        ports:
          - port: 80
            name: http
          - port: 443
            name: https
        externalIPs:
          - ${MASTER_IP}
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: traefik-console
        namespace: kube-system
        labels:
          k8s-app: traefik-ingress-lb
      spec:
        selector:
          k8s-app: traefik-ingress-lb
        ports:
          - port: 8080
            name: webui
      ---
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: traefik-conf
        namespace: kube-system
      data:
        traefik.toml: |
          # traefik.toml
          defaultEntryPoints = ["http","https"]
          [entryPoints]
            [entryPoints.http]
            address = ":80"
            [entryPoints.http.redirect]
            entryPoint = "https"
            [entryPoints.https]
            address = ":443"
            [entryPoints.https.tls]
          [acme]
          email = "$EMAIL"
          storageFile = "/acme/acme.json"
          entryPoint = "https"
          onDemand = true
          onHostRule = true
          caServer = "https://acme-staging.api.letsencrypt.org/directory"
          [[acme.domains]]
          main = "${DOMAIN}"
      ---
      apiVersion: extensions/v1beta1
      kind: Deployment
      metadata:
        name: traefik-ingress-controller
        namespace: kube-system
        labels:
          k8s-app: traefik-ingress-lb
      spec:
        replicas: 1
        revisionHistoryLimit: 0
        template:
          metadata:
            labels:
              k8s-app: traefik-ingress-lb
              name: traefik-ingress-lb
          spec:
            terminationGracePeriodSeconds: 60
            volumes:
              - name: config
                configMap:
                  name: traefik-conf
              - name: acme
                hostPath:
                  path: /etc/traefik/acme/acme.json
            containers:
              - image: containous/traefik:experimental
                name: traefik-ingress-lb
                imagePullPolicy: Always
                volumeMounts:
                  - mountPath: "/config"
                    name: "config"
                  - mountPath: "/acme/acme.json"
                    name: "acme"
                ports:
                  - containerPort: 80
                    hostPort: 80
                  - containerPort: 443
                    hostPort: 443
                  - containerPort: 8080
                args:
                  - --configfile=/config/traefik.toml
                  - --web
                  - --kubernetes
                  - --logLevel=DEBUG
  - path: "/home/${USERNAME}/local-storage-admin.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: local-storage-admin
        namespace: kube-system
      ---
      apiVersion: rbac.authorization.k8s.io/v1beta1
      kind: ClusterRoleBinding
      metadata:
        name: local-storage-provisioner-pv-binding
        namespace: kube-system
      subjects:
      - kind: ServiceAccount
        name: local-storage-admin
        namespace: kube-system
      roleRef:
        kind: ClusterRole
        name: system:persistent-volume-provisioner
        apiGroup: rbac.authorization.k8s.io
      ---
      apiVersion: rbac.authorization.k8s.io/v1beta1
      kind: ClusterRoleBinding
      metadata:
        name: local-storage-provisioner-node-binding
        namespace: kube-system
      subjects:
      - kind: ServiceAccount
        name: local-storage-admin
        namespace: kube-system
      roleRef:
        kind: ClusterRole
        name: system:node
        apiGroup: rbac.authorization.k8s.io
  - path: "/home/${USERNAME}/local-storage-provisioner.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      apiVersion: extensions/v1beta1
      kind: DaemonSet
      metadata:
        name: local-volume-provisioner
        namespace: kube-system
      spec:
        template:
          metadata:
            labels:
              app: local-volume-provisioner
          spec:
            containers:
            - name: provisioner
              image: "quay.io/external_storage/local-volume-provisioner:latest"
              imagePullPolicy: Always
              securityContext:
                privileged: true
              volumeMounts:
              - name: discovery-vol
                mountPath: "/local-disks"
              env:
              - name: MY_NODE_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: spec.nodeName
            volumes:
            - name: discovery-vol
              hostPath:
                path: "/mnt/disks"
            serviceAccount: local-storage-admin
  - path: "/home/${USERNAME}/local-storage-class.yaml"
    owner: ${USERNAME}:${USERNAME}
    content: |
      kind: StorageClass
      apiVersion: storage.k8s.io/v1
      metadata:
        name: local-storage
        annotations:
          storageclass.kubernetes.io/is-default-class: "true"
      provisioner: "local-storage"
  - path: "/home/${USERNAME}/auth"
    owner: ${USERNAME}:${USERNAME}
    content: |
$( echo $AUTH | base64 --decode | sed 's/^/      /' )
  - path: "/home/${USERNAME}/bootstrap.sh"
    owner: ${USERNAME}:${USERNAME}
    permissions: 0700
    content: |
      GREEN=\$(tput setaf 2)
      CYAN=\$(tput setaf 6)
      NORMAL=\$(tput sgr0)
      BOLD=\$(tput bold)
      YELLOW=\$(tput setaf 3)

      _spinner() {
          local on_success=" Completed "
          local on_fail="  Failed   "
          local green
          local red
          green="\$(tput setaf 2)"
          red="\$(tput setaf 5)"
          nc="\$(tput sgr0)"
          case \$1 in
              start)
                  let column=\$(tput cols)-\${#2}+10
                  echo -ne \${2}
                  printf "%\${column}s"
                  i=0
                  sp=( "[\$(echo -e '\xE2\x97\x8F')          ]"
                       "[ \$(echo -e '\xE2\x97\x8F')         ]"
                       "[  \$(echo -e '\xE2\x97\x8F')        ]"
                       "[   \$(echo -e '\xE2\x97\x8F')       ]"
                       "[    \$(echo -e '\xE2\x97\x8F')      ]"
                       "[     \$(echo -e '\xE2\x97\x8F')     ]"
                       "[      \$(echo -e '\xE2\x97\x8F')    ]"
                       "[       \$(echo -e '\xE2\x97\x8F')   ]"
                       "[        \$(echo -e '\xE2\x97\x8F')  ]"
                       "[         \$(echo -e '\xE2\x97\x8F') ]"
                       "[          \$(echo -e '\xE2\x97\x8F')]"
                       "[         \$(echo -e '\xE2\x97\x8F') ]"
                       "[        \$(echo -e '\xE2\x97\x8F')  ]"
                       "[       \$(echo -e '\xE2\x97\x8F')   ]"
                       "[      \$(echo -e '\xE2\x97\x8F')    ]"
                       "[     \$(echo -e '\xE2\x97\x8F')     ]"
                       "[    \$(echo -e '\xE2\x97\x8F')      ]"
                       "[   \$(echo -e '\xE2\x97\x8F')       ]"
                       "[  \$(echo -e '\xE2\x97\x8F')        ]"
                       "[ \$(echo -e '\xE2\x97\x8F')         ]"
                       "[\$(echo -e '\xE2\x97\x8F')          ]")
                  delay=0.04

                  while :
                  do
                      printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\${sp[i]}"
                      i=\$((i+1))
                      i=\$((i%20))
                      sleep \$delay
                  done
                  ;;
              stop)
                  if [[ -z \${3} ]]; then
                      echo "spinner is not running.."
                      exit 1
                  fi

                  kill \$3 > /dev/null 2>&1
                  echo -ne "\r"
                  echo -ne "\${4}"
                  let column=\$(tput cols)-\${#4}+10
                  printf "%\${column}s"
                  # inform the user uppon success or failure
                  echo -en "\b\b\b\b\b\b\b\b\b\b\b\b\b["
                  if [[ \$2 -eq 0 ]]; then
                      echo -en "\${green}\${on_success}\${nc}"
                  else
                      echo -en "\${red}\${on_fail}\${nc}"
                  fi
                  echo -e "]"
                  ;;
              update)
                  if [[ -z \${3} ]]; then
                      echo "spinner is not running.."
                      exit 1
                  fi
                  kill \$3 > /dev/null 2>&1
                  echo -ne "\r"
                  ;;
              *)
                  echo "invalid argument, try {start/stop}"
                  exit 1
                  ;;
          esac
      }

      start_spinner() {
          _spinner "start" "\${1}" &
          _sp_pid=\$!
          disown
      }

      stop_spinner() {
          _spinner "stop" 0 \$_sp_pid "\$1"
          unset _sp_pid
      }

      update_spinner() {
          _spinner "update" 0 \$_sp_pid
          unset _sp_pid
          start_spinner "\${1}"
      }

      echo_pending() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        start_spinner "\$str"
      }

      echo_update() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        update_spinner "\$str"
      }

      echo_completed() {
        local str
        str="\${CYAN}[$LINODE_ID]\${NORMAL} \$1"
        stop_spinner "\$str"
      }

      echo_pending "Installing kubectl"
      wget -q https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
      chmod +x kubectl
      sudo mkdir -p /opt/bin
      sudo mv kubectl /opt/bin/kubectl
      export PATH=\$PATH:/opt/bin

      echo_update "Starting etcd"
      sudo systemctl start etcd2 >/dev/null
      sudo systemctl enable etcd2 >/dev/null 2>&1
      sudo systemctl daemon-reload >/dev/null
      while ! curl -s -X PUT -d "value={\"Network\":\"10.2.0.0/16\",\"Backend\":{\"Type\":\"vxlan\"}}" "${ETCD_ENDPOINT}/v2/keys/coreos.com/network/config" >/dev/null ; do sleep 5 ; done

      echo_update "Starting flannel (might take a while)"
      while ! sudo systemctl start flanneld >/dev/null 2>&1; do sleep 5 ; done
      sudo systemctl enable flanneld >/dev/null 2>&1

      echo_update "Setting defaults for kubectl"
      kubectl config set-cluster ${USERNAME}-cluster --server=https://${MASTER_IP}:6443 --certificate-authority=/etc/kubernetes/ssl/ca.pem >/dev/null
      kubectl config set-credentials ${USERNAME} --certificate-authority=/etc/kubernetes/ssl/ca.pem --client-key=/etc/kubernetes/ssl/admin-key.pem --client-certificate=/etc/kubernetes/ssl/admin.pem >/dev/null
      kubectl config set-context default-context --cluster=${USERNAME}-cluster --user=${USERNAME} >/dev/null
      kubectl config use-context default-context >/dev/null

      echo_update "Starting kubelet (might take a while)"
      sudo systemctl start kubelet >/dev/null
      sudo systemctl enable kubelet >/dev/null 2>&1
      while ! curl -s http://127.0.0.1:8080/version >/dev/null 2>&1; do sleep 5 ; done
      sleep 10

      echo_update "Installing kube-dns"
      kubectl create -f kube-dns.yaml >/dev/null 2>&1
      while ! kubectl get pods --namespace=kube-system | grep kube-dns | grep Running >/dev/null 2>&1; do sleep 5 ; done
      sleep 10

      echo_update "Creating kube-secret"
      kubectl --namespace=kube-system create secret generic kubesecret --from-file /home/${USERNAME}/auth >/dev/null

      echo_update "Installing traefik"
      kubectl create -f /home/${USERNAME}/traefik.yaml >/dev/null 2>&1
      while ! kubectl get pods --namespace=kube-system | grep traefik | grep Running >/dev/null 2>&1; do sleep 5 ; done
      sleep 10

      echo_update "Installing heapster"
      kubectl create -f heapster.yaml >/dev/null 2>&1
      while ! kubectl get pods --namespace=kube-system | grep heapster | grep Running >/dev/null 2>&1; do sleep 5 ; done

      echo_update "Installing kube-dashboard"
      kubectl create -f kube-dashboard.yaml >/dev/null 2>&1
      while ! kubectl get pods --namespace=kube-system | grep dashboard | grep Running >/dev/null 2>&1; do sleep 5 ; done

      echo_update "Installing local storage class"
      kubectl create -f local-storage-class.yaml >/dev/null 2>&1

      echo_update "Creating local storage admin"
      kubectl create -f local-storage-admin.yaml >/dev/null 2>&1

      echo_update "Installing local storage provisioner"
      kubectl create -f local-storage-provisioner.yaml >/dev/null 2>&1
      echo_completed "Provisioning master node"

      exit 0
EOF

cat >> cloud-config.yaml <<-EOF
coreos:
  units:
  - name: localstorage.service
    command: start
    content: |
       [Unit]
       Description=command
       [Service]
       Type=oneshot
       RemainAfterExit=true
       ExecStart=/bin/sh -c "for disk in \$( ls /dev -1 | grep '^sd[bcdefgh]$'); do mkdir -p /mnt/disks/\$disk; mount /dev/\$disk /mnt/disks/\$disk; echo Mounted disk \$disk; done"
  - name: kubelet.service
    command: start
    content: |
      [Service]
      Environment=KUBELET_IMAGE_TAG=${K8S_VER}
      Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
        --volume var-log,kind=host,source=/var/log \
        --mount volume=var-log,target=/var/log \
        --volume dns,kind=host,source=/etc/resolv.conf \
        --mount volume=dns,target=/etc/resolv.conf \
        --volume local-storage,kind=host,source=/mnt/disks \
        --mount volume=local-storage,target=/mnt/disks"
      ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
      ExecStartPre=/usr/bin/mkdir -p /var/log/containers
      ExecStartPre=/usr/bin/mkdir -p /mnt/disks
      ExecStartPre=-/usr/bin/rkt rm --uuid-file=/var/run/kubelet-pod.uuid
      ExecStart=/usr/lib/coreos/kubelet-wrapper \
      --api-servers=http://127.0.0.1:8080 \
      --register-schedulable=true \
      --cni-conf-dir=/etc/kubernetes/cni/net.d \
      --network-plugin=cni \
      --container-runtime=docker \
      --allow-privileged=true \
      --pod-manifest-path=/etc/kubernetes/manifests \
      --hostname-override=${ADVERTISE_IP} \
      --cluster_dns=${DNS_SERVICE_IP} \
      --cluster_domain=cluster.local \
      --feature-gates=PersistentLocalVolumes=true,AffinityInAnnotations=true
      ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
      Restart=always
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
EOF
fi

apt-get -y install gawk
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
chmod u+x coreos-install
./coreos-install -d /dev/sda -c cloud-config.yaml
reboot
