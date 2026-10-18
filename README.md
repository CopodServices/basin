# basin

Packaging for [vul-os/basin](https://github.com/vul-os/basin): the container image
`ghcr.io/copodservices/basin` that runs the basin server.

Basin is a pgwire-speaking database server whose data lives on an S3-compatible
bucket. A project is a bucket prefix rather than a provisioned instance, which is
why it is a candidate for the client-facing database tier: per-customer databases
cost bytes instead of a whole PostgreSQL instance, and their bytes stay out of the
panel database.

This repository holds packaging only. Upstream source is not patched; each build
downloads one upstream release artifact, verifies its SHA-256 against the release
`SHA256SUMS`, strips debug info, and copies the binaries into a Debian runtime.
See [NOTICE.md](NOTICE.md) for the provenance detail and [LICENSE](LICENSE) for the
upstream Apache-2.0 license.

## Images

| Tag | Meaning |
| --- | --- |
| `ghcr.io/copodservices/basin:<version>` | Upstream release `<version>`, for example `0.1.10` |
| `ghcr.io/copodservices/basin:latest` | The newest packaged release |

Both tags are multi-arch (`linux/amd64`, `linux/arm64`). The image runs as UID 65534,
listens on `5432`, keeps its data directory at `/var/basin`, and ships `basin-server`
as the entrypoint plus `basinctl` for operator work.

## Releasing

[`.github/workflows/release.yaml`](.github/workflows/release.yaml) publishes a release
on a schedule: **every Monday at 19:00 Asia/Jakarta** (`0 12 * * 1` in UTC). Each run
asks GitHub for the newest upstream release, and publishes the image only when that
version is not in the registry yet, so quiet weeks produce no image and no noise.

Trigger it by hand with **Actions > Release > Run workflow**, optionally passing a
version and `force: true` to republish a tag that already exists.

## Building locally

```bash
docker build --build-arg BASIN_VERSION=0.1.10 -t basin-server .

docker run --rm --publish 5432:5432 \
  --env BASIN_STORAGE_BACKEND=local \
  --env BASIN_PROJECTS=basin=* \
  --env BASIN_SHARD_ENABLED=1 \
  basin-server

psql --host 127.0.0.1 --port 5432 --username basin
```

`BASIN_CATALOG` defaults to `memory`, which loses all catalog state on restart. A
durable deployment points it at PostgreSQL; see
[`docs/deployment.md`](docs/deployment.md) for the cluster shape.

## Consuming the image

```yaml
containers:
  - name: basin
    image: ghcr.io/copodservices/basin:0.1.10
    env:
      - name: BASIN_BIND
        value: 0.0.0.0:5432
```

The image is private, so a namespace needs a pull secret for `ghcr.io`; the cluster
namespace and manifests live in the
[`infrastructure`](https://github.com/CopodServices/infrastructure) repository.
