#!/bin/bash

# ─────── Colors ───────
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

# ─────── Static Credentials ───────
USERNAME="Administrator"
PASSWORD="Gcp@dm!n2025"

# Windows startup command
STARTUP_SCRIPT="net user Administrator ${PASSWORD} && net user Administrator /active:yes"

# ─────── Output file ───────
RDP_OUTPUT="rdp.txt"
> "$RDP_OUTPUT"

# ─────── Good global GCP regions ───────
REGIONS=(
  "us-central1"       # Iowa
  "us-east1"          # South Carolina
  "us-east4"          # N. Virginia
  "us-west1"          # Oregon
  "us-west2"          # Los Angeles
  "us-west3"          # Salt Lake City
  "us-west4"          # Las Vegas
  "europe-west1"      # Belgium
  "europe-west2"      # London
  "europe-west3"      # Frankfurt
  "europe-west4"      # Netherlands
  "europe-north1"     # Finland
  "asia-east1"        # Taiwan
  "asia-east2"        # Hong Kong
  "asia-south1"       # Mumbai
  "asia-southeast1"   # Singapore
  "asia-southeast2"   # Jakarta
  "asia-northeast1"   # Tokyo
  "asia-northeast2"   # Osaka
  "australia-southeast1" # Sydney
  "southamerica-east1"   # São Paulo
)

# ─────── Instance settings ───────
INSTANCE_COUNT=3
MACHINE_TYPE="e2-standard-4"
DISK_SIZE="50"
DISK_TYPE="pd-ssd"
IMAGE_PROJECT="windows-cloud"

# ─────── Fetch latest image ───────
echo -e "${CYAN}🔍 Fetching latest Windows Server 2022 Datacenter image...${NC}"
IMAGE_NAME=$(gcloud compute images list \
  --project="$IMAGE_PROJECT" \
  --no-standard-images \
  --filter="name~'windows-server-2022-dc-v.*' AND NOT name~'core'" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | head -n 1)

if [[ -z "$IMAGE_NAME" ]]; then
  IMAGE_NAME="windows-server-2022-dc-v20250514"
  echo -e "${RED}✖ Could not fetch latest image. Using fallback: $IMAGE_NAME${NC}"
else
  echo -e "${GREEN}✔ Using image: ${YELLOW}${IMAGE_NAME}${NC}"
fi

# ─────── Billing checker ───────
check_billing() {
  local project_id="$1"
  billing_info=$(gcloud billing accounts list --project="$project_id" --format="json" 2>/dev/null)
  echo "$billing_info" | jq -e 'length > 0' >/dev/null
  return $?
}

# ─────── Create instance ───────
create_instance() {
  local project_id="$1"
  local region="$2"
  local instance_name="$3"

  echo -e "${CYAN}→ Creating instance ${YELLOW}$instance_name${CYAN} in ${YELLOW}$region${NC}"

  ZONES=($(gcloud compute zones list --project="$project_id" --filter="region:($region)" --format="value(name)"))
  for zone in "${ZONES[@]}"; do
    echo -e "${YELLOW}↪ Trying zone: $zone${NC}"

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
      --quiet &>/dev/null

    if [[ $? -eq 0 ]]; then
      IP=$(gcloud compute instances describe "$instance_name" \
        --project="$project_id" \
        --zone="$zone" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

      echo "${IP}:${USERNAME}:${PASSWORD}" >> "$RDP_OUTPUT"
      echo -e "${GREEN}✔ Success: ${instance_name} → ${IP}${NC}"
      return 0
    else
      echo -e "${RED}✖ Failed in zone: $zone. Trying next...${NC}"
    fi
  done

  echo -e "${RED}✖ All zones failed in region: $region${NC}"
  return 1
}

# ─────── Main Execution ───────
PROJECTS=($(gcloud projects list --format="value(projectId)"))

for project in "${PROJECTS[@]}"; do
  echo -e "${YELLOW}➤ Checking billing for project: $project${NC}"

  if check_billing "$project"; then
    echo -e "${GREEN}✔ Billing active. Proceeding with instance creation...${NC}"
    
    for i in $(seq 1 "$INSTANCE_COUNT"); do
      region_index=$(( RANDOM % ${#REGIONS[@]} ))
      region="${REGIONS[$region_index]}"
      instance_name="rdp-${project}-${i}-${region//-/}"
      create_instance "$project" "$region" "$instance_name"
    done

  else
    echo -e "${RED}✖ Billing not enabled for project: $project. Skipping.${NC}"
  fi
done

# ─────── Completion ───────
echo -e "${GREEN}✅ Done! RDP login details saved in: ${CYAN}${RDP_OUTPUT}${NC}"
