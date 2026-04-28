#!/bin/bash
# Create a stable self-signed code-signing cert in the login keychain so that
# rebuilds carry the same designated requirement, letting TCC (Accessibility,
# Screen Recording) grants survive reinstalls.

set -euo pipefail

CERT_NAME="uSwitch Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "→ cert '$CERT_NAME' already in login keychain"
    exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

cat > config.cnf <<EOF
[req]
distinguished_name = req_dn
prompt = no
[req_dn]
CN = $CERT_NAME
[v3_codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

# Pin to system openssl (LibreSSL): Homebrew's OpenSSL 3.x writes PKCS12 files
# the macOS `security` tool can't read.
OPENSSL=/usr/bin/openssl

"$OPENSSL" req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -nodes \
    -days 36500 -config config.cnf -extensions v3_codesign >/dev/null 2>&1

# Import key and cert as separate PEMs — `security import` links them by
# matching the cert's public key to the private key already in the keychain.
security import key.pem  -k "$KEYCHAIN" -T /usr/bin/codesign -A >/dev/null
security import cert.pem -k "$KEYCHAIN" -T /usr/bin/codesign -A >/dev/null

echo "✅ created self-signed cert '$CERT_NAME' in login keychain"
