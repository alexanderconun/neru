#!/usr/bin/env bash
#
# Create the "Homekey Local Signing" self-signed code signing identity in your
# login keychain, once. scripts/dist.sh finds it by name and signs Homekey.app
# with it, so macOS keeps the Accessibility grant across rebuilds: an ad-hoc
# signature is pinned to a hash that every build changes.
#
#   scripts/setup-signing.sh [--trust]
#
# --trust also marks the certificate trusted for code signing. codesign and the
# permission checks work without it; it only makes `security find-identity -v`
# list the identity, and macOS asks for your password in a dialog to do it.
#
# Safe to run again: an existing identity is left alone, since a second one with
# the same name makes `codesign --sign "Homekey Local Signing"` ambiguous.
set -euo pipefail

name="Homekey Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"
# LibreSSL: its PKCS#12 output uses the legacy ciphers `security import` reads.
# Homebrew's OpenSSL 3 writes AES/SHA-256, which import can reject as a "MAC
# verification failed" (and LibreSSL refuses OpenSSL 3's -legacy flag).
openssl=/usr/bin/openssl

trust=0
case "${1:-}" in
    "") ;;
    --trust) trust=1 ;;
    *) echo "usage: scripts/setup-signing.sh [--trust]" >&2; exit 2 ;;
esac

# No -v (it hides untrusted self-signed identities) and no `| grep -q` (under
# pipefail an early grep exit can SIGPIPE security into reading as a miss).
case "$(security find-identity -p codesigning "$keychain" 2>/dev/null || true)" in
    *"\"$name\""*)
        echo "\"$name\" already exists in your login keychain; nothing to do."
        exit 0
        ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Some macOS versions refuse to import a p12 with an empty password, so it gets
# a throwaway one that never leaves this script.
pass="$("$openssl" rand -hex 16)"

cat >"$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

"$openssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
"$openssl" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -passout "pass:$pass" -out "$tmp/id.p12"

# -T lets codesign use the private key without asking every time.
security import "$tmp/id.p12" -k "$keychain" -f pkcs12 -P "$pass" -T /usr/bin/codesign

if [ "$trust" = 1 ]; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$tmp/cert.pem" ||
        echo "Trust step skipped; codesign still works with this identity."
fi

echo
security find-identity -p codesigning "$keychain" | grep -F "\"$name\""
cat <<EOF

✓ Created "$name" (valid for 10 years).

Next:
  1. Rebuild: scripts/build-app.sh. It signs with this identity on its own;
     NERU_SIGN_IDENTITY overrides it.
  2. The first signing may ask to use the key: enter your login password and
     click Always Allow.
  3. Install the new build as the script prints, and re-grant Accessibility
     one last time. Later rebuilds keep the grant.
EOF
