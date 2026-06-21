<#
  Module 3 - code path. Creates the Fabric SQL database and runs the OLTP seed:
    1. Create sqldb_orders (if missing).
    2. Run oltp_seed.sql (schema + insert a few orders).
  Mirroring to OneLake Delta happens automatically (~30s) - watch it in the SQL analytics endpoint.

  Or follow the UI steps in this folder's README instead.

  Usage: pwsh module-3-sql-database-mirroring/run.ps1
#>
. "$PSScriptRoot/../module-0-setup/common.ps1"

$cfg = Import-DotEnv
$h = Get-FabricHeaders
$wsId = $cfg.WORKSPACE_ID
if (-not $wsId) { throw "No WORKSPACE_ID in .env. Run: pwsh module-0-setup/setup.ps1 -Action infra" }

# 1. SQL database
Write-Host "== SQL database ==" -ForegroundColor Cyan
$sqlId = New-FabricItemIfMissing $wsId "sqlDatabases" $cfg.SQLDB_NAME `
    @{ displayName=$cfg.SQLDB_NAME; description="OLTP + auto-mirror to OneLake" } $h
Set-DotEnvValue "SQLDB_ID" $sqlId

# Resolve server FQDN + database name
$sqldb = Invoke-FabricGet "workspaces/$wsId/sqlDatabases/$sqlId" $h
$server = $sqldb.properties.serverFqdn
$db = $sqldb.properties.databaseName
if (-not $server) { throw "SQL database not ready yet - wait ~30s and re-run." }
Write-Host "[ok] server: $server / $db" -ForegroundColor Green

# 2. Run the OLTP seed
Write-Host "== Run oltp_seed.sql ==" -ForegroundColor Cyan
$sql = Get-Content (Join-Path $PSScriptRoot "oltp_seed.sql") -Raw
Invoke-FabricSql $server $db $sql
Write-Host "[ok] orders seeded" -ForegroundColor Green
Write-Host "`nEnd result: dbo.Orders + dbo.OrderItems written. Within ~30s they mirror to OneLake Delta" -ForegroundColor Magenta
Write-Host "(open the sqldb_orders SQL analytics endpoint to see them). Continue with Module 4 (UI)." -ForegroundColor Magenta
