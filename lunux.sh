#!/bin/bash

# Colors
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

# Output file
VPS_OUTPUT="vps.txt"
> "$VPS_OUTPUT"  # Clear old output

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
DISK_SIZE="50"
DISK_TYPE="pd-standard"

# Image info (Ubuntu 24.04 LTS)
IMAGE_FAMILY="ubuntu-2404-lts-amd64"
IMAGE_PROJECT="ubuntu-os-cloud"

# Function to generate random password (lowercase letters only)
gen_pass() {
  tr -dc 'a-z' < /dev/urandom | head -c 12
}

# Create instance function
create_instance() {
  local project_id="$1"
  local region="$2"
  local instance_name="$3"
  local PASSWORD=$(gen_pass)

  echo -e "${CYAN}→ Creating: $instance_name in $region [Project: $project_id]${NC}"

  ZONES=($(gcloud compute zones list --project="$project_id" --filter="region:($region)" --format="value(name)"))
  for zone in "${ZONES[@]}"; do
    echo -e "${YELLOW}↪ Zone: $zone${NC}"

    # Prepare startup script (inject random password)
    STARTUP_SCRIPT=$(cat <<EOF
#!/bin/bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
sudo sed -i "s/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/" /etc/ssh/sshd_config
sudo sed -i "s/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/" /etc/ssh/sshd_config
echo "root:${PASSWORD}" | sudo chpasswd
if [ -d /etc/ssh/sshd_config.d/ ]; then
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "\$f" ] || continue
    sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" "\$f"
    sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" "\$f"
    sudo sed -i "s/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/" "\$f"
    sudo sed -i "s/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/" "\$f"
  done
fi
sudo systemctl daemon-reload
sudo systemctl restart ssh
sudo systemctl enable ssh
EOF
)

    gcloud compute instances create "$instance_name" \
      --project="$project_id" \
      --zone="$zone" \
      --machine-type="$MACHINE_TYPE" \
      --image-family="$IMAGE_FAMILY" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size="$DISK_SIZE" \
      --boot-disk-type="$DISK_TYPE" \
      --metadata=startup-script="$STARTUP_SCRIPT" \
      --tags=vps-instance \
      --scopes=cloud-platform \
      --quiet &> /dev/null

    if [ $? -eq 0 ]; then
      IP=$(gcloud compute instances describe "$instance_name" --project="$project_id" --zone="$zone" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
      echo "${IP}:root:${PASSWORD}" >> "$VPS_OUTPUT"
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
      instance_name="vps-${project}-${i}-${region//-/}"
      create_instance "$project" "$region" "$instance_name"
    done
  else
    echo -e "${RED}✖ Billing inactive. Skipping: $project${NC}"
  fi
done

echo -e "${GREEN}✅ Done! VPS details saved in ${CYAN}${VPS_OUTPUT}${NC}"
