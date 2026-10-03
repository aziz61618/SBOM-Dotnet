$dependenciesFile = "formatted_dependencies.txt"
$licensesFile = "sbom-licenses.txt"
$outputFile = "sbom-result.txt"
$csvOutputFile = "sbom-result.csv"

# Column widths
$dependencyWidth = 50
$currentVersionWidth = 15
$latestVersionWidth = 15
$dependencyTypeWidth = 18
$licenseWidth = 25
$licenseUrlWidth = 60

# Output header with proper spacing
$header = "{0}{1}{2}{3}{4}{5}" -f `
    "Dependency".PadRight($dependencyWidth), `
    "Current Version".PadRight($currentVersionWidth), `
    "Latest Version".PadRight($latestVersionWidth), `
    "Dependency Type".PadRight($dependencyTypeWidth), `
    "License".PadRight($licenseWidth), `
    "License URL"

$header | Out-File -FilePath $outputFile

# Initialize hash tables for licenses and output to check duplicates
$licenseInfo = @{}
$outputEntries = @{}

# Initialize collection for CSV output
$csvEntries = @{}

# Read licenses file into a hash table
try {
    Get-Content -Path $licensesFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "") { return } # Skip empty lines

        # Skip the header line and lines starting with separators or non-license info
        if ($line -like "*Reference*" -or $line -like "*----*") {
            return
        }

        $line = $line.TrimStart('|').TrimEnd('|').Trim()
        $parts = $line -split '\s*\|\s*'
        
        if ($parts.Length -eq 4) {
            $dependency = $parts[0].Trim()
            $version = $parts[1].Trim()
            $license = $parts[2].Trim()
            $licenseUrl = $parts[3].Trim()

            if (-not $licenseInfo.ContainsKey($dependency)) {
                $licenseInfo[$dependency] = @{
                    Version = $version
                    License = $license
                    LicenseUrl = $licenseUrl
                }
            } else {
                Write-Output "Duplicate entry found for ${dependency} in ${licensesFile}."
            }
        } else {
            Write-Output "Skipping invalid line in ${licensesFile}: ${line}"
        }
    }
} catch {
    Write-Error "Error reading ${licensesFile}: $_"
}

# Read dependencies file and merge with license info
$headerSkipped = $false
try {
    Get-Content -Path $dependenciesFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "") { return }

        # Skip the first line (header) from dependencies file
        if (-not $headerSkipped) {
            $headerSkipped = $true
            return
        }

        # formatted_dependencies.txt now contains:
        # Dependency
        # Current Version
        # Latest Version
        # Dependency Type
        $fields = $line -split '\s+', 4

        if ($fields.Length -ge 4) {
            $depTrimmed = $fields[0].Trim()
            $currentVersion = $fields[1].Trim()
            $latestVersion = $fields[2].Trim()
            $dependencyType = $fields[3].Trim()

            # Skip if already in output to avoid duplicates
            if ($outputEntries.ContainsKey($depTrimmed)) { return }

            # Check if license info exists for the dependency
            if ($licenseInfo.ContainsKey($depTrimmed)) {
                $licenseData = $licenseInfo[$depTrimmed]
                $license = $licenseData.License
                $licenseUrl = $licenseData.LicenseUrl
            } else {
                $license = "N/A"
                $licenseUrl = "N/A"
            }

            # Check for version differences and append ** if they are different
            if ($currentVersion -ne $latestVersion) {
                $currentVersion += "**"
                $latestVersion += "**"
            }

            # Write TXT output
            $outputLine = "{0}{1}{2}{3}{4}{5}" -f `
                $depTrimmed.PadRight($dependencyWidth), `
                $currentVersion.PadRight($currentVersionWidth), `
                $latestVersion.PadRight($latestVersionWidth), `
                $dependencyType.PadRight($dependencyTypeWidth), `
                $license.PadRight($licenseWidth), `
                $licenseUrl

            $outputLine | Out-File -FilePath $outputFile -Append

            # Store CSV entry
            $csvEntries[$depTrimmed] = [PSCustomObject]@{
                Dependency      = $depTrimmed
                CurrentVersion  = $currentVersion
                LatestVersion   = $latestVersion
                DependencyType  = $dependencyType
                License         = $license
                LicenseURL      = $licenseUrl
            }

            # Add to output entries to avoid future duplicates
            $outputEntries[$depTrimmed] = $true

            # Remove matched entry from licenseInfo
            if ($licenseInfo.ContainsKey($depTrimmed)) {
                $licenseInfo.Remove($depTrimmed)
            }
        } else {
            Write-Output "Skipping invalid line in ${dependenciesFile}: ${line}"
        }
    }
} catch {
    Write-Error "Error reading ${dependenciesFile}: $_"
}

# Add remaining entries from licenses file not matched in dependencies
foreach ($depTrimmed in @($licenseInfo.Keys)) {
    if ($outputEntries.ContainsKey($depTrimmed)) { continue }

    $licenseData = $licenseInfo[$depTrimmed]
    $licenseVersion = $licenseData.Version
    $license = $licenseData.License
    $licenseUrl = $licenseData.LicenseUrl

    # Existing behavior: use license version for both current/latest
    $outputLine = "{0}{1}{2}{3}{4}{5}" -f `
        $depTrimmed.PadRight($dependencyWidth), `
        $licenseVersion.PadRight($currentVersionWidth), `
        $licenseVersion.PadRight($latestVersionWidth), `
        "Unknown".PadRight($dependencyTypeWidth), `
        $license.PadRight($licenseWidth), `
        $licenseUrl

    $outputLine | Out-File -FilePath $outputFile -Append

    # Store CSV entry
    $csvEntries[$depTrimmed] = [PSCustomObject]@{
        Dependency      = $depTrimmed
        CurrentVersion  = $licenseVersion
        LatestVersion   = $licenseVersion
        DependencyType  = "Unknown"
        License         = $license
        LicenseURL      = $licenseUrl
    }
}

# Generate CSV report
$csvEntries.Values |
    Export-Csv -Path $csvOutputFile -NoTypeInformation -Encoding UTF8

Write-Output ""
Write-Output "SBOM TXT report generated: $outputFile"
Write-Output "SBOM CSV report generated: $csvOutputFile"
