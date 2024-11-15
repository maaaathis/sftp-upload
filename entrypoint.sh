#!/bin/sh
set -eu

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    log "Error occurred in script at line $1"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

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

# Define temporary file paths
TEMP_SSH_PRIVATE_KEY_FILE='../private_key.pem'
TEMP_SFTP_FILE='../sftp'

# Ensure the remote path is not empty
if [ -z "$REMOTE_PATH" ]; then
    log 'Error: remote_path is empty'
    exit 1
fi

# Function to perform SFTP upload
perform_sftp_upload() {
    log 'Starting SFTP transfer...'
    printf "%s\n" "put -r $LOCAL_PATH/* $REMOTE_PATH/" > "$TEMP_SFTP_FILE"
    if [ -n "$PASSWORD" ]; then
        SSHPASS="$PASSWORD" sshpass -e sftp -oBatchMode=no -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$USERNAME@$SERVER"
    else
        sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER"
    fi
    log 'SFTP transfer completed successfully'
}

# Function to delete contents of remote directory
delete_remote_directory_contents() {
    log 'Deleting contents of remote directory...'
    DELETE_COMMAND="find \"$REMOTE_PATH\" -mindepth 1 -delete"
    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$SERVER" "$DELETE_COMMAND"
    else
        ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$USERNAME@$SERVER" "$DELETE_COMMAND"
    fi
    log 'Contents of remote directory deleted successfully'
}

# Main execution
if [ -n "$PASSWORD" ]; then
    log 'Using SSH password authentication'
    apk add --no-cache sshpass
else
    log 'Using SSH private key authentication'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
fi

if [ "$DELETE_REMOTE_FILES" = "true" ]; then
    delete_remote_directory_contents
fi

perform_sftp_upload

log 'SFTP upload completed'
exit 0
