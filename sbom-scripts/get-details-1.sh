```bash
#!/bin/bash

set -u

###############################################################################
# Configuration
###############################################################################

export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

REPORT_DIR="./sbom-reports"

mkdir -p "$REPORT_DIR"

echo "============================================================"
echo " .NET Dependency / License Scan"
echo "============================================================"

echo ""
echo "DOTNET:"
dotnet --info

echo ""
echo "============================================================"
echo " Installing required tools"
echo "============================================================"

# Install dotnet-project-licenses only if not already installed
if ! command -v dotnet-project-licenses >/dev/null 2>&1; then
    dotnet tool install --global dotnet-project-licenses
else
    echo "dotnet-project-licenses already installed"
fi

echo ""
echo "Installed global tools:"
dotnet tool list -g

###############################################################################
# Discover projects and solutions
###############################################################################

echo ""
echo "============================================================"
echo " Discovering .NET projects and solutions"
echo "============================================================"

# Find all .csproj files recursively
mapfile -d '' PROJECTS < <(
    find . \
        -type f \
        -name "*.csproj" \
        -not -path "*/bin/*" \
        -not -path "*/obj/*" \
        -print0
)

# Find all .sln files recursively
mapfile -d '' SOLUTIONS < <(
    find . \
        -type f \
        -name "*.sln" \
        -not -path "*/bin/*" \
        -not -path "*/obj/*" \
        -print0
)

echo ""
echo "Projects found : ${#PROJECTS[@]}"
echo "Solutions found: ${#SOLUTIONS[@]}"

echo ""

if [ "${#PROJECTS[@]}" -eq 0 ]; then
    echo "ERROR: No .csproj files found."
    exit 1
fi

echo "Projects:"
for project in "${PROJECTS[@]}"; do
    echo "  - $project"
done

echo ""
echo "Solutions:"
for solution in "${SOLUTIONS[@]}"; do
    echo "  - $solution"
done

###############################################################################
# Restore
###############################################################################

echo ""
echo "============================================================"
echo " Restoring .NET dependencies"
echo "============================================================"

RESTORE_FAILED=0

for project in "${PROJECTS[@]}"; do

    echo ""
    echo "------------------------------------------------------------"
    echo "Restoring project:"
    echo "$project"
    echo "------------------------------------------------------------"

    if ! dotnet restore "$project"; then
        echo "ERROR: Restore failed for $project"
        RESTORE_FAILED=1
    fi

done

if [ "$RESTORE_FAILED" -ne 0 ]; then
    echo ""
    echo "WARNING: One or more projects failed restore."
    echo "Dependency reports may therefore be incomplete."
fi

###############################################################################
# Direct + Transitive dependency report
###############################################################################

echo ""
echo "============================================================"
echo " Generating consolidated dependency report"
echo " Direct + Transitive dependencies"
echo "============================================================"

DEPENDENCY_REPORT="$REPORT_DIR/dependency-report.txt"

{
    echo "============================================================"
    echo " CONSOLIDATED .NET DEPENDENCY REPORT"
    echo " Direct + Transitive Dependencies"
    echo " Generated: $(date)"
    echo "============================================================"
    echo ""

    for project in "${PROJECTS[@]}"; do

        echo ""
        echo "################################################################"
        echo "# PROJECT: $project"
        echo "################################################################"
        echo ""

        dotnet list "$project" package --include-transitive || {
            echo "ERROR: Dependency scan failed for $project"
        }

        echo ""

    done

} > "$DEPENDENCY_REPORT"

echo ""
echo "Dependency report generated:"
echo "$DEPENDENCY_REPORT"

###############################################################################
# JSON dependency report
###############################################################################

echo ""
echo "============================================================"
echo " Generating JSON dependency reports"
echo "============================================================"

JSON_DIR="$REPORT_DIR/dependencies-json"
mkdir -p "$JSON_DIR"

PROJECT_INDEX=0

for project in "${PROJECTS[@]}"; do

    PROJECT_INDEX=$((PROJECT_INDEX + 1))

    # Convert project path into a safe filename
    PROJECT_NAME=$(basename "$project" .csproj)

    JSON_FILE="$JSON_DIR/${PROJECT_INDEX}_${PROJECT_NAME}.json"

    echo ""
    echo "Generating:"
    echo "  Project : $project"
    echo "  Output  : $JSON_FILE"

    dotnet list "$project" package \
        --include-transitive \
        --format json \
        > "$JSON_FILE" || {
            echo "ERROR: JSON dependency scan failed for $project"
        }

done

###############################################################################
# License report - Direct + Transitive
###############################################################################

echo ""
echo "============================================================"
echo " Generating consolidated license report"
echo " Direct + Transitive dependencies"
echo "============================================================"

LICENSE_REPORT="$REPORT_DIR/sbom-licenses.txt"

{
    echo "============================================================"
    echo " CONSOLIDATED .NET LICENSE REPORT"
    echo " Direct + Transitive Dependencies"
    echo " Generated: $(date)"
    echo "============================================================"
    echo ""

    for project in "${PROJECTS[@]}"; do

        echo ""
        echo "################################################################"
        echo "# PROJECT: $project"
        echo "################################################################"
        echo ""

        dotnet-project-licenses \
            -i "$project" \
            --include-transitive || {
                echo "ERROR: License scan failed for $project"
            }

        echo ""

    done

} > "$LICENSE_REPORT"

echo ""
echo "License report generated:"
echo "$LICENSE_REPORT"

###############################################################################
# Outdated dependency report
###############################################################################

echo ""
echo "============================================================"
echo " Generating outdated dependency report"
echo "============================================================"

OUTDATED_REPORT="$REPORT_DIR/outdated-dependencies.txt"

{
    echo "============================================================"
    echo " CONSOLIDATED OUTDATED DEPENDENCY REPORT"
    echo " Generated: $(date)"
    echo "============================================================"
    echo ""

    for project in "${PROJECTS[@]}"; do

        echo ""
        echo "################################################################"
        echo "# PROJECT: $project"
        echo "################################################################"
        echo ""

        dotnet list "$project" package --outdated || {
            echo "WARNING: Outdated package check failed for $project"
        }

        echo ""

    done

} > "$OUTDATED_REPORT"

###############################################################################
# Summary
###############################################################################

echo ""
echo "============================================================"
echo " SCAN COMPLETE"
echo "============================================================"

echo ""
echo "Projects scanned:"
echo "  ${#PROJECTS[@]}"

echo ""
echo "Solutions discovered:"
echo "  ${#SOLUTIONS[@]}"

echo ""
echo "Reports:"
echo "  Dependency report : $DEPENDENCY_REPORT"
echo "  License report    : $LICENSE_REPORT"
echo "  Outdated report   : $OUTDATED_REPORT"
echo "  JSON reports      : $JSON_DIR"

echo ""
echo "============================================================"
```
