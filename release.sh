#!/bin/bash
# SendCUIEmail - Release Script
# Creates a release package and optionally tags/pushes to GitHub

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
VERSION=""
PUSH_TAG=false
CREATE_RELEASE=false

print_usage() {
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Arguments:"
    echo "  version        Version number (e.g., 1.0.0)"
    echo ""
    echo "Options:"
    echo "  --push         Push tag to remote"
    echo "  --release      Create GitHub release (implies --push)"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 1.0.0              # Create release package locally"
    echo "  $0 1.0.0 --push       # Create package and push tag"
    echo "  $0 1.0.0 --release    # Create package and GitHub release"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH_TAG=true
            shift
            ;;
        --release)
            CREATE_RELEASE=true
            PUSH_TAG=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo -e "${RED}Unexpected argument: $1${NC}"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo -e "${RED}ERROR: Version number required${NC}"
    echo ""
    print_usage
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Invalid version format. Use semver (e.g., 1.0.0)${NC}"
    exit 1
fi

TAG="v$VERSION"
DIST_DIR="$SCRIPT_DIR/.dist"
RELEASE_NAME="SendCUIEmail-$VERSION"
RELEASE_DIR="$DIST_DIR/$RELEASE_NAME"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  SendCUIEmail Release Script${NC}"
echo -e "${CYAN}  Version: $VERSION${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}WARNING: You have uncommitted changes.${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Tag $TAG already exists.${NC}"
    exit 1
fi

# Run tests first (full test suite including integration and verification PDF)
echo -e "${CYAN}[1/6] Running tests...${NC}"
if [ -x "$SCRIPT_DIR/test.sh" ]; then
    "$SCRIPT_DIR/test.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Tests failed. Aborting release.${NC}"
        exit 1
    fi
elif command -v pwsh &> /dev/null; then
    echo -e "${YELLOW}WARNING: test.sh not found, running Test.ps1 only${NC}"
    pwsh -NoProfile -File "$SCRIPT_DIR/Test.ps1"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Tests failed. Aborting release.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}WARNING: PowerShell Core not installed. Skipping tests.${NC}"
    echo "         Install with: brew install powershell"
fi

# Create dist directory
echo ""
echo -e "${CYAN}[2/6] Creating release directory...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Copy release files
echo -e "${CYAN}[3/6] Copying files...${NC}"
RELEASE_FILES=(
    "Encrypt.bat"
    "Encrypt.ps1"
    "Decrypt.bat"
    "Decrypt.ps1"
    "Test.bat"
    "Test.ps1"
    "test.sh"
    "README.md"
    "LICENSE"
)

for file in "${RELEASE_FILES[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        cp "$SCRIPT_DIR/$file" "$RELEASE_DIR/"
        echo "  - $file"
    else
        echo -e "${YELLOW}  - $file (not found, skipping)${NC}"
    fi
done

# Copy examples folder
if [ -d "$SCRIPT_DIR/examples" ]; then
    mkdir -p "$RELEASE_DIR/examples"
    cp "$SCRIPT_DIR/examples/"*.tex "$RELEASE_DIR/examples/" 2>/dev/null || true
    echo "  - examples/*.tex"
fi

# Create version file
echo "$VERSION" > "$RELEASE_DIR/VERSION"
echo "  - VERSION"

# Create ZIP archive
echo ""
echo -e "${CYAN}[4/6] Creating ZIP archive...${NC}"
cd "$DIST_DIR"
ZIP_FILE="$RELEASE_NAME.zip"
rm -f "$ZIP_FILE"
zip -r "$ZIP_FILE" "$RELEASE_NAME"
echo "  Created: $DIST_DIR/$ZIP_FILE"

# Calculate checksum
echo ""
echo -e "${CYAN}[5/6] Calculating checksum...${NC}"
if command -v sha256sum &> /dev/null; then
    sha256sum "$ZIP_FILE" > "$ZIP_FILE.sha256"
elif command -v shasum &> /dev/null; then
    shasum -a 256 "$ZIP_FILE" > "$ZIP_FILE.sha256"
fi
echo "  Created: $DIST_DIR/$ZIP_FILE.sha256"
cat "$ZIP_FILE.sha256"

# Git operations
echo ""
echo -e "${CYAN}[6/6] Git operations...${NC}"
cd "$SCRIPT_DIR"

# Create tag
git tag -a "$TAG" -m "Release $VERSION"
echo "  Created tag: $TAG"

if [ "$PUSH_TAG" = true ]; then
    echo "  Pushing tag to remote..."
    git push origin "$TAG"
    echo -e "  ${GREEN}Tag pushed successfully${NC}"
fi

if [ "$CREATE_RELEASE" = true ]; then
    echo "  Creating GitHub release..."
    if command -v gh &> /dev/null; then
        gh release create "$TAG" \
            "$DIST_DIR/$ZIP_FILE" \
            "$DIST_DIR/$ZIP_FILE.sha256" \
            --title "SendCUIEmail $VERSION" \
            --notes "## SendCUIEmail $VERSION

### Files
- \`$ZIP_FILE\` - Release package
- \`$ZIP_FILE.sha256\` - SHA-256 checksum

### Installation
1. Download and extract the ZIP file
2. Run \`Encrypt.bat\` (Windows) or \`pwsh Encrypt.ps1\` (macOS/Linux)

### What's Included
- Encryption and decryption scripts
- Automated test suite
- Sample LaTeX test document

See [README.md](https://github.com/brucedombrowski/SendCUIEmail/blob/main/README.md) for full documentation."
        echo -e "  ${GREEN}GitHub release created successfully${NC}"
    else
        echo -e "${YELLOW}  WARNING: GitHub CLI (gh) not installed. Skipping release creation.${NC}"
        echo "           Install with: brew install gh"
    fi
fi

# Summary
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Release $VERSION Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Release files:"
echo "  $DIST_DIR/$ZIP_FILE"
echo "  $DIST_DIR/$ZIP_FILE.sha256"
echo ""
if [ "$PUSH_TAG" = false ]; then
    echo "Next steps:"
    echo "  1. Review the release package"
    echo "  2. Push the tag: git push origin $TAG"
    echo "  3. Create release: gh release create $TAG $DIST_DIR/$ZIP_FILE"
fi
