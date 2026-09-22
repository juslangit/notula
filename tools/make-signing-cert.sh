#!/usr/bin/env bash
# Creates a local code-signing certificate for Notula, once.
#
# Why this exists: an ad-hoc signed app is identified by the hash of its own
# bytes, so every rebuild looks like a different app and macOS asks for the
# microphone and screen permissions all over again. Signing with a certificate
# that stays the same makes the permission stick across rebuilds.
#
# The certificate is self-signed, lives only in this login keychain, and is
# trusted by nothing except this Mac's own record of what Notula is.
set -euo pipefail
NAME="Notula Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "→ '$NAME' already exists"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS's importer predates OpenSSL 3's defaults, hence the old-style algorithms.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/id.p12" -passout pass:notula \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

security import "$WORK/id.p12" -k "$KEYCHAIN" -P notula -T /usr/bin/codesign -A >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "→ created '$NAME'"
security find-identity -v -p codesigning | sed -n '1,3p'
