#!/bin/bash

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting GCP Project and Instance Management Script...${NC}"
echo -e "${CYAN}This script will list your billing-enabled projects and delete any Compute Engine instances found within them.${NC}"
echo ""

# Get a list of all projects, robustly handling newline separation
# Using 'readarray' (Bash 4+) or 'mapfile' is safer but 'grep -v' works for basic cases
# Adding --quiet to gcloud commands to suppress non-error output
PROJECT_IDS_RAW=$(gcloud projects list --format="value(projectId)" --quiet 2>/dev/null)

# Convert newline-separated project IDs into an array for safer iteration
IFS=$'\n' read -r -d '' -a PROJECT_IDS <<< "$PROJECT_IDS_RAW"

if [ ${#PROJECT_IDS[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: No projects found or unable to list projects. Please check your permissions.${NC}"
    exit 1
fi

for PROJECT_ID in "${PROJECT_IDS[@]}"; do
    echo -e "${MAGENTA}--- Processing Project: ${PROJECT_ID} ---${NC}"

    # Set the current project context for subsequent gcloud commands
    gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null

    # Check if billing is enabled for the current project
    BILLING_INFO=$(gcloud beta billing projects describe "$PROJECT_ID" --format="json" --quiet 2>/dev/null)

    # Use grep to check for billing status
    if echo "$BILLING_INFO" | grep -q '"billingEnabled": true'; then
        echo -e "${GREEN}  Billing: ENABLED${NC}"

        INSTANCES_FOUND=false
        
        # List all Compute Engine instances in the current project, across all zones
        # Ensure name and zone are extracted for deletion command
        ALL_INSTANCES=$(gcloud compute instances list --format="value(name,zone)" --project="$PROJECT_ID" --quiet 2>/dev/null)

        if [ -n "$ALL_INSTANCES" ]; then
            INSTANCES_FOUND=true
            echo -e "${YELLOW}  Compute Engine instances found:${NC}"
            
            # Read instance name and zone line by line
            echo "$ALL_INSTANCES" | while read -r INSTANCE_NAME INSTANCE_ZONE; do
                echo -e "    - Instance: ${CYAN}${INSTANCE_NAME}${NC} (Zone: ${CYAN}${INSTANCE_ZONE}${NC})"
                echo -e "${RED}      Attempting to delete instance: ${INSTANCE_NAME} in zone ${INSTANCE_ZONE}...${NC}"
                
                # Attempt to delete the instance
                if gcloud compute instances delete "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" --project="$PROJECT_ID" --quiet 2>/dev/null; then
                    echo -e "${GREEN}        SUCCESS: Instance '${INSTANCE_NAME}' deleted.${NC}"
                else
                    echo -e "${RED}        FAILED: Could not delete instance '${INSTANCE_NAME}'. Check permissions or instance status.${NC}"
                fi
            done # End of while loop for instances
        fi # End of if [ -n "$ALL_INSTANCES" ]

        if [ "$INSTANCES_FOUND" == "false" ]; then
            echo -e "${GREEN}  No Compute Engine instances found in this project.${NC}"
        fi

    elif echo "$BILLING_INFO" | grep -q '"billingEnabled": false'; then
        echo -e "${YELLOW}  Billing: DISABLED${NC}"
        echo -e "${YELLOW}  Skipping instance check as billing is disabled for this project.${NC}"
    else
        # This covers cases where billing info couldn't be retrieved (e.g., permissions, very new project)
        echo -e "${RED}  ERROR: Could not determine billing status for project. Check permissions or if billing is not set up.${NC}"
    fi # End of if/elif/else for billing status

    echo "" # Add a newline for better readability between projects
done # End of for loop for PROJECT_ID

echo -e "${BLUE}Script execution complete.${NC}"