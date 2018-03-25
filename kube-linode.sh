#!/bin/bash
set +e
base64_args=""
$(base64 --wrap=0 <(echo "test") >/dev/null 2>&1)
if [ $? -eq 0 ]; then
    base64_args="--wrap=0"
fi
set -e

source display.sh
source linode-utilities.sh

check_dep jq
check_dep openssl
check_dep curl
check_dep htpasswd
check_dep kubectl
check_dep ssh
check_dep base64
check_dep bc
check_dep ssh-keygen
check_dep openssl
check_dep awk
check_dep sed
check_dep cat
check_dep tr

if [[ "$1" != "create" && "$1" != "destroy" ]]; then
  echo "${bold}${red}Not a valid action!${normal}"
  echo "Type ${green}./kube-linode.sh create${normal} to create a cluster"
  echo "Type ${green}./kube-linode.sh destroy${normal} to destroy created cluster"
  exit 1
fi

unset DATACENTER_ID
unset MASTER_PLAN
unset WORKER_PLAN
unset DOMAIN
unset EMAIL
unset MASTER_ID
unset API_KEY
unset USERNAME
unset NO_OF_WORKERS
unset REBOOT_STRATEGY
unset WORKER_IDS

stty -echo
tput civis

if [ -f settings.env ] ; then
    . settings.env
else
    touch settings.env
fi

# -- command line argument overrides --
options=$@

for argument in $options
  do
    case $argument in
      --datacenter_id=*)           DATACENTER_ID=${argument/*=/""} ;;
      --master_plan=*)             MASTER_PLAN=${argument/*=/""} ;;
      --worker_plan=*)             WORKER_PLAN=${argument/*=/""} ;;
      --no_of_workers=*)           NO_OF_WORKERS=${argument/*=/""} ;;
      --domain=*)                  DOMAIN=${argument/*=/""} ;;
      --email=*)                   EMAIL=${argument/*=/""} ;;
      --master_id=*)               MASTER_ID=${argument/*=/""} ;;
      --api_key=*)                 API_KEY=${argument/*=/""} ;;
      --username=*)                USERNAME=${argument/*=/""} ;;
      --install_k8s_dashboard=*)   INSTALL_K8S_DASHBOARD=${argument/*=/""} ;;
      --install_traefik=*)         INSTALL_TRAEFIK=${argument/*=/""} ;;
      --install_rook=*)            INSTALL_ROOK=${argument/*=/""} ;;
      --install_prometheus=*)      INSTALL_PROMETHEUS=${argument/*=/""} ;;
      --reboot_strategy=*)         REBOOT_STRATEGY=${argument/*=/""} ;;
    esac
  done

read_api_key
read_datacenter
read_master_plan
read_worker_plan
read_domain
read_email
read_no_of_workers
read_username
read_install_options
read_reboot_strategy

if [[ ! ( -f ~/.ssh/id_rsa && -f ~/.ssh/id_rsa.pub ) ]]; then
    spinner "Generating new SSH key" "ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N \"\""
else
    eval `ssh-agent -s` >/dev/null 2>&1
    ssh-add -l | grep -q "$(ssh-keygen -lf ~/.ssh/id_rsa  | awk '{print $2}')" || ssh-add ~/.ssh/id_rsa >/dev/null 2>&1
fi

if [[ -f auth && -f manifests/grafana/grafana-credentials.yaml ]]  ; then : ; else
    read -s -p "${green}?${normal}${bold} Enter your dashboard password: ${normal}" PASSWORD
    tput cub "$(tput cols)"
    tput el
    [ -e auth ] && rm auth
    htpasswd -b -c auth $USERNAME $PASSWORD >/dev/null 2>&1
    [ -e manifests/grafana/grafana-credentials.yaml ] && rm manifests/grafana/grafana-credentials.yaml
cat > manifests/grafana/grafana-credentials.yaml <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-credentials
data:
  user: $( echo -n $USERNAME | base64 $base64_args )
  password: $( echo -n $PASSWORD | base64 $base64_args )
EOF
fi

if [ "$1" == "destroy" ]; then
  spinner "Retrieving master linode (if any)" get_master_id MASTER_ID
  if ! [[ $MASTER_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
    tput el
    echo "${red}No master node found! Cluster is likely to have been deleted.${normal}"
  else
    spinner "Retrieving worker linodes (if any)" list_worker_ids WORKER_IDS
    tput el
    echo "${bold}${red}The following nodes will be deleted:${normal}"
    echo "  ${cyan}${arrow}${normal} master_$MASTER_ID [https://manager.linode.com/linodes/dashboard/master_$MASTER_ID]"
    for WORKER_ID in $WORKER_IDS; do
      echo "  ${cyan}${arrow}${normal} worker_$WORKER_ID [https://manager.linode.com/linodes/dashboard/worker_$WORKER_ID]"
    done
    text_input "Are you sure you want to delete the cluster? [y/n] " \
      response "^[yn]$" "Please enter either 'y' or 'n'"
    tput civis

    if [[ "$response" =~ ^y$ ]]; then
      for WORKER_ID in $WORKER_IDS; do
        spinner "${CYAN}[$WORKER_ID]${NORMAL} Deleting worker node" "delete_linode $WORKER_ID"
      done
      spinner "${CYAN}[$MASTER_ID]${NORMAL} Deleting master node" "delete_linode $MASTER_ID"
    fi
  fi
  spinner "Retrieving DNS record for $DOMAIN" "get_domains \"$DOMAIN\"" DOMAIN_ID
  if [[ $DOMAIN_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
    text_input "Do you want to delete the DNS record for $DOMAIN? [y/n] " \
      response "^[yn]$" "Please enter either 'y' or 'n'"
    tput civis
    if [[ "$response" =~ ^y$ ]]; then
      spinner "Deleting DNS record for $DOMAIN" delete_domain
    fi
  fi

  text_input "Do you want to delete the current cluster configuration (including ~/.kube/config)? [y/n] " \
    response "^[yn]$" "Please enter either 'y' or 'n'"
  tput civis
  if [[ "$response" =~ ^y$ ]]; then
    [ -e manifests/grafana/grafana-credentials.yaml ] && rm manifests/grafana/grafana-credentials.yaml
    [ -e cluster ] && rm -rf cluster
    [ -e ~/.kube/config ] && rm ~/.kube/config
    [ -e auth ] && rm auth
    [ -e settings.env ] && rm settings.env
    touch settings.env
    echo "API_KEY=$API_KEY" >> settings.env
  fi
elif [ "$1" == "create" ]; then
  spinner "Retrieving master linode (if any)" get_master_id MASTER_ID

  if ! [[ $MASTER_ID =~ ^[0-9]+$ ]] 2>/dev/null; then
     spinner "Retrieving list of workers" list_worker_ids WORKER_IDS
     for WORKER_ID in $WORKER_IDS; do
        spinner "${CYAN}[$WORKER_ID]${NORMAL} Deleting worker (since certs are now invalid)"\
                    "linode_api linode.delete LinodeID=$WORKER_ID skipChecks=true"
     done

     spinner "Creating master linode" "create_linode $DATACENTER_ID $MASTER_PLAN" MASTER_ID
     spinner "Adding private IP" "add_private_ip $MASTER_ID"

     spinner "${CYAN}[$MASTER_ID]${NORMAL} Initializing labels" \
             "linode_api linode.update LinodeID=$MASTER_ID Label=\"master_${MASTER_ID}\" lpm_displayGroup=\"$DOMAIN (Unprovisioned)\""
  fi

  spinner "${CYAN}[$MASTER_ID]${NORMAL} Getting public IP" "get_public_ip $MASTER_ID" MASTER_IP
  declare "PUBLIC_$MASTER_ID=$MASTER_IP"

  spinner "${CYAN}[$MASTER_IP]${NORMAL} Getting private IP" "get_private_ip $MASTER_ID" PRIVATE_IP
  declare "PRIVATE_$MASTER_ID=$PRIVATE_IP"

  spinner "${CYAN}[$MASTER_IP]${NORMAL} Retrieving provision status" "is_provisioned $MASTER_ID" IS_PROVISIONED

  if [ $IS_PROVISIONED = false ] ; then
    update_dns $MASTER_ID
    install master $MASTER_ID
  fi

  tput el
  echo "${CYAN}[$MASTER_IP]${NORMAL} Master provisioned"

  spinner "${CYAN}[$MASTER_IP]${NORMAL} Retrieving current number of workers" get_no_of_workers CURRENT_NO_OF_WORKERS
  NO_OF_NEW_WORKERS=$( echo "$NO_OF_WORKERS - $CURRENT_NO_OF_WORKERS" | bc )

  if [[ $NO_OF_NEW_WORKERS -gt 0 ]]; then
      for WORKER in $( seq $NO_OF_NEW_WORKERS ); do
          spinner "Creating worker linode" "create_linode $DATACENTER_ID $WORKER_PLAN" WORKER_ID
          spinner "Adding private IP" "add_private_ip $WORKER_ID"
          spinner "Initializing labels" "change_to_unprovisioned $WORKER_ID worker"
      done
  fi

  spinner "Retrieving list of workers" list_worker_ids WORKER_IDS

  for WORKER_ID in $WORKER_IDS; do
     spinner "${CYAN}[$WORKER_ID]${NORMAL} Getting public IP" "get_public_ip $WORKER_ID" PUBLIC_IP
     declare "PUBLIC_$WORKER_ID=$PUBLIC_IP"

     spinner "${CYAN}[$PUBLIC_IP]${NORMAL} Getting private IP" "get_private_ip $WORKER_ID" PRIVATE_IP
     declare "PRIVATE_$WORKER_ID=$PRIVATE_IP"

     if [ "$( is_provisioned $WORKER_ID )" = false ] ; then
       install worker $WORKER_ID
     fi
     tput el
     echo "${CYAN}[$PUBLIC_IP]${NORMAL} Worker provisioned"
  done
fi

wait

tput cnorm
stty echo
