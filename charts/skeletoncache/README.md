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

## Environment variables impacted

- `LIMITER_CATEGORIES`: computed from `skeletoncache.limits` unless `skeletoncache.limiter.categories` is explicitly provided.
- `LIMITER_URI`: set via `skeletoncache.limiter.uri`.
