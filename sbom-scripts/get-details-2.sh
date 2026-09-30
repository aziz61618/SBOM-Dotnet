#################### for command dotnet --list package #####################
#!/bin/bash
# Define file paths
input_file="outdated-dependencies.txt"
output_file="formatted_dependencies.txt"
# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
    echo "File $input_file not found!"
    exit 1
fi
# Write the header to the output file
echo -e "Dependency\tCurrent Version\tLatest Version" > "$output_file"
# Initialize an associative array to track added dependencies
declare -A seen_dependencies
# Process the input file
while IFS= read -r line; do
    # Check if the line starts with '>'
    if [[ "$line" == *">"* ]]; then
        # Remove '>' symbol and any leading spaces
        formatted_line=$(echo "$line" | sed 's/^[[:space:]]*>[[:space:]]*//')
        # Extract dependency name, current version, and latest version (ignore resolved version)
        dependency=$(echo "$formatted_line" | awk '{print $1}')
        current_version=$(echo "$formatted_line" | awk '{print $2}')
        latest_version=$(echo "$formatted_line" | awk '{print $4}') # Using $4 for the latest version
        # Check if the dependency has already been added
        if [[ -z "${seen_dependencies[$dependency]}" ]]; then
            # Write the formatted line to the output file
            echo -e "$dependency\t$current_version\t$latest_version" >> "$output_file"
            # Mark dependency as added
            seen_dependencies[$dependency]=1
        fi
    fi
done < "$input_file"
# Output file location
echo "Formatted dependencies saved to $output_file:"
cat "$output_file"