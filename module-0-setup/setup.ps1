<#
.SYNOPSIS
  One script to set up, run, and tear down the Fabric demo. Driven by the repo .env.

.DESCRIPTION
  Actions:
    deps       Check/install dependencies (Azure CLI login + microsoft-fabric extension).
    provision  Create RG + capacity + workspaces + items + workspace identity (idempotent).
    data       Generate sample data and upload the CSVs to OneLake (Files/bronze).
    notebooks  Upload the module-1 notebooks (binds the default lakehouse).
    all        deps + provision + data + notebooks (full setup).
    run        Run notebooks headlessly and report pass/fail (smoke test).
    pause      Pause the capacity (stop billing).
    resume     Resume the capacity.
    status     Show capacity state.
    teardown   Delete the workspaces (optionally the capacity / resource group).

.EXAMPLE
  pwsh module-0-setup/setup.ps1 -Action all
  pwsh module-0-setup/setup.ps1 -Action run
  pwsh module-0-setup/setup.ps1 -Action pause
  pwsh module-0-setup/setup.ps1 -Action teardown -DeleteResourceGroup
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("deps","provision","data","notebooks","all","run","pause","resume","status","teardown")]
    [string]$Action,

    # run
    [string[]]$Notebooks = @("01_bronze_ingest","02_silver_transform","03_gold_aggregate","04_vorder_demo","05_shortcuts","06_cross_engine_reads"),
    [int]$TimeoutMinutes = 12,
    # data
    [int]$SalesRows = 50000, [int]$TelemetryEvents = 2000, [int]$Stores = 12, [int]$Products = 200, [int]$Seed = 42,
    # teardown
    [switch]$DeleteCapacity, [switch]$DeleteResourceGroup
)

$ErrorActionPreference = "Stop"
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$EnvPath    = Join-Path $RepoRoot ".env"
$DataDir    = Join-Path $PSScriptRoot "data"
$NotebookDir= Join-Path $RepoRoot "module-1-onelake-lakehouse"
$FabricBase = "https://api.fabric.microsoft.com/v1"

# ---------- .env helpers ----------
function Import-DotEnv {
    $path = $EnvPath
    if (-not (Test-Path $path)) {
        $example = Join-Path $RepoRoot ".env.example"
        if (Test-Path $example) { Write-Warning ".env not found - using .env.example defaults. Copy it to .env and fill it in."; $path = $example }
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
    if (-not (Test-Path $EnvPath)) { return }
    $found = $false
    $out = Get-Content $EnvPath | ForEach-Object {
        if ($_ -match "^\s*$([regex]::Escape($Key))\s*=") { $found = $true; "$Key=$Value" } else { $_ }
    }
    if (-not $found) { $out += "$Key=$Value" }
    Set-Content -Path $EnvPath -Value $out
}

# ---------- auth / REST helpers ----------
function Get-FabricHeaders {
    $t = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv 2>$null
    if (-not $t) { throw "Could not get a Fabric token. Run 'az login' (or: setup.ps1 -Action deps)." }
    return @{ Authorization = "Bearer $t"; "Content-Type" = "application/json" }
}
function Get-StorageHeaders {
    $t = az account get-access-token --resource "https://storage.azure.com" --query accessToken -o tsv 2>$null
    if (-not $t) { throw "Could not get a storage token. Run 'az login'." }
    return @{ Authorization = "Bearer $t"; "x-ms-version" = "2021-10-04" }
}
function Invoke-FabricGet([string]$Path, [hashtable]$Headers) { Invoke-RestMethod -Uri "$FabricBase/$Path" -Headers $Headers -Method Get }

function New-FabricItemIfMissing([string]$WorkspaceId, [string]$Collection, [string]$DisplayName, [hashtable]$Body, [hashtable]$Headers) {
    $existing = (Invoke-FabricGet "workspaces/$WorkspaceId/$Collection" $Headers).value | Where-Object { $_.displayName -eq $DisplayName }
    if ($existing) { Write-Host "[skip] $Collection/$DisplayName exists ($($existing.id))" -ForegroundColor DarkGray; return $existing.id }
    $resp = Invoke-WebRequest -Uri "$FabricBase/workspaces/$WorkspaceId/$Collection" -Headers $Headers -Method Post -Body ($Body | ConvertTo-Json -Depth 10)
    if ($resp.StatusCode -eq 202) {
        $op = @($resp.Headers["Location"])[0]; if (-not $op) { $op = @($resp.Headers["Operation-Location"])[0] }
        Write-Host "[wait] $Collection/$DisplayName provisioning..." -ForegroundColor Yellow
        for ($i=0; $i -lt 60; $i++) { Start-Sleep 5; $st = Invoke-RestMethod -Uri $op -Headers $Headers; if ($st.status -eq "Succeeded") { break }; if ($st.status -eq "Failed") { throw "Provisioning $DisplayName failed." } }
        $id = ((Invoke-FabricGet "workspaces/$WorkspaceId/$Collection" $Headers).value | Where-Object { $_.displayName -eq $DisplayName }).id
    } else { $id = ($resp.Content | ConvertFrom-Json).id }
    Write-Host "[ok]   $Collection/$DisplayName -> $id" -ForegroundColor Green
    return $id
}

# ---------- actions ----------
function Invoke-Deps {
    Write-Host "== Dependencies ==" -ForegroundColor Cyan
    $az = (Get-Command az -ErrorAction SilentlyContinue)
    if (-not $az) { throw "Azure CLI not found. Install it: https://aka.ms/installazcli (then re-run)." }
    Write-Host "[ok] Azure CLI: $((az version --query '\"azure-cli\"' -o tsv))" -ForegroundColor Green
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct) { Write-Host "Not logged in - launching 'az login'..." -ForegroundColor Yellow; az login | Out-Null; $acct = az account show -o json | ConvertFrom-Json }
    Write-Host "[ok] Logged in: $($acct.name)" -ForegroundColor Green
    Write-Host "Installing/updating the 'microsoft-fabric' CLI extension..." -ForegroundColor Yellow
    az extension add --upgrade --name microsoft-fabric --only-show-errors 2>$null
    Write-Host "[ok] microsoft-fabric extension: $((az extension show --name microsoft-fabric --query version -o tsv 2>$null))" -ForegroundColor Green
    Write-Host "Notebook libraries (pyspark, requests, notebookutils) ship with the Fabric runtime - nothing to install." -ForegroundColor DarkGray
    Write-Host "Optional: 'pip install ms-fabric-cli' for the interactive 'fab' CLI." -ForegroundColor DarkGray
}

function Invoke-Provision {
    $cfg = Import-DotEnv
    Write-Host "== Provision ==" -ForegroundColor Cyan
    $admin = $cfg.CAPACITY_ADMIN_UPN; if (-not $admin) { $admin = az ad signed-in-user show --query userPrincipalName -o tsv }
    az group create --name $cfg.RESOURCE_GROUP --location $cfg.REGION --only-show-errors | Out-Null
    az extension add --name microsoft-fabric --only-show-errors 2>$null
    $capObj = az fabric capacity show --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME -o json 2>$null | ConvertFrom-Json
    if (-not $capObj) {
        Write-Host "Creating capacity $($cfg.CAPACITY_NAME) ($($cfg.CAPACITY_SKU)) in $($cfg.REGION)..." -ForegroundColor Yellow
        az fabric capacity create --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME --administration "{members:[$admin]}" --sku "{name:$($cfg.CAPACITY_SKU),tier:Fabric}" --location $cfg.REGION | Out-Null
    } else { Write-Host "[skip] capacity exists (state $($capObj.state))" -ForegroundColor DarkGray }

    $h = Get-FabricHeaders
    $capId = ((Invoke-FabricGet "capacities" $h).value | Where-Object { $_.displayName -eq $cfg.CAPACITY_NAME }).id
    if (-not $capId) { throw "Capacity not visible to Fabric yet - wait ~1 min and re-run." }
    Set-DotEnvValue "FABRIC_CAPACITY_ID" $capId

    function Get-OrCreateWs($name) {
        $w = (Invoke-FabricGet "workspaces" $h).value | Where-Object { $_.displayName -eq $name }
        if (-not $w) { $w = Invoke-RestMethod -Uri "$FabricBase/workspaces" -Headers $h -Method Post -Body (@{ displayName=$name; capacityId=$capId } | ConvertTo-Json); Write-Host "[ok]   workspace $name -> $($w.id)" -ForegroundColor Green }
        else { Write-Host "[skip] workspace $name exists ($($w.id))" -ForegroundColor DarkGray }
        return $w.id
    }
    $wsId = Get-OrCreateWs $cfg.WORKSPACE_NAME
    $wsTestId = Get-OrCreateWs $cfg.TEST_WORKSPACE_NAME
    Set-DotEnvValue "WORKSPACE_ID" $wsId; Set-DotEnvValue "TEST_WORKSPACE_ID" $wsTestId

    # Workspace identity (Trusted Workspace Access / MPE)
    try {
        $wi = (Invoke-FabricGet "workspaces/$wsId" $h).workspaceIdentity
        if (-not $wi) {
            Write-Host "Provisioning workspace identity..." -ForegroundColor Yellow
            $r = Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/provisionIdentity" -Headers $h -Method Post -Body "{}"
            $op = @($r.Headers["Location"])[0]; if ($op) { for ($i=0;$i -lt 24;$i++){ Start-Sleep 5; $s=Invoke-RestMethod -Uri $op -Headers $h; if ($s.status -in @("Succeeded","Failed")){break} } }
            $wi = (Invoke-FabricGet "workspaces/$wsId" $h).workspaceIdentity
        } else { Write-Host "[skip] workspace identity exists" -ForegroundColor DarkGray }
        if ($wi) { Set-DotEnvValue "WORKSPACE_IDENTITY_APP_ID" $wi.applicationId; Set-DotEnvValue "WORKSPACE_IDENTITY_SP_ID" $wi.servicePrincipalId }
    } catch { Write-Host "[warn] workspace identity not provisioned: $($_.Exception.Message)" -ForegroundColor Yellow }

    $lhId  = New-FabricItemIfMissing $wsId "lakehouses"   $cfg.LAKEHOUSE_NAME  @{ displayName=$cfg.LAKEHOUSE_NAME;  description="Medallion lakehouse"; creationPayload=@{ enableSchemas=$true } } $h
    $whId  = New-FabricItemIfMissing $wsId "warehouses"   $cfg.WAREHOUSE_NAME  @{ displayName=$cfg.WAREHOUSE_NAME;  description="T-SQL serving warehouse" } $h
    $sqlId = New-FabricItemIfMissing $wsId "sqlDatabases" $cfg.SQLDB_NAME      @{ displayName=$cfg.SQLDB_NAME;      description="OLTP + auto-mirror" } $h
    $ehId  = New-FabricItemIfMissing $wsId "eventhouses"  $cfg.EVENTHOUSE_NAME @{ displayName=$cfg.EVENTHOUSE_NAME; description="Real-Time Intelligence eventhouse" } $h
    $kqlId = ((Invoke-FabricGet "workspaces/$wsId/kqlDatabases" $h).value | Where-Object { $_.displayName -eq $cfg.EVENTHOUSE_NAME }).id
    $pl = (Invoke-FabricGet "workspaces/$wsId/items" $h).value | Where-Object { $_.displayName -eq $cfg.PIPELINE_NAME -and $_.type -eq "DataPipeline" }
    if (-not $pl) { Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/items" -Headers $h -Method Post -Body (@{ displayName=$cfg.PIPELINE_NAME; type="DataPipeline"; description="Build Copy + Notebook activities live" } | ConvertTo-Json) | Out-Null; Write-Host "[ok]   pipeline $($cfg.PIPELINE_NAME)" -ForegroundColor Green }
    else { Write-Host "[skip] pipeline exists" -ForegroundColor DarkGray }

    Set-DotEnvValue "LAKEHOUSE_ID" $lhId; Set-DotEnvValue "WAREHOUSE_ID" $whId; Set-DotEnvValue "SQLDB_ID" $sqlId; Set-DotEnvValue "EVENTHOUSE_ID" $ehId; if ($kqlId) { Set-DotEnvValue "KQLDB_ID" $kqlId }
    Write-Host "Provisioned. IDs saved to .env." -ForegroundColor Cyan
}

function New-SampleData {
    Write-Host "== Generate sample data ==" -ForegroundColor Cyan
    $rng = [System.Random]::new($Seed)
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $cities = @("Dubai","Abu Dhabi","Sharjah","Riyadh","Jeddah","Doha","Manama","Kuwait City","Muscat","Cairo","Amman","Beirut")
    $cats   = @("Electronics","Grocery","Apparel","Home","Beauty","Sports","Toys","Books")
    (1..$Stores | ForEach-Object { [pscustomobject]@{ store_id=$_; store_name="Contoso $($cities[($_-1)%$cities.Count])"; city=$cities[($_-1)%$cities.Count]; region=@("North","Central","South")[$_%3] } }) | Export-Csv (Join-Path $DataDir "stores.csv") -NoTypeInformation
    (1..$Products | ForEach-Object { $c=$cats[$rng.Next(0,$cats.Count)]; [pscustomobject]@{ product_id=$_; product_name="$c Item $_"; category=$c; unit_price=[math]::Round(($rng.NextDouble()*490+10),2) } }) | Export-Csv (Join-Path $DataDir "products.csv") -NoTypeInformation
    $start = (Get-Date).AddDays(-365)
    $sw = [System.IO.StreamWriter]::new((Join-Path $DataDir "sales.csv")); $sw.WriteLine("sale_id,sale_ts,store_id,product_id,quantity,discount_pct")
    for ($i=1; $i -le $SalesRows; $i++) { $ts=$start.AddMinutes($rng.Next(0,525600)).ToString("yyyy-MM-dd HH:mm:ss"); $sw.WriteLine("$i,$ts,$($rng.Next(1,$Stores+1)),$($rng.Next(1,$Products+1)),$($rng.Next(1,6)),$(@(0,0,0,5,10,15,20)[$rng.Next(0,7)])") }
    $sw.Close()
    $sensors = @("freezer","hvac","foot_traffic","checkout_queue")
    $tw = [System.IO.StreamWriter]::new((Join-Path $DataDir "telemetry.ndjson"))
    for ($i=1; $i -le $TelemetryEvents; $i++) {
        $s=$sensors[$rng.Next(0,$sensors.Count)]
        switch ($s) { "freezer" {$v=[math]::Round(($rng.NextDouble()*12-4),1);$u="C"} "hvac" {$v=[math]::Round(($rng.NextDouble()*15+18),1);$u="C"} "foot_traffic" {$v=$rng.Next(0,120);$u="count"} "checkout_queue" {$v=$rng.Next(0,15);$u="people"} }
        $tw.WriteLine(([pscustomobject]@{ event_id=[guid]::NewGuid().ToString(); event_ts=(Get-Date).AddSeconds(-1*$rng.Next(0,3600)).ToUniversalTime().ToString("o"); store_id=$rng.Next(1,$Stores+1); sensor=$s; value=$v; unit=$u } | ConvertTo-Json -Compress))
    }
    $tw.Close()
    Write-Host "[ok] data in $DataDir" -ForegroundColor Green
}

function Send-Data {
    $cfg = Import-DotEnv
    Write-Host "== Upload data to OneLake ==" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $DataDir "sales.csv"))) { New-SampleData }
    $wsId = $cfg.WORKSPACE_ID; $lhId = $cfg.LAKEHOUSE_ID
    $sh = Get-StorageHeaders
    $root = "https://onelake.dfs.fabric.microsoft.com/$wsId/$lhId/$($cfg.BRONZE_FILES_PATH)"
    Get-ChildItem $DataDir -Filter *.csv | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName); $url = "$root/$($_.Name)"
        Invoke-WebRequest -Uri "${url}?resource=file" -Headers $sh -Method Put -ContentType "application/octet-stream" | Out-Null
        Invoke-WebRequest -Uri "${url}?action=append&position=0" -Headers $sh -Method Patch -Body $bytes -ContentType "application/octet-stream" | Out-Null
        Invoke-WebRequest -Uri "${url}?action=flush&position=$($bytes.Length)" -Headers $sh -Method Patch | Out-Null
        Write-Host "[ok] uploaded $($_.Name)" -ForegroundColor Green
    }
}

function Send-Notebooks {
    $cfg = Import-DotEnv
    Write-Host "== Upload notebooks ==" -ForegroundColor Cyan
    $h = Get-FabricHeaders
    $wsId = $cfg.WORKSPACE_ID; $lhId = $cfg.LAKEHOUSE_ID
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
}

function Invoke-RunNotebooks {
    $cfg = Import-DotEnv
    Write-Host "== Run notebooks (smoke test) ==" -ForegroundColor Cyan
    $h = Get-FabricHeaders; $wsId = $cfg.WORKSPACE_ID
    $all = (Invoke-FabricGet "workspaces/$wsId/notebooks" $h).value
    $results = @()
    foreach ($name in $Notebooks) {
        $nb = $all | Where-Object { $_.displayName -eq $name }
        if (-not $nb) { Write-Host "[skip] $name not found" -ForegroundColor DarkGray; continue }
        Write-Host "[run ] $name ..." -ForegroundColor Yellow -NoNewline
        $h = Get-FabricHeaders
        $resp = Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/items/$($nb.id)/jobs/instances?jobType=RunNotebook" -Headers $h -Method Post -Body "{}"
        $poll = @($resp.Headers["Location"])[0]; $deadline = (Get-Date).AddMinutes($TimeoutMinutes); $status = "Unknown"
        while ((Get-Date) -lt $deadline) {
            Start-Sleep 15
            try { $st = Invoke-RestMethod -Uri $poll -Headers (Get-FabricHeaders); $status = $st.status } catch { $status = "PollError" }
            if ($status -in @("Completed","Failed","Cancelled","Deduped")) { break }
            Write-Host "." -NoNewline
        }
        Write-Host " $status" -ForegroundColor $(if ($status -eq "Completed") {"Green"} else {"Red"})
        $results += [pscustomobject]@{ Notebook=$name; Status=$status }
    }
    Write-Host "`n==== Run summary ====" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    if ($results.Status -contains "Failed") { exit 1 }
}

function Set-Capacity([string]$Mode) {
    $cfg = Import-DotEnv
    if ($Mode -eq "pause")  { Write-Host "Pausing $($cfg.CAPACITY_NAME)..." -ForegroundColor Yellow; az fabric capacity suspend --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME }
    if ($Mode -eq "resume") { Write-Host "Resuming $($cfg.CAPACITY_NAME)..." -ForegroundColor Yellow; az fabric capacity resume  --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME }
    $c = az fabric capacity show --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME -o json | ConvertFrom-Json
    Write-Host ("Capacity {0}: state={1}, sku={2}, region={3}" -f $c.name, $c.state, $c.sku.name, $c.location) -ForegroundColor Cyan
}

function Invoke-Teardown {
    $cfg = Import-DotEnv
    $h = Get-FabricHeaders
    foreach ($name in @($cfg.WORKSPACE_NAME, $cfg.TEST_WORKSPACE_NAME)) {
        $w = (Invoke-FabricGet "workspaces" $h).value | Where-Object { $_.displayName -eq $name }
        if ($w) { Write-Host "Deleting workspace $name..." -ForegroundColor Yellow; Invoke-RestMethod -Uri "$FabricBase/workspaces/$($w.id)" -Headers $h -Method Delete | Out-Null; Write-Host "[ok] deleted" -ForegroundColor Green }
        else { Write-Host "[skip] $name not found" -ForegroundColor DarkGray }
    }
    if ($DeleteResourceGroup) { Write-Host "Deleting resource group $($cfg.RESOURCE_GROUP)..." -ForegroundColor Yellow; az group delete --name $cfg.RESOURCE_GROUP --yes --no-wait }
    elseif ($DeleteCapacity) { Write-Host "Deleting capacity $($cfg.CAPACITY_NAME)..." -ForegroundColor Yellow; az fabric capacity delete --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME --yes }
    Write-Host "Teardown complete." -ForegroundColor Cyan
}

# ---------- dispatch ----------
switch ($Action) {
    "deps"      { Invoke-Deps }
    "provision" { Invoke-Provision }
    "data"      { New-SampleData; Send-Data }
    "notebooks" { Send-Notebooks }
    "all"       { Invoke-Deps; Invoke-Provision; New-SampleData; Send-Data; Send-Notebooks; Write-Host "`nFull setup done. Pause when idle: setup.ps1 -Action pause" -ForegroundColor Magenta }
    "run"       { Invoke-RunNotebooks }
    "pause"     { Set-Capacity "pause" }
    "resume"    { Set-Capacity "resume" }
    "status"    { Set-Capacity "status" }
    "teardown"  { Invoke-Teardown }
}
