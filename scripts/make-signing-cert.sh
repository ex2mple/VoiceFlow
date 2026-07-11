#!/bin/bash
# One-time setup: create a local self-signed code-signing identity
# ("VoiceFlow Dev") in the login keychain and trust it for code signing.
#
# Why: the Makefile used to sign ad-hoc (`codesign --sign -`), so every
# rebuild looked like a brand-new app to the keychain and macOS asked for
# the keychain password on every launch. Signing with one stable local
# certificate makes "Always Allow" stick across rebuilds.
#
# macOS will show its own dialogs during this script (trust change, and
# later a codesign key-access prompt) — type the password there, not here.
set -euo pipefail

CN="VoiceFlow Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl # the system LibreSSL: its p12 defaults are importable

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CN"; then
  echo "✓ Identity '$CN' already exists — nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = dn
[dn]
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -subj "/CN=$CN" -config "$TMP/ext.cnf" -extensions ext 2>/dev/null

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/dev.p12" -passout pass:voiceflow

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P voiceflow -T /usr/bin/codesign

# Trust it for code signing (user domain; macOS asks for your password once).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || true

if security find-identity -v -p codesigning | grep -q "$CN"; then
  echo "✓ Created and trusted '$CN'."
  echo "  Now run: make run"
  echo "  • codesign may ask to use the key — click «Always Allow»."
  echo "  • On first launch the keychain asks once more — click «Разрешать всегда»."
  echo "  After that: no more password prompts, even after rebuilds."
else
  echo "✗ Identity is not valid yet. Open Keychain Access, find the"
  echo "  '$CN' certificate, and set Trust → Code Signing → Always Trust."
  exit 1
fi
