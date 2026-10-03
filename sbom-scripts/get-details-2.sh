```bash
#################### for command dotnet --list package #####################
#!/bin/bash

# Define file paths
input_file="outdated-dependencies.txt"
dependency_file="dependency-report.txt"
output_file="formatted_dependencies.txt"
csv_output_file="formatted_dependencies.csv"

# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
    echo "File $input_file not found!"
    exit 1
fi

# Check if dependency report exists
if [[ ! -f "$dependency_file" ]]; then
    echo "File $dependency_file not found!"
    exit 1
fi

# Write the header to the output file
echo -e "Dependency\tCurrent Version\tLatest Version\tDependency Type" > "$output_file"

# Write the header to the CSV file
echo '"Dependency","Current Version","Latest Version","Dependency Type"' > "$csv_output_file"

# Initialize associative arrays
declare -A seen_dependencies
declare -A dependency_type

###############################################################################
# Read dependency-report.txt and determine Direct / Transitive
###############################################################################

current_type=""

while IFS= read -r line; do

    # Detect direct dependency section
    if [[ "$line" == *"Top-level Package"* ]]; then
        current_type="Direct"
        continue
    fi

    # Detect transitive dependency section
    if [[ "$line" == *"Transitive Package"* ]]; then
        current_type="Transitive"
        continue
    fi

    # Process dependency rows
    if [[ "$line" == *">"* ]]; then

        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')

        dependency=$(echo "$formatted_line" | awk '{print $1}')

        if [[ -n "$dependency" && -n "$current_type" ]]; then

            # If dependency is found as direct, Direct takes precedence
            if [[ "$current_type" == "Direct" ]]; then
                dependency_type[$dependency]="Direct"

            elif [[ -z "${dependency_type[$dependency]}" ]]; then
                dependency_type[$dependency]="Transitive"
            fi

        fi
    fi

done < "$dependency_file"

###############################################################################
# Process outdated-dependencies.txt
###############################################################################

while IFS= read -r line; do

    # Check if the line starts with '>'
    if [[ "$line" == *">"* ]]; then

        # Remove '>' symbol and any leading spaces
        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')

        # Extract dependency name, current version, and latest version
        # (ignore resolved version)
        dependency=$(echo "$formatted_line" | awk '{print $1}')
        current_version=$(echo "$formatted_line" | awk '{print $2}')
        latest_version=$(echo "$formatted_line" | awk '{print $4}')

        # Determine whether dependency is Direct or Transitive
        dependency_type_value="${dependency_type[$dependency]:-Unknown}"

        # Check if the dependency has already been added
        if [[ -z "${seen_dependencies[$dependency]}" ]]; then

            # Write the formatted line to TXT
            echo -e "$dependency\t$current_version\t$latest_version\t$dependency_type_value" >> "$output_file"

            # Write the formatted line to CSV
            echo "\"$dependency\",\"$current_version\",\"$latest_version\",\"$dependency_type_value\"" >> "$csv_output_file"

            # Mark dependency as added
            seen_dependencies[$dependency]=1
        fi
    fi

done < "$input_file"

###############################################################################
# Output file locations
###############################################################################

echo "Formatted dependencies saved to $output_file:"
cat "$output_file"

echo ""
echo "Formatted dependencies CSV saved to $csv_output_file:"
cat "$csv_output_file"
```
