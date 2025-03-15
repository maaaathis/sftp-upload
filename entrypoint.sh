#!/bin/sh -l

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables for input parameters
SERVER="$2"
PORT="$3"
SSH_PRIVATE_KEY="$4"
LOCAL_PATH="$5"
REMOTE_PATH="$6"
SFTP_ARGS="$7"
DELETE_REMOTE_FILES="$8"
SSH_PASSWORD="${12}"
SSH_USERNAME="${11}"

# Function to log with timestamp
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Install required packages
log "Installiere benötigte Pakete..."
apk update
apk add --no-cache sshpass openssh-client rsync

# Benutzername enthält ein @ - wir müssen vorsichtig mit Anführungszeichen arbeiten
log "SSH-Benutzername: $SSH_USERNAME"

# Function to delete remote directory via SSH
delete_via_ssh() {
  log "Lösche Remote-Dateien via SSH..."
  SSH_CMD="rm -rf $REMOTE_PATH && mkdir -p $REMOTE_PATH"
  log "SSH-Befehl: $SSH_CMD"
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Verwende SSH Passwort-Authentifizierung für das Löschen"
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
    
    log "Verwende SSH Key-Authentifizierung für das Löschen"
    ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SSH_USERNAME@$SERVER" "$SSH_CMD"
  else
    log "FEHLER: Keine Authentifizierungsmethode verfügbar"
    exit 1
  fi
  
  log "Remote-Verzeichnis erfolgreich gelöscht"
}

# Delete remote files if requested
if [ "$DELETE_REMOTE_FILES" = "true" ]; then
  delete_via_ssh
fi

# Function to sync files using rsync
rsync_transfer() {
  log "Starte rsync-Übertragung mit SSH-Zugangsdaten..."
  
  # Ensure local path has trailing slash for rsync
  LOCAL_PATH_RSYNC="$LOCAL_PATH"
  if [ ! -z "$LOCAL_PATH" ] && [ "${LOCAL_PATH: -1}" != "/" ]; then
    LOCAL_PATH_RSYNC="$LOCAL_PATH/"
  fi
  
  log "Quellpfad: $LOCAL_PATH_RSYNC"
  log "Zielpfad: $REMOTE_PATH"
  
  # List local directory contents
  log "Inhalt des lokalen Verzeichnisses:"
  ls -la "$LOCAL_PATH"
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Verwende rsync mit SSH Passwort"
    export SSHPASS="$SSH_PASSWORD"
    rsync -avz --progress --delete -e "sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no" "$LOCAL_PATH_RSYNC" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/"
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
    
    log "Verwende rsync mit SSH Key"
    rsync -avz --progress --delete -e "ssh -p $PORT -i $TEMP_SSH_PRIVATE_KEY_FILE -o StrictHostKeyChecking=no" "$LOCAL_PATH_RSYNC" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/"
  else
    log "FEHLER: Keine Authentifizierungsmethode verfügbar"
    return 1
  fi
}

# Function for direct SCP transfer as fallback
scp_transfer() {
  log "Fallback: Starte SCP-Übertragung..."
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Verwende SCP mit SSH Passwort"
    cd "$LOCAL_PATH" && find . -type f | while read file; do
      dir=$(dirname "$file")
      if [ "$dir" != "." ]; then
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$SSH_USERNAME@$SERVER" "mkdir -p $REMOTE_PATH/$dir"
      fi
      sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=no -P "$PORT" "$file" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/$file"
    done
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
    
    log "Verwende SCP mit SSH Key"
    cd "$LOCAL_PATH" && find . -type f | while read file; do
      dir=$(dirname "$file")
      if [ "$dir" != "." ]; then
        ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SSH_USERNAME@$SERVER" "mkdir -p $REMOTE_PATH/$dir"
      fi
      scp -o StrictHostKeyChecking=no -i "$TEMP_SSH_PRIVATE_KEY_FILE" -P "$PORT" "$file" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/$file"
    done
  else
    log "FEHLER: Keine Authentifizierungsmethode verfügbar"
    return 1
  fi
}

# Try file transfers
log "Starte Dateiübertragung..."

if rsync_transfer; then
  log "Dateiübertragung via rsync erfolgreich abgeschlossen"
elif scp_transfer; then
  log "Dateiübertragung via SCP erfolgreich abgeschlossen"
else
  log "FEHLER: Alle Übertragungsmethoden sind fehlgeschlagen"
  exit 1
fi

log "Deployment erfolgreich abgeschlossen"
exit 0