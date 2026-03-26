#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 <keystore_name> [new_keystore_name]"
    echo ""
    echo "Examples:"
    echo "  $0 cnode01"
    echo "  $0 cnode01 cnode01_new"
    echo ""
    echo "Notes:"
    echo "  - Default keystore directory: ~/.foundry/keystores"
    echo "  - Set KEYSTORE_DIR to override the keystore directory"
    echo "  - If new_keystore_name is omitted, the script will replace the original"
    echo "    keystore after creating a timestamped backup."
}

require_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

read_secret() {
    local prompt=$1
    local value=""

    printf '%s' "$prompt" >&2
    if [ -t 0 ]; then
        IFS= read -r -s value
    else
        IFS= read -r value
    fi
    printf '\n' >&2

    printf '%s' "$value"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 1
fi

require_command cast
require_command expect

KEYSTORE_DIR=${KEYSTORE_DIR:-"$HOME/.foundry/keystores"}
SOURCE_NAME=$1
REQUESTED_TARGET_NAME=${2:-$SOURCE_NAME}
SOURCE_PATH="$KEYSTORE_DIR/$SOURCE_NAME"

if [ ! -d "$KEYSTORE_DIR" ]; then
    echo "Error: keystore directory does not exist: $KEYSTORE_DIR" >&2
    exit 1
fi

if [ ! -f "$SOURCE_PATH" ]; then
    echo "Error: keystore file does not exist: $SOURCE_PATH" >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d%H%M%S)
if [ "$REQUESTED_TARGET_NAME" = "$SOURCE_NAME" ]; then
    REPLACE_ORIGINAL=1
    TARGET_NAME=".rekey.${SOURCE_NAME}.${TIMESTAMP}.$$"
else
    REPLACE_ORIGINAL=0
    TARGET_NAME=$REQUESTED_TARGET_NAME
fi

TARGET_PATH="$KEYSTORE_DIR/$TARGET_NAME"
BACKUP_PATH="$KEYSTORE_DIR/${SOURCE_NAME}.bak.${TIMESTAMP}"
IMPORT_LOG=$(mktemp /tmp/reset_keystore_password.import.XXXXXX)
SUCCESS=0

cleanup() {
    rm -f "$IMPORT_LOG"
    if [ "$SUCCESS" -ne 1 ] && [ -f "$TARGET_PATH" ]; then
        rm -f "$TARGET_PATH"
    fi
}
trap cleanup EXIT

if [ -e "$TARGET_PATH" ]; then
    echo "Error: target keystore already exists: $TARGET_PATH" >&2
    exit 1
fi

OLD_PASSWORD=$(read_secret "Old keystore password: ")
NEW_PASSWORD1=$(read_secret "New keystore password: ")
NEW_PASSWORD2=$(read_secret "Repeat new password: ")

if [ "$NEW_PASSWORD1" != "$NEW_PASSWORD2" ]; then
    echo "Error: new passwords do not match" >&2
    exit 1
fi

PRIVATE_KEY=$(CAST_UNSAFE_PASSWORD="$OLD_PASSWORD" cast wallet decrypt-keystore -k "$KEYSTORE_DIR" "$SOURCE_NAME" 2>/dev/null | grep -o '0x[a-fA-F0-9]\{64\}' | head -1 || true)
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: failed to decrypt keystore. Check the old password." >&2
    exit 1
fi

SOURCE_ADDRESS=$(cast wallet address "$PRIVATE_KEY" | tr -d '\r')

PRIVATE_KEY_ENV="$PRIVATE_KEY" \
KEYSTORE_DIR_ENV="$KEYSTORE_DIR" \
TARGET_NAME_ENV="$TARGET_NAME" \
CAST_UNSAFE_PASSWORD="$NEW_PASSWORD1" \
expect <<'EOF' >"$IMPORT_LOG" 2>&1
set timeout -1
set private_key $env(PRIVATE_KEY_ENV)
unset env(PRIVATE_KEY_ENV)

spawn cast wallet import -k $env(KEYSTORE_DIR_ENV) $env(TARGET_NAME_ENV) --interactive
expect "Enter private key:"
send -- "$private_key\r"
expect eof
EOF

TARGET_ADDRESS=$(grep -o '0x[a-fA-F0-9]\{40\}' "$IMPORT_LOG" | tail -1 | tr -d '\r' || true)

unset OLD_PASSWORD
unset NEW_PASSWORD1
unset NEW_PASSWORD2
unset PRIVATE_KEY

if [ -z "$TARGET_ADDRESS" ]; then
    echo "Error: failed to create the new keystore" >&2
    cat "$IMPORT_LOG" >&2
    exit 1
fi

SOURCE_ADDRESS_LOWER=$(printf '%s' "$SOURCE_ADDRESS" | tr '[:upper:]' '[:lower:]')
TARGET_ADDRESS_LOWER=$(printf '%s' "$TARGET_ADDRESS" | tr '[:upper:]' '[:lower:]')

if [ "$SOURCE_ADDRESS_LOWER" != "$TARGET_ADDRESS_LOWER" ]; then
    echo "Error: address mismatch after re-encryption" >&2
    exit 1
fi

if [ "$REPLACE_ORIGINAL" -eq 1 ]; then
    mv "$SOURCE_PATH" "$BACKUP_PATH"
    mv "$TARGET_PATH" "$SOURCE_PATH"
    FINAL_PATH="$SOURCE_PATH"
else
    FINAL_PATH="$TARGET_PATH"
fi

SUCCESS=1

echo ""
echo "Keystore password updated successfully."
echo "Address: $TARGET_ADDRESS"
echo "Keystore file: $FINAL_PATH"
if [ "$REPLACE_ORIGINAL" -eq 1 ]; then
    echo "Backup file: $BACKUP_PATH"
else
    echo "Original keystore preserved at: $SOURCE_PATH"
fi
echo ""
