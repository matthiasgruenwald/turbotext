#!/bin/bash
set -euo pipefail

# Turbotext macOS App - Build & Run
# Voraussetzungen: Full Xcode with Command Line Tools, xcodegen

RUN_AFTER=true
INSTALL_APP=false
BUILD_CONFIGURATION="Release"
UNIVERSAL_ARCHS="arm64 x86_64"
SIMULATED_KEYS=false

for arg in "$@"; do
    case "$arg" in
        --debug)
            BUILD_CONFIGURATION="Debug"
            ;;
        --run)
            RUN_AFTER=true
            ;;
        --no-run)
            RUN_AFTER=false
            ;;
        --install)
            INSTALL_APP=true
            ;;
        --release)
            BUILD_CONFIGURATION="Release"
            ;;
        --simulated-keys)
            SIMULATED_KEYS=true
            ;;
        *)
            echo "Unbekannte Option: $arg"
            echo "Verwendung: ./build.sh [--install] [--no-run] [--release] [--debug] [--simulated-keys]"
            exit 1
            ;;
    esac
done

verify_universal_app() {
    local app_path="$1"
    local app_name
    local binary_path
    local archs

    app_name="$(basename "$app_path" .app)"
    binary_path="$app_path/Contents/MacOS/$app_name"

    if [ ! -f "$binary_path" ]; then
        echo "❌ Konnte App-Binary nicht finden: $binary_path"
        exit 1
    fi

    archs="$(lipo -archs "$binary_path" 2>/dev/null || true)"

    if [[ -z "$archs" ]]; then
        echo "❌ Konnte Architekturen nicht lesen: $binary_path"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
        echo "❌ Build ist nicht universal. Erwartet: arm64 + x86_64"
        echo "   Gefunden: $archs"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    echo "✅ Universal Binary verifiziert: $archs"
}

# Ad-hoc signing produces a new code signing identity on every build, so the Keychain stops
# recognising the rebuilt app and asks for the keychain password again. Setting
# TURBOTEXT_SIGN_IDENTITY to a self-signed certificate keeps the identity stable across builds
# and stops the repeated prompt. See README, "Keychain prompt on every rebuild".
sign_app() {
    local app_path="$1"

    if [ -n "${TURBOTEXT_SIGN_IDENTITY:-}" ]; then
        echo "🔏 Signiere lokale Development-App mit '$TURBOTEXT_SIGN_IDENTITY'. Dieses Artefakt ist nicht notarisiert."
        codesign --force --sign "$TURBOTEXT_SIGN_IDENTITY" "$app_path" 2>&1
        return
    fi

    echo "🔏 Signiere lokale Development-App ad-hoc. Dieses Artefakt ist nicht notarisiert."
    codesign --force --sign - "$app_path" 2>&1
}

ensure_xcodebuild_available() {
    if xcodebuild -version >/dev/null 2>&1; then
        return
    fi

    local default_xcode="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$default_xcode" ]; then
        export DEVELOPER_DIR="$default_xcode"
        if xcodebuild -version >/dev/null 2>&1; then
            echo "⚠️  Aktiver Developer-Pfad nutzt kein vollständiges Xcode. Verwende: $DEVELOPER_DIR"
            return
        fi
    fi

    echo "❌ xcodebuild ist nicht verfügbar."
    echo "   Installiere Xcode und wähle es mit:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/TurbotextMac"
PROJECT_FILE="$PROJECT_DIR/TurbotextMac.xcodeproj"
DERIVED_DATA_PATH="$SCRIPT_DIR/.derivedData-turbotextmac-build"
cd "$PROJECT_DIR"

ensure_xcodebuild_available

if [ "${TURBOTEXT_SKIP_XCODEGEN:-false}" = "1" ] || [ "${TURBOTEXT_SKIP_XCODEGEN:-false}" = "true" ]; then
    if [ -d "$PROJECT_FILE" ]; then
        echo "⚠️  Überspringe XcodeGen – nutze vorhandenes Xcode-Projekt."
    else
        echo "❌ TURBOTEXT_SKIP_XCODEGEN ist gesetzt, aber $PROJECT_FILE fehlt."
        exit 1
    fi
elif command -v xcodegen &> /dev/null; then
    echo "⚙️  Generiere Xcode-Projekt ..."
    xcodegen generate 2>&1
elif [ -d "$PROJECT_FILE" ]; then
    echo "⚠️  xcodegen nicht gefunden – nutze vorhandenes Xcode-Projekt."
else
    echo "❌ xcodegen fehlt."
    echo "   Installiere xcodegen explizit mit:"
    echo "   brew install xcodegen"
    echo "   Oder stelle sicher, dass $PROJECT_FILE vorhanden ist."
    exit 1
fi

# Bauen
echo "🔨 Baue Turbotext ..."
xcodebuild \
    -project TurbotextMac.xcodeproj \
    -scheme TurbotextMac \
    -destination 'platform=macOS' \
    -configuration "$BUILD_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="$UNIVERSAL_ARCHS" \
    clean build

# App finden
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/Turbotext.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build fehlgeschlagen – keine App gefunden."
    exit 1
fi

verify_universal_app "$APP_PATH"

# Resources manuell ins Bundle kopieren (xcodegen kopiert sie nicht automatisch)
echo "📋 Kopiere Resources ..."
RESOURCES_DIR="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp -f "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || true
cp -f "$PROJECT_DIR/Resources/menubar_icon.png" "$RESOURCES_DIR/" 2>/dev/null || true
cp -f "$PROJECT_DIR/Resources/menubar_icon@2x.png" "$RESOURCES_DIR/" 2>/dev/null || true

# In Projektordner kopieren
DEST="$SCRIPT_DIR/Turbotext.app"
rm -rf "$DEST"
cp -R "$APP_PATH" "$DEST"
sign_app "$DEST"
verify_universal_app "$DEST"

RUN_TARGET="$DEST"

if [ "$INSTALL_APP" = true ]; then
    APPS_DIR="/Applications"
    INSTALL_DEST="$APPS_DIR/Turbotext.app"
    if [ ! -w "$APPS_DIR" ]; then
        echo "❌ /Applications ist nicht beschreibbar."
        echo "   Führe den Befehl mit passenden Rechten erneut aus oder ziehe die App manuell nach /Applications."
        exit 1
    fi
    rm -rf "$INSTALL_DEST"
    cp -R "$DEST" "$INSTALL_DEST"
    sign_app "$INSTALL_DEST"
    verify_universal_app "$INSTALL_DEST"
    RUN_TARGET="$INSTALL_DEST"
fi

echo ""
echo "✅ Fertig! App liegt unter:"
echo "   $DEST"
if [ "$INSTALL_APP" = true ]; then
    echo "   $RUN_TARGET"
fi
echo ""
echo "Build-Typ: $BUILD_CONFIGURATION"
echo "Architekturen: $UNIVERSAL_ARCHS"
echo "Kompatibel: Apple Silicon + Intel (macOS 14+)"
echo ""
echo "Nächste Schritte:"
echo "1. App starten"
echo "2. Direktes Einfügen: Bedienungshilfen erlauben"
echo "   (optional: Eingabeüberwachung manuell über +-Button hinzufügen, s. Hinweis im Hauptfenster)"
echo "3. Groq Key eintragen (ggf. OpenAI)"
echo "4. Hotkey benutzen, Mikrofonnutzung erlauben"
echo "5. Fertig – ab sofort per Hotkey diktieren"
echo ""

# Optional: direkt starten
if [ "$RUN_AFTER" = true ]; then
    if [ "$SIMULATED_KEYS" = true ]; then
        echo "🚀 Starte Turbotext mit simulierten API-Keys (kein Keychain-Zugriff) ..."
        open "$RUN_TARGET" --args --simulated-credentials
    else
        echo "🚀 Starte Turbotext ..."
        open "$RUN_TARGET"
    fi
fi
