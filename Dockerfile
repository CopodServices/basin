# syntax=docker/dockerfile:1

# Basin is a single Rust binary that speaks pgwire on the front and keeps its
# columnar data on an S3-compatible bucket (or a local directory). This image
# packages the upstream release artifact rather than compiling the workspace:
# the crate graph pulls in the whole DataFusion tree, so a from-source build
# costs tens of minutes of CI per run for a byte-identical result.

ARG DEBIAN_SUITE=trixie-slim

# --- fetch -------------------------------------------------------------------
# Runs on the builder, downloads the release tarball for the target
# architecture, and verifies it against the release SHA256SUMS.
FROM --platform=$BUILDPLATFORM debian:${DEBIAN_SUITE} AS fetch

# Default for a local `docker build .`: the release this repository was last
# verified against. CI and the release workflow always pass an explicit value.
ARG BASIN_VERSION=0.1.10
ARG TARGETARCH

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) triple=x86_64-unknown-linux-gnu ;; \
        arm64) triple=aarch64-unknown-linux-gnu ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/vul-os/basin/releases/download/v${BASIN_VERSION}"; \
    file="basin-${BASIN_VERSION}-${triple}.tar.gz"; \
    curl --fail --silent --show-error --location --retry 3 --output "${file}" "${base}/${file}"; \
    curl --fail --silent --show-error --location --retry 3 --output SHA256SUMS "${base}/SHA256SUMS"; \
    grep " ${file}\$" SHA256SUMS > "${file}.sha256"; \
    sha256sum --check "${file}.sha256"; \
    tar --extract --gzip --file "${file}" --strip-components=1

# --- strip -------------------------------------------------------------------
# The release ships unstripped debug builds (~327 MiB for basin-server). binutils
# in the fetch stage runs on the builder, so it cannot read an ELF for another
# architecture (strip: Unable to recognise the format). This stage is the target
# architecture, running under emulation for a cross build, so its own strip
# always matches the binary it is handed.
FROM debian:${DEBIAN_SUITE} AS strip

RUN apt-get update \
    && apt-get install --yes --no-install-recommends binutils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /src/basin-server /src/basinctl /usr/local/bin/

RUN strip --strip-all /usr/local/bin/basin-server /usr/local/bin/basinctl

# --- runtime -----------------------------------------------------------------
FROM debian:${DEBIAN_SUITE} AS runtime

LABEL org.opencontainers.image.title="basin-server" \
      org.opencontainers.image.description="Serverless Postgres on an S3-compatible bucket: multi-tenant, bucket-native, self-hosted" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/vul-os/basin"

# ca-certificates for the object store and any HTTPS dial; netcat for the
# health probe below (basin-server itself is fully static apart from glibc).
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && install --directory --owner 65534 --group 65534 /var/basin

COPY --from=strip /usr/local/bin/basin-server /usr/local/bin/basin-server
COPY --from=strip /usr/local/bin/basinctl /usr/local/bin/basinctl
COPY --from=fetch /src/LICENSE /usr/share/licenses/basin/LICENSE
COPY --from=fetch /src/README.md /usr/share/licenses/basin/README.md

USER 65534:65534

# HOME must point at the writable data directory: basin resolves its disk
# cache through the platform cache dir, which without HOME lands on a path the
# uid 65534 user cannot create, silently disabling the cache.
ENV HOME=/var/basin \
    BASIN_BIND=0.0.0.0:5432 \
    BASIN_DATA_DIR=/var/basin

VOLUME ["/var/basin"]
EXPOSE 5432

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD ["nc", "-z", "127.0.0.1", "5432"]

ENTRYPOINT ["/usr/local/bin/basin-server"]
