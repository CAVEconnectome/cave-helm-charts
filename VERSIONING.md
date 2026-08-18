# Versioning and releasing charts

## The rule

Every chart carries two numbers in `Chart.yaml`, and they mean different things:

- **`appVersion`** — the version of the *application image* the chart deploys.
- **`version`** — the version of the *chart itself*. This is what consumers pin.

| What changed | `version` | `appVersion` |
|---|---|---|
| Application image only | `= appVersion` (no suffix) | new app version |
| Chart only (templates/values) | bump **patch**, add **`-r.N`** | **unchanged** |
| Both | `= appVersion` (no suffix) | new app version |

Worked example, starting from app `5.26.0`:

```
5.26.0        appVersion 5.26.0    app release
5.26.1-r.1    appVersion 5.26.0    chart-only change   (patch bumped, appVersion held)
5.26.1-r.2    appVersion 5.26.0    another chart-only change
5.26.1        appVersion 5.26.1    app release -- suffix dropped, appVersion catches up
5.26.2-r.1    appVersion 5.26.1    chart-only change
```

The chart-only versions are prereleases of the *next* patch. If the next app release turns out to be
a minor bump instead (`5.27.0`), that is fine — `5.27.0` still sorts above `5.26.1-r.2`, and the
`5.26.1-r.*` line simply never gets a `5.26.1` release.

## Why the patch bump, and why hold `appVersion`

Both halves of the rule fix a real failure we hit on 2026-08-18.

**Bump the patch so the newest chart sorts highest.** The earlier convention suffixed the *current*
version (`5.26.0` → `5.26.0-r1`). But in semver a prerelease sorts *below* its own release, so the
newest chart ranked below the one it superseded. Verified with `helm repo index`, which is Helm's
own sort:

```
5.26.1-r1 > 5.26.0     <- patch bumped: newest chart ranks highest   correct
5.26.0-r1 < 5.26.0     <- old scheme:   newest chart ranked LOWEST   wrong
5.26.1    > 5.26.1-r2  <- the eventual app release outranks its chart-only predecessors
```

**Don't reuse a version you will want later.** A chart-only change once went out as plain `5.26.1`,
which consumed the name the eventual `5.26.1` app release needed — the repo would have had to skip a
patch. `5.26.1-r.N` and `5.26.1` are distinct strings, so nothing is burned.

**Holding `appVersion` is what makes a chart-only release actually chart-only.** 15 of the 20 charts
here (32 templates) default their image tag to `.Chart.AppVersion`:

```yaml
{{- $raw := .Values.materialize.tag | default .Values.materialize.version | default .Chart.AppVersion -}}
```

So bumping `appVersion` during a values retune silently changes the deployed image for every consumer
that does not pin a tag. That happened: `appVersion` went `5.25.2` → `5.26.0` alongside a values-only
change, and because minniev7 pinned no tag, a pure chart retune would also have swapped the running
`v5.25.2` image for `v5.26.0`. Holding `appVersion` prevents this structurally, rather than relying
on every consumer to pin a tag.

## Use `-r.N`, not `-rN`

Semver compares non-numeric prerelease identifiers as ASCII strings, and splits on dots. `"r10"` and
`"r9"` are single non-numeric identifiers compared character by character, so `'1' < '9'` and:

```
5.26.1-r10  <  5.26.1-r9      -- plain rN breaks at the 10th release
5.26.1-r.10 >  5.26.1-r.9     -- the dot makes 10 a numeric identifier, compared numerically
```

With `-r.N` the `N` is its own purely-numeric identifier, so it is compared as a number and there is
no ceiling. Both lines above were verified against `helm repo index`.

This is not hypothetical. As of 2026-08-18 `pychunkedgraph` is at `2.20.0-r7` and `tourguide` at
`0.2.3-r8` — three and two chart-only releases respectively from publishing a chart that sorts below
its predecessor. Switch those to `-r.N` at their next chart-only release; already-published `-rN`
tags stay as they are, since renaming a published release is worse than a one-time discontinuity.

## Prereleases are invisible without `--devel`

Anything with a `-` suffix is a semver prerelease, so Helm excludes it from `helm search repo` and
from unpinned `helm install`/`helm upgrade`:

```
helm search repo cave/materializationengine --versions           # highest non-prerelease only
helm search repo cave/materializationengine --versions --devel    # includes -r.N
```

An unpinned consumer resolving "latest" therefore gets the last *app* release and never a chart-only
fix. That is acceptable here because deployments pin exact versions via helmfile:

```yaml
chart: cave/materializationengine
version: 5.26.0-r1     # exact pin -- resolves prereleases fine
```

If a chart ever needs to serve unpinned consumers, the alternative is the stock Helm convention: let
`version` float free of `appVersion` with no suffix at all (chart `5.26.1`, app `5.26.0`), accepting
that the two numbers no longer line up.

## Charts where the two numbers legitimately differ

The `version` base normally equals `appVersion`, which makes the deployed app readable straight off
the chart version. Some charts opt out for good reasons — `skeletoncache` tracks a build tag
(`appVersion: vLoggingArchiveFix11`), and `authinfo`, `infoservice`, `landingpage`, `nglstate` and
`swaggerui` version their charts independently of upstream apps they do not release. That is fine;
the rules that always hold are: **hold `appVersion` for chart-only changes**, and **never publish a
version string you will want later**.

## How publishing works

`.github/workflows/release.yaml` runs [chart-releaser](https://github.com/helm/chart-releaser-action)
on every push to `main`. For each chart whose `version` is new it:

1. packages the chart and creates a GitHub Release tagged `<chart>-<version>` with the `.tgz` attached,
2. rewrites `index.yaml` on the `gh-pages` branch to point at that release asset.

`CR_SKIP_EXISTING: "true"`, so an unchanged `version` is a no-op — **if you forget to bump `version`,
your change is silently not published.** GitHub Pages then serves `index.yaml`, which is what
`helm repo update` reads. Two consequences worth knowing:

- There is a lag between the push and the chart being resolvable, covering the release workflow plus
  the Pages build *and* deploy. Until the Pages **deploy** step finishes, `helm pull --version <new>`
  fails with `no chart version found`.
- Pages cancels an in-flight deployment when a newer push supersedes it, and the legacy Pages API
  reports those cancellations as `errored`. Do not read a red status as a broken build — check the
  `pages build and deployment` run's own steps, and look at whether `Build with Jekyll` succeeded,
  before concluding anything is wrong.

## Unpublishing a chart version

Only for a version published in error, and only if nothing consumes it. Check the download count
first:

```bash
gh api repos/CAVEconnectome/cave-helm-charts/releases/tags/<chart>-<version> \
  --jq '.assets[] | "\(.name): \(.download_count) downloads"'
```

Then delete the release and tag, and remove the `index.yaml` entry:

```bash
gh release delete <chart>-<version> --repo CAVEconnectome/cave-helm-charts --yes --cleanup-tag
# then on gh-pages, delete that chart's entry block from index.yaml and push
```

When editing `index.yaml`, **match on the chart's `.tgz` URL, not on the version string.** Different
charts share version numbers — removing `materializationengine 5.26.1` while `emannotationschemas`
was also at `5.26.1` nearly delisted the wrong chart. Assert that the block you delete contains both
`name: <chart>` and `<chart>-<version>.tgz`, and re-verify the other chart afterwards.
