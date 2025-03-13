#!/bin/sh -l

# Exit immediately if a command exits with a non-zero status or if a variable is unset.
set -eu

# Define variables for input parameters
SFTP_USERNAME="$1"
SERVER="$2"
PORT="$3"
SSH_PRIVATE_KEY="$4"
LOCAL_PATH="$5"
REMOTE_PATH="$6"
SFTP_ARGS="$7"
DELETE_REMOTE_FILES="$8"
SFTP_PASSWORD="$9"
USE_SFTP_FOR_DELETE="${10:-true}"
SSH_USERNAME="${11:-$SFTP_USERNAME}"
SSH_PASSWORD="${12:-$SFTP_PASSWORD}"

# Use /tmp for temporary files
TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
TEMP_SFTP_FILE='/tmp/sftp'
TEMP_SFTP_DELETE_FILE='/tmp/sftp_delete'

# Function to log with timestamp
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Function to display debug info
debug_info() {
  log "Debug info:"
  log "- LOCAL_PATH: $LOCAL_PATH"
  log "- REMOTE_PATH: $REMOTE_PATH"
  log "- SFTP_USERNAME: $SFTP_USERNAME"
  log "- SSH_USERNAME: $SSH_USERNAME"
  log "- SFTP_PASSWORD provided: $([ -n "$SFTP_PASSWORD" ] && echo 'Yes' || echo 'No')"
  log "- SSH_PASSWORD provided: $([ -n "$SSH_PASSWORD" ] && echo 'Yes' || echo 'No')"
  log "- SSH_PRIVATE_KEY provided: $([ -n "$SSH_PRIVATE_KEY" ] && echo 'Yes' || echo 'No')"
  log "- DELETE_REMOTE_FILES: $DELETE_REMOTE_FILES"
  log "- USE_SFTP_FOR_DELETE: $USE_SFTP_FOR_DELETE"
  log "- Current directory content:"
  ls -la
}

# Ensure the remote path is not empty
if [ -z "$REMOTE_PATH" ]; then
    log 'Error: remote_path is empty'
    exit 1
fi

# Display debug info
debug_info

# Install sshpass if password authentication is needed
if [ -n "$SFTP_PASSWORD" ] || [ -n "$SSH_PASSWORD" ]; then
    log 'Installing sshpass for password authentication'
    apk add --no-cache sshpass
fi

# Handle SSH private key if provided
if [ -n "$SSH_PRIVATE_KEY" ]; then
    log 'Setting up SSH private key'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
else
    log 'No SSH private key provided'
fi

# Function to delete remote directory via SSH
delete_via_ssh() {
    log 'Deleting remote files via SSH...'
    SSH_CMD="rm -rf $REMOTE_PATH && mkdir -p $REMOTE_PATH"
    log "SSH command: $SSH_CMD"
    
    if [ -n "$SSH_PASSWORD" ]; then
        log "Using SSH password authentication for deletion"
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
    elif [ -n "$SSH_PRIVATE_KEY" ]; then
        log "Using SSH key authentication for deletion"
        ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
    else
        log "Error: No authentication method available for SSH delete"
        exit 1
    fi
    
    log 'Remote directory cleared successfully via SSH'
}

# Function to delete remote files via SFTP
delete_via_sftp() {
    log 'Deleting remote files via SFTP protocol...'
    
    # Extract parent directory and basename
    REMOTE_DIR=$(dirname "$REMOTE_PATH")
    REMOTE_BASE=$(basename "$REMOTE_PATH")
    
    # Create temporary SFTP batch commands file
    {
        echo "cd $REMOTE_DIR"
        echo "ls -la"
        echo "rm -rf $REMOTE_BASE"
        echo "mkdir $REMOTE_BASE"
        echo "ls -la"
    } > "$TEMP_SFTP_DELETE_FILE"
    
    log "SFTP delete commands:"
    cat "$TEMP_SFTP_DELETE_FILE"
    
    # Execute SFTP commands
    if [ -n "$SFTP_PASSWORD" ]; then
        log "Using SFTP password authentication for deletion"
        sshpass -p "$SFTP_PASSWORD" sftp -b "$TEMP_SFTP_DELETE_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$SFTP_USERNAME@$SERVER"
    elif [ -n "$SSH_PRIVATE_KEY" ]; then
        log "Using SFTP key authentication for deletion"
        sftp -b "$TEMP_SFTP_DELETE_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SFTP_USERNAME@$SERVER"
    else
        log "Error: No authentication method available for SFTP delete"
        exit 1
    fi
    
    log 'Remote directory cleared successfully via SFTP'
}

# Delete remote files if requested
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
    if [ "$USE_SFTP_FOR_DELETE" = "true" ]; then
        delete_via_sftp
    else
        delete_via_ssh
    fi
fi

# Prepare SFTP file for upload
log 'Preparing SFTP transfer...'
echo "put -r $LOCAL_PATH/* $REMOTE_PATH/" > "$TEMP_SFTP_FILE"
log "SFTP commands for upload:"
cat "$TEMP_SFTP_FILE"

# Perform SFTP transfer
log 'Starting SFTP transfer...'
if [ -n "$SFTP_PASSWORD" ]; then
    log "Using SFTP with password authentication"
    sshpass -p "$SFTP_PASSWORD" sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$SFTP_USERNAME@$SERVER"
elif [ -n "$SSH_PASSWORD" ]; then
    log "Using SSH password for SFTP authentication"
    sshpass -p "$SSH_PASSWORD" sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$SFTP_USERNAME@$SERVER"
elif [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Using SFTP with key authentication"
    sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SFTP_USERNAME@$SERVER"
else
    log "Error: No authentication method available for SFTP upload"
    exit 1
fi

log 'Upload successful'
exit 0