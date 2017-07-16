#!/bin/bash
set -e
mkdir -p ~/.kube-linode
echo -ne '                          (0%)\r'
[ -e ~/.kube-linode/install-coreos.sh ] && rm ~/.kube-linode/install-coreos.sh
[ -e ~/.kube-linode/kube-linode.sh ] && rm ~/.kube-linode/kube-linode.sh
[ -e ~/.kube-linode/utilities.sh ] && rm ~/.kube-linode/utilities.sh
[ -e ~/.kube-linode/inquirer.sh ] && rm ~/.kube-linode/inquirer.sh
[ -e ~/.kube-linode/ora.sh ] && rm ~/.kube-linode/ora.sh

[ -e ~/.kube-linode/heapster.yaml ] && rm ~/.kube-linode/heapster.yaml
[ -e ~/.kube-linode/kube-dashboard.yaml ] && rm ~/.kube-linode/kube-dashboard.yaml
[ -e ~/.kube-linode/local-storage.yaml ] && rm ~/.kube-linode/local-storage.yaml
[ -e ~/.kube-linode/traefik.yaml ] && rm ~/.kube-linode/traefik.yaml

echo -ne '#####                     (33%)\r'
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/install-coreos.sh > ~/.kube-linode/install-coreos.sh
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/heapster.yaml > ~/.kube-linode/heapster.yaml
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/kube-dashboard.yaml > ~/.kube-linode/kube-dashboard.yaml
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/local-storage.yaml > ~/.kube-linode/local-storage.yaml
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/traefik.yaml > ~/.kube-linode/traefik.yaml

echo -ne '#############             (66%)\r'
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/kube-linode.sh > ~/.kube-linode/kube-linode.sh
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/inquirer.sh > ~/.kube-linode/inquirer.sh
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/ora.sh > ~/.kube-linode/ora.sh
echo -ne '####################      (90%)\r'
curl -s -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/kahkhang/kube-linode/master/utilities.sh > ~/.kube-linode/utilities.sh

chmod +x ~/.kube-linode/kube-linode.sh

[ ! -e /usr/local/bin/kube-linode ] && ln -s ~/.kube-linode/kube-linode.sh /usr/local/bin/kube-linode
hash kube-linode

echo -ne '######################   (100%)\n'
echo 'kube-linode installed! 🎉             '
echo "Run \`kube-linode\` to provision a cluster"
