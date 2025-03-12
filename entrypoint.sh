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
SFTP_ARGS="$7"
DELETE_REMOTE_FILES="$8"
PASSWORD="${9}"
USE_SFTP_FOR_DELETE="${10:-true}"

# Define temporary file paths
TEMP_SSH_PRIVATE_KEY_FILE='../private_key.pem'
TEMP_SFTP_FILE='../sftp'
TEMP_SFTP_DELETE_FILE='../sftp_delete'
TEMP_DIR_LIST_FILE='../dir_list'

# Function to log with timestamp
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Ensure the remote path is not empty
if [ -z "$REMOTE_PATH" ]; then
    log 'Error: remote_path is empty'
    exit 1
fi

# Function to delete remote files via SFTP
delete_via_sftp() {
    log 'Deleting remote files via SFTP protocol...'
    
    # Extract parent directory and basename
    REMOTE_DIR=$(dirname "$REMOTE_PATH")
    REMOTE_BASE=$(basename "$REMOTE_PATH")
    
    # Create temporary SFTP batch commands file
    {
        echo "cd $REMOTE_DIR"
        echo "ls -la"  # List before deletion for debugging
        echo "rm -rf $REMOTE_BASE"
        echo "mkdir $REMOTE_BASE"
        echo "ls -la"  # List after deletion for debugging
    } > "$TEMP_SFTP_DELETE_FILE"
    
    # Execute SFTP commands
    if [ -n "$PASSWORD" ]; then
        SSHPASS="$PASSWORD" sshpass -e sftp -b "$TEMP_SFTP_DELETE_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$USERNAME@$SERVER"
    else
        sftp -b "$TEMP_SFTP_DELETE_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER"
    fi
    
    log 'Remote directory cleared successfully via SFTP'
}

# Function to delete remote files via SSH
delete_via_ssh() {
    log 'Deleting remote files via SSH...'
    
    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$SERVER" "rm -rf $REMOTE_PATH && mkdir -p $REMOTE_PATH"
    else
        ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER" "rm -rf $REMOTE_PATH && mkdir -p $REMOTE_PATH"
    fi
    
    log 'Remote directory cleared successfully via SSH'
}

# Check if password is provided
if [ -n "$PASSWORD" ]; then
    log 'Using SSH password authentication'
    apk add --no-cache sshpass

    # Delete remote files if DELETE_REMOTE_FILES is set to true
    if [ "$DELETE_REMOTE_FILES" = "true" ]; then
        if [ "$USE_SFTP_FOR_DELETE" = "true" ]; then
            delete_via_sftp
        else
            delete_via_ssh
        fi
    fi

    # Start SFTP transfer
    log 'Starting SFTP transfer...'
    printf "%s" "put -r $LOCAL_PATH $REMOTE_PATH" > "$TEMP_SFTP_FILE"
    SSHPASS="$PASSWORD" sshpass -e sftp -oBatchMode=no -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$USERNAME@$SERVER"

    log 'Upload successful'
    exit 0
fi

# Use SSH private key for authentication
log 'Using SSH private key authentication'
printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"  # Ensure the private key has the correct permissions

# Delete remote files if DELETE_REMOTE_FILES is set to true
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
    if [ "$USE_SFTP_FOR_DELETE" = "true" ]; then
        delete_via_sftp
    else
        delete_via_ssh
    fi
fi

# Start SFTP transfer
log 'Starting SFTP transfer...'
printf "%s" "put -r $LOCAL_PATH $REMOTE_PATH" > "$TEMP_SFTP_FILE"
sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER"

log 'Upload successful'
exit 0