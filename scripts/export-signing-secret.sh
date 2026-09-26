#!/bin/bash
# Store the "uSwitch Self-Signed" certificate and its private key in the repo's
# MACOS_SIGN_P12 / MACOS_SIGN_P12_PASSWORD secrets, so CI signs releases with
# the same identity as local builds.
#
# Keychain Access cannot export it as .p12 (setup-cert.sh imports the key and
# cert separately), and `security export` can only export every identity at
# once. So export them all to a temp dir, keep the key that matches our cert,
# and rebuild a .p12 with just that pair. The temp dir is removed on exit.

set -euo pipefail

CERT_NAME="uSwitch Self-Signed"
REPO="nunoh/uSwitch"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# System LibreSSL: its PKCS12 output is readable by `security import`.
OPENSSL=/usr/bin/openssl

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
umask 077

security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > cert.pem
cert_sha1=$("$OPENSSL" x509 -in cert.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
cert_pub=$("$OPENSSL" x509 -in cert.pem -noout -pubkey)
echo "→ certificate $CERT_NAME ($cert_sha1)"

echo "→ exporting keychain identities (macOS may ask to allow each key)"
export_pass=$("$OPENSSL" rand -hex 16)
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$export_pass" -o all.p12
"$OPENSSL" pkcs12 -in all.p12 -nocerts -nodes -passin "pass:$export_pass" -out keys.pem 2>/dev/null
rm all.p12

# keys.pem holds every exported key; split it and keep the one whose public
# key matches the certificate.
awk '/-----BEGIN .*PRIVATE KEY-----/ { n++ } n { print > ("key" n ".pem") }' keys.pem
rm keys.pem
match=""
for key in key*.pem; do
    if [ "$("$OPENSSL" pkey -in "$key" -pubout 2>/dev/null)" = "$cert_pub" ]; then
        match=$key
    fi
done
if [ -z "$match" ]; then
    echo "✗ no exported private key matches $CERT_NAME" >&2
    exit 1
fi

p12_pass=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$match" -in cert.pem -name "$CERT_NAME" \
    -passout "pass:$p12_pass" -out sign.p12
rm key*.pem

# Import it the way CI does, into a throwaway keychain, and check the identity.
check_kc="$tmp/check.keychain-db"
security create-keychain -p check "$check_kc"
security import sign.p12 -k "$check_kc" -P "$p12_pass" -T /usr/bin/codesign >/dev/null
if ! security find-identity "$check_kc" | grep -q "$cert_sha1"; then
    security delete-keychain "$check_kc"
    echo "✗ the rebuilt .p12 does not import as $CERT_NAME" >&2
    exit 1
fi
security delete-keychain "$check_kc"
echo "→ .p12 imports as $CERT_NAME"

base64 -i sign.p12 | gh secret set MACOS_SIGN_P12 --repo "$REPO"
printf '%s' "$p12_pass" | gh secret set MACOS_SIGN_P12_PASSWORD --repo "$REPO"
echo "✅ MACOS_SIGN_P12 and MACOS_SIGN_P12_PASSWORD set on $REPO"
