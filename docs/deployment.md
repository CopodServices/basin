# Deploying basin-server

How the packaged image is meant to run on the `copod` k3s cluster. The manifests
themselves live in the [infrastructure](https://github.com/CopodServices/infrastructure)
repository, under the `system-db` namespace, so cluster state stays in one place and
this repository stays packaging.

## What the process needs

| Variable | Purpose |
| --- | --- |
| `BASIN_BIND` | pgwire listen address, `0.0.0.0:5432` in the image |
| `BASIN_CATALOG` | Catalog backend. `memory` is volatile and dev-only; production points at a PostgreSQL DSN, for example `postgres://basin:...@basin-catalog-db-rw.system-db.svc.cluster.local:5432/basin?sslmode=disable` |
| `BASIN_STORAGE_BACKEND` | `local` for a filesystem volume, `s3` or `tigris` for an object store |
| `BASIN_STORAGE_BUCKET`, `BASIN_STORAGE_ENDPOINT`, `BASIN_STORAGE_REGION`, `BASIN_STORAGE_ACCESS_KEY_ID`, `BASIN_STORAGE_SECRET_ACCESS_KEY` | Object store coordinates, required when the backend is `s3` |
| `BASIN_DATA_DIR`, `BASIN_WAL_DIR` | Local working set: the data cache and the WAL. Both belong on a PersistentVolume |
| `BASIN_SHARD_ENABLED` | `1` routes writes through the WAL and compactor, which a durable deployment wants |
| `BASIN_PROJECTS` | Static project list, `user=*` or `user=<ulid>`. Replaces the project-provisioning API for now |
| `BASIN_AUTH_ENABLED` | `1` turns on signup, JWT and refresh handling |

## The two moving parts

**Catalog.** Durable deployments put `BASIN_CATALOG` on PostgreSQL because the catalog
is the commit point for table schemas, snapshot manifests and file references. On this
cluster that is a CloudNativePG cluster of its own, so basin catalog state never shares
an instance with the panel database.

**Object store.** Basin is bucket-native: with `BASIN_STORAGE_BACKEND=s3` the data
directory holds only the cache and the WAL, and every project is a prefix in one bucket.
The alternative, `BASIN_STORAGE_BACKEND=local`, folds storage into `BASIN_DATA_DIR` on a
volume and is the shape for a single-node trial.

## Shape on k3s

```
namespace system-db
|-- Cluster/basin-catalog-db          CloudNativePG, longhorn storage
|-- StatefulSet/minio                 S3-compatible store for the basin bucket
|-- Job/minio-init                    creates the bucket once
|-- Deployment/basin                  the packaged image, 5432
`-- Service/basin                     pgwire entrypoint inside the cluster
```

The panel stops provisioning per-site roles and databases on `panel-db` and hands
clients a basin endpoint instead, which is what keeps customer data off the panel
instance. That integration lives in the panel, not here.
