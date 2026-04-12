#!/bin/bash
# Remove all Camel app deployments from all user namespaces.
set -euo pipefail

source "$(dirname "$0")/config.sh"

info "Cleaning Camel apps from all user namespaces"

for i in $(seq 1 "$NUM_USERS"); do
  NS="user${i}-devspaces"
  for APP in "${APPS[@]}"; do
    oc delete deployment/"${APP}" -n "${NS}" --ignore-not-found
  done
  oc delete service/r2k -n "${NS}" --ignore-not-found
done

info "All Camel app deployments removed"
