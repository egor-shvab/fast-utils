#!/usr/bin/env bash
# Creates a self-signed code signing identity "FastUtils Dev" in the login keychain.
# Run once per Mac. A stable signature keeps macOS privacy permissions (Screen Recording,
# Accessibility) across rebuilds; ad-hoc signing would reset them every build.
# The certificate is NOT marked as trusted system-wide; codesign does not need that.
set -euo pipefail

NAME="FastUtils Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "Identity \"$NAME\" already exists, nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(openssl rand -hex 16)"

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout "pass:$PASS"

# -T lets codesign use the private key without a keychain prompt on every build.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo "Created identity \"$NAME\":"
security find-identity -p codesigning | grep "\"$NAME\""
