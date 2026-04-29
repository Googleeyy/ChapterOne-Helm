#!/bin/bash
# Setup script for git hooks
# This script installs the git hooks from .githooks directory to .git/hooks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Git Hooks Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if .githooks directory exists
if [ ! -d ".githooks" ]; then
    echo -e "${RED}Error: .githooks directory not found${NC}"
    echo "Please run this script from the root of the repository."
    exit 1
fi

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo -e "${RED}Error: Not a git repository${NC}"
    echo "Please run this script from the root of a git repository."
    exit 1
fi

echo -e "${YELLOW}Installing git hooks...${NC}"

# Create .git/hooks directory if it doesn't exist
mkdir -p .git/hooks

# Copy hooks from .githooks to .git/hooks
for hook in .githooks/*; do
    if [ -f "$hook" ]; then
        hook_name=$(basename "$hook")
        target=".git/hooks/$hook_name"
        
        echo "Installing $hook_name..."
        
        # Copy the hook
        cp "$hook" "$target"
        
        # Make it executable
        chmod +x "$target"
        
        echo -e "${GREEN}✓ $hook_name installed${NC}"
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Git hooks installed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Installed hooks:"
echo "  - pre-commit   : Validates YAML, detects secrets, tests Helm templates"
echo "  - commit-msg   : Validates commit message format (Conventional Commits)"
echo "  - pre-push     : Comprehensive validation before pushing"
echo ""
echo -e "${YELLOW}Note: These hooks will run automatically on git operations.${NC}"
echo "To bypass a hook temporarily, use: git commit --no-verify"
echo ""
echo "To uninstall hooks, delete the files in .git/hooks/"
