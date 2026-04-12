#!/bin/bash
# Deploy the 4 Camel apps to all user namespaces using the images built by build.sh.
# Each deployment gets per-user credentials from the lab-config Secret.
# Deployments are created scaled to zero — students scale up when instructed.
set -euo pipefail

source "$(dirname "$0")/config.sh"

info "Deploying Camel apps to all users"

oc project "${BUILD_NS}"

# Phase 1: Deploy mocks on all worker nodes to pull images
mapfile -t ALL_NODES < <(
  oc get nodes -l node-role.kubernetes.io/worker --no-headers -o name | cut -d/ -f2
)
info "Found ${#ALL_NODES[@]} worker nodes"

declare -A IMAGES
for APP in "${APPS[@]}"; do
  IMAGES[$APP]=$(oc get deployment "$APP" -n "${BUILD_NS}" -o jsonpath='{.spec.template.spec.containers[0].image}')
  info "${APP} image: ${IMAGES[$APP]}"
done

for APP in "${APPS[@]}"; do
  for i in "${!ALL_NODES[@]}"; do
    node="${ALL_NODES[$i]}"
    oc create deployment "mock${i}-${APP}" \
      --image="${IMAGES[$APP]}" \
      -n "${BUILD_NS}" \
      --dry-run=client -o yaml | \
      oc patch -f - --type=strategic --dry-run=client -o yaml \
        -p "{\"metadata\":{\"labels\":{\"group\":\"mock\"}},\"spec\":{\"template\":{\"spec\":{\"nodeName\":\"${node}\"},\"metadata\":{\"labels\":{\"group\":\"mock\"}}}}}" | \
      oc apply -f -
  done
done

oc wait --for=condition=Ready pod -l group=mock -n "${BUILD_NS}" --timeout=120s
info "All mock pods running — images cached on all nodes"

# Phase 2: Deploy to all user namespaces with per-user credentials
KAFKA_ANNOTATION='[{"apiVersion":"kafka.strimzi.io/v1beta2","kind":"Kafka","name":"my-cluster"}]'

for i in $(seq 1 "$NUM_USERS"); do
  NS="user${i}-devspaces"
  info "Deploying to ${NS}"

  # Read per-user credentials from lab-config
  USER_CONFIG=$(oc get secret lab-config -n "${NS}" -o json | jq -r '.data["config"]' | base64 -d)
  RC_TOKEN=$(echo "$USER_CONFIG" | grep '^rocketchat_token=' | cut -d'=' -f2-)
  RC_USERID=$(echo "$USER_CONFIG" | grep '^rocketchat_userid=' | cut -d'=' -f2-)
  MX_TOKEN=$(echo "$USER_CONFIG" | grep '^matrix_token=' | cut -d'=' -f2-)
  MX_ROOM=$(echo "$USER_CONFIG" | grep '^matrix_room=' | cut -d'=' -f2-)

  # Create service for r2k (webhook receiver)
  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: r2k
  namespace: ${NS}
  labels:
    app: r2k
spec:
  selector:
    app: r2k
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF

  for APP in "${APPS[@]}"; do
    IMAGE="${IMAGES[$APP]}"

    cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP}
  namespace: ${NS}
  labels:
    app: ${APP}
    app.kubernetes.io/part-of: org.example.project
    app.kubernetes.io/runtime: camel
    app.openshift.io/runtime: camel
  annotations:
    app.openshift.io/connects-to: '${KAFKA_ANNOTATION}'
spec:
  replicas: 0
  selector:
    matchLabels:
      app: ${APP}
  template:
    metadata:
      labels:
        app: ${APP}
        app.kubernetes.io/part-of: org.example.project
    spec:
      containers:
        - name: ${APP}
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
            - name: KUBERNETES_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: MATRIX_TOKEN
              value: "${MX_TOKEN}"
            - name: MATRIX_ROOM
              value: "${MX_ROOM}"
            - name: ROCKETCHAT_TOKEN
              value: "${RC_TOKEN}"
            - name: ROCKETCHAT_USERID
              value: "${RC_USERID}"
          readinessProbe:
            httpGet:
              path: /observe/health/ready
              port: 9876
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              path: /observe/health/live
              port: 9876
            initialDelaySeconds: 10
          startupProbe:
            httpGet:
              path: /observe/health/started
              port: 9876
            initialDelaySeconds: 5
  revisionHistoryLimit: 2
EOF
  done
done

# Phase 3: Clean up mocks
oc delete deployment -l group=mock -n "${BUILD_NS}"

info "All apps deployed (scaled to zero)"
