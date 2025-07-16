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

# Function to get the default billing account
get_default_billing_account() {
  gcloud billing accounts list --filter="open=true" --format="value(name)" --limit=1
}

# Function to enable Compute Engine API for a project
enable_compute_api() {
  local project_id="$1"
  echo -e "\n\033[1;34mEnabling Compute Engine API for project: \033[0m\033[1;33m$project_id\033[0m"
  gcloud services enable compute.googleapis.com --project="$project_id"
  if [[ $? -eq 0 ]]; then
    echo -e "\033[1;32mCompute Engine API enabled successfully for project: \033[0m\033[1;33m$project_id\033[0m"
  else
    echo -e "\033[1;31mFailed to enable Compute Engine API for project: \033[0m\033[1;33m$project_id\033[0m"
  fi
}

# Function to create a project and set billing account
create_project() {
  local project_id="$1"
  local billing_account="$2"

  echo -e "\n\033[1;34mCreating project: \033[0m\033[1;33m$project_id\033[0m"
  gcloud projects create "$project_id" --quiet # Add --quiet to suppress output

  if [[ $? -eq 0 ]]; then
    echo -e "\033[1;32mProject \033[0m\033[1;33m$project_id\033[0m\033[1;32m created successfully.\033[0m"

    # Link billing account
    gcloud beta billing projects link "$project_id" --billing-account="$billing_account" --quiet #and --quiet

    if [[ $? -eq 0 ]]; then
      echo -e "\033[1;32mBilling account linked to project \033[0m\033[1;33m$project_id\033[0m\033[1;32m.\033[0m"
       # Enable required APIs
      gcloud services enable \
          serviceusage.googleapis.com \
          compute.googleapis.com \
          container.googleapis.com \
          cloudapis.googleapis.com \
          --project="$project_id" --quiet
      if [[ $? -eq 0 ]]; then
        echo -e "\033[1;32mRequired APIs enabled for project \033[0m\033[1;33m$project_id\033[0m\033[1;32m.\033[0m"
      else
        echo -e "\033[1;31mFailed to enable required APIs for project \033[0m\033[1;33m$project_id\033[0m\033[1;31m.\033[0m"
      fi
    else
      echo -e "\033[1;31mFailed to link billing account to project \033[0m\033[1;33m$project_id\033[0m\033[1;31m.\033[0m"
      return 1
    fi

    return 0
  else
    echo -e "\033[1;31mFailed to create project \033[0m\033[1;33m$project_id\033[0m\033[1;31m.\033[0m"
    return 1
  fi
}

# Main script logic

# Get the default billing account
DEFAULT_BILLING_ACCOUNT=$(get_default_billing_account)

if [[ -z "$DEFAULT_BILLING_ACCOUNT" ]]; then
  echo -e "\033[1;31mNo default billing account found. Please create a billing account and set it as default.\033[0m"
  exit 1
else
  echo -e "\033[1;32mDefault billing account: \033[0m\033[1;33m$DEFAULT_BILLING_ACCOUNT\033[0m"
fi

# Get list of existing projects
existing_projects=$(gcloud projects list --format="value(projectId)")
project_count=0
existing_project_list=()

if [[ -n "$existing_projects" ]]; then
  IFS=$'\n' read -r -d '' -a existing_project_list <<< "$existing_projects" # Read into array
  project_count=${#existing_project_list[@]}
  echo -e "\n\033[1;34mFound \033[0m\033[1;33m$project_count\033[0m\033[1;34m existing projects.\033[0m"
else
  echo -e "\n\033[1;34mNo existing projects found.\033[0m"
fi

# Check billing status of existing projects and enable Compute Engine API
projects_to_keep=()
for project in "${existing_project_list[@]}"; do
  check_billing "$project"
  if [[ $? -eq 0 ]]; then
    echo -e "\033[1;32mProject \033[0m\033[1;33m$project\033[0m\033[1;32m has billing enabled.\033[0m"
    projects_to_keep+=("$project") #keep the project
    enable_compute_api "$project" # Enable API
  else
    echo -e "\033[1;31mProject \033[0m\033[1;33m$project\033[0m\033[1;31m does not have billing enabled.  Deleting it.\033[0m"
    gcloud projects delete "$project" --quiet --force-dependents #delete project
  fi
done

# Calculate how many new projects to create
projects_to_create=$((1 - ${#projects_to_keep[@]}))

echo -e "\n\033[1;34mNeed to create \033[0m\033[1;33m$projects_to_create\033[0m\033[1;34m new projects.\033[0m"

# Create new projects if needed
for ((i=1; i<=projects_to_create; i++)); do
  project_id="project-$(( $(date +%s) + $i ))" # Ensure unique project IDs
  create_project "$project_id" "$DEFAULT_BILLING_ACCOUNT"
  if [[ $? -eq 0 ]]; then
    projects_to_keep+=("$project_id") # add to the list of projects to keep
    enable_compute_api "$project_id"
  fi
done

# Enable Compute Engine API for all projects
echo -e "\n\033[1;34mEnsuring Compute Engine API is enabled for all final projects:\033[0m"
for project in "${projects_to_keep[@]}"; do
  enable_compute_api "$project"
done
# List all projects
echo -e "\n\033[1;34mListing all final projects:\033[0m"
gcloud projects list
