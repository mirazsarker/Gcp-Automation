#!/bin/bash

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for default billing account
DEFAULT_BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open=true" --format="value(name)" --limit=1)

if [[ -z "$DEFAULT_BILLING_ACCOUNT" ]]; then
  echo -e "${RED}Billing gone${NC}"
  exit 1
else
  echo -e "${GREEN}Default billing account found: ${YELLOW}$DEFAULT_BILLING_ACCOUNT${NC}"
  echo -e "${GREEN}Running project-delete.sh...${NC}"
  sh project-delete.sh
fi
