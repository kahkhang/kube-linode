## Provision a Kubernetes / CoreOS Cluster on Linode  [![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/kahkhang/kube-linode/master/LICENSE) [![Twitter](https://img.shields.io/twitter/url/https/github.com/kahkhang/kube-linode.svg?style=social)](https://twitter.com/intent/tweet?text=Wow:&url=%5Bobject%20Object%5D)

Automatically provisions a scalable CoreOS/Kubernetes cluster on Linode, comprising of a single schedulable Kubernetes master host with a custom number of worker nodes.

There is zero configuration needed (all you need is an API Key with a valid domain that uses [Linode's DNS servers](https://www.linode.com/docs/networking/dns/dns-manager-overview#set-domain-names-to-use-linodes-name-servers))

![Demo](demo.gif)

### What's included
* Load Balancer and automatic SSL/TLS renewal using [Traefik](https://github.com/containous/traefik)
* Two basic auth protected subdomains (assuming you are using example.com):
  * https://kube.example.com ([Kubernetes Dashboard](https://github.com/kubernetes/dashboard))
  * https://traefik.example.com ([Traefik Web UI](https://github.com/containous/traefik#web-ui))
* [Flannel](https://github.com/coreos/flannel/blob/master/README.md) cluster networking
* Metric collection using [Heapster](https://github.com/kubernetes/heapster)
* Customizable [local persistent volumes](https://github.com/kubernetes-incubator/external-storage/blob/master/local-volume/README.md)

### Usage

To install the script:
```sh
curl -s https://raw.githubusercontent.com/kahkhang/kube-linode/master/install.sh | bash
```

Just type `kube-linode` into your console, and have a :coffee:!
```sh
kube-linode
```

Settings are stored in `~/.kube-linode/settings.env`.

To increase the number of workers, simply modify `NO_OF_WORKERS` in `settings.env` to your desired worker count, then run `kube-linode` again.

### Dependencies
You have a Linode Account, which you can get [here](https://www.linode.com/?r=0affaec6ca42ca06f5f2c2d3d8d1ceb354e222c1).

OSX's [homebrew](https://brew.sh/): ``` brew install jq openssl curl kubectl ```

Arch Linux: Follow the instructions [here](https://github.com/kahkhang/kube-linode/issues/4#issuecomment-311601422)

### Acknowledgements
This source code was based on APIC-NET's [k8s-cluster](https://github.com/APNIC-net/linode-k8s-cluster), using a
modified version of [CoreOS](https://coreos.com/kubernetes/docs/latest/getting-started.html)'s manual installation instructions and [Linode's API](https://www.linode.com/api).
