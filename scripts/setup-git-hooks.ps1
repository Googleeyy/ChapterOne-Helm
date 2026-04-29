# Setup script for git hooks (PowerShell version)
# This script installs the git hooks from .githooks directory to .git/hooks

$ErrorActionPreference = "Stop"

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput Cyan "========================================"
Write-ColorOutput Cyan "  Git Hooks Setup Script"
Write-ColorOutput Cyan "========================================"
Write-Output ""

# Check if .githooks directory exists
if (-not (Test-Path ".githooks")) {
    Write-ColorOutput Red "Error: .githooks directory not found"
    Write-Output "Please run this script from the root of the repository."
    exit 1
}

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-ColorOutput Red "Error: Not a git repository"
    Write-Output "Please run this script from the root of a git repository."
    exit 1
}

Write-ColorOutput Yellow "Installing git hooks..."

# Create .git/hooks directory if it doesn't exist
New-Item -ItemType Directory -Force -Path ".git/hooks" | Out-Null

# Copy hooks from .githooks to .git/hooks
Get-ChildItem ".githooks" -Filter "*" | ForEach-Object {
    $hookName = $_.Name
    $target = ".git/hooks/$hookName"
    
    Write-Output "Installing $hookName..."
    
    # Copy the hook
    Copy-Item $_.FullName $target -Force
    
    # Make it executable (on Unix-like systems)
    # On Windows, Git will handle this automatically
    
    Write-ColorOutput Green "✓ $hookName installed"
}

Write-Output ""
Write-ColorOutput Green "========================================"
Write-ColorOutput Green "  Git hooks installed successfully!"
Write-ColorOutput Green "========================================"
Write-Output ""
Write-Output "Installed hooks:"
Write-Output "  - pre-commit   : Validates YAML, detects secrets, tests Helm templates"
Write-Output "  - commit-msg   : Validates commit message format (Conventional Commits)"
Write-Output "  - pre-push     : Comprehensive validation before pushing"
Write-Output ""
Write-ColorOutput Yellow "Note: These hooks will run automatically on git operations."
Write-Output "To bypass a hook temporarily, use: git commit --no-verify"
Write-Output ""
Write-Output "To uninstall hooks, delete the files in .git/hooks\"
