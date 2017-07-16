#!/bin/bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source $DIR/inquirer.sh
source $DIR/ora.sh

set +e
base64_args=""
$(base64 --wrap=0 <(echo "test") >/dev/null 2>&1)
if [ $? -eq 0 ]; then
    base64_args="--wrap=0"
fi
set -e

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
      DiskList=$DISK_ID,$(join STORAGE_DISK_IDS ",") KernelID=213 RootDeviceNum=1 helper_network=false
}

transfer_acme() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" \
  "sudo truncate -s 0 /etc/traefik/acme/acme.json; echo '$( base64 $base64_args < ~/.kube-linode/acme.json )' \
   | base64 --decode | sudo tee --append /etc/traefik/acme/acme.json" 2>/dev/null >/dev/null
}

delete_bootstrap_script() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" \
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

validate_disk_sizes() {
  IFS=$'\n'
  local sizes=($(echo $1 | tr ',' '\n'))
  local total_size=0
  for disk_size in ${sizes[@]}; do
    total_size=$(($total_size+$disk_size))
  done

  if [ $total_size -le $TOTAL_DISK_SIZE ]; then
    echo true
  else
    echo false
  fi
}

install() {
    local NODE_TYPE
    local LINODE_ID
    local PLAN
    local ROOT_PASSWORD
    local COREOS_OLD_DISK_SIZE
    local COREOS_DISK_SIZE
    local STORAGE_DISK_SIZE
    NODE_TYPE=$1
    LINODE_ID=$2
    reset_linode $LINODE_ID
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Generating root password" "openssl rand -base64 32" ROOT_PASSWORD
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving current plan" "get_plan_id $LINODE_ID" PLAN
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Retrieving maximum available disk size" "get_max_disk_size $PLAN" TOTAL_DISK_SIZE

    INSTALL_DISK_SIZE=1024
    STORAGE_DISK_SIZE=0

    tput el
    text_input "Enter local storage size (comma separated in mb, total below ${TOTAL_DISK_SIZE}mb):" \
           DISK_SIZES_INPUT "^[0-9]+(,[0-9]+){0,6}$" "Enter valid disk sizes" validate_disk_sizes
    stty -echo
    tput civis
    tput cuu1
    tput el
    tput el1

    IFS=$'\n'
    DISK_SIZES=($(echo $DISK_SIZES_INPUT | tr ',' '\n'))
    STORAGE_DISK_IDS=()
    for DISK_SIZE in ${DISK_SIZES[@]}; do
      if [ "$DISK_SIZE" -gt "0" ]; then
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating ${DISK_SIZE}mb storage disk" "create_ext4_disk $LINODE_ID $DISK_SIZE Storage" STORAGE_DISK_ID
        STORAGE_DISK_SIZE=$(($STORAGE_DISK_SIZE+$DISK_SIZE))
        STORAGE_DISK_IDS+=( $STORAGE_DISK_ID )
      fi
    done

    COREOS_OLD_DISK_SIZE=$( echo "${TOTAL_DISK_SIZE}-${INSTALL_DISK_SIZE}-${STORAGE_DISK_SIZE}" | bc )
    COREOS_DISK_SIZE=$( echo "${TOTAL_DISK_SIZE}-${STORAGE_DISK_SIZE}" | bc )

    spinner "${CYAN}[$LINODE_ID]${NORMAL} Creating CoreOS disk" "create_raw_disk $LINODE_ID $COREOS_OLD_DISK_SIZE CoreOS" DISK_ID

    eval IP=\$PUBLIC_$LINODE_ID
    eval PRIVATE_IP=\$PRIVATE_$LINODE_ID
    if [ "$NODE_TYPE" = "master" ] ; then
        PARAMS=$( cat <<-EOF
          {
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "ip": "$IP",
              "node_type": "$NODE_TYPE",
              "advertise_ip": "$IP",
              "PUBLIC_IP": "$IP",
              "PRIVATE_IP": "$PRIVATE_IP",
              "etcd_endpoint" : "http://${MASTER_IP}:2379",
              "k8s_ver": "v1.7.0_coreos.0",
              "dns_service_ip": "10.3.0.10",
              "k8s_service_ip": "10.3.0.1",
              "service_ip_range": "10.3.0.0/24",
              "pod_network": "10.2.0.0/16",
              "USERNAME": "$USERNAME",
              "DOMAIN" : "$DOMAIN",
              "EMAIL" : "$EMAIL",
              "MASTER_IP" : "$MASTER_IP",
              "LINODE_ID": "$LINODE_ID"
          }
EOF
        )
    fi

    if [ "$NODE_TYPE" = "worker" ] ; then
        PARAMS=$( cat <<-EOF
          {
              "ssh_key": "$( cat ~/.ssh/id_rsa.pub )",
              "ip": "$IP",
              "node_type": "$NODE_TYPE",
              "advertise_ip": "$IP",
              "PUBLIC_IP": "$IP",
              "PRIVATE_IP": "$PRIVATE_IP",
              "etcd_endpoint" : "http://${MASTER_IP}:2379",
              "k8s_ver": "v1.7.0_coreos.0",
              "dns_service_ip": "10.3.0.10",
              "k8s_service_ip": "10.3.0.1",
              "service_ip_range": "10.3.0.0/24",
              "pod_network": "10.2.0.0/16",
              "USERNAME": "$USERNAME",
              "DOMAIN" : "$DOMAIN",
              "EMAIL" : "$EMAIL",
              "MASTER_IP" : "$MASTER_IP",
              "LINODE_ID": "$LINODE_ID"
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
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Resizing CoreOS disk $DISK_ID" "linode_api linode.disk.resize LinodeID=$LINODE_ID DiskID=$DISK_ID Size=$COREOS_DISK_SIZE"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Booting CoreOS" "linode_api linode.boot LinodeID=$LINODE_ID ConfigID=$CONFIG_ID"
    spinner "${CYAN}[$LINODE_ID]${NORMAL} Waiting for CoreOS to be ready" "wait_jobs $LINODE_ID; sleep 20"

    if [ "$NODE_TYPE" = "master" ] ; then
        if [ -e ~/.kube-linode/acme.json ] ; then
            spinner "${CYAN}[$LINODE_ID]${NORMAL} Transferring acme.json" transfer_acme
        fi
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Provisioning master node (might take a while)" provision_master
        if kubectl get nodes | grep --quiet "$IP"; then
          spinner "${CYAN}[$LINODE_ID]${NORMAL} Changing status to provisioned" "change_to_provisioned $LINODE_ID $NODE_TYPE"
        else
          tput el
          echo "${CYAN}[$LINODE_ID]${NORMAL} Master node is uncontactable! Please run kube-linode again to re-provision."
          exit 1
        fi
    fi

    if [ "$NODE_TYPE" = "worker" ] ; then
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Provisioning worker node (might take a while)" provision_worker
        spinner "${CYAN}[$LINODE_ID]${NORMAL} Changing status to provisioned" "change_to_provisioned $LINODE_ID $NODE_TYPE"
    fi
}

provision_master() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" \
          "sudo ./bootstrap.sh" 2>/dev/null
  [ -e $DIR/cluster ] && rm -rf $DIR/cluster
  mkdir $DIR/cluster
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r ${USERNAME}@${IP}:/home/${USERNAME}/assets/* $DIR/cluster
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" "rm -rf /home/${USERNAME}/assets && rm -rf /home/${USERNAME}/bootstrap.sh"

  mkdir -p $HOME/.kube
  if [ -e $HOME/.kube/config ]; then
    yes | cp $HOME/.kube/config $HOME/.kube/config.bak
  fi

  yes | cp $DIR/cluster/auth/kubeconfig $HOME/.kube/config
  kubectl --namespace=kube-system create secret generic kubesecret --from-file $DIR/auth

  kubectl create -f $DIR/heapster.yaml --validate=false
  cat $DIR/kube-dashboard.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | kubectl create --validate=false -f -
  kubectl create -f $DIR/local-storage.yaml --validate=false
  cat $DIR/traefik.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | sed "s/\${MASTER_IP}/${IP}/g" | sed "s/\$EMAIL/${EMAIL}/g" | kubectl create --validate=false -f -
}

provision_worker() {
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $DIR/cluster/auth/kubeconfig ${USERNAME}@${IP}:/home/${USERNAME}/kubeconfig
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" "sudo ./bootstrap.sh" 2>/dev/null
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "${USERNAME}@$IP" "rm -rf /home/${USERNAME}/kubeconfig && rm -rf /home/${USERNAME}/bootstrap.sh"
}

update_script() {
  local SCRIPT_ID
  SCRIPT_ID=$( linode_api stackscript.list | jq ".DATA" | jq -c '.[] | select(.LABEL == "CoreOS_Kube_Cluster") | .STACKSCRIPTID' | sed -n 1p )
  if ! [[ $SCRIPT_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
      SCRIPT_ID=$( linode_api stackscript.create DistributionIDList=140 Label=CoreOS_Kube_Cluster script="$( cat ~/.kube-linode/install-coreos.sh )" \
                  | jq ".DATA.StackScriptID" )
  else
      linode_api stackscript.update StackScriptID=${SCRIPT_ID} script="$( cat ~/.kube-linode/install-coreos.sh )" >/dev/null
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
   sed -i.bak '/^API_KEY/d' ~/.kube-linode/settings.env
   echo "API_KEY=$API_KEY" >> ~/.kube-linode/settings.env
   rm ~/.kube-linode/settings.env.bak
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
      echo "MASTER_PLAN=$MASTER_PLAN" >> ~/.kube-linode/settings.env
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
      echo "WORKER_PLAN=$WORKER_PLAN" >> ~/.kube-linode/settings.env
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
      echo "DATACENTER_ID=$DATACENTER_ID" >> ~/.kube-linode/settings.env
  fi
}

read_domain() {
  if ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; then
      while ! [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]] 2>/dev/null; do
         text_input "Enter Domain Name: " DOMAIN "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$" "Please enter a valid domain name"
      done
      echo "DOMAIN=$DOMAIN" >> ~/.kube-linode/settings.env
  fi
  tput civis
}

read_email() {
  email_regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
  if ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; then
      while ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; do
         text_input "Enter Email: " EMAIL "^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$" "Please enter a valid email"
      done
      echo "EMAIL=$EMAIL" >> ~/.kube-linode/settings.env
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
  linode_api domain.create DomainID=$DOMAIN_ID Domain="$DOMAIN" TTL_sec=300 axfr_ips="none" Expire_sec=604800 \
                           SOA_Email="$EMAIL" Retry_sec=300 status=1 Refresh_sec=300 Type=master >/dev/null
}

update_dns() {
  local LINODE_ID=$1
  local DOMAIN_ID
  local IP
  local IP_ADDRESS_ID
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
      echo "NO_OF_WORKERS=$NO_OF_WORKERS" >> ~/.kube-linode/settings.env
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
