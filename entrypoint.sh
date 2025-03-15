#!/bin/sh -l

# Exit immediately if a command exits with a non-zero status
set -e

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
TEMP_SFTP_FILE='/tmp/sftp_commands'

# Function to log with timestamp
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Function to validate parameters
validate_params() {
  if [ -z "$SFTP_USERNAME" ]; then
    log "ERROR: SFTP username is empty!"
    exit 1
  fi

  if [ -z "$SSH_USERNAME" ]; then
    log "ERROR: SSH username is empty!"
    exit 1
  fi

  if [ -z "$SERVER" ]; then
    log "ERROR: Server address is empty!"
    exit 1
  fi

  if [ -z "$REMOTE_PATH" ]; then
    log "ERROR: Remote path is empty!"
    exit 1
  fi

  if [ -z "$LOCAL_PATH" ]; then
    log "ERROR: Local path is empty!"
    exit 1
  fi

  log "Validated parameters:"
  log "- SFTP Username: $SFTP_USERNAME"
  log "- SSH Username: $SSH_USERNAME"
  log "- Server: $SERVER"
  log "- Port: $PORT"
  log "- Local Path: $LOCAL_PATH"
  log "- Remote Path: $REMOTE_PATH"
  log "- Delete Remote Files: $DELETE_REMOTE_FILES"
  log "- Using password authentication: $([ -n "$SFTP_PASSWORD" ] || [ -n "$SSH_PASSWORD" ] && echo 'Yes' || echo 'No')"
  log "- Using key authentication: $([ -n "$SSH_PRIVATE_KEY" ] && echo 'Yes' || echo 'No')"
}

# Validate parameters
validate_params

# Install required packages
log "Installing required packages..."
apk update
apk add --no-cache sshpass openssh-client

# Handle SSH private key if provided
if [ -n "$SSH_PRIVATE_KEY" ]; then
  log "Setting up SSH private key"
  printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
  chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
else
  log "No SSH private key provided"
fi

# Function to delete remote directory via SSH
delete_via_ssh() {
  log "Deleting remote files via SSH..."
  SSH_CMD="rm -rf $REMOTE_PATH && mkdir -p $REMOTE_PATH"
  log "SSH command: $SSH_CMD"
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Using SSH password authentication for deletion with user: $SSH_USERNAME"
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Using SSH key authentication for deletion with user: $SSH_USERNAME"
    ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
  else
    log "ERROR: No authentication method available for SSH delete"
    exit 1
  fi
  
  log "Remote directory cleared successfully via SSH"
}

# Delete remote files if requested
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
  delete_via_ssh
fi

# Function to execute SFTP using sshpass
sftp_transfer() {
  log "Starting SFTP transfer..."
  log "Preparing SFTP batch commands file"
  
  # Create SFTP batch file
  cat > "$TEMP_SFTP_FILE" << EOF
cd $REMOTE_PATH
put -r $LOCAL_PATH/* .
EOF
  
  log "SFTP commands:"
  cat "$TEMP_SFTP_FILE"
  
  if [ -n "$SFTP_PASSWORD" ]; then
    log "Using SFTP password authentication with user: $SFTP_USERNAME"
    echo "Using sshpass with SFTP password..."
    SSHPASS="$SFTP_PASSWORD" sshpass -e sftp -oStrictHostKeyChecking=no -P "$PORT" -b "$TEMP_SFTP_FILE" "$SFTP_USERNAME@$SERVER"
  elif [ -n "$SSH_PASSWORD" ]; then
    log "Using SSH password for SFTP authentication with user: $SFTP_USERNAME"
    echo "Using sshpass with SSH password..."
    SSHPASS="$SSH_PASSWORD" sshpass -e sftp -oStrictHostKeyChecking=no -P "$PORT" -b "$TEMP_SFTP_FILE" "$SFTP_USERNAME@$SERVER"
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Using SFTP with key authentication with user: $SFTP_USERNAME"
    sftp -oStrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" -P "$PORT" -b "$TEMP_SFTP_FILE" "$SFTP_USERNAME@$SERVER"
  else
    log "ERROR: No authentication method available for SFTP upload"
    exit 1
  fi
}

# Alternative approach using direct scp for file transfer
scp_transfer() {
  log "Falling back to SCP transfer..."
  
  if [ -n "$SFTP_PASSWORD" ]; then
    log "Using SCP with SFTP password authentication with user: $SFTP_USERNAME"
    cd "$LOCAL_PATH" && find . -type f -exec sshpass -p "$SFTP_PASSWORD" scp -o StrictHostKeyChecking=no -P "$PORT" {} "$SFTP_USERNAME@$SERVER:$REMOTE_PATH/" \;
  elif [ -n "$SSH_PASSWORD" ]; then
    log "Using SCP with SSH password authentication with user: $SFTP_USERNAME"
    cd "$LOCAL_PATH" && find . -type f -exec sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=no -P "$PORT" {} "$SFTP_USERNAME@$SERVER:$REMOTE_PATH/" \;
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Using SCP with key authentication with user: $SFTP_USERNAME"
    cd "$LOCAL_PATH" && find . -type f -exec scp -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" -P "$PORT" {} "$SFTP_USERNAME@$SERVER:$REMOTE_PATH/" \;
  else
    log "ERROR: No authentication method available for SCP upload"
    exit 1
  fi
}

# Try SFTP first, then fall back to SCP if it fails
echo "Attempting file transfer..."
if ! sftp_transfer; then
  log "SFTP transfer failed, trying SCP instead"
  scp_transfer || { log "ERROR: All file transfer methods failed"; exit 1; }
fi

log "File transfer completed successfully"
exit 0