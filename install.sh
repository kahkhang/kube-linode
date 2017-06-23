#!/bin/sh
mkdir ~/.kube-linode
curl https://raw.githubusercontent.com/kahkhang/kube-linode/master/install-coreos.sh > ~/.kube-linode/install-coreos.sh
curl https://raw.githubusercontent.com/kahkhang/kube-linode/master/kube-linode.sh > ~/.kube-linode/kube-linode.sh
curl https://raw.githubusercontent.com/kahkhang/kube-linode/master/utilities.sh > ~/.kube-linode/utilities.sh

# chmod +x
chmod +x ~/.kube-linode/install-coreos.sh
chmod +x ~/.kube-linode/kube-linode.sh
chmod +x ~/.kube-linode/utilities.sh

ln -s ~/.kube-linode/kube-linode.sh /usr/local/bin/kube-linode
/usr/local/bin/kube-linode
