# Provenance

The container image built from this repository redistributes unmodified binaries
from the upstream project [vul-os/basin](https://github.com/vul-os/basin), licensed
under Apache-2.0 (see [LICENSE](LICENSE), copied from the release artifact).

Each build downloads one release tarball, `basin-<version>-<triple>.tar.gz`, plus the
release `SHA256SUMS`, verifies the digest, and copies two binaries into the runtime
image:

| Binary | Role |
| --- | --- |
| `basin-server` | The pgwire server, the image entrypoint |
| `basinctl` | Operator CLI, unused by the entrypoint |

The only modification applied to the artifacts is `strip --strip-all`, which drops the
debug and symbol tables the upstream release publishes with. No upstream source is
patched here; this repository contains packaging only.
