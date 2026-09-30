#!/bin/bash

# Define input and output files
INPUT_FILE="sbom-result.txt"
STARRED_OUTPUT_FILE="outdated-dependencies.csv"
NON_STARRED_OUTPUT_FILE="Latest-dependencies.csv"

# Add CSV headers
echo "Dependency,Current Version,Latest Version,License,License URL" > "$STARRED_OUTPUT_FILE"
echo "Dependency,Current Version,Latest Version,License,License URL" > "$NON_STARRED_OUTPUT_FILE"

# Process the input file, skipping the first two lines (header and underline)
awk 'NR > 2 {
    line = $0;

    # Find the first occurrence of a version pattern (X.Y.Z)
    match(line, /[0-9]+\.[0-9]+\.[0-9]+/);
    
    # Extract dependency name (everything before the first version number)
    dependency = substr(line, 1, RSTART - 1);

    # Extract the remaining part (versions, license, and license URL)
    remaining = substr(line, RSTART);

    # Split remaining part into fields
    split(remaining, fields, " ");

    # Assign values
    current_version = fields[1];
    latest_version = fields[2];
    license = fields[3];

    # If a license URL exists, it starts after the license column
    license_url = (length(fields) > 3) ? fields[4] : "";

    # Remove "**" from versions
    gsub(/\*\*/, "", current_version);
    gsub(/\*\*/, "", latest_version);

    # Trim spaces
    gsub(/^ *| *$/, "", dependency);
    gsub(/^ *| *$/, "", current_version);
    gsub(/^ *| *$/, "", latest_version);
    gsub(/^ *| *$/, "", license);
    gsub(/^ *| *$/, "", license_url);

    # Ensure license and license URL are enclosed in quotes for CSV safety
    formatted_license = "\"" license "\"";
    formatted_license_url = "\"" license_url "\"";

    # Append to respective CSV file
    if (fields[1] ~ /\*\*/ || fields[2] ~ /\*\*/) {
        print dependency "," current_version "," latest_version "," formatted_license "," formatted_license_url >> "'"$STARRED_OUTPUT_FILE"'"
    } else {
        print dependency "," current_version "," latest_version "," formatted_license "," formatted_license_url >> "'"$NON_STARRED_OUTPUT_FILE"'"
    }
}' "$INPUT_FILE"

echo "Filtering completed. Check '$STARRED_OUTPUT_FILE' and '$NON_STARRED_OUTPUT_FILE'."
