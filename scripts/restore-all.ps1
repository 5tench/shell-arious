# Get all files from VS Code Local History
$historyPath = "$env:APPDATA\Code\User\History"
$files = Get-ChildItem -Path $historyPath -Recurse -File

# Function to extract destination path from file content
function Get-DestinationPath {
    param($content)
    if ($content -match '"associatedResource":"file:\/\/([^"]+)"') {
        return $matches[1]
    }
    return $null
}

# Create a hashtable to store the latest version of each file
$latestVersions = @{}

# Process each file and keep track of the latest version
foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $destPath = Get-DestinationPath $content
    if ($destPath) {
        # If we haven't seen this file before, or this version is newer
        if (-not $latestVersions.ContainsKey($destPath) -or 
            $file.LastWriteTime -gt $latestVersions[$destPath].LastWriteTime) {
            $latestVersions[$destPath] = @{
                SourceFile = $file
                Content = $content
                LastWriteTime = $file.LastWriteTime
            }
        }
    }
}

# Create directories and restore files
foreach ($destPath in $latestVersions.Keys) {
    $dir = Split-Path $destPath
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created directory: $dir"
    }

    $fileInfo = $latestVersions[$destPath]
    $content = $fileInfo.Content

    # Extract the actual file content
    if ($content -match '"content":"([^"]+)"') {
        $fileContent = $matches[1]
        # Unescape the content
        $fileContent = $fileContent -replace '\\n', "`n" -replace '\\r', "`r" -replace '\\t', "`t" -replace '\\\"', '"'
        Set-Content -Path $destPath -Value $fileContent -Force
        Write-Host "Restored file: $destPath"
    }
}

Write-Host "`nRestoration complete! All directories and files have been restored."