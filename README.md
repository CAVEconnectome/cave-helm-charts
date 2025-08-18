# cave-helm-charts
repository to store helm charts for deploying CAVE services to kubernetes

## Overview

This repository contains Helm charts for deploying CAVE services onto Kubernetes. These charts are primarily developed and validated on Google Cloud (GKE) and integrate with Google Cloud services such as Pub/Sub, Cloud Storage, and Workload Identity.

These charts are intended to be used in concert with the Terraform modules in the companion repository:

- Terraform modules: https://github.com/CAVEconnectome/terraform-google-cave

That repository provisions cluster infrastructure and renders sane defaults for various chart values (for example, queue/exchange names, Bigtable instances, Redis, and credentials wiring) to streamline deployments.

## Cloud and platform compatibility

The charts target Google Kubernetes Engine (GKE) and Google Cloud primitives. When running on other Kubernetes platforms, you may need to adapt:

- Eventing/scalers: KEDA configurations using the GCP Pub/Sub scaler.
- Auth: Workload Identity and Google IAM annotations on ServiceAccounts.
- Storage and buckets: Google Cloud Storage paths and related environment variables.
- Monitoring: Google Managed Prometheus (GMP) PodMonitoring resources/annotations.
- Ingress/load balancing: GKE/GCLB-specific annotations or classes.

Contributions to improve portability are welcome.

## instructions to use

```
helm repo add cave https://caveconnectome.github.io/cave-helm-charts/
```

now you can search for charts in this repo 

```
helm search repo cave
```

## Chart docs

- SkeletonCache: charts/skeletoncache/README.md (rate-limiting defaults and how to override per-minute limits)

For additional charts, see the README files under each chart directory in `charts/`.

## Using with Terraform

If you're using Terraform, the companion modules repo (https://github.com/CAVEconnectome/terraform-google-cave) includes templates and wiring to supply defaults and inject environment-specific settings into these charts. Refer to that repo's documentation for end-to-end cluster provisioning and Helm deployment flows.