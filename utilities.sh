#!/bin/bash
# BSD 3-Clause License
# Modifications by Andrew Low, Copyright (C) 2017
# Copyright (c) 2016, APNIC Pty Ltd
# All rights reserved.

GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
NORMAL=$(tput sgr0)
BOLD=$(tput bold)
YELLOW=$(tput setaf 3)

check_dep() {
    command -v $1 >/dev/null 2>&1 || { echo "Please install \`${BOLD}$1${NORMAL}\` before running this script." >&2; exit 1; }
}

echo_pending() {
  local PADDING
  local STR_WITH_PADDING
  PADDING=$(printf '%0.1s' "."{1..94})
  STR_WITH_PADDING="${CYAN}${NORMAL}$1"
  if [ -z "$2" ]; then :; else
      STR_WITH_PADDING="${CYAN}[$2]${NORMAL} $1"
  fi
  printf "%s%s[%s]\n" "$STR_WITH_PADDING" "${PADDING:${#STR_WITH_PADDING}}" "${YELLOW}  Pending  ${NORMAL}"
}

echo_completed() {
  local PADDING
  local STR_WITH_PADDING
  PADDING=$(printf '%0.1s' "."{1..94})
  STR_WITH_PADDING="${CYAN}${NORMAL}$1"
  if [ -z "$2" ]; then :; else
      STR_WITH_PADDING="${CYAN}[$2]${NORMAL} $1"
  fi
  printf "%s%s[%s]\n" "$STR_WITH_PADDING" "${PADDING:${#STR_WITH_PADDING}}" "${GREEN} Completed ${NORMAL}"
}

linode_api() {
    args=(-F "api_action=$1") ; shift
    for arg in "$@" ; do
        args+=(-F "$arg")
    done
    curl -s -X POST "https://api.linode.com/"  -H 'cache-control: no-cache' \
         -H 'content-type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW' \
         -F "api_key=$API_KEY" "${args[@]}"
}

wait_jobs() {
    LINODE_ID=$1
    while true ; do
        if ( linode_api linode.job.list LinodeID=$LINODE_ID pendingOnly=1 | jq -Mje '.DATA == []' >/dev/null ) ; then
            break
        fi
        sleep 3
    done
}

wait_boot() {
    LINODE_ID=$1
    while true ; do
        if ( linode_api linode.job.list LinodeID=$LINODE_ID | jq ".DATA" | grep "Lassie initiated boot: CoreOS" >/dev/null ) ; then
            break
        fi
        sleep 3
    done
    sleep 10
}

get_status() {
  linode_api linode.list LinodeID=$1 | jq ".DATA" | jq -c ".[] | .STATUS" | sed -n 1p
}

list_worker_ids() {
  linode_api linode.list | jq ".DATA" | jq -c "[ .[] | select(.LPM_DISPLAYGROUP | contains (\"$DOMAIN\")) ]" | jq -c ".[] | select(.LABEL | startswith(\"worker_\")) | .LINODEID"
}

get_master_id() {
  linode_api linode.list | jq ".DATA" | jq -c "[ .[] | select(.LPM_DISPLAYGROUP | contains (\"$DOMAIN\")) ]" | jq -c ".[] | select(.LABEL | startswith(\"master_\")) | .LINODEID" | sed -n 1p
}

is_provisioned() {
  local IS_PROVISIONED=false
  if [ $( linode_api linode.list LinodeID=$1 | jq ".DATA" | jq -c ".[] | .LPM_DISPLAYGROUP == \"$DOMAIN\"") = true ] ; then
    IS_PROVISIONED=true
  fi
  echo $IS_PROVISIONED
}

reset_linode() {
    local LINODE_ID=$1
    local DISK_IDS
    local CONFIG_IDS
    local STATUS
    echo_pending "Retrieving current status" $LINODE_ID
    STATUS=$( get_status $LINODE_ID )
    echo_completed "Current status: $STATUS" $LINODE_ID

    if [ $STATUS = 1 ]; then
      echo_pending "Shutting down linode" $LINODE_ID
      linode_api linode.shutdown LinodeID=$LINODE_ID >/dev/null
      wait_jobs $LINODE_ID
      echo_completed "Shutdown command issued" $LINODE_ID
    fi

    echo_pending "Retrieving disk list" $LINODE_ID
    DISK_IDS=$( linode_api linode.disk.list LinodeID=$LINODE_ID | jq ".DATA" | jq -c ".[] | .DISKID" )
    echo_completed "Retrieved disk list" $LINODE_ID

    for DISK_ID in $DISK_IDS; do
        echo_pending "Deleting disk $DISK_ID" $LINODE_ID
        linode_api linode.disk.delete LinodeID=$LINODE_ID DiskID=$DISK_ID >/dev/null
        echo_completed "Deleted disk $DISK_ID" $LINODE_ID
    done

    echo_pending "Retrieving config list" $LINODE_ID
    CONFIG_IDS=$( linode_api linode.config.list LinodeID=$LINODE_ID | jq ".DATA" | jq -c ".[] | .ConfigID" )
    echo_completed "Retrieved config list" $LINODE_ID

    for CONFIG_ID in $CONFIG_IDS; do
        echo_pending "Deleting config $CONFIG_ID" $LINODE_ID
        linode_api linode.config.delete LinodeID=$LINODE_ID ConfigID=$CONFIG_ID >/dev/null
        echo_completed "Deleted config $CONFIG_ID" $LINODE_ID
    done

    echo_pending "Waiting for all jobs to complete" $LINODE_ID
    wait_jobs $LINODE_ID
    echo_completed "All jobs completed" $LINODE_ID
}

list_plans() {
  echo ""
  linode_api avail.linodeplans | jq ".DATA" | jq -r '.[] | [.PLANID, .RAM, .DISK, .PRICE] | @csv' | \
    awk -v FS="," 'BEGIN{print "--------------------------------------------------------";print "PlanID\tRAM (mb)\tDisk (gb)\tCost Per Month";print "--------------------------------------------------------"}{gsub(/"/g, "", $1); printf "%s\t%s\t\t%s\t\tUS\$%s%s",$1,$2,$3,$4,ORS}END{ print "--------------------------------------------------------" }'
}

grab_ip() {
  local LINODE_ID=$1
  local IP
  echo_pending "Retrieving IP Address" $LINODE_ID
  eval $( linode_api linode.ip.list LinodeID=$LINODE_ID | jq -Mje ".DATA[] | \
          if .ISPUBLIC==1 then \"PUBLIC_$LINODE_ID=\", .IPADDRESS \
          else \"PRIVATE_$LINODE_ID=\", .IPADDRESS, \"\\nHOSTNAME_$LINODE_ID=\", \
               .RDNS_NAME end, \"\\n\"" )
  IP="$( eval echo \$PUBLIC_$LINODE_ID )"
  echo_completed "IP Address: $IP" $LINODE_ID
}

gen_master_certs() {
  MASTER_IP=$1
  LINODE_ID=$2
  echo_pending "Generating master certificates" $LINODE_ID
  mkdir -p ~/.kube-linode/certs >/dev/null
  [ -e ~/.kube-linode/certs/openssl.cnf ] && rm ~/.kube-linode/certs/openssl.cnf >/dev/null
  cat > ~/.kube-linode/certs/openssl.cnf <<-EOF
    [req]
    req_extensions = v3_req
    distinguished_name = req_distinguished_name
    [req_distinguished_name]
    [ v3_req ]
    basicConstraints = CA:FALSE
    keyUsage = nonRepudiation, digitalSignature, keyEncipherment
    subjectAltName = @alt_names
    [alt_names]
    DNS.1 = kubernetes
    DNS.2 = kubernetes.default
    DNS.3 = kubernetes.default.svc
    DNS.4 = kubernetes.default.svc.cluster.local
    IP.1 = 10.3.0.1
    IP.2 = $MASTER_IP
EOF
  openssl genrsa -out ~/.kube-linode/certs/ca-key.pem 2048 >/dev/null 2>&1
  openssl req -x509 -new -nodes -key ~/.kube-linode/certs/ca-key.pem -days 10000 -out ~/.kube-linode/certs/ca.pem -subj "/CN=kube-ca" >/dev/null 2>&1
  openssl genrsa -out ~/.kube-linode/certs/apiserver-key.pem 2048 >/dev/null 2>&1
  openssl req -new -key ~/.kube-linode/certs/apiserver-key.pem -out ~/.kube-linode/certs/apiserver.csr -subj "/CN=kube-apiserver" -config ~/.kube-linode/certs/openssl.cnf >/dev/null 2>&1
  openssl x509 -req -in ~/.kube-linode/certs/apiserver.csr -CA ~/.kube-linode/certs/ca.pem -CAkey ~/.kube-linode/certs/ca-key.pem -CAcreateserial -out ~/.kube-linode/certs/apiserver.pem -days 365 -extensions v3_req -extfile ~/.kube-linode/certs/openssl.cnf >/dev/null 2>&1
  openssl genrsa -out ~/.kube-linode/certs/admin-key.pem 2048 >/dev/null 2>&1
  openssl req -new -key ~/.kube-linode/certs/admin-key.pem -out ~/.kube-linode/certs/admin.csr -subj "/CN=kube-admin" >/dev/null 2>&1
  openssl x509 -req -in ~/.kube-linode/certs/admin.csr -CA ~/.kube-linode/certs/ca.pem -CAkey ~/.kube-linode/certs/ca-key.pem -CAcreateserial -out ~/.kube-linode/certs/admin.pem -days 365 >/dev/null 2>&1
  echo_completed "Generated master certificates" $LINODE_ID
}

gen_worker_certs() {
  WORKER_FQDN=$1
  WORKER_IP=$1
  LINODE_ID=$2
  echo_pending "Generating worker certificates" $LINODE_ID
  if [ -f ~/.kube-linode/certs/worker-openssl.cnf ] ; then : ; else
      cat > ~/.kube-linode/certs/worker-openssl.cnf <<-EOF
        [req]
        req_extensions = v3_req
        distinguished_name = req_distinguished_name
        [req_distinguished_name]
        [ v3_req ]
        basicConstraints = CA:FALSE
        keyUsage = nonRepudiation, digitalSignature, keyEncipherment
        subjectAltName = @alt_names
        [alt_names]
        IP.1 = \$ENV::WORKER_IP
EOF
  fi

  openssl genrsa -out ~/.kube-linode/certs/${WORKER_FQDN}-worker-key.pem 2048 >/dev/null 2>&1
  WORKER_IP=${WORKER_IP} openssl req -new -key ~/.kube-linode/certs/${WORKER_FQDN}-worker-key.pem -out ~/.kube-linode/certs/${WORKER_FQDN}-worker.csr -subj "/CN=${WORKER_FQDN}" -config ~/.kube-linode/certs/worker-openssl.cnf >/dev/null 2>&1
  WORKER_IP=${WORKER_IP} openssl x509 -req -in ~/.kube-linode/certs/${WORKER_FQDN}-worker.csr -CA ~/.kube-linode/certs/ca.pem -CAkey ~/.kube-linode/certs/ca-key.pem -CAcreateserial -out ~/.kube-linode/certs/${WORKER_FQDN}-worker.pem -days 365 -extensions v3_req -extfile ~/.kube-linode/certs/worker-openssl.cnf >/dev/null 2>&1
  echo_pending "Generated worker certificates" $LINODE_ID
}

install() {
    local NODE_TYPE
    local LINODE_ID
    local PLAN
    local ROOT_PASSWORD
    local DISK_SIZE
    local COREOS_OLD_DISK_SIZE
    local COREOS_DISK_SIZE
    local STORAGE_DISK_SIZE
    NODE_TYPE=$1
    LINODE_ID=$2
    reset_linode $LINODE_ID
    echo_pending "Installing $NODE_TYPE node" $LINODE_ID
    ROOT_PASSWORD=$( openssl rand -base64 32 )
    echo_completed "Installer root password: $ROOT_PASSWORD" $LINODE_ID

    echo_pending "Retrieving current plan" $LINODE_ID
    PLAN=$( linode_api linode.list LinodeID=$LINODE_ID | jq ".DATA[0].PLANID" )
    echo_completed "Current plan: $PLAN" $LINODE_ID

    echo_pending "Retrieving maximum available disk size" $LINODE_ID
    TOTAL_DISK_SIZE=$( echo "$( linode_api avail.linodeplans PlanID=$PLAN | jq ".DATA[0].DISK" )" "*1024" | bc )
    INSTALL_DISK_SIZE=1024
    STORAGE_DISK_SIZE=10240
    COREOS_OLD_DISK_SIZE=$( echo "${TOTAL_DISK_SIZE}-${INSTALL_DISK_SIZE}-${STORAGE_DISK_SIZE}" | bc )
    COREOS_DISK_SIZE=$( echo "${TOTAL_DISK_SIZE}-${STORAGE_DISK_SIZE}" | bc )
    echo_completed "CoreOS disk size: ${COREOS_DISK_SIZE}mb" $LINODE_ID
    echo_completed "Storage disk size: ${STORAGE_DISK_SIZE}mb" $LINODE_ID
    echo_completed "Install disk size: ${INSTALL_DISK_SIZE}mb" $LINODE_ID
    echo_completed "Total disk size: ${TOTAL_DISK_SIZE}mb" $LINODE_ID

    echo_pending "Creating storage disk" $LINODE_ID
    STORAGE_DISK_ID="$( linode_api linode.disk.create LinodeID=$LINODE_ID \
       Label="LocalStorage" Type=ext4 Size=$STORAGE_DISK_SIZE | jq '.DATA.DiskID' )"
    echo_completed "Created storage disk $STORAGE_DISK_ID" $LINODE_ID

    echo_pending "Creating CoreOS disk" $LINODE_ID
    DISK_ID="$( linode_api linode.disk.create LinodeID=$LINODE_ID \
       Label="CoreOS" Type=raw Size=$COREOS_OLD_DISK_SIZE | jq '.DATA.DiskID' )"
    echo_completed "Created CoreOS disk $DISK_ID" $LINODE_ID

    eval PUBLIC_IP=\$PUBLIC_$LINODE_ID
    if [ "$NODE_TYPE" = "master" ] ; then
        gen_master_certs $PUBLIC_IP $LINODE_ID
        echo_pending "Initializing stackscript parameters" $LINODE_ID
        PARAMS=$( cat <<-EOF
          {
              "admin_key_cert": "$( base64 < ~/.kube-linode/certs/admin-key.pem )",
              "admin_cert": "$( base64 < ~/.kube-linode/certs/admin.pem )",
              "apiserver_key_cert": "$( base64 < ~/.kube-linode/certs/apiserver-key.pem )",
              "apiserver_cert": "$( base64 < ~/.kube-linode/certs/apiserver.pem )",
              "ca_key_cert": "$( base64 < ~/.kube-linode/certs/ca-key.pem )",
              "ca_cert": "$( base64 < ~/.kube-linode/certs/ca.pem )",
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "public_ip": "$PUBLIC_IP",
              "node_type": "$NODE_TYPE",
              "advertise_ip": "$PUBLIC_IP",
              "etcd_endpoint" : "http://${MASTER_IP}:2379",
              "k8s_ver": "v1.7.0-beta.2_coreos.0",
              "dns_service_ip": "10.3.0.10",
              "k8s_service_ip": "10.3.0.1",
              "service_ip_range": "10.3.0.0/24",
              "pod_network": "10.2.0.0/16",
              "USERNAME": "$USERNAME",
              "DOMAIN" : "$DOMAIN",
              "EMAIL" : "$EMAIL",
              "MASTER_IP" : "$MASTER_IP",
              "AUTH" : "$( base64 < ~/.kube-linode/auth )",
              "LINODE_ID": "$LINODE_ID"
          }
EOF
        )
        echo_completed "Initialized stackscript parameters" $LINODE_ID
    fi

    if [ "$NODE_TYPE" = "worker" ] ; then
        gen_worker_certs $PUBLIC_IP $LINODE_ID
        echo_pending "Initializing stackscript parameters" $LINODE_ID
        PARAMS=$( cat <<-EOF
          {
              "worker_key_cert": "$( base64 < ~/.kube-linode/certs/${PUBLIC_IP}-worker-key.pem )",
              "worker_cert": "$( base64 < ~/.kube-linode/certs/${PUBLIC_IP}-worker.pem )",
              "ca_cert": "$( base64 < ~/.kube-linode/certs/ca.pem )",
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "public_ip": "$PUBLIC_IP",
              "node_type": "$NODE_TYPE",
              "advertise_ip": "$PUBLIC_IP",
              "etcd_endpoint" : "http://${MASTER_IP}:2379",
              "k8s_ver": "v1.7.0-beta.2_coreos.0",
              "dns_service_ip": "10.3.0.10",
              "k8s_service_ip": "10.3.0.1",
              "service_ip_range": "10.3.0.0/24",
              "pod_network": "10.2.0.0/16",
              "USERNAME": "$USERNAME",
              "DOMAIN" : "$DOMAIN",
              "EMAIL" : "$EMAIL",
              "MASTER_IP" : "$MASTER_IP",
              "AUTH" : "$( base64 < ~/.kube-linode/auth )",
              "LINODE_ID": "$LINODE_ID"
          }
EOF
        )
        echo_completed "Initialized stackscript parameters" $LINODE_ID
    fi

    # Create the install OS disk from script
    echo_pending "Creating install disk" $LINODE_ID
    INSTALL_DISK_ID=$(linode_api linode.disk.createfromstackscript LinodeID=$LINODE_ID StackScriptID=$SCRIPT_ID \
        DistributionID=140 Label=Installer Size=$INSTALL_DISK_SIZE \
        StackScriptUDFResponses="$PARAMS" rootPass="$ROOT_PASSWORD" | jq ".DATA.DiskID" )
    echo_completed "Created install disk $INSTALL_DISK_ID" $LINODE_ID

    # Configure the installer to boot
    echo_pending "Creating boot configuration" $LINODE_ID
    CONFIG_ID=$(linode_api linode.config.create LinodeID=$LINODE_ID KernelID=138 Label="Installer" \
        DiskList=$DISK_ID,$INSTALL_DISK_ID RootDeviceNum=2 | jq ".DATA.ConfigID" )
    echo_completed "Created boot configuration $CONFIG_ID" $LINODE_ID

    echo_pending "Booting installer" $LINODE_ID
    linode_api linode.boot LinodeID=$LINODE_ID ConfigID=$CONFIG_ID >/dev/null
    wait_jobs $LINODE_ID
    echo_completed "Installer booted" $LINODE_ID

    echo_pending "Updating CoreOS config" $LINODE_ID
    linode_api linode.config.update LinodeID=$LINODE_ID ConfigID=$CONFIG_ID Label="CoreOS" \
        DiskList=$DISK_ID,$STORAGE_DISK_ID KernelID=213 RootDeviceNum=1 >/dev/null
    echo_completed "Updated CoreOS config" $LINODE_ID

    echo_pending "Installing CoreOS (might take a while)" $LINODE_ID
    wait_boot $LINODE_ID
    echo_completed "CoreOS installed and booting" $LINODE_ID

    echo_pending "Shutting down CoreOS" $LINODE_ID
    linode_api linode.shutdown LinodeID=$LINODE_ID >/dev/null

    echo_pending "Deleting install disk $INSTALL_DISK_ID" $LINODE_ID
    linode_api linode.disk.delete LinodeID=$LINODE_ID DiskID=$INSTALL_DISK_ID >/dev/null

    echo_pending "Resizing CoreOS disk $DISK_ID" $LINODE_ID
    linode_api linode.disk.resize LinodeID=$LINODE_ID DiskID=$DISK_ID Size=$COREOS_DISK_SIZE >/dev/null

    echo_pending "Booting CoreOS" $LINODE_ID
    linode_api linode.boot LinodeID=$LINODE_ID ConfigID=$CONFIG_ID >/dev/null

    wait_jobs $LINODE_ID
    sleep 10
    echo_pending "CoreOS boot initiated" $LINODE_ID

    echo_pending "Waiting for CoreOS to boot" $LINODE_ID
    sleep 15
    echo_completed "Starting to provision $NODE_TYPE node" $LINODE_ID

    if [ "$NODE_TYPE" = "master" ] ; then
        if [ -e acme.json ] ; then
            echo_pending "Transferring acme.json" $LINODE_ID
            ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$PUBLIC_IP" \
            "sudo truncate -s 0 /etc/traefik/acme/acme.json; echo '$( base64 < acme.json )' \
             | base64 --decode | sudo tee --append /etc/traefik/acme/acme.json" 2>/dev/null >/dev/null
            echo_completed "Transferred acme.json" $LINODE_ID
        fi
    fi
    ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$PUBLIC_IP" \
            "./bootstrap.sh" 2>/dev/null
    echo_pending "Deleting bootstrap script" $LINODE_ID
    ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$PUBLIC_IP" \
            "rm bootstrap.sh" 2>/dev/null
    echo_completed "Bootstrap script deleted" $LINODE_ID

    echo_pending "Changing status to provisioned" $LINODE_ID
    linode_api linode.update LinodeID=$LINODE_ID Label="${NODE_TYPE}_${LINODE_ID}" lpm_displayGroup="$DOMAIN" >/dev/null
    echo_completed "Status changed to provisioned" $LINODE_ID

    echo_completed "Installed $NODE_TYPE node" $LINODE_ID
}

update_script() {
  echo_pending "Updating install script"
  SCRIPT_ID=$( linode_api stackscript.list | jq ".DATA" | jq -c '.[] | select(.LABEL == "CoreOS_Kube_Cluster") | .STACKSCRIPTID' | sed -n 1p )
  if ! [[ $SCRIPT_ID =~ ^-?[0-9]+$ ]] 2>/dev/null; then
      SCRIPT_ID=$( linode_api stackscript.create DistributionIDList=140 Label=CoreOS_Kube_Cluster script="$( cat ~/.kube-linode/install-coreos.sh )" \
                  | jq ".DATA.StackScriptID" )
  else
      linode_api stackscript.update StackScriptID=${SCRIPT_ID} script="$( cat ~/.kube-linode/install-coreos.sh )" >/dev/null
  fi
  echo_completed "Updated install script"
}

read_api_key() {
  if ! [[ $API_KEY =~ ^[0-9a-zA-Z]+$ ]] 2>/dev/null; then
      while ! [[ $API_KEY =~ ^-?[0-9a-zA-Z]+$ ]] 2>/dev/null; do
         printf "Enter Linode API Key (https://manager.linode.com/profile/api) : "
         read API_KEY
      done
      while ! linode_api test.echo | jq -e ".ERRORARRAY == []" >/dev/null; do
         printf "Enter Linode API Key (https://manager.linode.com/profile/api) : "
         read API_KEY
      done
      echo "API_KEY=$API_KEY" >> settings.env
  else
      if ! linode_api test.echo | jq -e ".ERRORARRAY == []" >/dev/null; then
        while ! linode_api test.echo | jq -e ".ERRORARRAY == []" >/dev/null; do
           printf "Enter Linode API Key (https://manager.linode.com/profile/api) : "
           read API_KEY
        done
        echo "API_KEY=$API_KEY" >> settings.env
      fi
  fi
}

read_master_plan() {
  if ! [[ $MASTER_PLAN =~ ^[0-9]+$ ]] 2>/dev/null; then
      list_plans
      while ! [[ $MASTER_PLAN =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         printf "Enter PlanID for master node: "
         read MASTER_PLAN
      done
      echo "MASTER_PLAN=$MASTER_PLAN" >> settings.env
  fi

}

read_worker_plan() {
  if ! [[ $WORKER_PLAN =~ ^[0-9]+$ ]] 2>/dev/null; then
      list_plans
      while ! [[ $WORKER_PLAN =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         printf "Enter PlanID for worker node: "
         read WORKER_PLAN
      done
      echo "WORKER_PLAN=$WORKER_PLAN" >> settings.env
  fi

}

list_datacenters() {
  linode_api avail.datacenters | jq ".DATA" | jq -r '.[] | [.DATACENTERID, .LOCATION] | @csv' | \
    awk -v FS="," 'BEGIN{print "--------------------------";print "ID\tLocation";print "--------------------------"}{gsub(/"/, "", $2); printf "%s\t%s%s",$1,$2,ORS}END{print "--------------------------"}'
}

read_datacenter() {
  if ! [[ $DATACENTER_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
      list_datacenters
      while ! [[ $DATACENTER_ID =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         printf "Enter ID for Data Center: "
         read DATACENTER_ID
      done
      echo "DATACENTER_ID=$DATACENTER_ID" >> settings.env
  fi
}

read_domain() {
  if ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; then
      while ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; do
         printf "Enter Domain Name: "
         read DOMAIN
      done
      echo "DOMAIN=$DOMAIN" >> settings.env
  fi
}

read_email() {
  email_regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
  if ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; then
      while ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; do
         printf "Enter Email: "
         read EMAIL
      done
      echo "EMAIL=$EMAIL" >> settings.env
  fi
}

update_dns() {
  local LINODE_ID=$1
  local DOMAIN_ID
  local PUBLIC_IP
  local IP_ADDRESS_ID
  local RESOURCE_IDS
  eval PUBLIC_IP=\$PUBLIC_$LINODE_ID
  echo_pending "Updating DNS record for $DOMAIN" $LINODE_ID
  DOMAIN_ID=$( linode_api domain.list | jq ".DATA" | jq -c ".[] | select(.DOMAIN == \"$DOMAIN\") | .DOMAINID" )
  if ! [[ $DOMAIN_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
      linode_api domain.create DomainID=$DOMAIN_ID Domain="$DOMAIN" TTL_sec=300 axfr_ips="none" Expire_sec=604800 \
                               SOA_Email="$EMAIL" Retry_sec=300 status=1 Refresh_sec=300 Type=master >/dev/null
  fi
  DOMAIN_ID=$( linode_api domain.list | jq ".DATA" | jq -c ".[] | select(.DOMAIN == \"$DOMAIN\") | .DOMAINID" )
  linode_api domain.update DomainID=$DOMAIN_ID Domain="$DOMAIN" TTL_sec=300 axfr_ips="none" Expire_sec=604800 \
                           SOA_Email="$EMAIL" Retry_sec=300 status=1 Refresh_sec=300 Type=master >/dev/null
  echo_completed "Updated DNS record for $DOMAIN" $LINODE_ID

  echo_pending "Retrieving list of resources for $DOMAIN" $LINODE_ID
  RESOURCE_IDS=$( linode_api domain.resource.list DomainID=$DOMAIN_ID | jq ".DATA" | jq ".[] | .RESOURCEID" )
  echo_completed "Retrieved list of resources for $DOMAIN" $LINODE_ID

  for RESOURCE_ID in $RESOURCE_IDS; do
      echo_pending "Deleting domain resource record $RESOURCE_ID" $LINODE_ID
      linode_api domain.resource.delete DomainID=$DOMAIN_ID ResourceID=$RESOURCE_ID >/dev/null
      echo_completed "Deleted domain resource record $RESOURCE_ID" $LINODE_ID
  done

  echo_pending "Adding 'A' DNS record to $DOMAIN with target $PUBLIC_IP" $LINODE_ID
  linode_api domain.resource.create DomainID=$DOMAIN_ID \
             TARGET="$PUBLIC_IP" TTL_SEC=0 PORT=80 PROTOCOL="" PRIORITY=10 WEIGHT=5 TYPE="A" NAME="" >/dev/null
  echo_completed "Added 'A' DNS record to $DOMAIN with target $PUBLIC_IP" $LINODE_ID

  echo_pending "Adding wildcard 'CNAME' record with target $DOMAIN" $LINODE_ID
  linode_api domain.resource.create DomainID=$DOMAIN_ID \
             TARGET="$DOMAIN" TTL_SEC=0 PORT=80 PROTOCOL="" PRIORITY=10 WEIGHT=5 TYPE="CNAME" NAME="*" >/dev/null
  echo_completed "Added wildcard 'CNAME' record with target $DOMAIN" $LINODE_ID

  echo_pending "Updating reverse DNS record of $PUBLIC_IP to $DOMAIN" $LINODE_ID
  IP_ADDRESS_ID=$( linode_api linode.ip.list | jq ".DATA" | jq -c ".[] | select(.IPADDRESS == \"$PUBLIC_IP\") | .IPADDRESSID" | sed -n 1p )
  linode_api linode.ip.setrdns IPAddressID=$IP_ADDRESS_ID Hostname="$DOMAIN" >/dev/null
  echo_completed "Updated reverse DNS record of $PUBLIC_IP to $DOMAIN" $LINODE_ID
}

read_no_of_workers() {
  if ! [[ $NO_OF_WORKERS =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $NO_OF_WORKERS =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         printf "Enter number of workers: "
         read NO_OF_WORKERS
      done
      echo "NO_OF_WORKERS=$NO_OF_WORKERS" >> settings.env
  fi
}
