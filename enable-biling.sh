#!/bin/bash

# Colors for better output
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get default billing account
get_default_billing_account() {
  gcloud billing accounts list --filter="open=true" --format="value(name)" --limit=1
}

# Check if billing is properly linked to the project
check_project_billing() {
  local project_id="$1"
  local billing_status
  billing_status=$(gcloud beta billing projects describe "$project_id" --format="value(billingEnabled)")
  [[ "$billing_status" == "True" ]]
}

# Link billing account to project
link_billing() {
  local project_id="$1"
  local billing_account="$2"

  echo -e "${BLUE}Linking billing account to project: ${YELLOW}$project_id${NC}"
  gcloud beta billing projects link "$project_id" --billing-account="$billing_account" --quiet

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Billing linked successfully to project: ${YELLOW}$project_id${NC}"
  else
    echo -e "${RED}Failed to link billing to project: ${YELLOW}$project_id${NC}"
    return 1
  fi
}

# Enable required APIs
enable_apis() {
  local project_id="$1"
  echo -e "${BLUE}Enabling required APIs for project: ${YELLOW}$project_id${NC}"

  gcloud services enable \
    compute.googleapis.com \
    serviceusage.googleapis.com \
    cloudapis.googleapis.com \
    container.googleapis.com \
    --project="$project_id" --quiet

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}APIs enabled for project: ${YELLOW}$project_id${NC}"
  else
    echo -e "${RED}Failed to enable APIs for project: ${YELLOW}$project_id${NC}"
  fi
}

# Create a new project and link billing
create_project() {
  local project_id="$1"
  local billing_account="$2"

  echo -e "${BLUE}Creating project: ${YELLOW}$project_id${NC}"
  gcloud projects create "$project_id" --quiet

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Project created: ${YELLOW}$project_id${NC}"
    link_billing "$project_id" "$billing_account" && enable_apis "$project_id"
  else
    echo -e "${RED}Failed to create project: ${YELLOW}$project_id${NC}"
  fi
}

# Main
DEFAULT_BILLING_ACCOUNT=$(get_default_billing_account)

if [[ -z "$DEFAULT_BILLING_ACCOUNT" ]]; then
  echo -e "${RED}No open billing account found. Please create one first.${NC}"
  exit 1
else
  echo -e "${GREEN}Using default billing account: ${YELLOW}$DEFAULT_BILLING_ACCOUNT${NC}"
fi

# Get existing projects
existing_projects=$(gcloud projects list --format="value(projectId)")
projects_to_keep=()

if [[ -z "$existing_projects" ]]; then
  echo -e "${YELLOW}No existing projects found.${NC}"
else
  echo -e "${BLUE}Checking existing projects...${NC}"
  while IFS= read -r project; do
    echo -e "${YELLOW}Checking billing for project: $project${NC}"
    if check_project_billing "$project"; then
      echo -e "${GREEN}Billing already enabled for: ${YELLOW}$project${NC}"
      projects_to_keep+=("$project")
      enable_apis "$project"
    else
      echo -e "${RED}Billing not enabled for: ${YELLOW}$project${NC}"
      link_billing "$project" "$DEFAULT_BILLING_ACCOUNT" && {
        projects_to_keep+=("$project")
        enable_apis "$project"
      }
    fi
  done <<< "$existing_projects"
fi

# Create more if less than 3
to_create=$((3 - ${#projects_to_keep[@]}))
echo -e "${BLUE}Need to create ${YELLOW}$to_create${NC} new project(s)."

for ((i = 1; i <= to_create; i++)); do
  new_project_id="auto-project-$RANDOM-$(( $(date +%s) + $i ))"
  create_project "$new_project_id" "$DEFAULT_BILLING_ACCOUNT"
  projects_to_keep+=("$new_project_id")
done

# Final list
echo -e "\n${BLUE}Final list of active projects with billing and APIs enabled:${NC}"
for project in "${projects_to_keep[@]}"; do
  echo -e "${YELLOW}- $project${NC}"
done
