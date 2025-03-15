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

# Fix LOCAL_PATH if it contains wildcards
if echo "$LOCAL_PATH" | grep -q '\*'; then
  log "Wildcard im Pfad erkannt, verwende den Basis-Arbeitsverzeichnis"
  LOCAL_PATH="."
fi

# Debug directory information
log "SSH-Benutzername: $SSH_USERNAME"
log "Aktuelles Verzeichnis: $(pwd)"
log "Inhalt des aktuellen Verzeichnisses:"
ls -la

log "Zu übertragende Dateien:"
find "$LOCAL_PATH" -type f | sort

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
  
  log "Quellpfad: $LOCAL_PATH"
  log "Zielpfad: $REMOTE_PATH"
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Verwende rsync mit SSH Passwort"
    export SSHPASS="$SSH_PASSWORD"
    rsync -avz --progress --delete -e "sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no" "$LOCAL_PATH/" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/"
    return $?
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
    
    log "Verwende rsync mit SSH Key"
    rsync -avz --progress --delete -e "ssh -p $PORT -i $TEMP_SSH_PRIVATE_KEY_FILE -o StrictHostKeyChecking=no" "$LOCAL_PATH/" "$SSH_USERNAME@$SERVER:$REMOTE_PATH/"
    return $?
  else
    log "FEHLER: Keine Authentifizierungsmethode verfügbar"
    return 1
  fi
}

# Function for tar+ssh transfer as a reliable alternative
tar_ssh_transfer() {
  log "Verwende tar+ssh für die Übertragung..."
  
  if [ -n "$SSH_PASSWORD" ]; then
    log "Verwende SSH Passwort für tar+ssh Übertragung"
    tar -cz -C "$LOCAL_PATH" . | sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$SSH_USERNAME@$SERVER" "tar -xz -C $REMOTE_PATH"
    return $?
  elif [ -n "$SSH_PRIVATE_KEY" ]; then
    TEMP_SSH_PRIVATE_KEY_FILE='/tmp/private_key.pem'
    printf "%s" "$SSH_PRIVATE_KEY" > "$TEMP_SSH_PRIVATE_KEY_FILE"
    chmod 600 "$TEMP_SSH_PRIVATE_KEY_FILE"
    
    log "Verwende SSH Key für tar+ssh Übertragung"
    tar -cz -C "$LOCAL_PATH" . | ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$TEMP_SSH_PRIVATE_KEY_FILE" "$SSH_USERNAME@$SERVER" "tar -xz -C $REMOTE_PATH"
    return $?
  else
    log "FEHLER: Keine Authentifizierungsmethode verfügbar"
    return 1
  fi
}

# Try multiple file transfer methods
log "Starte Dateiübertragung..."

# Try rsync first
if rsync_transfer; then
  log "Dateiübertragung via rsync erfolgreich abgeschlossen"
  exit 0
fi

log "rsync fehlgeschlagen, versuche tar+ssh methode..."

# Try tar+ssh as reliable fallback
if tar_ssh_transfer; then
  log "Dateiübertragung via tar+ssh erfolgreich abgeschlossen"
  exit 0
else
  log "FEHLER: Alle Übertragungsmethoden sind fehlgeschlagen"
  exit 1
fi