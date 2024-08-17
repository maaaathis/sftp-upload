#!/bin/sh -l

# Exit immediately if a command exits with a non-zero status or if a variable is unset.
set -eu

# Define variables for input parameters
USERNAME="$1"
SERVER="$2"
PORT="$3"
SSH_PRIVATE_KEY="$4"
LOCAL_PATH="$5"
REMOTE_PATH="$6"
SFTP_ONLY="$7"
SFTP_ARGS="$8"
DELETE_REMOTE_FILES="$9"
PASSWORD="${10}"

# Define temporary file paths
TEMP_SSH_PRIVATE_KEY_FILE='../private_key.pem'
TEMP_SFTP_FILE='../sftp'

# Ensure the remote path is not empty
if [ -z "$REMOTE_PATH" ]; then
    echo 'Error: remote_path is empty'
    exit 1
fi

# Check if password is provided
if [ -n "$PASSWORD" ]; then
    echo 'Using SSH password authentication'
    apk add --no-cache sshpass

    # Delete remote files if DELETE_REMOTE_FILES is set to true
    if [ "$DELETE_REMOTE_FILES" = "true" ]; then
        echo 'Deleting remote files...'
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$SERVER" rm -rf "$REMOTE_PATH"
    fi

    # Skip directory creation if SFTP_ONLY is true, otherwise create directory
    if [ "$SFTP_ONLY" != "true" ]; then
        echo 'Creating directory on remote server if it does not exist...'
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$SERVER" mkdir -p "$REMOTE_PATH"
    else
        echo 'Skipping directory creation as SFTP_ONLY is set to true'
    fi

    # Start SFTP transfer
    echo 'Starting SFTP transfer...'
    printf "%s" "put -r $LOCAL_PATH $REMOTE_PATH" >"$TEMP_SFTP_FILE"
    SSHPASS="$PASSWORD" sshpass -e sftp -oBatchMode=no -b "$TEMP_SFTP_FILE" -P "$PORT" "$SFTP_ARGS" -o StrictHostKeyChecking=no "$USERNAME@$SERVER"

    echo 'Upload successful'
    exit 0
fi

# Use SSH private key for authentication
echo 'Using SSH private key authentication'
printf "%s" "$SSH_PRIVATE_KEY" >"$TEMP_SSH_PRIVATE_KEY_FILE"
chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"  # Ensure the private key has the correct permissions

# Delete remote files if DELETE_REMOTE_FILES is set to true
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
    echo 'Deleting remote files...'
    ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER" rm -rf "$REMOTE_PATH"
fi

# Skip directory creation if SFTP_ONLY is true, otherwise create directory
if [ "$SFTP_ONLY" != "true" ]; then
    echo 'Creating directory on remote server if it does not exist...'
    ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER" mkdir -p "$REMOTE_PATH"
else
    echo 'Skipping directory creation as SFTP_ONLY is set to true'
fi

# Start SFTP transfer
echo 'Starting SFTP transfer...'
printf "%s" "put -r $LOCAL_PATH $REMOTE_PATH" >"$TEMP_SFTP_FILE"
sftp -b "$TEMP_SFTP_FILE" -P "$PORT" "$SFTP_ARGS" -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER"

echo 'Upload successful'
exit 0
