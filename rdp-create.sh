#!/bin/bash

# Function to check if a project has billing enabled
check_billing() {
  local project_id_arg="$1"
  billing_info=$(gcloud billing accounts list --project="$project_id_arg" --format="json")
  if echo "$billing_info" | jq -e 'length > 0'; then
    return 0 # Billing is enabled
  else
    return 1 # Billing is not enabled or no billing account found
  fi
}

# Fetch active project IDs dynamically
PROJECTS=($(gcloud projects list --format="value(projectId)"))

# Define available locations (regions) in the US
REGIONS=("us-central1" "us-east1" "us-west1" "us-east4" "us-west2" "us-west3" "us-west4")

# Define instance configuration
INSTANCE_COUNT=3
MACHINE_TYPE="e2-standard-4"  # 4 vCPU, 16GB RAM
IMAGE_NAME="windows-server-2019-dc-v20250213"
IMAGE_PROJECT="windows-cloud"
DISK_SIZE="50"  # 100GB SSD
DISK_TYPE="pd-ssd"

# Function to create an RDP instance with region handling
create_instance() {
  local project_id="$1"
  local region="$2"
  local instance_name="$3"

  echo "Attempting to create instance: $instance_name in project: $project_id (Region: $region)"

  # Get available zones in the specified region
  local ZONES=($(gcloud compute zones list --project="$project_id" --filter="region~'$region$'" --format="value(name)"))

  if [ ${#ZONES[@]} -eq 0 ]; then
    echo "No available zones found in region: $region for project: $project_id" >&2
    return 1
  fi

  # Try creating the instance in each zone of the region until successful
  for zone in "${ZONES[@]}"; do
    echo "Trying to create instance in zone: $zone"
    gcloud compute instances create "$instance_name" \
      --project="$project_id" \
      --zone="$zone" \
      --machine-type="$MACHINE_TYPE" \
      --image="$IMAGE_NAME" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size="$DISK_SIZE" \
      --boot-disk-type="$DISK_TYPE" \
      --metadata enable-oslogin=FALSE \
      --tags=rdp-instance \
      --scopes=cloud-platform

    if [ $? -eq 0 ]; then
      echo "Instance $instance_name created successfully in zone: $zone!"
      return 0 # Instance created successfully, exit the function
    else
      echo "Failed to create instance in zone: $zone" >&2
    fi
  done

  echo "Failed to create instance: $instance_name in region: $region after trying all zones." >&2
  return 1
}

# Loop through projects and create RDP instances
for project in "${PROJECTS[@]}"; do
  echo "Checking billing status for project: $project"
  if check_billing "$project"; then
    echo "Billing is enabled for project: $project. Proceeding with instance creation."
    for i in $(seq 1 "$INSTANCE_COUNT"); do
      instance_base_name="rdp-${project}-${i}"
      # Cycle through the US regions
      region_index=$(( (i - 1) % ${#REGIONS[@]} ))
      region="${REGIONS[$region_index]}"
      instance_name="${instance_base_name}-${region//-/}" # Append region to instance name
      create_instance "$project" "$region" "$instance_name"
    done
  else
    echo "Billing is NOT enabled for project: $project. Skipping instance creation."
  fi
done

echo "Script finished!"