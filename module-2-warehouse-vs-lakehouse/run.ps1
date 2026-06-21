<#
  Module 2 - code path. Creates the warehouse and runs the SQL end-to-end:
    1. Create wh_retail (if missing).
    2. Run warehouse_ddl.sql  (build dim_store + fact_sales_daily FROM the lakehouse gold, multi-table tran).
    3. Run cross_query.sql    (warehouse table JOIN lakehouse table - one T-SQL surface).

  Prereq: Module 1 has produced the gold tables (lh_retail.gold.*).
  Or follow the UI steps in this folder's README instead.

  Usage: pwsh module-2-warehouse-vs-lakehouse/run.ps1
#>
. "$PSScriptRoot/../module-0-setup/common.ps1"

$cfg = Import-DotEnv
$h = Get-FabricHeaders
$wsId = $cfg.WORKSPACE_ID
if (-not $wsId) { throw "No WORKSPACE_ID in .env. Run: pwsh module-0-setup/setup.ps1 -Action infra" }

# 1. Warehouse
Write-Host "== Warehouse ==" -ForegroundColor Cyan
$whId = New-FabricItemIfMissing $wsId "warehouses" $cfg.WAREHOUSE_NAME `
    @{ displayName=$cfg.WAREHOUSE_NAME; description="T-SQL serving warehouse" } $h
Set-DotEnvValue "WAREHOUSE_ID" $whId

# Resolve the SQL connection string (server). DB name = warehouse display name.
$wh = Invoke-FabricGet "workspaces/$wsId/warehouses/$whId" $h
$server = $wh.properties.connectionString
if (-not $server) { throw "Warehouse has no connectionString yet - wait ~30s and re-run." }
$db = $cfg.WAREHOUSE_NAME
Write-Host "[ok] SQL endpoint: $server / $db" -ForegroundColor Green

# 2 + 3. Run the SQL scripts
foreach ($f in @("warehouse_ddl.sql","cross_query.sql")) {
    Write-Host "== Run $f ==" -ForegroundColor Cyan
    $sql = Get-Content (Join-Path $PSScriptRoot $f) -Raw
    Invoke-FabricSql $server $db $sql
    Write-Host "[ok] $f executed" -ForegroundColor Green
}
Write-Host "`nEnd result: dbo.dim_store + dbo.fact_sales_daily in $($cfg.WAREHOUSE_NAME), built from the lakehouse gold. Continue with Module 3." -ForegroundColor Magenta
