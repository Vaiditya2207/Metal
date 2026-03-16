#!/bin/bash
set -e

# Usage: ./scripts/update_version.sh <new_version>

NEW_VERSION=$1

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <new_version>"
    exit 1
fi

echo "Updating version to $NEW_VERSION..."

# 1. Update build.zig.zon
sed -i '' "s/\.version = \".*\"/\.version = \"$NEW_VERSION\"/" build.zig.zon

# 2. Update package.json
sed -i '' "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" package.json

# 3. Update src/main.zig (print statement)
sed -i '' "s/Version .*\"/Version $NEW_VERSION\"/" src/main.zig

# 4. Update CHANGELOG.md
# Replace the [Unreleased] placeholder or update the latest version if it's a draft
# For now, let's assume we update the top-most version entry if it's not [Unreleased]
# Or just prepend a new entry if it's a release.
# This is a simplified version. A real one might use 'standard-version' or similar.
TODAY=$(date +%Y-%m-%d)
sed -i '' "s/## \[.*\] - .*/## [$NEW_VERSION] - $TODAY/" CHANGELOG.md

echo "Version updated successfully."
