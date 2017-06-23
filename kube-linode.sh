#!/bin/bash

set -e
source ~/.kube-linode/utilities.sh

check_dep jq
check_dep openssl
check_dep curl
check_dep htpasswd
check_dep kubectl
check_dep ssh
check_dep base64

unset DATACENTER_ID
unset MASTER_PLAN
unset WORKER_PLAN
unset DOMAIN
unset EMAIL
unset MASTER_ID
unset API_KEY

if [ -f ~/.kube-linode/settings.env ] ; then
    . ~/.kube-linode/settings.env
else
    touch ~/.kube-linode/settings.env
fi

read_api_key
read_datacenter
read_master_plan
read_worker_plan
read_domain
read_email
read_no_of_workers

#TODO: allow entering of username
USERNAME=$( whoami )

if [[ ! ( -f ~/.ssh/id_rsa && -f ~/.ssh/id_rsa.pub ) ]]; then
    echo_pending "Generating new SSH key"
    ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
    echo_completed "Generating new SSH key"
fi

if [ -f auth ]  ; then : ; else
    echo "Key in your dashboard password (Required for https://kube.$DOMAIN, https://traefik.$DOMAIN)"
    htpasswd -c ~/.kube-linode/auth $USERNAME
fi

update_script

echo_pending "Retrieving master linode (if any)"
MASTER_ID=$( get_master_id )
echo_completed "Retrieved master linode" $MASTER_ID

if ! [[ $MASTER_ID =~ ^-?[0-9]+$ ]] 2>/dev/null; then
   echo_pending "Retrieving list of workers"
   WORKER_IDS=$( list_worker_ids )
   echo_completed "Retrieved list of workers"
   for WORKER_ID in $WORKER_IDS; do
      echo_pending "Deleting worker (since certs are now invalid)" $WORKER_ID
      linode_api linode.delete LinodeID=$WORKER_ID skipChecks=true >/dev/null
      echo_completed "Deleted worker" $WORKER_ID
   done
   WORKER_ID=

   echo_pending "Creating master linode"
   MASTER_ID=$( linode_api linode.create DatacenterID=$DATACENTER_ID PlanID=$MASTER_PLAN | jq ".DATA.LinodeID" )
   echo_completed "Created master linode $MASTER_ID"

   echo_pending "Initializing labels" $MASTER_ID
   linode_api linode.update LinodeID=$MASTER_ID Label="master_${MASTER_ID}" lpm_displayGroup="$DOMAIN (Unprovisioned)" >/dev/null
   echo_pending "Initialized labels" $MASTER_ID

   if [ -d ~/.kube-linode/certs ]; then
     echo_pending "Removing existing certificates" $MASTER_ID
     rm -rf ~/.kube-linode/certs;
     echo_completed "Removed existing certificates" $MASTER_ID
   fi
fi

grab_ip $MASTER_ID
MASTER_IP=$( eval echo \$PUBLIC_$MASTER_ID )

echo_pending "Retrieving provision status" $MASTER_ID
if [ "$( is_provisioned $MASTER_ID )" = false ] ; then
  echo_completed "Master node not provisioned" $MASTER_ID
  update_dns $MASTER_ID &
  install master $MASTER_ID

  echo_pending "Setting defaults for kubectl"
  kubectl config set-cluster ${USERNAME}-cluster --server=https://${MASTER_IP}:6443 --certificate-authority=~/.kube-linode/certs/ca.pem >/dev/null
  kubectl config set-credentials ${USERNAME} --certificate-authority=~/.kube-linode/certs/ca.pem --client-key=~/.kube-linode/certs/admin-key.pem --client-certificate=~/.kube-linode/certs/admin.pem >/dev/null
  kubectl config set-context default-context --cluster=${USERNAME}-cluster --user=${USERNAME} >/dev/null
  kubectl config use-context default-context >/dev/null
  echo_completed "Set defaults for kubectl"
else
  echo_completed "Master node provisioned" $MASTER_ID
fi

echo_pending "Retrieving current number of workers" $MASTER_ID
CURRENT_NO_OF_WORKERS=$( echo "$( list_worker_ids | wc -l ) + 0" | bc )
echo_completed "Current number of workers: $CURRENT_NO_OF_WORKERS" $MASTER_ID

NO_OF_NEW_WORKERS=$( echo "$NO_OF_WORKERS - $CURRENT_NO_OF_WORKERS" | bc )
echo_completed "Number of new workers to add: $NO_OF_NEW_WORKERS" $MASTER_ID

if [[ $NO_OF_NEW_WORKERS -gt 0 ]]; then
    for WORKER in $( seq $NO_OF_NEW_WORKERS ); do
        echo_pending "Creating worker linode" $MASTER_ID
        WORKER_ID=$( linode_api linode.create DatacenterID=$DATACENTER_ID PlanID=$WORKER_PLAN | jq ".DATA.LinodeID" )
        linode_api linode.update LinodeID=$WORKER_ID Label="worker_${WORKER_ID}" lpm_displayGroup="$DOMAIN (Unprovisioned)" >/dev/null
        echo_completed "Created worker linode" $WORKER_ID
    done
fi

echo_pending "Retrieving list of workers" $MASTER_ID
WORKER_IDS=$( list_worker_ids )
echo_pending "Retrieved list of workers" $MASTER_ID

for WORKER_ID in $WORKER_IDS; do
   grab_ip $WORKER_ID
   echo_pending "Retrieving provision status" $WORKER_ID
   if [ "$( is_provisioned $WORKER_ID )" = false ] ; then
     echo_completed "Worker not provisioned" $WORKER_ID
     install worker $WORKER_ID &
   else
     echo_completed "Worker provisioned" $WORKER_ID
   fi
done

trap 'kill $(jobs -p) 2>/dev/null' EXIT
wait

echo "Cluster provisioned successfully!"
echo "Worker nodes might take a while to appear on the dashboard."
echo "Go to https://kube.$DOMAIN and https://traefik.$DOMAIN to monitor your cluster."
