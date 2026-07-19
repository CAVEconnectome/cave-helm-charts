# SkeletonCache Helm Chart

## Rate limiting defaults

This chart exposes per-endpoint rate limits via `skeletoncache.limits` (units: requests per minute). At render time, the chart converts these to the `LIMITER_CATEGORIES` environment variable automatically.

- Units: per-minute. Values are rendered as `<N>/minute`.
- Override by creating your own values file and editing the numbers under `skeletoncache.limits`.
- You can still provide a raw string override via `skeletoncache.limiter.categories` if you need full control; when set, that string is used instead of the map.

Example override (values.yaml):

skeletoncache:
  limits:
    get_refusal_list: 200
    query_cache: 150
    skeleton_exists: 150
    get_skeleton_that_exists: 1200
    get_skeleton_that_doesnt_exist: 20
    get_skeleton_via_msg_that_exists: 1200
    get_skeleton_via_msg_that_doesnt_exist: 20
    get_skeletons_bulk: 20
    get_skeletons_bulk_async: 20

## Datastack name remapping

This chart exposes public-facing datastack name remapping via `skeletoncache.datastackRemapping` (a normal map). At render time, the chart converts this to the `SKELETON_DATASTACK_NAME_REMAPPING` environment variable as a JSON string.

- Override by creating your own values file and editing `skeletoncache.datastackRemapping`.
- You can still provide a raw string override via `skeletoncache.datastackRemap` if you need full control (e.g. non-JSON syntax); when set, that string is used instead of the map.

Example override (values.yaml):

skeletoncache:
  datastackRemapping:
    minnie65_public: minnie65_phase3_v1

## Environment variables impacted

- `LIMITER_CATEGORIES`: computed from `skeletoncache.limits` unless `skeletoncache.limiter.categories` is explicitly provided.
- `LIMITER_URI`: set via `skeletoncache.limiter.uri`.
- `SKELETON_DATASTACK_NAME_REMAPPING`: computed from `skeletoncache.datastackRemapping` unless `skeletoncache.datastackRemap` is explicitly provided.
