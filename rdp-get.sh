#!/bin/bash

# Fetch all active project IDs dynamically
PROJECTS=($(gcloud projects list --format="value(projectId)"))

# Function to reset password and retrieve RDP details
reset_password() {
  local project_id="$1"
  local zone="$2"
  local instance_id="$3"

  # Get external IP
  EXTERNAL_IP=$(gcloud compute instances describe "$instance_id" --project="$project_id" --zone="$zone" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

  if [ -z "$EXTERNAL_IP" ]; then
    echo "Error: Could not retrieve external IP for $instance_id" >&2
    return 1
  fi

  # Reset password for user 'admin' (auto-confirm with 'yes')
  PASSWORD=$(echo "Y" | gcloud compute reset-windows-password "$instance_id" --user=admin --project="$project_id" --zone="$zone" --format="get(password)")

  if [ -z "$PASSWORD" ]; then
    echo "Error: Could not reset password for $instance_id" >&2
    return 1
  fi

  # Save credentials in the desired format (ip:admin:pass)
  echo "$EXTERNAL_IP:admin:$PASSWORD" >> rdp.txt
}

# Loop through projects and process instances
for project in "${PROJECTS[@]}"; do
  # Get all instances and their zones
  INSTANCES=($(gcloud compute instances list --project="$project" --format="value(name,zone)"))

  for ((i = 0; i < ${#INSTANCES[@]}; i+=2)); do
    instance_id="${INSTANCES[i]}"
    zone="${INSTANCES[i+1]}"

    reset_password "$project" "$zone" "$instance_id"
  done
done
