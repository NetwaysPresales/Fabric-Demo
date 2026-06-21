<#
  common.ps1 - shared helpers for setup.ps1 and every module's run.ps1.
  Dot-source it:  . "$PSScriptRoot/../module-0-setup/common.ps1"
  It exposes: Import-DotEnv, Set-DotEnvValue, Get-FabricHeaders, Get-StorageHeaders,
              Invoke-FabricGet, New-FabricItemIfMissing, Get-OrCreateWorkspace,
              Wait-FabricOperation, Invoke-FabricSql.
#>

$ErrorActionPreference = "Stop"
$script:RepoRoot   = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$script:EnvPath    = Join-Path $RepoRoot ".env"
$script:DataDir    = Join-Path $RepoRoot "module-0-setup/data"
$script:FabricBase = "https://api.fabric.microsoft.com/v1"

function Import-DotEnv {
    $path = $script:EnvPath
    if (-not (Test-Path $path)) {
        $example = Join-Path $script:RepoRoot ".env.example"
        if (Test-Path $example) { Write-Warning ".env not found - using .env.example defaults."; $path = $example }
        else { throw "No .env or .env.example at repo root." }
    }
    $cfg = @{}
    Get-Content $path | ForEach-Object {
        $l = $_.Trim()
        if ($l -and -not $l.StartsWith("#") -and $l.Contains("=")) { $k,$v = $l -split "=",2; $cfg[$k.Trim()] = $v.Trim() }
    }
    return $cfg
}

function Set-DotEnvValue([string]$Key, [string]$Value) {
    if (-not (Test-Path $script:EnvPath)) { return }
    $found = $false
    $out = Get-Content $script:EnvPath | ForEach-Object {
        if ($_ -match "^\s*$([regex]::Escape($Key))\s*=") { $found = $true; "$Key=$Value" } else { $_ }
    }
    if (-not $found) { $out += "$Key=$Value" }
    Set-Content -Path $script:EnvPath -Value $out
}

function Get-FabricHeaders {
    $t = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv 2>$null
    if (-not $t) { throw "Could not get a Fabric token. Run 'az login'." }
    return @{ Authorization = "Bearer $t"; "Content-Type" = "application/json" }
}

function Get-StorageHeaders {
    $t = az account get-access-token --resource "https://storage.azure.com" --query accessToken -o tsv 2>$null
    if (-not $t) { throw "Could not get a storage token. Run 'az login'." }
    return @{ Authorization = "Bearer $t"; "x-ms-version" = "2021-10-04" }
}

function Invoke-FabricGet([string]$Path, [hashtable]$Headers) {
    Invoke-RestMethod -Uri "$script:FabricBase/$Path" -Headers $Headers -Method Get
}

function Wait-FabricOperation($Response, [hashtable]$Headers, [int]$MaxTries = 60) {
    $op = @($Response.Headers["Location"])[0]; if (-not $op) { $op = @($Response.Headers["Operation-Location"])[0] }
    if (-not $op) { return }
    for ($i=0; $i -lt $MaxTries; $i++) {
        Start-Sleep 5
        $st = Invoke-RestMethod -Uri $op -Headers $Headers
        if ($st.status -eq "Succeeded") { return }
        if ($st.status -eq "Failed")    { throw "Fabric operation failed." }
    }
}

function New-FabricItemIfMissing([string]$WorkspaceId, [string]$Collection, [string]$DisplayName, [hashtable]$Body, [hashtable]$Headers) {
    $existing = (Invoke-FabricGet "workspaces/$WorkspaceId/$Collection" $Headers).value | Where-Object { $_.displayName -eq $DisplayName }
    if ($existing) { Write-Host "[skip] $Collection/$DisplayName exists ($($existing.id))" -ForegroundColor DarkGray; return $existing.id }
    $resp = Invoke-WebRequest -Uri "$script:FabricBase/workspaces/$WorkspaceId/$Collection" -Headers $Headers -Method Post -Body ($Body | ConvertTo-Json -Depth 10)
    if ($resp.StatusCode -eq 202) {
        Write-Host "[wait] $Collection/$DisplayName provisioning..." -ForegroundColor Yellow
        Wait-FabricOperation $resp $Headers
        $id = ((Invoke-FabricGet "workspaces/$WorkspaceId/$Collection" $Headers).value | Where-Object { $_.displayName -eq $DisplayName }).id
    } else { $id = ($resp.Content | ConvertFrom-Json).id }
    Write-Host "[ok]   $Collection/$DisplayName -> $id" -ForegroundColor Green
    return $id
}

function Get-OrCreateWorkspace([string]$Name, [string]$CapacityId, [hashtable]$Headers) {
    $w = (Invoke-FabricGet "workspaces" $Headers).value | Where-Object { $_.displayName -eq $Name }
    if (-not $w) {
        $w = Invoke-RestMethod -Uri "$script:FabricBase/workspaces" -Headers $Headers -Method Post -Body (@{ displayName=$Name; capacityId=$CapacityId } | ConvertTo-Json)
        Write-Host "[ok]   workspace $Name -> $($w.id)" -ForegroundColor Green
    } else { Write-Host "[skip] workspace $Name exists ($($w.id))" -ForegroundColor DarkGray }
    return $w.id
}

# Run a .sql script (or text) against a Fabric SQL endpoint (warehouse / SQL DB / lakehouse SQL endpoint)
# using an Entra access token - no SqlServer module needed. Splits batches on lines that are just 'GO'.
function Invoke-FabricSql([string]$Server, [string]$Database, [string]$SqlText) {
    $token = az account get-access-token --resource "https://database.windows.net" --query accessToken -o tsv 2>$null
    if (-not $token) { throw "Could not get a SQL token. Run 'az login'." }
    $srv = if ($Server -match ",") { $Server } else { "$Server,1433" }   # serverFqdn sometimes already includes the port
    $conn = [System.Data.SqlClient.SqlConnection]::new("Server=tcp:$srv;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;")
    $conn.AccessToken = $token
    $conn.Open()
    try {
        $batches = [regex]::Split($SqlText, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() }
        foreach ($b in $batches) {
            $cmd = $conn.CreateCommand(); $cmd.CommandText = $b; $cmd.CommandTimeout = 300
            try { [void]$cmd.ExecuteNonQuery() }
            catch { Write-Host "[sql warn] $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    } finally { $conn.Close() }
}
