#!/bin/bash
#
# Interactive helper for setting up signing + notarisation credentials so
# build-app.sh can produce a notarised, Gatekeeper-trusted DMG.
#
# Run once on a new machine. Idempotent — safe to re-run.
#
set -e

NOTARY_PROFILE="${RD_NOTARY_PROFILE:-RemoteDiffNotary}"

echo "🔐 RemoteDiff signing & notarisation setup"
echo "=========================================="
echo ""

# ----------------------------------------------------------------------------
# 1. Check for a Developer ID Application certificate
# ----------------------------------------------------------------------------

CERT_LINE=$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -E '"Developer ID Application:' \
    | head -1)

if [ -z "$CERT_LINE" ]; then
    echo "❌ No 'Developer ID Application' certificate found in your keychain."
    echo ""
    echo "   You need a paid Apple Developer Program membership (\$99/year) and"
    echo "   a Developer ID Application certificate. To create one:"
    echo ""
    echo "   • Easiest:  Xcode → Settings → Accounts → your Apple ID →"
    echo "               Manage Certificates… → + → 'Developer ID Application'"
    echo ""
    echo "   • Or visit: https://developer.apple.com/account/resources/certificates/add"
    echo "               → 'Developer ID Application'"
    echo ""
    echo "   After creating it, re-run this script."
    exit 1
fi

CERT_NAME=$(echo "$CERT_LINE" | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
echo "✅ Found certificate: $CERT_NAME"
echo ""

# ----------------------------------------------------------------------------
# 2. Check for / create a notarytool keychain profile
# ----------------------------------------------------------------------------

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
    >/dev/null 2>&1; then
    echo "✅ Notary profile '$NOTARY_PROFILE' is already configured."
    echo ""
    echo "Everything is set up. Run: scripts/build-app.sh"
    exit 0
fi

echo "📨 Notary profile '$NOTARY_PROFILE' not found. Let's create it."
echo ""
echo "You'll need three things:"
echo ""
echo "  1. Your Apple ID email          (the one tied to your Developer account)"
echo "  2. Your Team ID                 (10-char string, e.g. ABCDE12345)"
echo "                                  Find it at:"
echo "                                  https://developer.apple.com/account#MembershipDetailsCard"
echo ""
echo "  3. An app-specific password     (NOT your Apple ID password!)"
echo "                                  Create one at:"
echo "                                  https://appleid.apple.com/account/manage"
echo "                                  → Sign-In and Security → App-Specific Passwords → Generate"
echo ""

read -rp "Apple ID email: " APPLE_ID
read -rp "Team ID:         " TEAM_ID
read -rsp "App-specific password (input hidden): " APP_PASSWORD
echo ""
echo ""

if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
    echo "❌ All three fields are required."
    exit 1
fi

echo "💾 Storing credentials in keychain profile '$NOTARY_PROFILE'..."
xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"

echo ""
echo "✅ Setup complete."
echo ""
echo "Next steps:"
echo "  • Build a notarised DMG:  scripts/build-app.sh"
echo "  • The first build runs a real notarisation submission and may take 1–5 min."
