#################### for command dotnet --list package #####################
#!/bin/bash

# Define file paths
input_file="outdated-dependencies.txt"
dependency_file="dependency-report.txt"
output_file="formatted_dependencies.txt"#################### for command dotnet --list package #####################
#!/bin/bash

# Define file paths
input_file="outdated-dependencies.txt"
dependency_file="dependency-report.txt"
output_file="formatted_dependencies.txt"
csv_output_file="formatted_dependencies.csv"

# Check if the dependency report exists
if [[ ! -f "$dependency_file" ]]; then
    echo "File $dependency_file not found!"
    exit 1
fi

# Check if outdated report exists
if [[ ! -f "$input_file" ]]; then
    echo "File $input_file not found!"
    exit 1
fi

###############################################################################
# Output headers
###############################################################################

echo -e "Dependency\tCurrent Version\tLatest Version\tDependency Type\tNuGet-Latest-Version" > "$output_file"

echo '"Dependency","Current Version","Latest Version","Dependency Type","NuGet-Latest-Version"' > "$csv_output_file"

###############################################################################
# Initialize associative arrays
###############################################################################

declare -A dependency_type
declare -A dependency_version
declare -A latest_version
declare -A nuget_latest_version
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
# Read outdated-dependencies.txt
#
# This file is authoritative only for:
#   - Current version
#   - Latest version
#
# Existing version parsing is intentionally preserved.
###############################################################################

while IFS= read -r line; do

    if [[ "$line" == *">"* ]]; then

        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')

        # Preserve existing parsing
        dependency=$(echo "$formatted_line" | awk '{print $1}')
        current_version=$(echo "$formatted_line" | awk '{print $2}')
        latest_version_value=$(echo "$formatted_line" | awk '{print $4}')

        if [[ -n "$dependency" ]]; then

            latest_version["$dependency"]="$latest_version_value"

            # Keep the existing current version from outdated report
            dependency_version["$dependency"]="$current_version"

        fi

    fi

done < "$input_file"

###############################################################################
# Query NuGet API for latest version
#
# This is an additional testing column only.
#
# NuGet API:
# https://api.nuget.org/v3-flatcontainer/<package-id>/index.json
#
# The package ID is converted to lowercase because the flat-container
# endpoint uses lowercase package IDs.
###############################################################################

echo ""
echo "============================================================"
echo "QUERYING NUGET FOR LATEST VERSIONS"
echo "============================================================"

for dependency in "${!dependency_type[@]}"; do

    ###########################################################################
    # Convert package ID to lowercase
    ###########################################################################

    package_id=$(echo "$dependency" | tr '[:upper:]' '[:lower:]')

    nuget_url="https://api.nuget.org/v3-flatcontainer/${package_id}/index.json"

    echo "Checking NuGet: $dependency"

    ###########################################################################
    # Call NuGet API
    ###########################################################################

    response=$(curl -sS --fail --max-time 15 "$nuget_url" 2>/dev/null)

    if [[ $? -ne 0 || -z "$response" ]]; then

        echo "  NuGet lookup failed: $dependency"
        nuget_latest_version["$dependency"]="N/A"
        continue

    fi

    ###########################################################################
    # Extract versions from JSON
    #
    # Uses Python because Python is already required by the migration/SBOM
    # environment and gives us reliable JSON parsing.
    ###########################################################################

    latest=$(printf '%s' "$response" | python3 -c '
import sys
import json

try:
    data = json.load(sys.stdin)
    versions = data.get("versions", [])

    # Remove prerelease versions.
    stable = [
        v for v in versions
        if "-" not in v
    ]

    if stable:
        print(stable[-1])
    else:
        print("N/A")

except Exception:
    print("N/A")
')

    ###########################################################################
    # Store result
    ###########################################################################

    if [[ -n "$latest" ]]; then
        nuget_latest_version["$dependency"]="$latest"
        echo "  NuGet latest: $latest"
    else
        nuget_latest_version["$dependency"]="N/A"
        echo "  NuGet latest: N/A"
    fi

done

###############################################################################
# Generate formatted output for ALL dependencies
###############################################################################

for dependency in "${!dependency_type[@]}"; do

    current_version="${dependency_version[$dependency]}"
    dependency_type_value="${dependency_type[$dependency]}"

    ###########################################################################
    # Get NuGet latest version
    ###########################################################################

    nuget_latest="${nuget_latest_version[$dependency]:-N/A}"

    ###########################################################################
    # If package exists in outdated report
    ###########################################################################

    if [[ -n "${latest_version[$dependency]}" ]]; then

        latest_version_value="${latest_version[$dependency]}"

        # Preserve existing ** behavior
        if [[ "$current_version" != "$latest_version_value" ]]; then
            current_version="${current_version}**"
            latest_version_value="${latest_version_value}**"
        fi

    else

        #######################################################################
        # Package is not outdated.
        #
        # We know current/resolved version, but we do NOT have a latest
        # version from outdated-dependencies.txt.
        #######################################################################

        latest_version_value="N/A"

    fi

    ###########################################################################
    # Prevent duplicates
    ###########################################################################

    if [[ -z "${seen_dependencies[$dependency]}" ]]; then

        #######################################################################
        # Write TXT
        #######################################################################

        echo -e "$dependency\t$current_version\t$latest_version_value\t$dependency_type_value\t$nuget_latest" \
            >> "$output_file"

        #######################################################################
        # Write CSV
        #######################################################################

        echo "\"$dependency\",\"$current_version\",\"$latest_version_value\",\"$dependency_type_value\",\"$nuget_latest\"" \
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
csv_output_file="formatted_dependencies.csv"

# Check if the dependency report exists
if [[ ! -f "$dependency_file" ]]; then
    echo "File $dependency_file not found!"
    exit 1
fi

# Check if outdated report exists
if [[ ! -f "$input_file" ]]; then
    echo "File $input_file not found!"
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
declare -A latest_version
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
# Read outdated-dependencies.txt
#
# This file is authoritative only for:
#   - Current version
#   - Latest version
#
# Existing version parsing is intentionally preserved.
###############################################################################

while IFS= read -r line; do

    if [[ "$line" == *">"* ]]; then

        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')

        # Preserve existing parsing
        dependency=$(echo "$formatted_line" | awk '{print $1}')
        current_version=$(echo "$formatted_line" | awk '{print $2}')
        latest_version_value=$(echo "$formatted_line" | awk '{print $4}')

        if [[ -n "$dependency" ]]; then

            latest_version["$dependency"]="$latest_version_value"

            # Keep the existing current version from outdated report
            dependency_version["$dependency"]="$current_version"

        fi

    fi

done < "$input_file"

###############################################################################
# Generate formatted output for ALL dependencies
###############################################################################

for dependency in "${!dependency_type[@]}"; do

    current_version="${dependency_version[$dependency]}"
    dependency_type_value="${dependency_type[$dependency]}"

    ###########################################################################
    # If package exists in outdated report
    ###########################################################################

    if [[ -n "${latest_version[$dependency]}" ]]; then

        latest_version_value="${latest_version[$dependency]}"

        # Preserve existing ** behavior
        if [[ "$current_version" != "$latest_version_value" ]]; then
            current_version="${current_version}**"
            latest_version_value="${latest_version_value}**"
        fi

    else

        #######################################################################
        # Package is not outdated.
        #
        # We know current/resolved version, but we do NOT have a latest
        # version from outdated-dependencies.txt.
        #######################################################################

        latest_version_value="N/A"

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

echo "Formatted dependencies saved to $output_file:"
cat "$output_file"

echo ""
echo "Formatted dependencies CSV saved to $csv_output_file:"
cat "$csv_output_file"
