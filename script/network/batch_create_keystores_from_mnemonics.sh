#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 <mnemonic_file> [keystore_dir]"
    echo ""
    echo "Input file format:"
    echo "  - One wallet per line"
    echo "  - Each line is a full BIP39 mnemonic phrase, words separated by spaces"
    echo "  - Blank lines and lines starting with # are ignored"
    echo ""
    echo "Output file name:"
    echo "  <prefix><index>_<last4_of_address>"
    echo "  Example: syx01_01ab"
    echo ""
    echo "Notes:"
    echo "  - Prefix is requested at runtime"
    echo "  - Password is requested at runtime and hidden while typing"
    echo "  - Default keystore dir: ~/.foundry/keystores"
}

require_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 1
fi

require_command cast

MNEMONIC_FILE=$1
KEYSTORE_DIR=${2:-"$HOME/.foundry/keystores"}

if [ ! -f "$MNEMONIC_FILE" ]; then
    echo "Error: mnemonic file not found: $MNEMONIC_FILE" >&2
    exit 1
fi

mkdir -p "$KEYSTORE_DIR"

read -r -p "Keystore prefix: " KEYSTORE_PREFIX
KEYSTORE_PREFIX=$(trim "$KEYSTORE_PREFIX")
if [ -z "$KEYSTORE_PREFIX" ]; then
    echo "Error: keystore prefix cannot be empty" >&2
    exit 1
fi

read -r -s -p "Keystore password: " KEYSTORE_PASSWORD
printf '\n' >&2
read -r -s -p "Repeat password: " KEYSTORE_PASSWORD2
printf '\n' >&2

if [ "$KEYSTORE_PASSWORD" != "$KEYSTORE_PASSWORD2" ]; then
    echo "Error: passwords do not match" >&2
    exit 1
fi

index=0
created=0
tmp_files=""

cleanup() {
    for tmp_file in $tmp_files; do
        rm -f "$tmp_file"
    done
}
trap cleanup EXIT

while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "$line")
    if [ -z "$line" ] || [[ "$line" == \#* ]]; then
        continue
    fi

    index=$((index + 1))
    wallet_no=$(printf '%02d' "$index")

    tmp_file=$(mktemp /tmp/syx_mnemonic.XXXXXX)
    tmp_files="$tmp_files $tmp_file"
    printf '%s\n' "$line" > "$tmp_file"

    address=$(CAST_UNSAFE_PASSWORD="$KEYSTORE_PASSWORD" cast wallet address --mnemonic "$tmp_file" | tr -d '\r' | grep -oE '0x[a-fA-F0-9]{40}' | head -1 || true)
    if [ -z "$address" ]; then
        echo "Error: failed to derive address for line $index" >&2
        exit 1
    fi

    last4=$(printf '%s' "$address" | tail -c 4 | tr '[:upper:]' '[:lower:]')
    keystore_name="${KEYSTORE_PREFIX}${wallet_no}_${last4}"
    keystore_path="$KEYSTORE_DIR/$keystore_name"

    if [ -e "$keystore_path" ]; then
        echo "Error: keystore already exists: $keystore_path" >&2
        exit 1
    fi

    CAST_UNSAFE_PASSWORD="$KEYSTORE_PASSWORD" cast wallet import -k "$KEYSTORE_DIR" "$keystore_name" --mnemonic "$tmp_file" >/dev/null
    created=$((created + 1))

    echo "$keystore_name -> $address"
done < "$MNEMONIC_FILE"

unset KEYSTORE_PASSWORD
unset KEYSTORE_PASSWORD2

echo ""
echo "Done. Created $created keystore file(s) in $KEYSTORE_DIR"
