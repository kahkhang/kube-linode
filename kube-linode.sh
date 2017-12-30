#!/bin/bash
set +e
base64_args=""
$(base64 --wrap=0 <(echo "test") >/dev/null 2>&1)
if [ $? -eq 0 ]; then
    base64_args="--wrap=0"
fi
set -e

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source $DIR/display.sh
source $DIR/linode-utilities.sh

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

unset DATACENTER_ID
unset MASTER_PLAN
unset WORKER_PLAN
unset DOMAIN
unset EMAIL
unset MASTER_ID
unset API_KEY
unset USERNAME
unset NO_OF_WORKERS

stty -echo
tput civis

if [ -f $DIR/settings.env ] ; then
    . $DIR/settings.env
else
    touch $DIR/settings.env
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

if [ "$1" == "teardown" ]; then
  spinner "Retrieving master linode (if any)" get_master_id MASTER_ID

  if [ -z "$MASTER_ID" ]; then
    exit "No Master node found!"
  fi

  spinner "Retrieving worker linodes (if any)" list_worker_ids WORKER_IDS

  if [ -z "$WORKER_IDS" ]; then
    exit "No Worker node found!"
  fi

  text_input "Are you sure you want to delete the local cluster? [y/N]" response

  if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    # TODO: gracefully shutdown
    for WORKER_ID in $WORKER_IDS; do
      spinner \
        "${CYAN}[$WORKER_ID]${NORMAL} Deleting worker" \
        "delete_linode $WORKER_ID"
    done

    spinner \
      "${CYAN}[$MASTER_ID]${NORMAL} Deleting master" \
      "delete_linode $MASTER_ID"

    spinner \
      "Deleting domain..." delete_domain

    rm -rf $DIR/cluster
    rm -rf $HOME/.kube
    rm $DIR/auth
    rm $DIR/settings.env
  fi

  exit 0
fi

if [[ ! ( -f ~/.ssh/id_rsa && -f ~/.ssh/id_rsa.pub ) ]]; then
    spinner "Generating new SSH key" "ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N \"\""
else
    eval `ssh-agent -s` >/dev/null 2>&1
    ssh-add -l | grep -q "$(ssh-keygen -lf ~/.ssh/id_rsa  | awk '{print $2}')" || ssh-add ~/.ssh/id_rsa >/dev/null 2>&1
fi

if [[ -f $DIR/auth && -f $DIR/manifests/grafana/grafana-credentials.yaml ]]  ; then : ; else
    read -s -p "Enter your dashboard password: " PASSWORD
    tput cub "$(tput cols)"
    tput el
    [ -e $DIR/auth ] && rm $DIR/auth
    htpasswd -b -c $DIR/auth $USERNAME $PASSWORD >/dev/null 2>&1
    [ -e $DIR/manifests/grafana/grafana-credentials.yaml ] && rm $DIR/manifests/grafana/grafana-credentials.yaml
cat > $DIR/manifests/grafana/grafana-credentials.yaml <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-credentials
data:
  user: $( echo -n $USERNAME | base64 $base64_args )
  password: $( echo -n $PASSWORD | base64 $base64_args )
EOF
fi

spinner "Updating install script" update_script SCRIPT_ID

spinner "Retrieving master linode (if any)" get_master_id MASTER_ID

if ! [[ $MASTER_ID =~ ^-?[0-9]+$ ]] 2>/dev/null; then
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

spinner "${CYAN}[$MASTER_ID]${NORMAL} Getting private IP" "get_private_ip $MASTER_ID" PRIVATE_IP
declare "PRIVATE_$MASTER_ID=$PRIVATE_IP"

spinner "${CYAN}[$MASTER_ID]${NORMAL} Retrieving provision status" "is_provisioned $MASTER_ID" IS_PROVISIONED

if [ $IS_PROVISIONED = false ] ; then
  update_dns $MASTER_ID
  install master $MASTER_ID
fi

tput el
echo "${CYAN}[$MASTER_ID]${NORMAL} Master provisioned (IP: $MASTER_IP)"

spinner "${CYAN}[$MASTER_ID]${NORMAL} Retrieving current number of workers" get_no_of_workers CURRENT_NO_OF_WORKERS
NO_OF_NEW_WORKERS=$( echo "$NO_OF_WORKERS - $CURRENT_NO_OF_WORKERS" | bc )

if [[ $NO_OF_NEW_WORKERS -gt 0 ]]; then
    for WORKER in $( seq $NO_OF_NEW_WORKERS ); do
        spinner "Creating worker linode" "create_linode $DATACENTER_ID $WORKER_PLAN" WORKER_ID
        spinner "Adding private IP" "add_private_ip $WORKER_ID"
        spinner "Initializing labels" "change_to_unprovisioned $WORKER_ID worker"
    done
fi

spinner "${CYAN}[$MASTER_ID]${NORMAL} Retrieving list of workers" list_worker_ids WORKER_IDS

for WORKER_ID in $WORKER_IDS; do
   spinner "${CYAN}[$WORKER_ID]${NORMAL} Getting public IP" "get_public_ip $WORKER_ID" PUBLIC_IP
   declare "PUBLIC_$WORKER_ID=$PUBLIC_IP"

   spinner "${CYAN}[$WORKER_ID]${NORMAL} Getting private IP" "get_private_ip $WORKER_ID" PRIVATE_IP
   declare "PRIVATE_$WORKER_ID=$PRIVATE_IP"

   if [ "$( is_provisioned $WORKER_ID )" = false ] ; then
     install worker $WORKER_ID
   fi
   tput el
   echo "${CYAN}[$WORKER_ID]${NORMAL} Worker provisioned (IP: $PUBLIC_IP)"
done

wait

tput cnorm
stty echo
