#!/bin/bash
set -euo pipefail
[[ -n "$REBOOT_STRATEGY" ]] || die "Need a reboot strategy. Run with eg. '\$REBOOT_STRATEGY=off ./install-coreos.sh'"

PUBLIC_IP=$(ip addr show eth0 | grep "inet\b" | grep "/24" | awk '{print $2}' | cut -d/ -f1)
PRIVATE_IP=$(ip addr show eth0 | grep "inet\b" | grep "/17" | awk '{print $2}' | cut -d/ -f1)

wget --quiet --no-check-certificate https://github.com/coreos/container-linux-config-transpiler/releases/download/v0.5.0/ct-v0.5.0-x86_64-unknown-linux-gnu -O ct
chmod +x ct
apt-get -y install gawk
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
chmod u+x coreos-install

cat container-linux-config.yaml \
  | sed "s/#SSH_KEY#/$(cat ~/.ssh/authorized_keys | grep '^ssh-rsa' | sed -n 1p | sed 's/\//\\\//g')/g" \
  | sed "s/#COREOS_PUBLIC_IPV4#/$PUBLIC_IP/g" \
  | sed "s/#COREOS_PRIVATE_IPV4#/$PRIVATE_IP/g" \
  | sed "s/#HOSTNAME#/$(echo $PUBLIC_IP | sed "s/\./-/g")/g" \
  | sed "s/#GATEWAY#/${PUBLIC_IP%.*}.1/g" \
  | sed "s/#DNS#/$(cat /etc/resolv.conf | awk '/^nameserver /{ print $0 }' | sed 's/nameserver //g' | tr '\n' ' ')/g" \
  | sed "s/#REBOOT_STRATEGY#/${REBOOT_STRATEGY}/g" \
  | ./ct > container-linux-config.json
./coreos-install -d /dev/sda -i container-linux-config.json
