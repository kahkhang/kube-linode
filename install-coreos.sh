#!/bin/bash

wget --no-check-certificate https://github.com/coreos/container-linux-config-transpiler/releases/download/v0.5.0/ct-v0.5.0-x86_64-unknown-linux-gnu -O ct
chmod +x ct
apt-get -y install gawk
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
chmod u+x coreos-install
./coreos-install -d /dev/sda -i container-linux-config.json
reboot
