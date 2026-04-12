#!/bin/bash
# Build the 4 Camel apps in the build user's namespace.
# Images are created as ImageStreams for reuse across all user namespaces.
# Credentials are read from the build user's lab-config Secret.
set -euo pipefail

source "$(dirname "$0")/config.sh"

info "Building Camel apps in ${BUILD_NS}"

oc project "${BUILD_NS}"

# Read build user's credentials from lab-config Secret
BUILD_CONFIG=$(oc get secret lab-config -n "${BUILD_NS}" -o json | jq -r '.data["config"]' | base64 -d)
RC_TOKEN=$(echo "$BUILD_CONFIG" | grep '^rocketchat_token=' | cut -d'=' -f2-)
RC_USERID=$(echo "$BUILD_CONFIG" | grep '^rocketchat_userid=' | cut -d'=' -f2-)
MX_TOKEN=$(echo "$BUILD_CONFIG" | grep '^matrix_token=' | cut -d'=' -f2-)
MX_ROOM=$(echo "$BUILD_CONFIG" | grep '^matrix_room=' | cut -d'=' -f2-)

info "Credentials loaded from lab-config in ${BUILD_NS}"

cd "${REPO_ROOT}/flows"

for APP in "${APPS[@]}"; do
  info "Building ${APP}..."
  camel kubernetes run ${APP}/* \
    --name "${APP}" \
    --local-kamelet-dir "${REPO_ROOT}/kamelets" \
    --cluster-type openshift \
    --env MATRIX_TOKEN="${MX_TOKEN}" \
    --env MATRIX_ROOM="${MX_ROOM}" \
    --env ROCKETCHAT_TOKEN="${RC_TOKEN}" \
    --env ROCKETCHAT_USERID="${RC_USERID}"
done

info "All apps built in ${BUILD_NS}"
