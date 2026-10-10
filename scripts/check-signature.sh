#!/bin/bash
# CI only: fail unless the app is signed with the "uSwitch Self-Signed"
# certificate. setup-cert.sh would mint a new one if the import failed, and
# a build signed with it would reset every user's permissions.
set -euo pipefail

# SHA-1 of the certificate. macOS ties permission grants to it.
SIGN_CERT_SHA1=bc502e940095ae5c30ff45f53bee3b6f97953a39

codesign -dr - "$1" 2>&1 | tee /dev/stderr \
  | grep -qi "certificate leaf = H\"$SIGN_CERT_SHA1\""
