#!/bin/sh
set -e
mkdir -p ~/.kube-linode
[ -e ~/.kube-linode/install-coreos.sh ] && rm ~/.kube-linode/install-coreos.sh
[ -e ~/.kube-linode/kube-linode.sh ] && rm ~/.kube-linode/kube-linode.sh
[ -e ~/.kube-linode/utilities.sh ] && rm ~/.kube-linode/utilities.sh

curl -s https://raw.githubusercontent.com/kahkhang/kube-linode/master/install-coreos.sh > ~/.kube-linode/install-coreos.sh
curl -s https://raw.githubusercontent.com/kahkhang/kube-linode/master/kube-linode.sh > ~/.kube-linode/kube-linode.sh
curl -s https://raw.githubusercontent.com/kahkhang/kube-linode/master/utilities.sh > ~/.kube-linode/utilities.sh

chmod +x ~/.kube-linode/install-coreos.sh
chmod +x ~/.kube-linode/kube-linode.sh
chmod +x ~/.kube-linode/utilities.sh

[ ! -e /usr/local/bin/kube-linode ] && ln -s ~/.kube-linode/kube-linode.sh /usr/local/bin/kube-linode && hash -r
