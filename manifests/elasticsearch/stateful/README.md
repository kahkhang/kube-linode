# Elasticsearch StatefulSet Data Pod
This directory contains Kubernetes configurations which run elasticsearch data pods as a [`StatefulSet`](https://kubernetes.io/docs/concepts/abstractions/controllers/statefulsets/), using storage provisioned using a [`StorageClass`](http://blog.kubernetes.io/2016/10/dynamic-provisioning-and-storage-in-kubernetes.html). Be sure to read and understand the documentation in the root directory, which deploys the data pods as a `Deployment` using an `emptyDir` for storage.

## Storage
The [`gce-storage-class.yaml`](gce-storage-class.yaml) file creates a `StorageClass` which allocates persistent disks in a google compute engine environment. It should be relatively simple to modify this file to suit your needs for a different environment.

The [`es-data-stateful.yaml`](es-data-stateful.yaml) file contains a `volumeClaimTemplates` section which references the `StorageClass` defined in [`gce-storage-class.yaml`](gce-storage-class.yaml), and requests a 12 GB disk. This is plenty of space for a demonstration cluster, but will fill up quickly under moderate to heavy load. Consider modifying the disk size to your needs.

## Deploy
The root directory contains instructions for deploying elasticsearch using a `Deployment` with transient storage for data pods. These brief instructions show a deployment using the `StatefulSet` and `StorageClass`.

```
kubectl create -f manifests/elasticsearch/es-discovery-svc.yaml
kubectl create -f manifests/elasticsearch/es-svc.yaml
kubectl create -f manifests/elasticsearch/es-master.yaml
```

Wait until `es-master` deployment is provisioned, and

```
kubectl create -f manifests/elasticsearch/es-client.yaml
kubectl create -f gce-storage-class.yaml
kubectl create -f manifests/elasticsearch/stateful/es-data-svc.yaml
kubectl create -f manifests/elasticsearch/stateful/es-data-stateful.yaml
```

Kubernetes creates the pods for a `StatefulSet` one at a time, waiting for each to come up before starting the next, so it may take a few minutes for all pods to be provisioned. Refer back to the documentation in the root directory for details on testing the cluster, and configuring a curator job to clean up.
