#!/bin/bash
set -e

###############################################################################
# Configuration
###############################################################################

INSTALL_DIR="$HOME/bin"
PROJECT_DIR="$(pwd)"

REPORT_FILE="$PROJECT_DIR/trivy-vulnerabilities.txt"
JSON_REPORT="$PROJECT_DIR/trivy-vulnerabilities.json"
CSV_REPORT="$PROJECT_DIR/trivy-consolidated-report.csv"

###############################################################################
# Ensure curl is installed
###############################################################################

if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found, attempting to install..."

    if [ "$(id -u)" -eq 0 ]; then
        apt-get update && apt-get install -y curl
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y curl
    else
        echo "ERROR: curl is required but cannot be installed without root/sudo." >&2
        exit 1
    fi
fi

###############################################################################
# Install Trivy
###############################################################################

TRIVY_VERSION=$(curl -fsSL \
    https://api.github.com/repos/aquasecurity/trivy/releases/latest \
    | grep '"tag_name":' \
    | sed -E 's/.*"v([^"]+)".*/\1/' || true)

if [ -z "$TRIVY_VERSION" ]; then
    echo "GitHub API request failed; using fallback Trivy v0.74.0"
    TRIVY_VERSION="0.74.0"
fi

echo "Installing Trivy v${TRIVY_VERSION}..."

mkdir -p "$INSTALL_DIR"

TRIVY_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

if ! curl -sfL "$TRIVY_URL" -o trivy.tar.gz; then
    echo "ERROR: Failed to download Trivy from $TRIVY_URL" >&2
    exit 1
fi

tar -xzf trivy.tar.gz -C "$INSTALL_DIR" trivy
rm -f trivy.tar.gz

TRIVY="$INSTALL_DIR/trivy"

if [ ! -x "$TRIVY" ]; then
    echo "ERROR: Trivy installation failed." >&2
    exit 1
fi

###############################################################################
# Discover .NET files recursively
###############################################################################

echo ""
echo "============================================================"
echo "TRIVY .NET MULTI-MODULE FILESYSTEM SCAN"
echo "============================================================"
echo "Repository root: $PROJECT_DIR"

echo ""
echo "Discovering .NET project and dependency files..."

mapfile -t DOTNET_FILES < <(
    find "$PROJECT_DIR" \
        -type d \( \
            -name .git -o \
            -name .svn -o \
            -name .hg \
        \) -prune -o \
        -type f \( \
            -name '*.csproj' -o \
            -name '*.fsproj' -o \
            -name '*.vbproj' -o \
            -name '*.sln' -o \
            -name '*.slnx' -o \
            -name 'packages.lock.json' -o \
            -name 'packages.config' -o \
            -name '*.deps.json' -o \
            -name '*.runtimeconfig.json' \
        \) -print
)

if [ "${#DOTNET_FILES[@]}" -gt 0 ]; then
    echo "Found ${#DOTNET_FILES[@]} .NET project/dependency files:"
    printf '%s\n' "${DOTNET_FILES[@]}"
else
    echo "WARNING: No common .NET project/dependency files found."
    echo "Trivy will still scan the repository for supported files."
fi

###############################################################################
# Run recursive filesystem vulnerability scan
###############################################################################

echo ""
echo "Running Trivy filesystem scan..."
echo "This scan does not require a Docker image."

"$TRIVY" fs \
    --scanners vuln \
    --format table \
    --exit-code 0 \
    --output "$REPORT_FILE" \
    "$PROJECT_DIR"

###############################################################################
# Generate JSON scan results for consolidation
###############################################################################

echo ""
echo "Generating structured JSON scan results..."

"$TRIVY" fs \
    --scanners vuln \
    --format json \
    --exit-code 0 \
    --output "$JSON_REPORT" \
    "$PROJECT_DIR"

###############################################################################
# Consolidate vulnerabilities into one CSV
###############################################################################

echo ""
echo "Generating consolidated vulnerability report..."

python3 - "$PROJECT_DIR" "$JSON_REPORT" "$CSV_REPORT" <<'PY'
import csv
import json
import os
import sys

root_dir = os.path.realpath(sys.argv[1])
json_file = sys.argv[2]
csv_file = sys.argv[3]

PROJECT_EXTENSIONS = (".csproj", ".fsproj", ".vbproj")


def find_subproject(target):
    """
    Associate a Trivy result with the nearest .NET project directory.
    If no project can be identified, use the target directory as fallback.
    """
    target_path = target if os.path.isabs(target) else os.path.join(
        root_dir, target
    )
    target_path = os.path.realpath(target_path)

    if os.path.isfile(target_path):
        current = os.path.dirname(target_path)
    else:
        current = target_path

    # Ignore targets outside the repository.
    if not (
        current == root_dir or current.startswith(root_dir + os.sep)
    ):
        return "(outside repository)"

    while True:
        try:
            project_files = sorted(
                name for name in os.listdir(current)
                if name.endswith(PROJECT_EXTENSIONS)
                and os.path.isfile(os.path.join(current, name))
            )
        except OSError:
            project_files = []

        if project_files:
            relative_dir = os.path.relpath(current, root_dir)
            project_path = os.path.join(
                relative_dir, project_files[0]
            )

            return (
                project_files[0]
                if relative_dir == "."
                else project_path.replace("\\", "/")
            )

        if current == root_dir:
            break

        parent = os.path.dirname(current)

        if parent == current or not (
            parent == root_dir or parent.startswith(root_dir + os.sep)
        ):
            break

        current = parent

    relative = os.path.relpath(
        os.path.dirname(target_path), root_dir
    )

    return "(root)" if relative == "." else relative.replace("\\", "/")


with open(json_file, encoding="utf-8") as file:
    data = json.load(file)

rows = []

for result in data.get("Results") or []:
    target = result.get("Target", "")
    subproject = find_subproject(target)

    for vulnerability in result.get("Vulnerabilities") or []:
        rows.append({
            "Sub-Project": subproject,
            "Target": target,
            "Library": vulnerability.get("PkgName", ""),
            "Installed Version": vulnerability.get("InstalledVersion", ""),
            "Vulnerability ID": vulnerability.get("VulnerabilityID", ""),
            "Severity": vulnerability.get("Severity", ""),
            "Fixed Version": vulnerability.get("FixedVersion", ""),
            "Title": vulnerability.get("Title", ""),
        })

columns = [
    "Sub-Project",
    "Target",
    "Library",
    "Installed Version",
    "Vulnerability ID",
    "Severity",
    "Fixed Version",
    "Title",
]

with open(csv_file, "w", newline="", encoding="utf-8-sig") as file:
    writer = csv.DictWriter(file, fieldnames=columns)
    writer.writeheader()
    writer.writerows(rows)

print(f"Consolidated vulnerability rows: {len(rows)}")
print(f"CSV report: {csv_file}")
PY

###############################################################################
# Display final reports
###############################################################################

echo ""
echo "============================================================"
echo "TRIVY SCAN COMPLETED"
echo "============================================================"

echo "Text report : $REPORT_FILE"
echo "JSON report : $JSON_REPORT"
echo "CSV report  : $CSV_REPORT"

echo ""
echo "Text report preview:"
cat "$REPORT_FILE"

echo ""
echo "Consolidated CSV report is ready for publishing as a pipeline artifact."
