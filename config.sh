#!/bin/bash
# Common configuration for build/deploy/clean scripts

die() {
  printf '\n\033[0;31mERROR:\033[0m %s\n\n' "$*" >&2
  exit 1
}

info() {
  printf '\033[0;34mINFO:\033[0m %s\n' "$*"
}

# Verify cluster-admin access
if ! oc auth can-i '*' '*' --all-namespaces >/dev/null 2>&1; then
  die "This script requires cluster-admin privileges."
fi

# Determine number of users from htpasswd secret
NUM_USERS=$(oc get secret htpasswd -n openshift-config -o jsonpath='{.data.htpasswd}' | base64 -d | grep user | wc -l)

# Build user is the last user
BUILD_USER="user${NUM_USERS}"
BUILD_NS="${BUILD_USER}-devspaces"

# Apps to build/deploy
APPS=(m2k r2k k2m k2r)

# Repo root (where this script lives)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
