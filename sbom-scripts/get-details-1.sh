#!/bin/bash

###############################################################################
# .NET SBOM / Dependency / License Scanner
#
# Purpose:
#   - Discover ALL .csproj and .sln files recursively
#   - Restore ALL projects
#   - Scan DIRECT + TRANSITIVE NuGet dependencies
#   - Generate consolidated dependency report
#   - Generate per-project JSON dependency reports
#   - Generate consolidated license report
#   - Generate consolidated outdated dependency report
#
# Expected .NET installation:
#   $HOME/dotnet
###############################################################################

set -u

###############################################################################
# Configuration
###############################################################################

export DOTNET_ROOT="$HOME/dotnet"
export PATH="$HOME/dotnet:$HOME/.dotnet/tools:$PATH"

REPORT_DIR="./sbom-reports"
JSON_DIR="$REPORT_DIR/dependencies-json"

mkdir -p "$REPORT_DIR"
mkdir -p "$JSON_DIR"

RESTORE_FAILED=0
DEPENDENCY_FAILED=0
LICENSE_FAILED=0
OUTDATED_FAILED=0

###############################################################################
# Helper functions
###############################################################################

print_separator() {
    echo "============================================================"
}

print_section() {
    echo ""
    print_separator
    echo "$1"
    print_separator
}

###############################################################################
# Environment validation
###############################################################################

print_section ".NET ENVIRONMENT"

echo "DOTNET_ROOT:"
echo "$DOTNET_ROOT"

echo ""
echo "PATH:"
echo "$PATH"

echo ""
echo "dotnet location:"
which dotnet || true

echo ""
echo "dotnet version:"
dotnet --version

echo ""
echo "Installed SDKs:"
dotnet --list-sdks

echo ""
echo "Installed runtimes:"
dotnet --list-runtimes

echo ""
echo "Checking libhostfxr.so:"
find "$DOTNET_ROOT" -name "libhostfxr.so" -print || true

###############################################################################
# Install / verify dotnet-project-licenses
###############################################################################

print_section "INSTALLING / VERIFYING DOTNET PROJECT LICENSES"

if ! command -v dotnet-project-licenses >/dev/null 2>&1; then

    echo "dotnet-project-licenses not found."
    echo "Installing..."

    dotnet tool install --global \
        dotnet-project-licenses \
        --add-source https://api.nuget.org/v3/index.json

else

    echo "dotnet-project-licenses already installed."

fi

echo ""
echo "Global .NET tools:"
dotnet tool list -g

echo ""
echo "dotnet-project-licenses location:"
which dotnet-project-licenses || true

echo ""
echo "Verifying dotnet-project-licenses..."

dotnet-project-licenses --help >/dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: dotnet-project-licenses could not be executed."
    echo "Check DOTNET_ROOT and libhostfxr.so."
    exit 1
fi

echo "dotnet-project-licenses is working."

###############################################################################
# Discover all .csproj files
###############################################################################

print_section "DISCOVERING .CSPROJ FILES"

mapfile -d '' PROJECTS < <(
    find . \
        -type f \
        -name "*.csproj" \
        -not -path "*/bin/*" \
        -not -path "*/obj/*" \
        -print0
)

PROJECT_COUNT="${#PROJECTS[@]}"

echo "Number of .csproj files found: $PROJECT_COUNT"

if [ "$PROJECT_COUNT" -eq 0 ]; then

    echo ""
    echo "ERROR: No .csproj files found."
    echo "Make sure the source repository has been checked out."
    exit 1

fi

echo ""

PROJECT_NUMBER=0

for project in "${PROJECTS[@]}"; do

    PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

    echo "[$PROJECT_NUMBER] $project"

done

###############################################################################
# Discover all .sln files
###############################################################################

print_section "DISCOVERING .SLN FILES"

mapfile -d '' SOLUTIONS < <(
    find . \
        -type f \
        -name "*.sln" \
        -not -path "*/bin/*" \
        -not -path "*/obj/*" \
        -print0
)

SOLUTION_COUNT="${#SOLUTIONS[@]}"

echo "Number of .sln files found: $SOLUTION_COUNT"

echo ""

if [ "$SOLUTION_COUNT" -gt 0 ]; then

    SOLUTION_NUMBER=0

    for solution in "${SOLUTIONS[@]}"; do

        SOLUTION_NUMBER=$((SOLUTION_NUMBER + 1))

        echo "[$SOLUTION_NUMBER] $solution"

    done

else

    echo "No .sln files found."

fi

###############################################################################
# Restore all projects
###############################################################################

print_section "RESTORING ALL .CSPROJ FILES"

PROJECT_NUMBER=0

for project in "${PROJECTS[@]}"; do

    PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

    echo ""
    echo "------------------------------------------------------------"
    echo "Restoring project [$PROJECT_NUMBER/$PROJECT_COUNT]"
    echo "$project"
    echo "------------------------------------------------------------"

    if dotnet restore "$project"; then

        echo "Restore successful: $project"

    else

        echo "ERROR: Restore failed: $project"
        RESTORE_FAILED=1

    fi

done

###############################################################################
# Direct + Transitive Dependency Report
###############################################################################

print_section "GENERATING CONSOLIDATED DIRECT + TRANSITIVE DEPENDENCY REPORT"

DEPENDENCY_REPORT="$REPORT_DIR/dependency-report.txt"

echo "Writing report:"
echo "$DEPENDENCY_REPORT"

{
    print_separator
    echo "CONSOLIDATED .NET DEPENDENCY REPORT"
    echo "DIRECT + TRANSITIVE DEPENDENCIES"
    echo "Generated: $(date)"
    print_separator

    echo ""
    echo "Total Projects: $PROJECT_COUNT"
    echo "Total Solutions: $SOLUTION_COUNT"
    echo ""

    PROJECT_NUMBER=0

    for project in "${PROJECTS[@]}"; do

        PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

        echo ""
        print_separator
        echo "PROJECT [$PROJECT_NUMBER/$PROJECT_COUNT]"
        echo "$project"
        print_separator
        echo ""

        if dotnet list "$project" package --include-transitive; then

            echo ""
            echo "Dependency scan successful."

        else

            echo ""
            echo "ERROR: Dependency scan failed for:"
            echo "$project"

            DEPENDENCY_FAILED=1

        fi

        echo ""

    done

} > "$DEPENDENCY_REPORT"

echo ""
echo "Dependency report generated:"
echo "$DEPENDENCY_REPORT"

###############################################################################
# Per-project JSON dependency reports
###############################################################################

print_section "GENERATING JSON DEPENDENCY REPORTS"

PROJECT_NUMBER=0

for project in "${PROJECTS[@]}"; do

    PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

    PROJECT_NAME="$(basename "$project" .csproj)"

    JSON_FILE="$JSON_DIR/${PROJECT_NUMBER}_${PROJECT_NAME}.json"

    echo ""
    echo "Project:"
    echo "$project"

    echo "JSON output:"
    echo "$JSON_FILE"

    if dotnet list "$project" package \
        --include-transitive \
        --format json \
        > "$JSON_FILE"; then

        echo "JSON dependency scan successful."

    else

        echo "ERROR: JSON dependency scan failed:"
        echo "$project"

        DEPENDENCY_FAILED=1

    fi

done

###############################################################################
# Consolidated License Report
###############################################################################

print_section "GENERATING CONSOLIDATED LICENSE REPORT"

LICENSE_REPORT="$REPORT_DIR/sbom-licenses.txt"

echo "Writing report:"
echo "$LICENSE_REPORT"

{
    print_separator
    echo "CONSOLIDATED .NET LICENSE REPORT"
    echo "DIRECT + TRANSITIVE DEPENDENCIES"
    echo "Generated: $(date)"
    print_separator

    echo ""
    echo "Total Projects: $PROJECT_COUNT"
    echo ""

    PROJECT_NUMBER=0

    for project in "${PROJECTS[@]}"; do

        PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

        echo ""
        print_separator
        echo "PROJECT [$PROJECT_NUMBER/$PROJECT_COUNT]"
        echo "$project"
        print_separator
        echo ""

        if dotnet-project-licenses \
            -i "$project" \
            --include-transitive; then

            echo ""
            echo "License scan successful."

        else

            echo ""
            echo "ERROR: License scan failed:"
            echo "$project"

            LICENSE_FAILED=1

        fi

        echo ""

    done

} > "$LICENSE_REPORT"

echo ""
echo "License report generated:"
echo "$LICENSE_REPORT"

###############################################################################
# Consolidated Outdated Dependency Report
###############################################################################

print_section "GENERATING CONSOLIDATED OUTDATED DEPENDENCY REPORT"

OUTDATED_REPORT="$REPORT_DIR/outdated-dependencies.txt"

echo "Writing report:"
echo "$OUTDATED_REPORT"

{
    print_separator
    echo "CONSOLIDATED OUTDATED DEPENDENCY REPORT"
    echo "Generated: $(date)"
    print_separator

    echo ""
    echo "Total Projects: $PROJECT_COUNT"
    echo ""

    PROJECT_NUMBER=0

    for project in "${PROJECTS[@]}"; do

        PROJECT_NUMBER=$((PROJECT_NUMBER + 1))

        echo ""
        print_separator
        echo "PROJECT [$PROJECT_NUMBER/$PROJECT_COUNT]"
        echo "$project"
        print_separator
        echo ""

        if dotnet list "$project" package --outdated; then

            echo ""
            echo "Outdated dependency scan completed."

        else

            echo ""
            echo "WARNING: Outdated dependency check failed:"
            echo "$project"

            OUTDATED_FAILED=1

        fi

        echo ""

    done

} > "$OUTDATED_REPORT"

echo ""
echo "Outdated dependency report generated:"
echo "$OUTDATED_REPORT"

###############################################################################
# Display generated reports
###############################################################################

print_section "GENERATED REPORTS"

echo "Report directory:"
echo "$REPORT_DIR"

echo ""

find "$REPORT_DIR" -type f -print | sort

###############################################################################
# Summary
###############################################################################

print_section "SBOM SCAN SUMMARY"

echo "Projects discovered      : $PROJECT_COUNT"
echo "Solutions discovered     : $SOLUTION_COUNT"
echo "Restore failures         : $RESTORE_FAILED"
echo "Dependency scan failures: $DEPENDENCY_FAILED"
echo "License scan failures   : $LICENSE_FAILED"
echo "Outdated scan failures  : $OUTDATED_FAILED"

echo ""
echo "Reports:"
echo "  Dependency report:"
echo "    $DEPENDENCY_REPORT"

echo ""
echo "  License report:"
echo "    $LICENSE_REPORT"

echo ""
echo "  Outdated dependency report:"
echo "    $OUTDATED_REPORT"

echo ""
echo "  JSON dependency reports:"
echo "    $JSON_DIR"

###############################################################################
# Final status
###############################################################################

if [ "$RESTORE_FAILED" -ne 0 ] || \
   [ "$DEPENDENCY_FAILED" -ne 0 ] || \
   [ "$LICENSE_FAILED" -ne 0 ]; then

    echo ""
    print_separator
    echo "SBOM SCAN FAILED"
    print_separator

    exit 1

fi

echo ""
print_separator
echo "SBOM SCAN COMPLETED SUCCESSFULLY"
print_separator

exit 0
