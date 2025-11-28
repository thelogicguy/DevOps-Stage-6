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

    # Strip ANSI color codes for reliable parsing
    sed 's/\x1b\[[0-9;]*m//g' /tmp/lock_info.txt > /tmp/lock_info_clean.txt

    # Extract lock info from the "Lock Info:" section
    # The Terraform output format is:
    # Lock Info:
    #   ID:        <lock-id>
    #   Path:      <path>
    #   Operation: <operation>
    #   Who:       <who>
    #   Version:   <version>
    #   Created:   <timestamp>
    #   Info:      <info>
    LOCK_ID=$(sed -n '/Lock Info:/,/^$/p' /tmp/lock_info_clean.txt | grep "ID:" | awk '{print $2}')
    LOCK_PATH=$(sed -n '/Lock Info:/,/^$/p' /tmp/lock_info_clean.txt | grep "Path:" | awk '{print $2}')
    LOCK_WHO=$(sed -n '/Lock Info:/,/^$/p' /tmp/lock_info_clean.txt | grep "Who:" | awk '{$1=""; print $0}' | xargs)
    LOCK_CREATED=$(sed -n '/Lock Info:/,/^$/p' /tmp/lock_info_clean.txt | grep "Created:" | awk '{$1=""; print $0}' | xargs)
    LOCK_OPERATION=$(sed -n '/Lock Info:/,/^$/p' /tmp/lock_info_clean.txt | grep "Operation:" | awk '{print $2}')

    # Validate that we successfully parsed the lock ID
    if [ -z "$LOCK_ID" ]; then
        echo -e "${RED}Error: Could not parse lock ID from Terraform output${NC}"
        echo ""
        echo "Raw Terraform output:"
        cat /tmp/lock_info.txt
        rm -f /tmp/lock_info.txt /tmp/lock_info_clean.txt
        exit 1
    fi

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
        if terraform force-unlock -force "$LOCK_ID"; then
            echo -e "${GREEN}✓ State unlocked${NC}"
            rm -f /tmp/lock_info.txt /tmp/lock_info_clean.txt
        else
            echo -e "${RED}Failed to unlock state${NC}"
            rm -f /tmp/lock_info.txt /tmp/lock_info_clean.txt
            exit 1
        fi
    else
        echo "Unlock cancelled"
        rm -f /tmp/lock_info.txt /tmp/lock_info_clean.txt
        exit 1
    fi
else
    echo -e "${RED}Error checking state (not a lock issue):${NC}"
    cat /tmp/lock_info.txt
    exit 1
fi

rm -f /tmp/lock_info.txt /tmp/lock_info_clean.txt
