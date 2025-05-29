#!/bin/bash

# Get all GCP project IDs
echo -e "\e[1;33mFetching all GCP projects...\e[0m"
PROJECTS=$(gcloud projects list --format="value(projectId)")

# Check if any projects exist
if [ -z "$PROJECTS" ]; then
    echo -e "\e[1;31mNo projects found in your account.\e[0m"
    exit 1
fi

# Display the list of projects
echo -e "\e[1;36mThe following projects will be deleted:\e[0m"
echo "$PROJECTS"
echo

# Auto-confirmed deletion
for PROJECT in $PROJECTS; do
    echo -e "\e[1;33mDeleting project: $PROJECT...\e[0m"
    gcloud projects delete "$PROJECT" --quiet
    echo -e "\e[1;32mDeleted: $PROJECT\e[0m"
done

echo -e "\e[1;32mAll projects deleted successfully.\e[0m"
