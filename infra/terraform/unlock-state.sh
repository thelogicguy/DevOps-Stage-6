#!/bin/bash
# unlock-state.sh - Helper script to check and unlock Terraform state
# Usage: ./unlock-state.sh [lock-id]

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Terraform State Lock Manager${NC}"
echo ""

# Check if lock ID provided as argument
if [ $# -eq 1 ]; then
    LOCK_ID="$1"
    echo -e "${YELLOW}Unlocking with provided ID: $LOCK_ID${NC}"
    terraform force-unlock -force "$LOCK_ID"
    echo -e "${GREEN}✓ State unlocked${NC}"
    exit 0
fi

# Otherwise, detect the lock
echo "Checking for state locks..."
if terraform plan -input=false -lock-timeout=5s &> /tmp/lock_info.txt; then
    echo -e "${GREEN}✓ No locks detected${NC}"
    rm -f /tmp/lock_info.txt
    exit 0
fi

if grep -q "Error acquiring the state lock" /tmp/lock_info.txt; then
    echo -e "${RED}Lock detected!${NC}"
    echo ""

    # Extract lock info
    LOCK_ID=$(grep "ID:" /tmp/lock_info.txt | awk '{print $2}')
    LOCK_PATH=$(grep "Path:" /tmp/lock_info.txt | awk '{print $2}')
    LOCK_WHO=$(grep "Who:" /tmp/lock_info.txt | cut -d: -f2- | xargs)
    LOCK_CREATED=$(grep "Created:" /tmp/lock_info.txt | cut -d: -f2- | xargs)
    LOCK_OPERATION=$(grep "Operation:" /tmp/lock_info.txt | awk '{print $2}')

    echo "Lock Details:"
    echo "  ID:        $LOCK_ID"
    echo "  Path:      $LOCK_PATH"
    echo "  Who:       $LOCK_WHO"
    echo "  Created:   $LOCK_CREATED"
    echo "  Operation: $LOCK_OPERATION"
    echo ""

    echo -e "${YELLOW}To unlock, run:${NC}"
    echo "  terraform force-unlock -force $LOCK_ID"
    echo ""

    read -p "Unlock now? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform force-unlock -force "$LOCK_ID"
        echo -e "${GREEN}✓ State unlocked${NC}"
    else
        echo "Unlock cancelled"
        exit 1
    fi
else
    echo -e "${RED}Error checking state (not a lock issue):${NC}"
    cat /tmp/lock_info.txt
    exit 1
fi

rm -f /tmp/lock_info.txt
