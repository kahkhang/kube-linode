## Provision a Kubernetes / CoreOS Cluster on Linode

Automatically provisions a scalable CoreOS/Kubernetes cluster on Linode, comprising of a single schedulable Kubernetes master host with a custom number of worker nodes.

There is zero configuration needed (all you need is an API Key with a valid domain that uses [Linode's DNS servers](https://www.linode.com/docs/networking/dns/dns-manager-overview#set-domain-names-to-use-linodes-name-servers))

### What's included
* Load Balancer and automatic SSL/TLS renewal using [Traefik](https://github.com/containous/traefik)
* Two basic auth protected subdomains (assuming you are using example.com):
  * https://kube.example.com ([Kubernetes Dashboard](https://github.com/kubernetes/dashboard))
  * https://traefik.example.com ([Traefik Web UI](https://github.com/containous/traefik#web-ui))
* [Flannel](https://github.com/coreos/flannel/blob/master/README.md) cluster networking
* Metric collection using [Heapster](https://github.com/kubernetes/heapster)
* [Local persistent volumes](https://github.com/kubernetes-incubator/external-storage/blob/master/local-volume/README.md)


### Requirements
This shell script uses the following programs: `jq`, `openssl`, `curl`, `htpasswd`.
`htpasswd`, `openssl`, and `curl` should be preinstalled with MacOS.

You should also have a Linode Account, which you can get [here](https://www.linode.com/?r=0affaec6ca42ca06f5f2c2d3d8d1ceb354e222c1).

To install using OSX's [homebrew](https://brew.sh/):
```sh
brew install jq openssl curl kubectl
```

### Usage

To download the script and run it:
```sh
(curl https://raw.githubusercontent.com/kahkhang/kube-linode/master/install.sh) | sh
```

Settings are stored in `settings.env`. If the script has been run at least once, to increase the number of workers, simply modify `NO_OF_WORKERS` in `settings.env` to your desired worker count, then run `./kube-linode.sh` again.

### Acknowledgements
This source code was based on APIC-NET's [k8s-cluster](https://github.com/APNIC-net/linode-k8s-cluster), using a
modified version of [CoreOS](https://coreos.com/kubernetes/docs/latest/getting-started.html)'s manual installation instructions and [Linode's API](https://www.linode.com/api).
