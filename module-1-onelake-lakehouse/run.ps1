<#
  Module 1 - code path. Builds the medallion end-to-end:
    1. Create the lakehouse (schemas enabled) if missing.
    2. Upload the raw CSVs to Files/bronze (so the notebooks have input).
    3. Upload the notebooks (with the default lakehouse bound).
    4. Run 00->04 headlessly and report pass/fail.

  Prereq: setup.ps1 -Action infra (workspace + storage + data must exist).
  Or just follow the UI steps in this folder's README instead.

  Usage:
    pwsh module-1-onelake-lakehouse/run.ps1            # full module
    pwsh module-1-onelake-lakehouse/run.ps1 -SkipRun   # build only, don't execute
#>
param([switch]$SkipRun, [int]$TimeoutMinutes = 12)

. "$PSScriptRoot/../module-0-setup/common.ps1"
$NotebookDir = $PSScriptRoot
$RunOrder = @("01_bronze_ingest","02_silver_transform","03_gold_aggregate","04_vorder_demo")

$cfg = Import-DotEnv
$h = Get-FabricHeaders
$wsId = $cfg.WORKSPACE_ID
if (-not $wsId) { throw "No WORKSPACE_ID in .env. Run: pwsh module-0-setup/setup.ps1 -Action infra" }

# 1. Lakehouse
Write-Host "== Lakehouse ==" -ForegroundColor Cyan
$lhId = New-FabricItemIfMissing $wsId "lakehouses" $cfg.LAKEHOUSE_NAME `
    @{ displayName=$cfg.LAKEHOUSE_NAME; description="Medallion lakehouse"; creationPayload=@{ enableSchemas=$true } } $h
Set-DotEnvValue "LAKEHOUSE_ID" $lhId

# 2. Upload raw CSVs to Files/bronze (code path; the UI path uses the Copy job instead)
Write-Host "== Upload CSVs to OneLake Files/bronze ==" -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $DataDir "sales.csv"))) { throw "No sample data. Run: setup.ps1 -Action data" }
$sh = Get-StorageHeaders
$root = "https://onelake.dfs.fabric.microsoft.com/$wsId/$lhId/$($cfg.BRONZE_FILES_PATH)"
Get-ChildItem $DataDir -Filter *.csv | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName); $url = "$root/$($_.Name)"
    Invoke-WebRequest -Uri "${url}?resource=file" -Headers $sh -Method Put -ContentType "application/octet-stream" | Out-Null
    Invoke-WebRequest -Uri "${url}?action=append&position=0" -Headers $sh -Method Patch -Body $bytes -ContentType "application/octet-stream" | Out-Null
    Invoke-WebRequest -Uri "${url}?action=flush&position=$($bytes.Length)" -Headers $sh -Method Patch | Out-Null
    Write-Host "[ok] uploaded $($_.Name)" -ForegroundColor Green
}

# 3. Upload notebooks (bind the default lakehouse)
Write-Host "== Upload notebooks ==" -ForegroundColor Cyan
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
Write-Host "[ok] default lakehouse '$($cfg.LAKEHOUSE_NAME)' bound into each notebook." -ForegroundColor Cyan

if ($SkipRun) { Write-Host "`n-SkipRun set. Open the notebooks in Fabric and run them, or re-run without -SkipRun." -ForegroundColor Magenta; return }

# 4. Run notebooks headlessly
Write-Host "== Run notebooks (00 -> 04) ==" -ForegroundColor Cyan
Start-Sleep 5   # let the just-created notebooks register
$all = (Invoke-FabricGet "workspaces/$wsId/notebooks" $h).value
$results = @()
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
    $results += [pscustomobject]@{ Notebook=$name; Status=$status }
}
Write-Host "`n==== Module 1 run summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "End result: bronze/silver/gold tables in $($cfg.LAKEHOUSE_NAME). Continue with Module 2." -ForegroundColor Magenta
