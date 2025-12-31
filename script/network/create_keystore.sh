#!/bin/bash

# Check parameters
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <keystore_name> [private_key]"
    echo "Example: $0 xxx_account 0x..."
    echo "Note: private_key is optional. If not provided, a new wallet will be created."
    return 1
fi

keystore_name=$1
PRIVATE_KEY=$2

if [ -z "$PRIVATE_KEY" ]; then
    # Ask whether to create a brand new keystore file, if yes, don't use private key, create a new keystore file directly in $network_dir
    echo -n "PRIVATE_KEY not found Do you want to create a brand new keystore file? (y/n): "
    read create_new
    if [[ "$create_new" == "y" || "$create_new" == "Y" ]]; then
        echo "Creating a brand new keystore file..."
        
        # Create keystore directory if it doesn't exist
        mkdir -p ~/.foundry/keystores
        
        # Create a new wallet and save to keystore with password
        tmp=$(cast wallet new ~/.foundry/keystores/)
        # Get the file pathfrom the tmp
        file_path=$(echo "$tmp" | grep -o '/.*keystores/[^[:space:]]*')
        dir_path=$(echo "$file_path" | grep -o '/.*keystores/')

        # rename the file name to keystore_name
        mv "$file_path" "$dir_path$keystore_name"
        
        # Get the address from the tmp
        new_address=$(echo "$tmp" | grep -oE '0x[a-fA-F0-9]{40}')

    else
        return 1
    fi
else
    # Ensure private key starts with 0x
    if [[ ! "$PRIVATE_KEY" == 0x* ]]; then
        PRIVATE_KEY="0x$PRIVATE_KEY"
    fi

    # Create keystore file
    echo "Creating keystore file '$keystore_name'..."
    echo "Please enter a password to encrypt your keystore file:"
    
    new_address=$(cast wallet import "$keystore_name" --private-key "$PRIVATE_KEY" | grep -o '0x[a-fA-F0-9]\{40\}')
        
    # Check if successful
    if ! [ $? -eq 0 ]; then
        echo "Failed to create keystore file"
        return 1
    fi
fi

echo ""
echo "Keystore file created successfully!"
echo "Keystore file located at: ~/.foundry/keystores/$keystore_name"
echo ""
echo "Remember to update the following variables in 'script/network/xxxx/.account':"
echo "KEYSTORE_ACCOUNT=$keystore_name"
echo "ACCOUNT_ADDRESS=$new_address"
echo ""