#!/bin/bash

# Snappy Web Agent Release Script
# This script helps create and push release tags to trigger GitHub Actions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="snappy-web-agent"
CARGO_TOML="Cargo.toml"

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Snappy Web Agent Release Script

Usage: $0 [VERSION] [OPTIONS]

Arguments:
  VERSION    Version number (e.g., 1.0.0, 1.2.3-beta.1)
             If not provided, will prompt for input

Options:
  -h, --help     Show this help message
  -d, --dry-run  Show what would be done without making changes
  -f, --force    Skip confirmation prompts
  --major        Auto-increment major version
  --minor        Auto-increment minor version
  --patch        Auto-increment patch version

Examples:
  $0 1.0.0                    # Release version 1.0.0
  $0 1.2.3-beta.1            # Release beta version
  $0 --minor                 # Auto-increment minor version
  $0 --dry-run 2.0.0         # Show what would happen
  $0 --force 1.1.0           # Skip confirmations

This script will:
1. Validate the version format
2. Update Cargo.toml with the new version
3. Create a git commit with the version update
4. Create and push a git tag (v<VERSION>)
5. Trigger GitHub Actions to build and release
EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
AUTO_INCREMENT=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --major)
            AUTO_INCREMENT="major"
            shift
            ;;
        --minor)
            AUTO_INCREMENT="minor"
            shift
            ;;
        --patch)
            AUTO_INCREMENT="patch"
            shift
            ;;
        -*)
            print_error "Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                print_error "Multiple version arguments provided"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository"
    exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    print_error "You have uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Get current version from Cargo.toml
get_current_version() {
    if [[ ! -f "$CARGO_TOML" ]]; then
        print_error "Cargo.toml not found"
        exit 1
    fi
    
    grep '^version = ' "$CARGO_TOML" | head -1 | sed 's/version = "\(.*\)"/\1/'
}

# Auto-increment version
auto_increment_version() {
    local current_version="$1"
    local increment_type="$2"
    
    # Parse current version (major.minor.patch)
    IFS='.' read -ra VERSION_PARTS <<< "$current_version"
    local major="${VERSION_PARTS[0]}"
    local minor="${VERSION_PARTS[1]}"
    local patch="${VERSION_PARTS[2]}"
    
    case "$increment_type" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "${major}.$((minor + 1)).0"
            ;;
        patch)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
        *)
            print_error "Invalid increment type: $increment_type"
            exit 1
            ;;
    esac
}

# Validate version format
validate_version() {
    local version="$1"
    
    # Basic semver pattern (allows pre-release and build metadata)
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$ ]]; then
        print_error "Invalid version format: $version"
        print_error "Expected format: X.Y.Z or X.Y.Z-prerelease or X.Y.Z+build"
        exit 1
    fi
}

# Update Cargo.toml version
update_cargo_version() {
    local new_version="$1"
    
    if [[ "$DRY_RUN" = true ]]; then
        print_info "Would update $CARGO_TOML version to $new_version"
        return
    fi
    
    # Use sed to update the version in Cargo.toml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed syntax
        sed -i '' "s/^version = \".*\"/version = \"$new_version\"/" "$CARGO_TOML"
    else
        # Linux sed syntax
        sed -i "s/^version = \".*\"/version = \"$new_version\"/" "$CARGO_TOML"
    fi
    
    print_success "Updated $CARGO_TOML version to $new_version"
}

# Create git commit and tag
create_release() {
    local version="$1"
    local tag="v$version"
    
    if [[ "$DRY_RUN" = true ]]; then
        print_info "Would create commit and tag for version $version"
        print_info "Would run: git add $CARGO_TOML"
        print_info "Would run: git commit -m \"Release version $version\""
        print_info "Would run: git tag -a $tag -m \"Release $tag\""
        print_info "Would run: git push origin main"
        print_info "Would run: git push origin $tag"
        return
    fi
    
    # Check if tag already exists
    if git tag -l | grep -q "^$tag$"; then
        print_error "Tag $tag already exists"
        exit 1
    fi
    
    # Create commit
    git add "$CARGO_TOML"
    git commit -m "Release version $version"
    
    # Create tag
    git tag -a "$tag" -m "Release $tag"
    
    # Push changes
    print_info "Pushing changes to remote..."
    git push origin main
    git push origin "$tag"
    
    print_success "Created and pushed tag $tag"
}

# Main execution
main() {
    print_info "Starting release process for $APP_NAME"
    
    # Get current version
    CURRENT_VERSION=$(get_current_version)
    print_info "Current version: $CURRENT_VERSION"
    
    # Determine new version
    if [[ -n "$AUTO_INCREMENT" ]]; then
        VERSION=$(auto_increment_version "$CURRENT_VERSION" "$AUTO_INCREMENT")
        print_info "Auto-incremented $AUTO_INCREMENT version: $VERSION"
    elif [[ -z "$VERSION" ]]; then
        echo
        echo -e "${YELLOW}Enter new version (current: $CURRENT_VERSION):${NC}"
        read -r VERSION
        
        if [[ -z "$VERSION" ]]; then
            print_error "Version cannot be empty"
            exit 1
        fi
    fi
    
    # Validate version
    validate_version "$VERSION"
    
    # Check if this is the same as current version
    if [[ "$VERSION" = "$CURRENT_VERSION" ]]; then
        print_error "New version ($VERSION) is the same as current version"
        exit 1
    fi
    
    # Show summary
    echo
    print_info "Release Summary:"
    echo "  Current version: $CURRENT_VERSION"
    echo "  New version: $VERSION"
    echo "  Tag: v$VERSION"
    echo "  Cargo.toml: Will be updated"
    echo "  Git: Will create commit and tag"
    echo "  GitHub Actions: Will trigger build and release"
    echo
    
    # Confirmation
    if [[ "$FORCE" != true && "$DRY_RUN" != true ]]; then
        echo -e "${YELLOW}Proceed with release? (y/N):${NC}"
        read -r CONFIRM
        
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            print_info "Release cancelled"
            exit 0
        fi
    fi
    
    # Execute release
    update_cargo_version "$VERSION"
    create_release "$VERSION"
    
    if [[ "$DRY_RUN" != true ]]; then
        echo
        print_success "Release $VERSION completed successfully!"
        print_info "GitHub Actions will build and publish the release artifacts"
        print_info "Monitor progress at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions"
    else
        echo
        print_info "Dry run completed. No changes were made."
    fi
}

# Run main function
main
