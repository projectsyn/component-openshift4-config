#!/bin/bash
set -exo pipefail

jq 'del(.metadata) | .metadata.name = "motd" | .data.message = ([.data.message] + input | join("\n\n"))' \
    <(kubectl -n openshift get cm motd-template -ojson) \
    <(kubectl get consolenotifications -l appuio.io/notification=true -ojson | jq '[.items[].spec.text]') \
    > /tmp/motd.yaml

if [ -z "$(jq -r '.data.message' /tmp/motd.yaml)" ]; then
    kubectl -n openshift delete cm motd --ignore-not-found
else
    kubectl -n openshift apply -f /tmp/motd.yaml
fi
