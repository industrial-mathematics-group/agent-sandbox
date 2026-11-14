#!/usr/bin/env bash
# Builds agent-sandbox images locally (Podman, Docker or Buildah) and in CI.
#
#   ./build.sh full                    # one flavor
#   ./build.sh node julia gateway      # several
#   ./build.sh --list                  # what exists
#   ./build.sh --aliases               # old flavor names (python, *-gui) and their successors
#   ./build.sh --registry ghcr.io/me --tag-suffix -amd64 --push node
#   ./build.sh --engine buildah node   # daemonless (CI runners without Docker)
#
# Every flavor is a chain: images/base -> its layers -> images/final. The base
# already has Python (uv) and the virtual display (Xvfb + Mesa), so every flavor
# has them and a host stores them once. No coding agent is part of any image: the
# claude-code and codex add-ons install them at container start.
# Each step is a normal `podman/docker build` with --build-arg BASE=<previous
# step>, so there is nothing engine-specific. Shared prefixes (base, base+node …)
# are built once per run and come from the build cache after that.
#
# Version pins (all optional, passed through as build args when set):
#   JULIA_VERSION  NODE_VERSION  UV_VERSION  ROCM_VERSION  ROCM_SUITE
# EXTRA_BUILD_FLAGS is appended to every build (e.g. "--network host" behind a proxy).
set -euo pipefail
cd "$(dirname "$0")"

# flavor -> layers between base and the final step
declare -A CHAIN=(
    [minimal]=""
    [minimal-chromium]="layers/chromium"
    [node]="images/node"
    [node-chromium]="images/node layers/chromium"
    [julia]="images/julia"
    [julia-chromium]="images/julia layers/chromium"
    [octave]="images/octave"
    [full]="images/node images/julia layers/chromium"
    [full-rocm]="images/node images/julia layers/chromium layers/rocm"
)
# Old flavor names -> the flavor that replaced them. Python and the virtual display
# moved into the base, so the python and -gui flavors are gone. Building a flavor
# also tags (and pushes) it under its old names, so existing deployments keep
# pulling updates. Deprecated: switch to the new name.
declare -A ALIAS=(
    [python]=minimal
    [python-gui]=minimal-chromium
    [julia-gui]=julia-chromium
    [octave-gui]=octave
)
# Gateway variants -> tag of agent-sandbox-gateway
declare -A GATEWAY=( [gateway]=latest [gateway-tailscale]=tailscale )
FLAVOR_ORDER="minimal minimal-chromium node node-chromium julia julia-chromium octave full full-rocm"

ENGINE=${ENGINE:-}
REGISTRY=localhost
SUFFIX=
PUSH=0
targets=()
while [ $# -gt 0 ]; do
    case "$1" in
        --engine)     ENGINE=$2; shift 2 ;;
        --registry)   REGISTRY=$2; shift 2 ;;
        --tag-suffix) SUFFIX=$2; shift 2 ;;
        --push)       PUSH=1; shift ;;
        --list)
            for f in $FLAVOR_ORDER; do printf '%-16s base %s\n' "$f" "$(echo "${CHAIN[$f]}" | sed 's|images/||g; s|layers/|+|g')"; done
            printf '%-16s gateway (plain)\n%-16s gateway (Tailscale exit node)\n' gateway gateway-tailscale
            exit 0 ;;
        --aliases)    # old name -> flavor, one per line (CI tags the old names too)
            for a in "${!ALIAS[@]}"; do echo "$a ${ALIAS[$a]}"; done | sort
            exit 0 ;;
        -h|--help)    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)           echo "unknown option $1" >&2; exit 2 ;;
        *)            targets+=("$1"); shift ;;
    esac
done
[ ${#targets[@]} -gt 0 ] || { echo "usage: $0 [options] FLAVOR... (see --list)" >&2; exit 2; }

if [ -z "$ENGINE" ]; then
    if command -v podman >/dev/null; then ENGINE=podman; else ENGINE=docker; fi
fi

version_args=()
for v in JULIA_VERSION NODE_VERSION UV_VERSION ROCM_VERSION ROCM_SUITE; do
    [ -n "${!v:-}" ] && version_args+=(--build-arg "$v=${!v}")
done
# shellcheck disable=SC2206  # intentional word splitting
extra=(${EXTRA_BUILD_FLAGS:-})

STAGE=localhost/agent-sandbox-stage
declare -A built=()

build() {   # build <context> <tag> [build args...]
    local ctx=$1 tag=$2; shift 2
    echo "==> $tag  ($ctx)"
    "$ENGINE" build "${extra[@]}" "${version_args[@]}" "$@" -t "$tag" -f "$ctx/Containerfile" "$ctx"
}

aliases_of() {   # aliases_of <flavor>: its old names
    local a
    for a in "${!ALIAS[@]}"; do [ "${ALIAS[$a]}" = "$1" ] && echo "$a"; done | sort
}

build_flavor() {
    local flavor=$1 prev key layer tag a
    if [ -n "${ALIAS[$flavor]+x}" ]; then
        echo "NOTE: flavor '$flavor' is now '${ALIAS[$flavor]}' (Python and Xvfb are in every image); building that." >&2
        flavor=${ALIAS[$flavor]}
    fi
    [ -n "${CHAIN[$flavor]+x}" ] || { echo "unknown flavor '$flavor' (see --list)" >&2; exit 2; }
    key=base
    prev=$STAGE:base
    if [ -z "${built[$key]:-}" ]; then build images/base "$prev"; built[$key]=1; fi
    for layer in ${CHAIN[$flavor]}; do
        key="$key+${layer##*/}"
        tag="$STAGE:$(echo "$key" | tr '+' '-')"
        if [ -z "${built[$key]:-}" ]; then build "$layer" "$tag" --build-arg "BASE=$prev"; built[$key]=1; fi
        prev=$tag
    done
    tag="$REGISTRY/agent-sandbox:$flavor$SUFFIX"
    build images/final "$tag" --build-arg "BASE=$prev" --build-arg "FLAVOR=$flavor"
    [ "$PUSH" = 1 ] && "$ENGINE" push "$tag"
    for a in $(aliases_of "$flavor"); do
        "$ENGINE" tag "$tag" "$REGISTRY/agent-sandbox:$a$SUFFIX"
        [ "$PUSH" = 1 ] && "$ENGINE" push "$REGISTRY/agent-sandbox:$a$SUFFIX"
    done
    return 0
}

build_gateway() {
    local variant=$1 tag base
    tag="$REGISTRY/agent-sandbox-gateway:${GATEWAY[$variant]}$SUFFIX"
    if [ "$variant" = gateway-tailscale ]; then
        base=docker.io/tailscale/tailscale:stable
        build gateway "$tag" --build-arg "BASE_IMAGE=$base" --build-arg VARIANT=tailscale
    else
        build gateway "$tag" --build-arg VARIANT=plain
    fi
    [ "$PUSH" = 1 ] && "$ENGINE" push "$tag"
    return 0
}

for t in "${targets[@]}"; do
    if [ "$t" = all ]; then
        for f in $FLAVOR_ORDER; do build_flavor "$f"; done
        build_gateway gateway; build_gateway gateway-tailscale
    elif [ -n "${GATEWAY[$t]+x}" ]; then
        build_gateway "$t"
    else
        build_flavor "$t"
    fi
done
