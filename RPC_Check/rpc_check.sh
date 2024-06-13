#!/bin/bash

# Variables for file names and paths
SCRIPT_DIR="/root/RPC_Check"
CSV_FILE="$SCRIPT_DIR/rpc_pool.csv"
LOG_FILE="$SCRIPT_DIR/events.log"
APACHE_CONF="/etc/apache2/sites-enabled/000-default-le-ssl.conf"
APACHE_CONF_BACKUP="/etc/apache2/000-default-le-ssl.conf.bak"

# Initialize APACHE_CHANGED flag
APACHE_CHANGED=false

export LOG_FILE
export CSV_FILE
export SCRIPT_DIR
export APACHE_CONF
export APACHE_CONF_BACKUP
export APACHE_CHANGED

# Function to add a BalancerMember to the Apache configuration
add_balancer_member() {
  local url=$1
  if ! grep -q "BalancerMember \"$url\"" "$APACHE_CONF"; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Adding $url to BalancerMember section in Apache config" >> "$LOG_FILE"
    # Use the comment as the marker to ensure we are adding it in the right place
    sed -i "/# Add Balancer Members Here/a\        BalancerMember \"$url\"" "$APACHE_CONF"
    APACHE_CHANGED=true
  fi
}

# Function to remove an RPC URL from the BalancerMember section in 000-default-le-ssl.conf
remove_balancer_member() {
  local url=$1
  if grep -q "BalancerMember \"$url\"" "$APACHE_CONF"; then
    sed -i "\|BalancerMember \"$url\"|d" "$APACHE_CONF"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Removed $url from BalancerMember section in Apache config" >> "$LOG_FILE"
    APACHE_CHANGED=true
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $url not found in BalancerMember section" >> "$LOG_FILE"
  fi
}

# Function to perform the curl request and log output and errors
query_rpc() {
  local url=$1
  local response=$(curl -s -m 10 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$url")
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "Processing URL: $url" >> "$LOG_FILE"
  if [ $? -eq 0 ]; then
    if [[ -z "$response" ]]; then
      echo "$timestamp - ERROR - $url - Empty response" >> "$LOG_FILE"
      echo "$url,Invalid Response" >> /tmp/rpc_results.tmp
    elif [[ "$response" == *"<html"* ]]; then
      echo "$timestamp - ERROR - $url - HTML response" >> "$LOG_FILE"
      echo "$url,Invalid Response" >> /tmp/rpc_results.tmp
    else
      local block_height=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(int(data['result'], 0))
except json.JSONDecodeError:
    print('ERROR: Invalid JSON')
except KeyError:
    print('ERROR: Missing key in JSON')
")

      if [[ "$block_height" == ERROR* ]]; then
        echo "$timestamp - ERROR - $url - $block_height" >> "$LOG_FILE"
        echo "$url,Invalid Response" >> /tmp/rpc_results.tmp
      else
        echo "Block Height for $url: $block_height" >> "$LOG_FILE"
        echo "$url,$block_height" >> /tmp/rpc_results.tmp
      fi
    fi
  else
    echo "$timestamp - ERROR - $url - Curl request failed" >> "$LOG_FILE"
    echo "$url,Invalid Response" >> /tmp/rpc_results.tmp
  fi
}

# Function to update the Health Status in the CSV file and Apache config
update_health_status() {
  local url=$1
  local status=$2
  local old_status=$(awk -F, -v url="$url" '$1 == url {print $2}' "$CSV_FILE")
  if [ "$old_status" != "$status" ]; then
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - Updating Health Status for $url from $old_status to $status in CSV file: $CSV_FILE" >> "$LOG_FILE"
    sed -i "s|^\($url,\).*\$|\1$status|" "$CSV_FILE"
    
    if [ "$status" == "Active" ]; then
      add_balancer_member "$url"
    elif [ "$status" == "Inactive" ]; then
      remove_balancer_member "$url"
    fi

    APACHE_CHANGED=true
  fi
}

# Change directory to script directory
cd "$SCRIPT_DIR" || exit

# Check if stop signal exists; exit if it does
if [ -f /tmp/rpc_check_stop_signal ]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") - Script execution skipped due to stop signal" >> "$LOG_FILE"
  exit 0
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") - Starting RPC check script" >> "$LOG_FILE"

# Encapsulate the code block within a function
process_urls() {
  # Clear previous temporary results
  rm -f /tmp/rpc_results.tmp

  # Read URLs from the CSV file, skipping the header line
  while IFS=, read -r url _; do
    # Skip processing if URL is empty
    if [ -z "$url" ]; then
      continue
    fi

    # Query each URL in parallel using background processes
    query_rpc "$url" &
  done < <(tail -n +2 "$CSV_FILE")

  # Wait for all background processes to finish
  wait

  # Initialize associative arrays
  declare -A block_heights
  declare -A health_status

  # Read results from temporary file
  while IFS=, read -r url result; do
    if [[ "$result" =~ ^[0-9]{8,9}$ ]]; then
      block_heights["$url"]=$result
      health_status["$url"]="Active"
    else
      block_heights["$url"]="Invalid Response"
      health_status["$url"]="Inactive"
    fi
  done < /tmp/rpc_results.tmp

  # Determine the maximum block height
  local max_block_height=0
  for height in "${block_heights[@]}"; do
    if [[ "$height" =~ ^[0-9]{8,9}$ ]] && [ "$height" -gt "$max_block_height" ]; then
      max_block_height="$height"
    fi
  done

  # Update CSV and Apache configuration based on results
  while IFS=, read -r url old_status old_height; do
    if [ "${block_heights[$url]}" != "Invalid Response" ]; then
      local current_height=${block_heights[$url]}
      local blocks_behind=$((max_block_height - current_height))
      if [ "$blocks_behind" -le 4 ]; then
        health_status[$url]="Active"
      else
        health_status[$url]="Inactive"
      fi
      sed -i "s|^\($url,\)\([^,]*\),.*$|\1${health_status[$url]},$current_height|" "$CSV_FILE"
    else
      sed -i "s|^\($url,\)\([^,]*\),.*$|\1${health_status[$url]},Invalid Response|" "$CSV_FILE"
    fi

    if [ "${health_status[$url]}" == "Active" ]; then
      add_balancer_member "$url"
    else
      remove_balancer_member "$url"
    fi
  done < <(tail -n +2 "$CSV_FILE")

  echo "All requests have been processed. Check the log file ($LOG_FILE) for details."
}

export -f query_rpc
export -f update_health_status
export -f add_balancer_member
export -f remove_balancer_member

# Call the function to process URLs
process_urls

# Reload Apache if changes were made
if $APACHE_CHANGED; then
  systemctl reload apache2
  echo "$(date +"%Y-%m-%d %H:%M:%S") - Apache2 reloaded due to changes in BalancerMember section" >> "$LOG_FILE"
fi

# Limit events.log to the latest 5000 lines
if [ -f "$LOG_FILE" ]; then
    total_lines=$(wc -l < "$LOG_FILE")
    if [ "$total_lines" -gt 5000 ]; then
        lines_to_keep=$((total_lines - 5000))
        sed -i "1,${lines_to_keep}d" "$LOG_FILE"
        echo "$(date +"%Y-%m-%d %H:%M:%S") - events.log trimmed to 5000 lines" >> "$LOG_FILE"
    fi
fi
