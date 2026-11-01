# PMOVES Remote-View — self-contained RustDesk server image.
#
# WHY THIS FILE EXISTS
# The fork ships two Dockerfiles that CANNOT build from a plain checkout:
#   - docker/Dockerfile       : FROM busybox + COPY rootfs /  -> the image has no server binaries
#   - docker-classic/Dockerfile: FROM scratch + COPY hbbs /usr/bin/hbbs  -> needs prebuilt binaries
# The fork's own .github/workflows/ghcr.yml papers over this by compiling the binaries in a
# separate CI job and downloading them into docker/rootfs/usr/bin before running
# docker/build-push-action with `context: "./docker"`.
# This root Dockerfile does the compiling itself, so `docker build .` from the repo root yields
# a runnable server image.
#
# EVIDENCE FOR EVERY NON-OBVIOUS CHOICE (all measured in this repo at the pinned commit)
#
# 1. Toolchain 1.81 (NOT ghcr.yml's 1.70.0).
#    Cargo.lock line 4 is `version = 4`. Lockfile v4 requires Cargo >= 1.78; cargo 1.70.0
#    refuses it outright:
#        error: failed to parse lock file at: /w/Cargo.lock
#        Caused by: lock file version `4` was found, but this version of Cargo does not
#        understand this lock file, perhaps Cargo needs to be updated?
#    .github/workflows/build.yaml already uses toolchain "1.81", so 1.81 is the toolchain this
#    repo's lockfile actually accepts.
#
# 2. Target x86_64-unknown-linux-musl, built natively (no cross).
#    .github/workflows/ghcr.yml publishes exactly this target
#    (matrix: { name: "amd64", target: "x86_64-unknown-linux-musl" }), and upstream
#    rustdesk/rustdesk-server does the same. rust:1.81-alpine's host triple IS
#    x86_64-unknown-linux-musl, so the build is native and the resulting binaries are
#    statically linked (musl target defaults to crt-static) -> they run inside the
#    glibc busybox:stable final stage without shipping any shared objects.
#
# 3. libs/hbb_common is a 40-BYTE POINTER FILE, not a submodule checkout.
#        $ git ls-tree HEAD libs/
#        100644 blob baf861b2cbf487e783c47cd2188e010caaee8028    libs/hbb_common
#        $ git cat-file -p baf861b2cbf487e783c47cd2188e010caaee8028
#        83419b6549636ee39dacef7776c473f5802e08d6
#    Cargo.toml needs it as a real path dependency (`hbb_common = { path = "libs/hbb_common" }`,
#    and [workspace] members = ["libs/hbb_common"]), so cargo cannot even parse the manifest
#    without it:
#        error: failed to load manifest for dependency `hbb_common`
#        Caused by: failed to read `/w/libs/hbb_common/Cargo.toml`
#    The file records the exact upstream hbb_common commit (it matches this repo's own history
#    entry "Bump libs/hbb_common from 7cf11f7 to 83419b6"), and .gitmodules names the source:
#        [submodule "libs/hbb_common"] path = libs/hbb_common
#        url = https://github.com/rustdesk/hbb_common
#    So the builder materialises hbb_common from that URL at exactly the recorded SHA — the
#    same content `git submodule update --init --recursive` would have produced for the
#    upstream gitlink. The SHA is read from the repo file at build time, not hardcoded.
#
# 4. sqlite is compiled in, not linked from the system.
#    Cargo.lock pins sqlx 0.6.0 -> sqlx-core 0.6.0 -> libsqlite3-sys 0.24.2, and sqlx-core's
#    manifest enables the "bundled" feature, so libsqlite3-sys builds the vendored
#    sqlite3/sqlite3.c that ships inside the crate. No system sqlite is required.
#
# 5. libsodium is linked statically from the system archive.
#    Cargo.lock pins sodiumoxide -> libsodium-sys 0.2.7. libsodium-sys 0.2.7 builds libsodium
#    from source unless SODIUM_LIB_DIR is set (its build.rs: "Must be called when no
#    SODIUM_USE_PKG_CONFIG env var is set" -> find_libsodium_env -> `cargo:rustc-link-lib=
#    static=sodium`). We point SODIUM_LIB_DIR at Alpine's libsodium-static archive, which keeps
#    the build fast and the final image free of any shared-object dependency.
#
# 6. The s6 service tree is reused byte-for-byte from docker/rootfs/ (this repo's own layout;
#    it is identical to upstream rustdesk/rustdesk-server's docker/rootfs at the same paths).
#    That tree references exactly three binaries:
#        docker/rootfs/etc/s6-overlay/s6-rc.d/hbbs/run  -> /usr/bin/hbbs
#        docker/rootfs/etc/s6-overlay/s6-rc.d/hbbr/run  -> /usr/bin/hbbr
#        docker/rootfs/etc/s6-overlay/s6-rc.d/key-secret/up.real -> /usr/bin/rustdesk-utils
#    (validatekeypair), so all three are produced and installed. Cargo.toml declares all three
#    bins: hbbs (default-run), hbbr (src/hbbr.rs), rustdesk-utils (src/utils.rs).
#
# 7. The final stage runs as root, exactly like this repo's docker/Dockerfile and upstream's
#    published rustdesk-server-s6 image (neither declares a USER). s6-overlay's /init needs root
#    to set up /run and the service directories, and the key-secret service writes the identity
#    keypair into the /data volume. Deliberately matching upstream keeps the runtime behaviour
#    identical; this differs from the uid/gid 65532 convention used by the PMOVES Python
#    service images, which are plain single-process images with no init system.

# ---------------------------------------------------------------------------
# Builder: compile hbbs / hbbr / rustdesk-utils for x86_64-unknown-linux-musl
# ---------------------------------------------------------------------------
FROM rust:1.81-alpine AS builder

# Build tooling for this crate graph:
#   git   -> cargo fetches git dependencies (async-speed-limit, reqwest fork, confy,
#            tokio-socks, sysinfo, default_net, machine-uid) and hbb_common itself
#   make  -> C build scripts of the vendored zstd / sqlite3 / libsodium sources
#   perl  -> C build scripts of the vendored ring / protobuf sources
#   pkgconf -> pkg-config backend used by some -sys build scripts
#   libsodium-static -> static libsodium.a for SODIUM_LIB_DIR (see note 5 above)
#   build-base/gcc   -> the C compiler that drives the -sys crates' cc builds
#   musl-dev        -> the musl CRT objects (crti.o / crn.o / crt1.o) that the
#                      x86_64-unknown-linux-musl LINK step needs. Without it every
#                      proc-macro crate fails to link:
#                          ld: cannot find crti.o: No such file or directory
#                          (paste-1.0.15 / dlopen_derive / time-macros)
#                      rust:1.81-alpine ships the compiler but not the musl CRT
#                      development files.
RUN apk add --no-cache build-base musl-dev git make perl pkgconf libsodium-dev libsodium-static

WORKDIR /src

# Manifest + lockfile first so dependency resolution is cached independently of the sources.
COPY Cargo.toml Cargo.lock ./
COPY .cargo/ ./.cargo/
COPY build.rs ./
COPY src/ ./src/

# libs/ carries libs/hbb_common, which at this commit is the 40-byte SHA pointer file.
# Fetch the real hbb_common at that exact SHA into the path cargo expects.
COPY libs/ ./libs/
COPY .env ./.env
COPY db_v2.sqlite3 ./db_v2.sqlite3

# .env supplies DATABASE_URL=sqlite://./db_v2.sqlite3. sqlx's query!/query_as! macros type-check
# against a live database at compile time (sqlx-macros 0.6.0 reads .env from CARGO_MANIFEST_DIR
# and then requires DATABASE_URL), and this repo's src/database.rs uses those macros against the
# `peer` table that db_v2.sqlite3 defines. Upstream documents the same split: DATABASE_URL is
# compile-time only, DB_URL is the runtime variable.
RUN set -eux; \
    hbb_sha="$(cat libs/hbb_common)"; \
    rm -f libs/hbb_common; \
    mkdir -p libs/hbb_common; \
    cd libs/hbb_common; \
    git init -q .; \
    git remote add origin https://github.com/rustdesk/hbb_common.git; \
    git fetch -q --depth 1 origin "$hbb_sha"; \
    git checkout -q FETCH_HEAD; \
    rm -rf .git; \
    cd /src; \
    test -f libs/hbb_common/Cargo.toml

# SODIUM_LIB_DIR -> static libsodium (see note 5).
ENV SODIUM_LIB_DIR=/usr/lib
# Fully static musl binary: no dynamic loader or shared object is needed at runtime.
ENV RUSTFLAGS="-C target-feature=+crt-static"

# --all-features and --release mirror .github/workflows/ghcr.yml:
#   cargo build --release --all-features --target=x86_64-unknown-linux-musl
RUN cargo build --release --all-features --target x86_64-unknown-linux-musl

# ---------------------------------------------------------------------------
# Final: this repo's own busybox + s6-overlay layout, with the binaries in place
# ---------------------------------------------------------------------------
FROM busybox:stable

# Same s6-overlay release and architecture as this repo's docker/Dockerfile.
ARG S6_OVERLAY_VERSION=3.2.0.0
ARG S6_ARCH=x86_64
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz /tmp
RUN \
  tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
  tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz && \
  rm /tmp/s6-overlay*.tar.xz && \
  ln -s /run /var/run

# This repo's s6 service tree (identical to upstream rustdesk/rustdesk-server's).
COPY docker/rootfs/ /

# The three binaries the s6 tree above invokes.
COPY --from=builder /src/target/x86_64-unknown-linux-musl/release/hbbs /usr/bin/hbbs
COPY --from=builder /src/target/x86_64-unknown-linux-musl/release/hbbr /usr/bin/hbbr
COPY --from=builder /src/target/x86_64-unknown-linux-musl/release/rustdesk-utils /usr/bin/rustdesk-utils
RUN chmod a+x /usr/bin/hbbs /usr/bin/hbbr /usr/bin/rustdesk-utils

ENV RELAY=relay.example.com
ENV ENCRYPTED_ONLY=0

EXPOSE 21115 21116 21116/udp 21117 21118 21119

HEALTHCHECK --interval=10s --timeout=5s CMD /usr/bin/healthcheck.sh

WORKDIR /data

VOLUME /data

ENTRYPOINT ["/init"]
