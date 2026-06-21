<#
  Module 5 - code path (PARTIAL - the rest is UI). Sets up the durable store:
    1. Create the eventhouse + KQL database (eh_telemetry).
    2. Best-effort: create the StoreTelemetry table + JSON ingestion mapping (eventhouse_setup.kql).
  The streaming bits - Eventstream, Real-Time Dashboard, Activator - are built in the UI
  (see this folder's README). Feed live data with: setup.ps1 -Action send-events (Event Hub).

  Usage: pwsh module-5-real-time-intelligence/run.ps1
#>
. "$PSScriptRoot/../module-0-setup/common.ps1"

$cfg = Import-DotEnv
$h = Get-FabricHeaders
$wsId = $cfg.WORKSPACE_ID
if (-not $wsId) { throw "No WORKSPACE_ID in .env. Run: pwsh module-0-setup/setup.ps1 -Action infra" }

# 1. Eventhouse (auto-creates a KQL database of the same name)
Write-Host "== Eventhouse + KQL database ==" -ForegroundColor Cyan
$ehId = New-FabricItemIfMissing $wsId "eventhouses" $cfg.EVENTHOUSE_NAME `
    @{ displayName=$cfg.EVENTHOUSE_NAME; description="Real-Time Intelligence eventhouse" } $h
Set-DotEnvValue "EVENTHOUSE_ID" $ehId
Start-Sleep 5
$kql = (Invoke-FabricGet "workspaces/$wsId/kqlDatabases" $h).value | Where-Object { $_.displayName -eq $cfg.EVENTHOUSE_NAME } | Select-Object -First 1
if (-not $kql) { throw "KQL database not visible yet - wait ~30s and re-run." }
Set-DotEnvValue "KQLDB_ID" $kql.id
$queryUri = $kql.properties.queryServiceUri
$dbName   = $kql.properties.databaseName; if (-not $dbName) { $dbName = $cfg.EVENTHOUSE_NAME }
Write-Host "[ok] KQL db '$dbName' @ $queryUri" -ForegroundColor Green

# 2. Best-effort: run the .create control commands from eventhouse_setup.kql
Write-Host "== Create StoreTelemetry table + mapping (best-effort) ==" -ForegroundColor Cyan
try {
    $ktoken = $null
    foreach ($res in @($queryUri, "https://kusto.fabric.microsoft.com", "https://api.kusto.windows.net")) {
        $ktoken = az account get-access-token --resource $res --query accessToken -o tsv 2>$null
        if ($ktoken) { Write-Host "[ok] kusto token via $res" -ForegroundColor DarkGray; break }
    }
    if (-not $ktoken) { throw "no kusto token (tried cluster URI + known resources)" }
    $raw = Get-Content (Join-Path $PSScriptRoot "eventhouse_setup.kql") -Raw
    $clean = (($raw -split "`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    $cmds = [regex]::Matches($clean, '(?ms)^\.create.*?(?=^\.create|^\s*StoreTelemetry|\Z)')
    $kh = @{ Authorization = "Bearer $ktoken"; "Content-Type" = "application/json" }
    foreach ($m in $cmds) {
        $body = @{ db = $dbName; csl = $m.Value.Trim() } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri "$queryUri/v1/rest/mgmt" -Headers $kh -Method Post -Body $body | Out-Null
        Write-Host "[ok] ran: $((($m.Value.Trim() -split "`n")[0]))" -ForegroundColor Green
    }
} catch {
    Write-Host "[warn] could not run KQL control commands via API: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Open the '$($cfg.EVENTHOUSE_NAME)' KQL queryset in the UI and paste eventhouse_setup.kql." -ForegroundColor Yellow
}

Write-Host "`nNext (UI): build the Eventstream (source = your Event Hub), Real-Time Dashboard, and Activator - see README." -ForegroundColor Magenta
Write-Host "Stream live data:  pwsh module-0-setup/setup.ps1 -Action send-events" -ForegroundColor Magenta
