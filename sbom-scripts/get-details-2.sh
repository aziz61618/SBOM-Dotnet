#################### for command dotnet --list package #####################
#!/bin/bash

# Define file paths
dependency_file="dependency-report.txt"
output_file="formatted_dependencies.txt"
csv_output_file="formatted_dependencies.csv"

# Check if the dependency report exists
if [[ ! -f "$dependency_file" ]]; then
    echo "File $dependency_file not found!"
    exit 1
fi

###############################################################################
# Output headers
###############################################################################

echo -e "Dependency\tCurrent Version\tLatest Version\tDependency Type" > "$output_file"

echo '"Dependency","Current Version","Latest Version","Dependency Type"' > "$csv_output_file"

###############################################################################
# Initialize associative arrays
###############################################################################

declare -A dependency_type
declare -A dependency_version
declare -A seen_dependencies

###############################################################################
# Read dependency-report.txt
#
# This file is authoritative for:
#   - ALL dependencies
#   - Direct / Transitive
#   - Resolved/current version
###############################################################################

current_type=""

while IFS= read -r line; do

    ###########################################################################
    # Detect Direct dependency section
    ###########################################################################

    if [[ "$line" == *"Top-level Package"* ]]; then
        current_type="Direct"
        continue
    fi

    ###########################################################################
    # Detect Transitive dependency section
    ###########################################################################

    if [[ "$line" == *"Transitive Package"* ]]; then
        current_type="Transitive"
        continue
    fi

    ###########################################################################
    # Process package rows
    ###########################################################################

    if [[ "$line" =~ ^[[:space:]]*\>[[:space:]]+ ]]; then

        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')

        dependency=$(echo "$formatted_line" | awk '{print $1}')

        if [[ "$current_type" == "Direct" ]]; then

            current_version=$(echo "$formatted_line" | awk '{print $3}')

            # Direct takes precedence if the same package appears elsewhere
            dependency_type["$dependency"]="Direct"
            dependency_version["$dependency"]="$current_version"

        elif [[ "$current_type" == "Transitive" ]]; then

            # Transitive rows have:
            # PackageName ... ResolvedVersion
            current_version=$(echo "$formatted_line" | awk '{print $NF}')

            # Only set Transitive if package is not already Direct
            if [[ -z "${dependency_type[$dependency]}" ]]; then
                dependency_type["$dependency"]="Transitive"
                dependency_version["$dependency"]="$current_version"
            fi

        fi

    fi

done < "$dependency_file"

###############################################################################
# Query NuGet for latest versions
#
# NuGet API is now authoritative for:
#   - Latest version
#
# Current/resolved version continues to come from dependency-report.txt.
###############################################################################

declare -A nuget_latest_version

echo ""
echo "============================================================"
echo "QUERYING NUGET FOR LATEST VERSIONS"
echo "============================================================"

for dependency in "${!dependency_type[@]}"; do

    # Convert package ID to lowercase for NuGet flat-container API
    package_id=$(echo "$dependency" | tr '[:upper:]' '[:lower:]')

    nuget_url="https://api.nuget.org/v3-flatcontainer/${package_id}/index.json"

    echo "Checking NuGet: $dependency"

    response=$(curl -sS --fail --max-time 15 "$nuget_url" 2>/dev/null)

    if [[ $? -ne 0 || -z "$response" ]]; then

        echo "  NuGet lookup failed: $dependency"

        nuget_latest_version["$dependency"]="N/A"

        continue

    fi

    nuget_version=$(printf '%s' "$response" | python3 -c '
import sys
import json

try:
    data = json.load(sys.stdin)
    versions = data.get("versions", [])

    # Keep only stable versions
    stable_versions = [
        version for version in versions
        if "-" not in version
    ]

    if stable_versions:
        print(stable_versions[-1])
    else:
        print("N/A")

except Exception:
    print("N/A")
')

    [[ -z "$nuget_version" ]] && nuget_version="N/A"

    nuget_latest_version["$dependency"]="$nuget_version"

    echo "  NuGet latest: $nuget_version"

done

###############################################################################
# Generate formatted output for ALL dependencies
###############################################################################

for dependency in "${!dependency_type[@]}"; do

    current_version="${dependency_version[$dependency]}"
    dependency_type_value="${dependency_type[$dependency]}"
    latest_version_value="${nuget_latest_version[$dependency]:-N/A}"

    ###########################################################################
    # Compare current version with NuGet latest version
    #
    # Preserve existing ** behavior
    ###########################################################################

    if [[ "$latest_version_value" != "N/A" ]]; then

        if [[ "$current_version" != "$latest_version_value" ]]; then
            current_version="${current_version}**"
            latest_version_value="${latest_version_value}**"
        fi

    fi

    ###########################################################################
    # Prevent duplicates
    ###########################################################################

    if [[ -z "${seen_dependencies[$dependency]}" ]]; then

        #######################################################################
        # Write TXT
        #######################################################################

        echo -e "$dependency\t$current_version\t$latest_version_value\t$dependency_type_value" \
            >> "$output_file"

        #######################################################################
        # Write CSV
        #######################################################################

        echo "\"$dependency\",\"$current_version\",\"$latest_version_value\",\"$dependency_type_value\"" \
            >> "$csv_output_file"

        seen_dependencies["$dependency"]=1

    fi

done

###############################################################################
# Output files
###############################################################################

echo ""
echo "============================================================"
echo "FORMATTED DEPENDENCIES"
echo "============================================================"

echo "Formatted dependencies saved to $output_file:"
cat "$output_file"

echo ""
echo "Formatted dependencies CSV saved to $csv_output_file:"
cat "$csv_output_file"
