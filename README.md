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

## Versioning and releasing

Read [VERSIONING.md](VERSIONING.md) before bumping a chart. In short:

- **version and appVersion bump together**: In general, we want the version of the chart and the code version to move together.  If you release a new version of the code, this should create an identical new version of the chart. So in general, set `version` equal to the new `appVersion`, with no suffix.
- **Chart-only change** (templates or values): The exception is if you need to change the chart without releasing new code.  In this case, bump the **patch** of `version` and add an **`-r.N`**
  suffix, and leave `appVersion` alone. e.g. `5.26.0` → `5.26.1-r.1`.  When a new appVersion comes out, it will supercede this release version. e.g `5.26.1 > 5.26.1.-r.1`

Both halves matter. The patch bump is what makes the newest chart sort *highest* (a prerelease of the
current version sorts below it, so suffixing without bumping ranks the new chart lowest). Holding
`appVersion` is what keeps a chart-only release from changing the deployed image — 15 of the 20 charts
default their image tag to `.Chart.AppVersion`. Use `-r.N` rather than `-rN`, because `r10` sorts
*below* `r9`.

## Cross-chart conventions

### Ingress request body size

Every chart that ships an `Ingress` exposes it in the same place — under the service's own values key,
then `ingress`, then `proxyBodySize`:

```yaml
materialize:          # or pychunkedgraph, skeletoncache, auth, ...
  ingress:
    proxyBodySize: "10m"
```

It renders to `nginx.ingress.kubernetes.io/proxy-body-size`. The default is `10m` everywhere, against
ingress-nginx's own default of `1m`. The reason for a uniform, explicit parameter rather than the
nginx default: over the cap the **ingress** returns its own nginx 413 before the request ever reaches
the application, so nothing is logged app-side and the failure is expensive to trace. `pcgl2cache` hit
exactly this on `/l2cache/api/v1/table/<t>/attributes`, which POSTs an L2 id list.

Templates read it as `{{ (.Values.<svc>.ingress).proxyBodySize | default "10m" | quote }}`. The
parentheses are load-bearing: they make the lookup nil-safe, so a consumer whose values file omits or
nulls `ingress` still renders instead of failing with `nil pointer evaluating interface {}`.

`edge` is the one chart with a legacy path — the value used to live inside its free-form
`edge.annotations` map. An explicit `nginx.ingress.kubernetes.io/proxy-body-size` there still wins, and
is omitted from the merged map so the annotation is emitted exactly once.

## Chart docs

- SkeletonCache: charts/skeletoncache/README.md (rate-limiting defaults and how to override per-minute limits)

For additional charts, see the README files under each chart directory in `charts/`.

## Using with Terraform

If you're using Terraform, the companion modules repo (https://github.com/CAVEconnectome/terraform-google-cave) includes templates and wiring to supply defaults and inject environment-specific settings into these charts. Refer to that repo's documentation for end-to-end cluster provisioning and Helm deployment flows.