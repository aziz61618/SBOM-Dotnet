# ----------- for command dotnet outdated > outdated-dependencies.txt ------------##
#!/bin/bash
# Define file paths
input_file="outdated-dependencies.txt"
output_file="formatted_dependencies.txt"
# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
    echo "File $input_file not found!"
    exit 1
fi
# Write the header to the output file with aligned columns
echo -e "Dependency\t\tCurrent Version\t\tLatest Version" > "$output_file"
# Process the input file
while IFS= read -r line; do
    # Check if the line contains "->" indicating a version update
    if [[ "$line" == *"->"* ]]; then
        # Extract and format the dependency information
        dependency=$(echo "$line" | awk -F' -> ' '{print $1}')
        current_version=$(echo "$line" | awk -F' -> ' '{print $2}')
        latest_version=$(echo "$line" | awk -F' -> ' '{print $3}')

        # Print formatted result to output file with alignment
        printf "%10s\t%-40s\t%20s\n" "$dependency" "$current_version" "$latest_version" >> "$output_file"
        #echo -e "$dependency\t$current_version\t$latest_version" >> "$output_file"
    fi
done < "$input_file"
# Output file location
echo "Formatted output saved to $output_file:"
cat "$output_file"