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
TEMP_SFTP_FILE='/tmp/sftp_commands'

# Function to log with timestamp
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Ensure the remote path is not empty
if [ -z "$REMOTE_PATH" ]; then
    log 'Error: remote_path is empty'
    exit 1
fi

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

# Delete remote files if requested
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
    delete_via_ssh
fi

# Prepare SFTP file for upload
log 'Preparing SFTP transfer...'
cat > "$TEMP_SFTP_FILE" << EOF
cd $REMOTE_PATH
put -r $LOCAL_PATH/* .
EOF
log "SFTP commands for upload:"
cat "$TEMP_SFTP_FILE"

# Perform SFTP transfer
log 'Starting SFTP transfer...'

# Function to execute SFTP transfer with password
sftp_with_password() {
    local username="$1"
    local password="$2"
    
    log "Using password authentication for SFTP with user: $username"
    
    # Create a temporary expect script to handle the password
    EXPECT_SCRIPT="/tmp/sftp_expect.sh"
    cat > "$EXPECT_SCRIPT" << EOF
#!/usr/bin/expect -f
set timeout -1
spawn sftp -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no "$username@$SERVER"
expect "password:"
send "$password\r"
expect "sftp>"
send "cd $REMOTE_PATH\r"
expect "sftp>"
send "put -r $LOCAL_PATH/* .\r"
expect "sftp>"
send "bye\r"
expect eof
EOF
    
    chmod +x "$EXPECT_SCRIPT"
    apk add --no-cache expect
    
    log "Running expect script for SFTP transfer"
    $EXPECT_SCRIPT
}

if [ -n "$SFTP_PASSWORD" ]; then
    log "Using SFTP password for authentication"
    sftp_with_password "$SFTP_USERNAME" "$SFTP_PASSWORD"
elif [ -n "$SSH_PASSWORD" ]; then
    log "Using SSH password for SFTP authentication"
    sftp_with_password "$SFTP_USERNAME" "$SSH_PASSWORD"
elif [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Using SFTP with key authentication"
    sftp -b "$TEMP_SFTP_FILE" -P "$PORT" $SFTP_ARGS -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SFTP_USERNAME@$SERVER"
else
    log "Error: No authentication method available for SFTP upload"
    exit 1
fi

log 'Upload successful'
exit 0