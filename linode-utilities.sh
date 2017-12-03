#!/bin/bash
if [ -z "${KUBECONFIG}" ]; then
    export KUBECONFIG=~/.kube/config
fi

control_c() {
  tput cub "$(tput cols)"
  tput el
  stty sane
  tput cnorm
  stty echo
  exit $?
}

trap control_c SIGINT

CYAN=$(tput setaf 6)
NORMAL=$(tput sgr0)
BOLD=$(tput bold)

check_dep() {
    command -v $1 >/dev/null 2>&1 || { echo "Please install \`${BOLD}$1${NORMAL}\` before running this script." >&2; exit 1; }
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
        if [[ $(linode_api linode.job.list LinodeID=$LINODE_ID | jq ".DATA" | \
        	        jq -c "[ .[] | select(.LABEL == \"Lassie initiated boot: CoreOS\") | select(.HOST_SUCCESS == 1)]" | \
        	        jq ".[] | .JOBID") =~ ^[0-9]+ ]]; then
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

shutdown() {
  local LINODE_ID=$1
  linode_api linode.shutdown LinodeID=$LINODE_ID >/dev/null
  wait_jobs $LINODE_ID
}

get_disk_ids() {
  local LINODE_ID=$1
  linode_api linode.disk.list LinodeID=$LINODE_ID | jq ".DATA" | jq -c ".[] | .DISKID"
}

get_config_ids() {
  local LINODE_ID=$1
  linode_api linode.config.list LinodeID=$LINODE_ID | jq ".DATA" | jq -c ".[] | .ConfigID"
}

reset_linode() {
    local LINODE_ID=$1
    local DISK_IDS
    local CONFIG_IDS
    local STATUS

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Getting status" "get_status $LINODE_ID" STATUS

    if [ "$STATUS" = "1" ]; then
      spinner "${CYAN}[$LINODE_ID]${NORMAL} Shutting down linode" "shutdown $LINODE_ID"
    fi

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving disk list" "get_disk_ids $LINODE_ID" DISK_IDS

    for DISK_ID in $DISK_IDS; do
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Deleting disk $DISK_ID" "linode_api linode.disk.delete LinodeID=$LINODE_ID DiskID=$DISK_ID"
    done

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving config list" "get_config_ids $LINODE_ID" CONFIG_IDS

    for CONFIG_ID in $CONFIG_IDS; do
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Deleting config $CONFIG_ID" "linode_api linode.config.delete LinodeID=$LINODE_ID ConfigID=$CONFIG_ID"
    done

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Waiting for all jobs to complete" "wait_jobs $LINODE_ID"
}

get_public_ip() {
  local LINODE_ID=$1
  local IP
  eval IP=\$PUBLIC_$LINODE_ID
  if ! [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] 2>/dev/null; then
      IP="$( linode_api linode.ip.list LinodeID=$LINODE_ID | jq -Mje '.DATA[] | select(.ISPUBLIC==1) | .IPADDRESS' | sed -n 1p )"
  fi
  echo $IP
}

get_private_ip() {
  local LINODE_ID=$1
  local IP
  eval IP=\$PRIVATE_$LINODE_ID
  if ! [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] 2>/dev/null; then
      IP="$( linode_api linode.ip.list LinodeID=$LINODE_ID | jq -Mje '.DATA[] | select(.ISPUBLIC==0) | .IPADDRESS' | sed -n 1p )"
  fi
  echo $IP
}

get_plan_id() {
  local LINODE_ID=$1
  linode_api linode.list LinodeID=$LINODE_ID | jq ".DATA[0].PLANID"
}

get_max_disk_size() {
  local PLAN=$1
  echo "$( linode_api avail.linodeplans PlanID=$PLAN | jq ".DATA[0].DISK" )" "*1024" | bc
}

create_raw_disk() {
  local LINODE_ID=$1
  local DISK_SIZE=$2
  local LABEL=$3
  linode_api linode.disk.create LinodeID=$LINODE_ID Label="$LABEL" Type=raw Size=$DISK_SIZE | jq '.DATA.DiskID'
}

create_ext4_disk() {
  local LINODE_ID=$1
  local DISK_SIZE=$2
  local LABEL=$3
  linode_api linode.disk.create LinodeID=$LINODE_ID Label="$LABEL" Type=ext4 Size=$DISK_SIZE | jq '.DATA.DiskID'
}

create_install_disk() {
  linode_api linode.disk.createfromstackscript LinodeID=$LINODE_ID StackScriptID=$SCRIPT_ID \
      DistributionID=140 Label=Installer Size=$INSTALL_DISK_SIZE \
      StackScriptUDFResponses="$PARAMS" rootPass="$ROOT_PASSWORD" | jq ".DATA.DiskID"
}

create_boot_configuration() {
  linode_api linode.config.create LinodeID=$LINODE_ID KernelID=138 Label="Installer" \
      DiskList=$DISK_ID,$INSTALL_DISK_ID RootDeviceNum=2 | jq ".DATA.ConfigID"
}

boot_linode() {
  local LINODE_ID=$1
  local CONFIG_ID=$2
  linode_api linode.boot LinodeID=$LINODE_ID ConfigID=$CONFIG_ID >/dev/null
  wait_jobs $LINODE_ID
}

update_coreos_config() {
  linode_api linode.config.update LinodeID=$LINODE_ID ConfigID=$CONFIG_ID Label="CoreOS" \
      DiskList=$DISK_ID KernelID=213 RootDeviceNum=1 helper_network=false
}

transfer_acme() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" \
  "sudo truncate -s 0 /etc/traefik/acme/acme.json; echo '$( base64 $base64_args < $DIR/acme.json )' \
   | base64 --decode | sudo tee --append /etc/traefik/acme/acme.json" 2>/dev/null >/dev/null
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" \
  "sudo chmod 600 /etc/traefik/acme/acme.json" 2>/dev/null >/dev/null
}

delete_bootstrap_script() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" \
          "rm bootstrap.sh" 2>/dev/null
}

change_to_provisioned() {
  local LINODE_ID=$1
  local NODE_TYPE=$2
  linode_api linode.update LinodeID=$LINODE_ID Label="${NODE_TYPE}_${LINODE_ID}" lpm_displayGroup="$DOMAIN"
}

change_to_unprovisioned() {
  local LINODE_ID=$1
  local NODE_TYPE=$2
  linode_api linode.update LinodeID=$LINODE_ID Label="${NODE_TYPE}_${LINODE_ID}" lpm_displayGroup="$DOMAIN (Unprovisioned)"
}

install() {
    local NODE_TYPE
    local LINODE_ID
    local PLAN
    local ROOT_PASSWORD
    local COREOS_OLD_DISK_SIZE
    NODE_TYPE=$1
    LINODE_ID=$2
    reset_linode $LINODE_ID
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Generating root password" "openssl rand -base64 32" ROOT_PASSWORD
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving current plan" "get_plan_id $LINODE_ID" PLAN
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving maximum available disk size" "get_max_disk_size $PLAN" TOTAL_DISK_SIZE

    INSTALL_DISK_SIZE=1024
    COREOS_OLD_DISK_SIZE=$((${TOTAL_DISK_SIZE}-${INSTALL_DISK_SIZE}))

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating CoreOS disk" "create_raw_disk $LINODE_ID $COREOS_OLD_DISK_SIZE CoreOS" DISK_ID

    eval IP=\$PUBLIC_$LINODE_ID
    eval PRIVATE_IP=\$PRIVATE_$LINODE_ID
    if [ "$NODE_TYPE" = "master" ] ; then
        PARAMS=$( cat <<-EOF
          {
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "node_type": "$NODE_TYPE",
              "PUBLIC_IP": "$IP",
              "PRIVATE_IP": "$PRIVATE_IP"
          }
EOF
        )
    fi

    if [ "$NODE_TYPE" = "worker" ] ; then
        PARAMS=$( cat <<-EOF
          {
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "node_type": "$NODE_TYPE",
              "PUBLIC_IP": "$IP",
              "PRIVATE_IP": "$PRIVATE_IP"
          }
EOF
        )
    fi

    # Create the install OS disk from script
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating install disk" create_install_disk INSTALL_DISK_ID

    # Configure the installer to boot
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating boot configuration" create_boot_configuration CONFIG_ID
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Booting installer" "boot_linode $LINODE_ID $CONFIG_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Updating CoreOS config" update_coreos_config
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Installing CoreOS (might take a while)" "wait_boot $LINODE_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Shutting down CoreOS" "linode_api linode.shutdown LinodeID=$LINODE_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Deleting install disk $INSTALL_DISK_ID" "linode_api linode.disk.delete LinodeID=$LINODE_ID DiskID=$INSTALL_DISK_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Resizing CoreOS disk $DISK_ID" "linode_api linode.disk.resize LinodeID=$LINODE_ID DiskID=$DISK_ID Size=$TOTAL_DISK_SIZE"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Booting CoreOS" "linode_api linode.boot LinodeID=$LINODE_ID ConfigID=$CONFIG_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Waiting for CoreOS to be ready" "wait_jobs $LINODE_ID; sleep 20"

    if [ "$NODE_TYPE" = "master" ] ; then
        if [ -e $DIR/acme.json ] ; then
            spinner "${CYAN}[$LINODE_ID]${NORMAL} Transferring acme.json" transfer_acme
        fi
    fi

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Provisioning $NODE_TYPE node (might take a while)" provision_$NODE_TYPE PROVISION_LOGS

    if [ "$( echo "${PROVISION_LOGS}" | tail -n1 )" = "provisioned $NODE_TYPE" ]; then
      spinner "${CYAN}[$LINODE_ID]${NORMAL} Changing status to provisioned" "change_to_provisioned $LINODE_ID $NODE_TYPE"
    else
      install $NODE_TYPE $LINODE_ID
    fi
}

provision_master() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" \
          "sudo ./bootstrap.sh" 2>/dev/null >/dev/null
  [ -e $DIR/cluster ] && rm -rf $DIR/cluster
  mkdir $DIR/cluster
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r core@${IP}:/home/core/assets/* $DIR/cluster
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" "rm -rf /home/core/bootstrap.sh"
  mkdir -p $HOME/.kube
  if [ -e $HOME/.kube/config ]; then
    yes | cp $HOME/.kube/config $HOME/.kube/config.bak
  fi
  yes | cp $DIR/cluster/auth/kubeconfig $HOME/.kube/config
  while true; do kubectl --namespace=kube-system create secret generic kubesecret --from-file $DIR/auth --request-timeout 0 && break || sleep 5; done
  if kubectl --request-timeout 0 get namespaces | grep -q "monitoring"; then
    echo "namespace monitoring exists"
  else
    while true; do kubectl create namespace "monitoring" --request-timeout 0 && break || sleep 5; done
  fi
  while true; do kubectl --namespace=monitoring create secret generic kubesecret --from-file $DIR/auth --request-timeout 0 && break || sleep 5; done
  while true; do kubectl apply -f $DIR/manifests/heapster.yaml --validate=false --request-timeout 0 && break || sleep 5; done
  while true; do cat $DIR/manifests/kube-dashboard.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done
  while true; do cat $DIR/manifests/traefik.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | sed "s/\${MASTER_IP}/${IP}/g" | sed "s/\$EMAIL/${EMAIL}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done
  echo "provisioned master"
}

provision_worker() {
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $DIR/cluster/auth/kubeconfig core@${IP}:/home/core/kubeconfig 2>/dev/null >/dev/null
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" "sudo ./bootstrap.sh" 2>/dev/null >/dev/null
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" "rm -rf /home/core/kubeconfig && rm -rf /home/core/bootstrap.sh" 2>/dev/null >/dev/null
  set +e
  until kubectl get nodes > /dev/null 2>&1; do sleep 1; done
  if ! kubectl --namespace rook get pods --request-timeout 0 2>/dev/null | grep -q "^rook-api"; then
    if ! kubectl --namespace rook get pods --request-timeout 0 2>/dev/null | grep -q "^rook-api"; then
      if ! kubectl --namespace rook get pods --request-timeout 0 2>/dev/null | grep -q "^rook-api"; then
        while true; do kubectl apply -f $DIR/manifests/rook/rook-operator.yaml --request-timeout 0 && break || sleep 5; done
        while true; do kubectl apply -f $DIR/manifests/rook/rook-cluster.yaml --request-timeout 0 && break || sleep 5; done
        while true; do kubectl apply -f $DIR/manifests/rook/rook-storageclass.yaml --request-timeout 0 && break || sleep 5; done
      fi
    fi
  fi
  until kubectl get nodes > /dev/null 2>&1; do sleep 1; done
  if ! kubectl --namespace monitoring get ingress --request-timeout 0 2>/dev/null | grep -q "^prometheus-ingress"; then
    if ! kubectl --namespace monitoring get ingress --request-timeout 0 2>/dev/null | grep -q "^prometheus-ingress"; then
      if ! kubectl --namespace monitoring get ingress --request-timeout 0 2>/dev/null | grep -q "^prometheus-ingress"; then
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/prometheus-operator --request-timeout 0 && break || sleep 5; done
        printf "Waiting for Operator to register third party objects..."
        until kubectl --namespace monitoring get servicemonitor > /dev/null 2>&1; do sleep 1; printf "."; done
        until kubectl --namespace monitoring get prometheus > /dev/null 2>&1; do sleep 1; printf "."; done
        until kubectl --namespace monitoring get alertmanager > /dev/null 2>&1; do sleep 1; printf "."; done
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/node-exporter --request-timeout 0 && break || sleep 5; done
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/kube-state-metrics --request-timeout 0 && break || sleep 5; done
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/grafana/grafana-credentials.yaml --request-timeout 0 && break || sleep 5; done
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/grafana --request-timeout 0 && break || sleep 5; done
        while true; do find $DIR/manifests/prometheus -type f ! -name prometheus-k8s-roles.yaml ! -name prometheus-k8s-role-bindings.yaml ! -name prometheus-k8s-ingress.yaml -exec kubectl --request-timeout 0 --namespace "monitoring" apply -f {} \; && break || sleep 5; done
        while true; do kubectl apply -f $DIR/manifests/prometheus/prometheus-k8s-roles.yaml --request-timeout 0 && break || sleep 5; done
        while true; do kubectl apply -f $DIR/manifests/prometheus/prometheus-k8s-role-bindings.yaml --request-timeout 0 && break || sleep 5; done
        while true; do kubectl --namespace monitoring apply -f $DIR/manifests/alertmanager/ --request-timeout 0 && break || sleep 5; done
        while true; do cat $DIR/manifests/prometheus/prometheus-k8s-ingress.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done
      fi
    fi
  fi
  set -e
  echo "provisioned worker"
}

update_script() {
  local SCRIPT_ID
  SCRIPT_ID=$( linode_api stackscript.list | jq ".DATA" | jq -c '.[] | select(.LABEL == "CoreOS_Kube_Cluster") | .STACKSCRIPTID' | sed -n 1p )
  if ! [[ $SCRIPT_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
      SCRIPT_ID=$( linode_api stackscript.create DistributionIDList=140 Label=CoreOS_Kube_Cluster script="$( cat $DIR/install-coreos.sh )" \
                  | jq ".DATA.StackScriptID" )
  else
      linode_api stackscript.update StackScriptID=${SCRIPT_ID} script="$( cat $DIR/install-coreos.sh )" >/dev/null
  fi
  echo $SCRIPT_ID
}

read_api_key() {
  local result=false
  if ! [[ $API_KEY =~ ^[0-9a-zA-Z]+$ ]] 2>/dev/null; then
      while ! [[ $API_KEY =~ ^-?[0-9a-zA-Z]+$ ]] 2>/dev/null; do
         text_input "Enter Linode API Key (https://manager.linode.com/profile/api) : " API_KEY
         tput civis
      done
      while true ; do
         spinner "Verifying API Key" check_api_key result
         if [ $result = true ] ; then
           break
         fi
         text_input "Enter Linode API Key (https://manager.linode.com/profile/api) : " API_KEY
         tput civis
      done
  else
      while true ; do
         spinner "Verifying API Key" check_api_key result
         if [ $result = true ] ; then
           break
         fi
         text_input "Enter Linode API Key (https://manager.linode.com/profile/api) : " API_KEY
         tput civis
      done
  fi
   sed -i.bak '/^API_KEY/d' $DIR/settings.env
   echo "API_KEY=$API_KEY" >> $DIR/settings.env
   rm $DIR/settings.env.bak
}

check_api_key() {
  if linode_api test.echo | jq -e ".ERRORARRAY == []" >/dev/null; then
    echo true
  else
    echo false
  fi
}

get_plans() {
  linode_api avail.linodeplans | jq ".DATA | sort_by(.PRICE)"
}

read_master_plan() {
  if ! [[ $MASTER_PLAN =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $MASTER_PLAN =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         IFS=$'\n'
         spinner "Retrieving plans" get_plans plan_data
         local plan_ids=($(echo $plan_data | jq -r '.[] | .PLANID'))
         local plan_list=($(echo $plan_data | jq -r '.[] | [.RAM, .PRICE] | @csv' | \
           awk -v FS="," '{ram=$1/1024; printf "%3sGB (\$%s/mo)%s",ram,$2,ORS}' 2>/dev/null))
         list_input_index "Select a master plan (https://www.linode.com/pricing)" plan_list selected_disk_id

         MASTER_PLAN=${plan_ids[$selected_disk_id]}
      done
      echo "MASTER_PLAN=$MASTER_PLAN" >> $DIR/settings.env
  fi

}

read_worker_plan() {
  if ! [[ $WORKER_PLAN =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $WORKER_PLAN =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         IFS=$'\n'
         spinner "Retrieving plans" get_plans plan_data
         tput el
         local plan_ids=($(echo $plan_data | jq -r '.[] | .PLANID'))
         local plan_list=($(echo $plan_data | jq -r '.[] | [.RAM, .PRICE] | @csv' | \
           awk -v FS="," '{ram=$1/1024; printf "%3sGB (\$%s/mo)%s",ram,$2,ORS}' 2>/dev/null))
         list_input_index "Select a worker plan (https://www.linode.com/pricing)" plan_list selected_disk_id

         WORKER_PLAN=${plan_ids[$selected_disk_id]}
      done
      echo "WORKER_PLAN=$WORKER_PLAN" >> $DIR/settings.env
  fi

}

get_datacenters() {
  linode_api avail.datacenters | jq ".DATA | sort_by(.LOCATION)"
}

read_datacenter() {
  if ! [[ $DATACENTER_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $DATACENTER_ID =~ ^-?[0-9]+$ ]] 2>/dev/null; do
         IFS=$'\n'
         spinner "Retrieving datacenters" get_datacenters datacenters_data
         tput el
         datacenters_ids=($(echo $datacenters_data | jq -r '.[] | .DATACENTERID'))
         datacenters_list=($(echo $datacenters_data | jq -r '.[] | .LOCATION'))
         list_input_index "Select a datacenter" datacenters_list selected_data_center_index
         DATACENTER_ID=${datacenters_ids[$selected_data_center_index]}
      done
      echo "DATACENTER_ID=$DATACENTER_ID" >> $DIR/settings.env
  fi
}

read_domain() {
  if ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; then
      while ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; do
         text_input "Enter Domain Name: " DOMAIN "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$" "Please enter a valid domain name"
      done
      echo "DOMAIN=$DOMAIN" >> $DIR/settings.env
  fi
  tput civis
}

read_email() {
  email_regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
  if ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; then
      while ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; do
         text_input "Enter Email: " EMAIL "^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$" "Please enter a valid email"
      done
      echo "EMAIL=$EMAIL" >> $DIR/settings.env
  fi
  tput civis
}

read_username() {
  if [ -z "$USERNAME" ]; then
    [ -e $DIR/auth ] && rm $DIR/auth
    [ -e $DIR/manifests/grafana/grafana-credentials.yaml ] && rm $DIR/manifests/grafana/grafana-credentials.yaml
    text_input "Enter dashboard username: " USERNAME
    echo "USERNAME=$USERNAME" >> $DIR/settings.env
  fi
  tput civis
}

get_domains() {
  local DOMAIN=$1
  linode_api domain.list | jq ".DATA" | jq -c ".[] | select(.DOMAIN == \"$DOMAIN\") | .DOMAINID"
}

get_resources() {
  local DOMAIN_ID=$1
  linode_api domain.resource.list DomainID=$DOMAIN_ID | jq ".DATA"
}

create_A_domain() {
  linode_api domain.resource.create DomainID=$DOMAIN_ID \
             TARGET="$IP" TTL_SEC=0 PORT=80 PROTOCOL='' PRIORITY=10 WEIGHT=5 TYPE='A' NAME='' >/dev/null
}

create_CNAME_domain() {
  linode_api domain.resource.create DomainID=$DOMAIN_ID \
             TARGET="$DOMAIN" TTL_SEC=0 PORT=80 PROTOCOL="" PRIORITY=10 WEIGHT=5 TYPE="CNAME" NAME="*" >/dev/null
}

get_ip_address_id() {
  linode_api linode.ip.list | jq ".DATA" | jq -c ".[] | select(.IPADDRESS == \"$IP\") | .IPADDRESSID" | sed -n 1p
}

update_domain() {
  linode_api domain.update DomainID=$DOMAIN_ID Domain="$DOMAIN" TTL_sec=300 axfr_ips="none" Expire_sec=604800 \
                           SOA_Email="$EMAIL" Retry_sec=300 status=1 Refresh_sec=300 Type=master >/dev/null
}

create_domain() {
  linode_api domain.create Domain="$DOMAIN" TTL_sec=300 axfr_ips="none" Expire_sec=604800 \
                           SOA_Email="$EMAIL" Retry_sec=300 status=1 Refresh_sec=300 Type=master >/dev/null
}

update_dns() {
  local LINODE_ID=$1
  local DOMAIN_ID
  local IP
  local RESOURCE_IDS
  eval IP=\$PUBLIC_$LINODE_ID
  spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving DNS record for $DOMAIN" "get_domains \"$DOMAIN\"" DOMAIN_ID
  if ! [[ $DOMAIN_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating DNS record for $DOMAIN" create_domain
  fi
  spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving DNS record for $DOMAIN" "get_domains \"$DOMAIN\"" DOMAIN_ID
  spinner "${CYAN}[$LINODE_ID]${NORMAL} Updating DNS record for $DOMAIN" update_domain

  spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving list of resources for $DOMAIN" "get_resources $DOMAIN_ID" RESOURCE_LIST

  IFS=$'\n'
  if ! [[ $(echo $RESOURCE_LIST | jq -c ".[] | select(.TYPE == \"A\" and .TARGET == \"$IP\") | .RESOURCEID" | sed -n 1p) =~ ^[0-9]+$ ]] 2>/dev/null; then
      RESOURCE_IDS=$(echo $RESOURCE_LIST | jq -c ".[] | select(.TYPE == \"A\" and .NAME == \"\") | .RESOURCEID")
      for RESOURCE_ID in $RESOURCE_IDS; do
          spinner "${CYAN}[$LINODE_ID]${NORMAL} Deleting 'A' DNS record $RESOURCE_ID" "linode_api domain.resource.delete DomainID=$DOMAIN_ID ResourceID=$RESOURCE_ID"
      done
      spinner "${CYAN}[$LINODE_ID]${NORMAL} Adding 'A' DNS record to $DOMAIN with target $IP" create_A_domain
  fi

  if ! [[ $(echo $RESOURCE_LIST | jq -c ".[] | select(.TYPE == \"CNAME\" and .TARGET == \"$DOMAIN\") | .RESOURCEID") =~ ^[0-9]+$ ]] 2>/dev/null; then
      spinner "${CYAN}[$LINODE_ID]${NORMAL} Adding wildcard 'CNAME' record with target $DOMAIN" create_CNAME_domain
  fi
}

read_no_of_workers() {
  if ! [[ $NO_OF_WORKERS =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $NO_OF_WORKERS =~ ^[0-9]+$ ]] 2>/dev/null; do
         text_input "Enter number of workers: " NO_OF_WORKERS "^[0-9]+$" "Please enter a number"
      done
      echo "NO_OF_WORKERS=$NO_OF_WORKERS" >> $DIR/settings.env
  fi
  tput civis
}

create_linode() {
  DATACENTER_ID=$1
  PLAN_ID=$2
  linode_api linode.create DatacenterID=$DATACENTER_ID PlanID=$PLAN_ID | jq ".DATA.LinodeID"
}

add_private_ip() {
  local LINODE_ID=$1
  linode_api linode.ip.addprivate LinodeID=$LINODE_ID
}

get_no_of_workers() {
  echo "$( list_worker_ids | wc -l ) + 0" | bc
}
