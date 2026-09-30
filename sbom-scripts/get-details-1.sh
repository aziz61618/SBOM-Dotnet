#!/bin/bash

################################################################################
# .NET SBOM Details Scanner - With Transitive Dependencies & Duplicate Filtering
# 
# This script scans .NET project dependencies (direct + transitive) using 
# dotnet-project-licenses and exports to structured CSV format.
# 
# Duplicate Filtering Strategy:
#   - Keeps all unique (name + version) combinations
#   - Only filters EXACT duplicates (same name AND same version)
#   - Different versions of the same package are kept as separate entries
#
# Output Files:
#   - outdated-dependencies.txt   : Outdated packages report
#   - sbom-licenses.txt           : Raw licenses report (all dependencies)
#   - project-dependency-output.csv : Parsed structured data (deduplicated exact matches only)
################################################################################

set -euo pipefail

# Configuration
export PATH="$PATH:$HOME/.dotnet/tools:/root/.dotnet/tools"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/sbom-scan.log"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Output files
OUT_CSV="project-dependency-output.csv"
OUTDATED_FILE="outdated-dependencies.txt"
LICENSES_FILE="sbom-licenses.txt"
TEMP_PARSED="${TEMP_DIR}/parsed_deps.txt"
TEMP_DEDUPLICATED="${TEMP_DIR}/deduplicated_deps.txt"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

################################################################################
# Tool Installation & Validation
################################################################################
install_tools() {
    log_info "Installing required .NET tools..."
    
    # Install dotnet-outdated-tool
    if ! dotnet tool list -g | grep -q "dotnet-outdated-tool"; then
        log_info "Installing dotnet-outdated-tool..."
        if ! dotnet tool install --global dotnet-outdated-tool --add-source https://api.nuget.org/v3/index.json 2>&1 | tee -a "$LOG_FILE"; then
            log_warn "dotnet-outdated-tool installation failed (non-critical)"
        fi
    else
        log_info "dotnet-outdated-tool already installed"
    fi
    
    # Install dotnet-project-licenses
    if ! dotnet tool list -g | grep -q "dotnet-project-licenses"; then
        log_info "Installing dotnet-project-licenses..."
        if ! dotnet tool install --global dotnet-project-licenses 2>&1 | tee -a "$LOG_FILE"; then
            log_error "dotnet-project-licenses installation failed (required)"
            return 1
        fi
    else
        log_info "dotnet-project-licenses already installed"
    fi
    
    log_success "All required tools are available"
    return 0
}

validate_tools() {
    log_info "Validating installed tools..."
    if ! dotnet tool list -g 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to list installed tools"
        return 1
    fi
    log_success "Tools validated"
    return 0
}

################################################################################
# Scan for Outdated Dependencies
################################################################################
scan_outdated() {
    log_info "Scanning for outdated dependencies..."
    
    if ! dotnet list package --outdated > "$OUTDATED_FILE" 2>&1; then
        log_warn "dotnet list package --outdated failed (non-critical)"
    fi
    
    if [ -s "$OUTDATED_FILE" ]; then
        log_success "Outdated dependencies report saved to $OUTDATED_FILE"
        log_info "Sample (first 10 lines):"
        head -10 "$OUTDATED_FILE" | sed 's/^/  /'
    else
        log_warn "No outdated dependencies report generated"
    fi
}

################################################################################
# Scan for Licenses (Direct & Transitive Dependencies)
################################################################################
scan_licenses() {
    log_info "Scanning for package licenses (including transitive dependencies)..."
    
    # Determine tool path
    TOOL_PATH="$HOME/.dotnet/tools/dotnet-project-licenses"
    if [ ! -f "$TOOL_PATH" ]; then
        TOOL_PATH="dotnet-project-licenses"
    fi
    
    if ! $TOOL_PATH -i "./" --include-transitive > "$LICENSES_FILE" 2>&1; then
        log_error "Failed to generate licenses report"
        return 1
    fi
    
    if [ ! -s "$LICENSES_FILE" ]; then
        log_error "Licenses file is empty"
        return 1
    fi
    
    log_success "Licenses report saved to $LICENSES_FILE"
    log_info "Report contains $(wc -l < "$LICENSES_FILE") lines"
    return 0
}

################################################################################
# Parse Licenses Report with Robust Regex
################################################################################
parse_licenses() {
    log_info "Parsing licenses report..."
    
    if [ ! -f "$LICENSES_FILE" ]; then
        log_error "Licenses file not found: $LICENSES_FILE"
        return 1
    fi
    
    > "$TEMP_PARSED"  # Clear temp file
    
    # Robust parsing for multiple .NET license report formats
    # Expected formats:
    #   1. PackageName (1.2.3) [Licenses: MIT]
    #   2. PackageName 1.2.3 - MIT
    #   3. @scope/PackageName (1.2.3) [Licenses: Apache-2.0; MIT]
    #   4. PackageName (1.2.3) - MIT; Apache-2.0
    
    while IFS= read -r line; do
        line=$(echo "$line" | xargs)  # Trim whitespace
        
        # Skip empty lines, headers, and separator lines
        if [ -z "$line" ] || echo "$line" | grep -qE "^(===|---|Package|---)" 2>/dev/null; then
            continue
        fi
        
        local name="" version="" license=""
        
        # Try format: PackageName (Version) [Licenses: License]
        if [[ $line =~ ^([a-zA-Z0-9._\-@/]+)[[:space:]]*\(([^)]+)\)[[:space:]]*\[.*[Ll]icense[s]?:[[:space:]]*([^\]]+)\] ]]; then
            name="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
            license="${BASH_REMATCH[3]}"
        # Try format: PackageName (Version) - License
        elif [[ $line =~ ^([a-zA-Z0-9._\-@/]+)[[:space:]]*\(([^)]+)\)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
            license="${BASH_REMATCH[3]}"
        # Try format: PackageName Version - License (without parentheses)
        elif [[ $line =~ ^([a-zA-Z0-9._\-@/]+)[[:space:]]+([0-9]+\.[0-9.]+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
            license="${BASH_REMATCH[3]}"
        else
            # Skip lines that don't match any expected format
            continue
        fi
        
        # Clean up extracted values
        name=$(echo "$name" | xargs)
        version=$(echo "$version" | xargs)
        license=$(echo "$license" | xargs)
        
        # Handle empty or unknown licenses
        if [ -z "$license" ] || [ "$license" = "UNKNOWN" ] || [ "$license" = "Unknown" ]; then
            license="UNKNOWN"
            license_status="Unknown"
        else
            license_status="Declared"
            # Trim trailing punctuation
            license=$(echo "$license" | sed 's/[,;:]*$//')
        fi
        
        # Validate package name and version
        if [ -z "$name" ] || [ -z "$version" ]; then
            log_warn "Skipping malformed line: $line"
            continue
        fi
        
        # Output in pipe-delimited format for deduplication
        # Format: name|version|license|license_status
        echo "$name|$version|$license|$license_status"
        
    done < "$LICENSES_FILE" > "$TEMP_PARSED"
    
    local parsed_count=$(wc -l < "$TEMP_PARSED")
    if [ "$parsed_count" -eq 0 ]; then
        log_error "No packages were parsed from licenses report"
        return 1
    fi
    
    log_success "Parsed $parsed_count package entries"
    return 0
}

################################################################################
# Deduplicate Packages (Remove Only EXACT Duplicates)
#
# Strategy:
#   - A duplicate is defined as: same name AND same version
#   - Different versions of the same package are kept (not filtered)
#   - Uses a set-based approach: name|version as unique key
################################################################################
deduplicate_packages() {
    log_info "Deduplicating packages (filtering only exact duplicates)..."
    
    if [ ! -f "$TEMP_PARSED" ]; then
        log_error "Parsed file not found"
        return 1
    fi
    
    > "$TEMP_DEDUPLICATED"  # Clear temp file
    
    # Use associative array with "name|version" as key to track unique combinations
    declare -A seen_packages
    local duplicate_count=0
    
    while IFS='|' read -r name version license license_status; do
        if [ -z "$name" ] || [ -z "$version" ]; then
            continue
        fi
        
        # Create unique key: name|version
        local unique_key="${name}|${version}"
        
        # Check if we've seen this exact package+version combination before
        if [ -v "seen_packages[$unique_key]" ]; then
            # Exact duplicate found (same name + same version)
            ((duplicate_count++))
            log_info "Skipping duplicate: $name ($version)"
            continue
        fi
        
        # First time seeing this name+version combination
        seen_packages[$unique_key]=1
        echo "$name|$version|$license|$license_status" >> "$TEMP_DEDUPLICATED"
        
    done < "$TEMP_PARSED"
    
    # Sort alphabetically by package name
    sort "$TEMP_DEDUPLICATED" -o "$TEMP_DEDUPLICATED"
    
    local unique_count=$(wc -l < "$TEMP_DEDUPLICATED")
    local original_count=$(wc -l < "$TEMP_PARSED")
    
    log_success "Deduplicated: $original_count entries → $unique_count unique packages"
    if [ $duplicate_count -gt 0 ]; then
        log_info "Removed $duplicate_count exact duplicate entries (same name + version)"
    fi
    
    return 0
}

################################################################################
# Export to CSV
################################################################################
export_csv() {
    log_info "Exporting to CSV format..."
    
    if [ ! -f "$TEMP_DEDUPLICATED" ]; then
        log_error "Deduplicated file not found"
        return 1
    fi
    
    # Write CSV header
    echo "Name,CurrentVersion,License,LicenseStatus,DependencyRoot" > "$OUT_CSV"
    
    # Write CSV rows with proper escaping
    local row_count=0
    while IFS='|' read -r name version license license_status; do
        # Escape quotes and wrap in quotes for CSV safety
        name_escaped="\"$(echo "$name" | sed 's/"/""/g')\""
        version_escaped="\"$(echo "$version" | sed 's/"/""/g')\""
        license_escaped="\"$(echo "$license" | sed 's/"/""/g')\""
        
        echo "$name_escaped,$version_escaped,$license_escaped,\"$license_status\",\"dotnet\"" >> "$OUT_CSV"
        ((row_count++))
    done < "$TEMP_DEDUPLICATED"
    
    log_success "Exported $row_count packages to $OUT_CSV"
    
    # Display sample output
    log_info "Sample output (first 5 rows):"
    head -6 "$OUT_CSV" | tail -5 | sed 's/^/  /'
    
    return 0
}

################################################################################
# Generate Summary Report
################################################################################
generate_summary() {
    log_info "Generating summary report..."
    
    echo ""
    echo "================================================================================"
    echo "                    .NET SBOM SCAN SUMMARY REPORT"
    echo "================================================================================"
    echo ""
    
    if [ -f "$OUTDATED_FILE" ] && [ -s "$OUTDATED_FILE" ]; then
        outdated_count=$(grep -c ">" "$OUTDATED_FILE" 2>/dev/null || echo "0")
        echo "📦 Outdated Dependencies: $outdated_count"
    fi
    
    if [ -f "$OUT_CSV" ]; then
        csv_count=$(tail -n +2 "$OUT_CSV" | wc -l)
        echo "📋 Total Unique Packages Scanned: $csv_count"
        echo ""
        
        # License status breakdown
        echo "License Status Breakdown:"
        declared=$(grep -c '"Declared"' "$OUT_CSV" 2>/dev/null || echo "0")
        unknown=$(grep -c '"Unknown"' "$OUT_CSV" 2>/dev/null || echo "0")
        echo "  ✓ Declared: $declared"
        echo "  ⚠ Unknown:  $unknown"
    fi
    
    echo ""
    echo "Output Files Generated:"
    [ -f "$OUTDATED_FILE" ] && echo "  ✓ $OUTDATED_FILE" || echo "  ✗ $OUTDATED_FILE (not generated)"
    [ -f "$LICENSES_FILE" ] && echo "  ✓ $LICENSES_FILE" || echo "  ✗ $LICENSES_FILE (not generated)"
    [ -f "$OUT_CSV" ] && echo "  ✓ $OUT_CSV" || echo "  ✗ $OUT_CSV (not generated)"
    
    echo ""
    echo "Log file: $LOG_FILE"
    echo "================================================================================"
    echo ""
}

################################################################################
# Main Execution
################################################################################
main() {
    log_info "Starting .NET SBOM scan..."
    log_info "Working directory: $(pwd)"
    
    # Install and validate tools
    if ! install_tools; then
        log_error "Tool installation failed"
        return 1
    fi
    
    if ! validate_tools; then
        log_error "Tool validation failed"
        return 1
    fi
    
    # Scan for dependencies
    scan_outdated
    
    if ! scan_licenses; then
        log_error "License scan failed"
        return 1
    fi
    
    # Parse and process
    if ! parse_licenses; then
        log_error "License parsing failed"
        return 1
    fi
    
    if ! deduplicate_packages; then
        log_error "Deduplication failed"
        return 1
    fi
    
    # Export results
    if ! export_csv; then
        log_error "CSV export failed"
        return 1
    fi
    
    # Generate summary
    generate_summary
    
    log_success "SBOM scan completed successfully!"
    return 0
}

# Run main function
if main; then
    exit 0
else
    log_error "SBOM scan failed. See $LOG_FILE for details."
    exit 1
fi
