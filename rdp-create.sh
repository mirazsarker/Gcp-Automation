#!/bin/bash

# Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

# Static credentials
USERNAME="Administrator"
PASSWORD="Gcp@dm!n2025"

# CMD-format startup script (properly escaped for command line)
STARTUP_SCRIPT="net user Administrator ${PASSWORD} && net user Administrator /active:yes"

# Output file
RDP_OUTPUT="rdp.txt"
> "$RDP_OUTPUT"  # Clear old output

# Function to check billing
check_billing() {
  local project_id="$1"
  billing_info=$(gcloud billing accounts list --project="$project_id" --format="json" 2>/dev/null)
  if echo "$billing_info" | jq -e 'length > 0' > /dev/null; then
    return 0
  else
    return 1
  fi
}

# Get all GCP project IDs
PROJECTS=($(gcloud projects list --format="value(projectId)"))

# US regions
REGIONS=("us-central1" "us-east1" "us-west1" "us-east4" "us-west2" "us-west3" "us-west4")

# Instance config
INSTANCE_COUNT=3
MACHINE_TYPE="e2-standard-4"
IMAGE_NAME="windows-server-2019-dc-v20250213"
IMAGE_PROJECT="windows-cloud"
DISK_SIZE="50"
DISK_TYPE="pd-ssd"

# Create instance function
create_instance() {
  local project_id="$1"
  local region="$2"
  local instance_name="$3"

  echo -e "${CYAN}→ Creating: $instance_name in $region [Project: $project_id]${NC}"

  ZONES=($(gcloud compute zones list --project="$project_id" --filter="region:($region)" --format="value(name)"))
  for zone in "${ZONES[@]}"; do
    echo -e "${YELLOW}↪ Zone: $zone${NC}"

    gcloud compute instances create "$instance_name" \
      --project="$project_id" \
      --zone="$zone" \
      --machine-type="$MACHINE_TYPE" \
      --image="$IMAGE_NAME" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size="$DISK_SIZE" \
      --boot-disk-type="$DISK_TYPE" \
      --metadata="enable-oslogin=FALSE,windows-startup-script-cmd=$STARTUP_SCRIPT" \
      --tags=rdp-instance \
      --scopes=cloud-platform \
      --quiet &> /dev/null

    if [ $? -eq 0 ]; then
      IP=$(gcloud compute instances describe "$instance_name" --project="$project_id" --zone="$zone" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
      echo "${IP}:${USERNAME}:${PASSWORD}" >> "$RDP_OUTPUT"
      echo -e "${GREEN}✔ Success: $instance_name @ $IP${NC}"
      return 0
    else
      echo -e "${RED}✖ Failed in $zone, trying next...${NC}"
    fi
  done

  echo -e "${RED}✖ Could not create $instance_name in $region${NC}"
  return 1
}

# Loop through all projects
for project in "${PROJECTS[@]}"; do
  echo -e "${YELLOW}➤ Checking billing: $project${NC}"
  if check_billing "$project"; then
    echo -e "${GREEN}✔ Billing active. Proceeding...${NC}"
    for i in $(seq 1 "$INSTANCE_COUNT"); do
      region_index=$(( (i - 1) % ${#REGIONS[@]} ))
      region="${REGIONS[$region_index]}"
      instance_name="rdp-${project}-${i}-${region//-/}"
      create_instance "$project" "$region" "$instance_name"
    done
  else
    echo -e "${RED}✖ Billing inactive. Skipping: $project${NC}"
  fi
done

echo -e "${GREEN}✅ Done! RDP details saved in ${CYAN}${RDP_OUTPUT}${NC}"
