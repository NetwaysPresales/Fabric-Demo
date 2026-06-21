<#
  Module 6 - code path. Trains + registers + scores an ML model on the gold layer:
    1. Ensure the lakehouse exists (created in Module 1).
    2. Upload ml_sales_forecast.ipynb (default lakehouse bound).
    3. Run it headlessly: MLflow train + register, write gold.sales_predictions.

  Prereq: Module 1 produced gold.sales_by_store_day.
  Or follow the UI steps in this folder's README instead.

  Usage:
    pwsh module-6-machine-learning/run.ps1            # build + run
    pwsh module-6-machine-learning/run.ps1 -SkipRun   # upload only
#>
param([switch]$SkipRun, [int]$TimeoutMinutes = 15)

. "$PSScriptRoot/../module-0-setup/common.ps1"
$NotebookDir = $PSScriptRoot
$RunOrder = @("ml_sales_forecast")

$cfg = Import-DotEnv
$h = Get-FabricHeaders
$wsId = $cfg.WORKSPACE_ID
if (-not $wsId) { throw "No WORKSPACE_ID in .env. Run: pwsh module-0-setup/setup.ps1 -Action infra" }

# 1. Lakehouse must exist (Module 1)
$lhId = $cfg.LAKEHOUSE_ID
if (-not $lhId) {
    $lhId = ((Invoke-FabricGet "workspaces/$wsId/lakehouses" $h).value | Where-Object { $_.displayName -eq $cfg.LAKEHOUSE_NAME }).id
}
if (-not $lhId) { throw "Lakehouse '$($cfg.LAKEHOUSE_NAME)' not found. Run Module 1 first (it builds the gold tables)." }
Write-Host "[ok] lakehouse $($cfg.LAKEHOUSE_NAME) -> $lhId" -ForegroundColor Green

# 2. Upload the notebook (bind default lakehouse)
Write-Host "== Upload ML notebook ==" -ForegroundColor Cyan
$existing = (Invoke-FabricGet "workspaces/$wsId/notebooks" $h).value
Get-ChildItem $NotebookDir -Filter *.ipynb | Sort-Object Name | ForEach-Object {
    $name = $_.BaseName
    $nb = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if (-not $nb.metadata) { $nb | Add-Member -NotePropertyName metadata -NotePropertyValue ([pscustomobject]@{}) -Force }
    $lh = [pscustomobject]@{ default_lakehouse=$lhId; default_lakehouse_name=$cfg.LAKEHOUSE_NAME; default_lakehouse_workspace_id=$wsId; known_lakehouses=@([pscustomobject]@{ id=$lhId }) }
    $nb.metadata | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{ lakehouse=$lh }) -Force
    $b64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($nb | ConvertTo-Json -Depth 50)))
    $def = @{ format="ipynb"; parts=@(@{ path="notebook-content.ipynb"; payload=$b64; payloadType="InlineBase64" }) }
    $m = $existing | Where-Object { $_.displayName -eq $name }
    if ($m) { Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/notebooks/$($m.id)/updateDefinition" -Headers $h -Method Post -Body (@{ definition=$def } | ConvertTo-Json -Depth 20) | Out-Null; Write-Host "[update] $name" -ForegroundColor Green }
    else { Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/notebooks" -Headers $h -Method Post -Body (@{ displayName=$name; definition=$def } | ConvertTo-Json -Depth 20) | Out-Null; Write-Host "[create] $name" -ForegroundColor Green }
}

if ($SkipRun) { Write-Host "`n-SkipRun set. Open ml_sales_forecast in Fabric and run it." -ForegroundColor Magenta; return }

# 3. Run headlessly
Write-Host "== Run ML notebook ==" -ForegroundColor Cyan
Start-Sleep 5
$all = (Invoke-FabricGet "workspaces/$wsId/notebooks" $h).value
foreach ($name in $RunOrder) {
    $nb = $all | Where-Object { $_.displayName -eq $name }
    if (-not $nb) { Start-Sleep 5; $all = (Invoke-FabricGet "workspaces/$wsId/notebooks" $h).value; $nb = $all | Where-Object { $_.displayName -eq $name } }
    if (-not $nb) { Write-Host "[skip] $name not found" -ForegroundColor DarkGray; continue }
    Write-Host "[run ] $name ..." -ForegroundColor Yellow -NoNewline
    $resp = Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/items/$($nb.id)/jobs/instances?jobType=RunNotebook" -Headers (Get-FabricHeaders) -Method Post -Body "{}"
    $poll = @($resp.Headers["Location"])[0]; $deadline = (Get-Date).AddMinutes($TimeoutMinutes); $status = "Unknown"
    while ((Get-Date) -lt $deadline) {
        Start-Sleep 15
        try { $status = (Invoke-RestMethod -Uri $poll -Headers (Get-FabricHeaders)).status } catch { $status = "PollError" }
        if ($status -in @("Completed","Failed","Cancelled","Deduped")) { break }
        Write-Host "." -NoNewline
    }
    Write-Host " $status" -ForegroundColor $(if ($status -eq "Completed") {"Green"} else {"Red"})
}
Write-Host "`nEnd result: MLflow experiment 'retail-sales-forecast' + registered model 'retail_sales_forecaster' + gold.sales_predictions." -ForegroundColor Magenta
