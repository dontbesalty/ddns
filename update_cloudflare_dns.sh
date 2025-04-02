#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# === Load Configuration from .env file if it exists ===
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    # Source the .env file, suppressing errors in case of invalid lines
    set -a # Automatically export all variables
    source "$ENV_FILE" 2>/dev/null
    set +a
    echo "Loaded configuration from $ENV_FILE" # Log this? Maybe later.
fi

# === Configuration (with defaults) ===
# Values from .env file override these defaults
# Cloudflare Settings
CF_API_TOKEN="${CF_API_TOKEN:-"YOUR_CLOUDFLARE_API_TOKEN"}"
CF_ZONE_ID="${CF_ZONE_ID:-"YOUR_ZONE_ID"}"
RECORD_NAME="${RECORD_NAME:-"subdomain.example.com"}" # The DNS record (subdomain) to update
RECORD_TYPE="${RECORD_TYPE:-"A"}"                     # Typically "A" for IPv4

# Pushover Notification Settings (Optional)
PUSHOVER_ENABLE="${PUSHOVER_ENABLE:-true}" # Set to false to disable Pushover notifications
PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-"YOUR_PUSHOVER_USER_KEY"}"
PUSHOVER_API_TOKEN="${PUSHOVER_API_TOKEN:-"YOUR_PUSHOVER_API_TOKEN"}"

# === Script Settings ===
# File to store the last known public IP address
IP_DIR="$HOME/.config/ddns"
IP_FILE="$IP_DIR/last_ip.txt"
# Log file location (macOS specific Library/Logs)
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/ddns_update.log"
# IP check service
IP_SERVICE="https://api.ipify.org"

# === Ensure directories exist ===
mkdir -p "$IP_DIR"
mkdir -p "$LOG_DIR"

# === Logging Function ===
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# === Pushover Notification Function ===
send_pushover() {
    if [[ "$PUSHOVER_ENABLE" != true ]]; then
        return 0 # Skip if disabled
    fi

    if [[ -z "$PUSHOVER_USER_KEY" || "$PUSHOVER_USER_KEY" == "YOUR_PUSHOVER_USER_KEY" || -z "$PUSHOVER_API_TOKEN" || "$PUSHOVER_API_TOKEN" == "YOUR_PUSHOVER_API_TOKEN" ]]; then
        log_message "WARNING: Pushover enabled but User Key or API Token is missing/placeholder. Skipping notification."
        return 1
    fi

    local message="$1"
    local title="${2:-DDNS Update}" # Optional title, default is "DDNS Update"

    log_message "Sending Pushover notification..."
    response=$(curl -s --fail -X POST "https://api.pushover.net/1/messages.json" \
        --form-string "token=$PUSHOVER_API_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "title=$title" \
        --form-string "message=$message")

    if [[ $? -eq 0 ]]; then
        log_message "Pushover notification sent successfully."
    else
        log_message "ERROR: Failed to send Pushover notification. Response: $response"
        return 1
    fi
    return 0
}


log_message "--- DDNS Update Script Started ---"

# === Check Dependencies ===
if ! command -v curl &> /dev/null; then
    log_message "ERROR: curl command not found. Please install curl."
    echo "ERROR: curl command not found. Please install curl." >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_message "ERROR: jq command not found. Please install jq (e.g., 'brew install jq')."
    echo "ERROR: jq command not found. Please install jq (e.g., 'brew install jq')." >&2
    exit 1
fi


# === Get Current Public IP ===
log_message "Fetching current public IP from $IP_SERVICE..."
CURRENT_IP=$(curl -s "$IP_SERVICE")

if [[ -z "$CURRENT_IP" ]]; then
    log_message "ERROR: Failed to fetch current IP address from $IP_SERVICE."
    exit 1
fi

# Basic IP validation (optional, but recommended)
if ! [[ "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_message "ERROR: Invalid IP address format received: $CURRENT_IP"
    exit 1
fi

log_message "Current Public IP: $CURRENT_IP"

# === Get Last Known IP ===
LAST_IP=""
if [[ -f "$IP_FILE" ]]; then
    LAST_IP=$(cat "$IP_FILE")
    log_message "Last Known IP: $LAST_IP"
else
    log_message "No previous IP file found ($IP_FILE). Will attempt update."
fi

# === Compare IPs ===
if [[ "$CURRENT_IP" == "$LAST_IP" ]]; then
    log_message "IP address unchanged ($CURRENT_IP). No update needed."
    log_message "--- DDNS Update Script Finished ---"
    exit 0
fi

log_message "IP address changed: $LAST_IP -> $CURRENT_IP. Updating Cloudflare..."

# === Update Cloudflare DNS ===

# --- Step 1: Get the DNS Record ID ---
log_message "Fetching DNS Record ID for $RECORD_NAME..."
API_URL="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=$RECORD_TYPE&name=$RECORD_NAME"

RECORD_RESPONSE=$(curl -s -X GET "$API_URL" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type: application/json")

# Check if the API call was successful (basic check)
if ! echo "$RECORD_RESPONSE" | jq -e '.success == true' > /dev/null; then
    ERROR_MSG=$(echo "$RECORD_RESPONSE" | jq -r '.errors[0].message // "Unknown API error"')
    log_message "ERROR: Failed to fetch DNS records. Cloudflare API Error: $ERROR_MSG"
    exit 1
fi

RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$RECORD_ID" ]]; then
    log_message "ERROR: DNS Record ID for $RECORD_NAME (Type: $RECORD_TYPE) not found in Zone $CF_ZONE_ID."
    exit 1
fi

log_message "Found DNS Record ID: $RECORD_ID"

# --- Step 2: Update the DNS Record ---
log_message "Updating DNS Record $RECORD_ID ($RECORD_NAME) to $CURRENT_IP..."
UPDATE_URL="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID"
JSON_PAYLOAD=$(jq -n --arg type "$RECORD_TYPE" --arg name "$RECORD_NAME" --arg content "$CURRENT_IP" \
               '{type: $type, name: $name, content: $content, proxied: false, ttl: 1}') # ttl: 1 means Auto

UPDATE_RESPONSE=$(curl -s -X PUT "$UPDATE_URL" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type: application/json" \
     --data "$JSON_PAYLOAD")

# Check if the update was successful
if echo "$UPDATE_RESPONSE" | jq -e '.success == true' > /dev/null; then
    log_message "SUCCESS: Cloudflare DNS record updated successfully."
    # Save the new IP to the file
    echo "$CURRENT_IP" > "$IP_FILE"
    log_message "Saved new IP ($CURRENT_IP) to $IP_FILE."
    # Send Pushover notification
    send_pushover "Updated $RECORD_NAME to $CURRENT_IP" "Cloudflare DDNS Success"
else
    ERROR_MSG=$(echo "$UPDATE_RESPONSE" | jq -r '.errors[0].message // "Unknown API error during update"')
    log_message "ERROR: Failed to update Cloudflare DNS record. API Error: $ERROR_MSG"
    exit 1
fi

log_message "--- DDNS Update Script Finished ---"
exit 0
