#!/bin/sh
# Creates a self-signed code-signing certificate in the login keychain, used by
# `make` to sign Stripe. Signing every build with the same certificate keeps
# macOS privacy permissions (Accessibility) granted across rebuilds; ad-hoc
# signatures change with every build, so macOS treats each one as a new app.
#
# Run once per Mac:  build-support/make-signing-identity.sh
set -e

NAME="${1:-Stripe Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<EOF
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
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -passout pass:stripe -out "$TMP/identity.p12" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null  # formats macOS can import

# -T lets codesign use the key without a keychain prompt on every build.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P stripe -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in the login keychain."
