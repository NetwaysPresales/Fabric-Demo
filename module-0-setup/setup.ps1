<#
.SYNOPSIS
  Infrastructure + data-source setup for the Fabric demo. Driven by the repo .env.
  This script does NOT build per-module Fabric items - each module has its own run.ps1
  (or you follow the UI steps in that module's README).

.DESCRIPTION
  Actions:
    deps        Check/install dependencies (Azure CLI login + microsoft-fabric extension).
    infra       Everything below in one go: capacity + workspace + storage + eventhub + data.
    capacity    Create the Fabric capacity (if missing).
    workspace   Create the Fabric workspace on the capacity (the shared container for all modules).
    storage     Create an Azure Blob Storage account + container and upload the raw CSVs.
    eventhub    Create an Event Hubs namespace + hub (the streaming source for Module 5).
    connection  Create a Fabric cloud connection to the blob account (used by Module 1's Copy job).
    data        (Re)generate the local sample data only.
    send-events Stream telemetry.ndjson into the Event Hub (run during the Module 5 demo).
    pause       Pause the capacity (stop billing).
    resume      Resume the capacity.
    status      Show capacity state.
    teardown    Delete the workspace(s) (optionally the capacity / resource group).

.EXAMPLE
  pwsh module-0-setup/setup.ps1 -Action infra      # one-time foundation
  pwsh module-0-setup/setup.ps1 -Action resume     # before a demo
  pwsh module-0-setup/setup.ps1 -Action pause      # after a demo
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("deps","infra","capacity","workspace","storage","eventhub","connection","data","send-events","pause","resume","status","teardown")]
    [string]$Action,

    # data
    [int]$SalesRows = 50000, [int]$TelemetryEvents = 2000, [int]$Stores = 12, [int]$Products = 200, [int]$Seed = 42,
    # teardown
    [switch]$DeleteCapacity, [switch]$DeleteResourceGroup
)

. "$PSScriptRoot/common.ps1"

# ---------- dependencies ----------
function Invoke-Deps {
    Write-Host "== Dependencies ==" -ForegroundColor Cyan
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI not found: https://aka.ms/installazcli" }
    Write-Host "[ok] Azure CLI: $((az version --query '\"azure-cli\"' -o tsv))" -ForegroundColor Green
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct) { Write-Host "Logging in..." -ForegroundColor Yellow; az login | Out-Null; $acct = az account show -o json | ConvertFrom-Json }
    Write-Host "[ok] Logged in: $($acct.name)" -ForegroundColor Green
    az extension add --upgrade --name microsoft-fabric --only-show-errors 2>$null
    Write-Host "[ok] microsoft-fabric extension ready." -ForegroundColor Green
    Write-Host "Notebook libraries ship with the Fabric runtime - nothing to pip install." -ForegroundColor DarkGray
}

# ---------- capacity ----------
function New-Capacity {
    $cfg = Import-DotEnv
    Write-Host "== Fabric capacity ==" -ForegroundColor Cyan
    $admin = $cfg.CAPACITY_ADMIN_UPN; if (-not $admin) { $admin = az ad signed-in-user show --query userPrincipalName -o tsv }
    az group create --name $cfg.RESOURCE_GROUP --location $cfg.REGION --only-show-errors | Out-Null
    az extension add --name microsoft-fabric --only-show-errors 2>$null
    $cap = az fabric capacity show --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME -o json 2>$null | ConvertFrom-Json
    if (-not $cap) {
        Write-Host "Creating capacity $($cfg.CAPACITY_NAME) ($($cfg.CAPACITY_SKU))..." -ForegroundColor Yellow
        az fabric capacity create --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME `
            --administration "{members:[$admin]}" --sku "{name:$($cfg.CAPACITY_SKU),tier:Fabric}" --location $cfg.REGION | Out-Null
    } else { Write-Host "[skip] capacity exists (state $($cap.state))" -ForegroundColor DarkGray }
    $h = Get-FabricHeaders
    $capId = ((Invoke-FabricGet "capacities" $h).value | Where-Object { $_.displayName -eq $cfg.CAPACITY_NAME }).id
    if (-not $capId) { throw "Capacity not visible to Fabric yet - wait ~1 min and re-run." }
    Set-DotEnvValue "FABRIC_CAPACITY_ID" $capId
    Write-Host "[ok] capacity id $capId" -ForegroundColor Green
    return $capId
}

# ---------- workspace ----------
function New-Workspace {
    $cfg = Import-DotEnv
    Write-Host "== Fabric workspace ==" -ForegroundColor Cyan
    $h = Get-FabricHeaders
    $capId = $cfg.FABRIC_CAPACITY_ID
    if (-not $capId) { $capId = ((Invoke-FabricGet "capacities" $h).value | Where-Object { $_.displayName -eq $cfg.CAPACITY_NAME }).id }
    $wsId     = Get-OrCreateWorkspace $cfg.WORKSPACE_NAME      $capId $h
    $wsTestId = Get-OrCreateWorkspace $cfg.TEST_WORKSPACE_NAME $capId $h
    Set-DotEnvValue "WORKSPACE_ID" $wsId; Set-DotEnvValue "TEST_WORKSPACE_ID" $wsTestId
    # Workspace identity (used by Module 7 - Trusted Workspace Access / MPE). Best-effort.
    try {
        $wi = (Invoke-FabricGet "workspaces/$wsId" $h).workspaceIdentity
        if (-not $wi) {
            Write-Host "Provisioning workspace identity..." -ForegroundColor Yellow
            $r = Invoke-WebRequest -Uri "$FabricBase/workspaces/$wsId/provisionIdentity" -Headers $h -Method Post -Body "{}"
            Wait-FabricOperation $r $h 24
            $wi = (Invoke-FabricGet "workspaces/$wsId" $h).workspaceIdentity
        } else { Write-Host "[skip] workspace identity exists" -ForegroundColor DarkGray }
        if ($wi) { Set-DotEnvValue "WORKSPACE_IDENTITY_APP_ID" $wi.applicationId; Set-DotEnvValue "WORKSPACE_IDENTITY_SP_ID" $wi.servicePrincipalId }
    } catch { Write-Host "[warn] workspace identity not provisioned: $($_.Exception.Message)" -ForegroundColor Yellow }
    return $wsId
}

# ---------- sample data ----------
function New-SampleData {
    Write-Host "== Generate sample data ==" -ForegroundColor Cyan
    $rng = [System.Random]::new($Seed)
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    # US cities + states so Power BI can render a Filled/Shape map by state (Module 4).
    $usStores = @(
        @{ city="New York";     state="New York";      region="Northeast" },
        @{ city="Los Angeles";  state="California";    region="West" },
        @{ city="Chicago";      state="Illinois";      region="Midwest" },
        @{ city="Houston";      state="Texas";         region="South" },
        @{ city="Phoenix";      state="Arizona";       region="West" },
        @{ city="Philadelphia"; state="Pennsylvania";  region="Northeast" },
        @{ city="Seattle";      state="Washington";    region="West" },
        @{ city="Miami";        state="Florida";       region="South" },
        @{ city="Atlanta";      state="Georgia";       region="South" },
        @{ city="Denver";       state="Colorado";      region="West" },
        @{ city="Boston";       state="Massachusetts"; region="Northeast" },
        @{ city="Detroit";      state="Michigan";      region="Midwest" }
    )
    $cats   = @("Electronics","Grocery","Apparel","Home","Beauty","Sports","Toys","Books")
    (1..$Stores | ForEach-Object { $u=$usStores[($_-1)%$usStores.Count]; [pscustomobject]@{ store_id=$_; store_name="Contoso $($u.city)"; city=$u.city; state=$u.state; region=$u.region } }) | Export-Csv (Join-Path $DataDir "stores.csv") -NoTypeInformation
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

# ---------- storage ----------
function New-Storage {
    $cfg = Import-DotEnv
    Write-Host "== Blob storage (raw CSV source) ==" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $DataDir "sales.csv"))) { New-SampleData }
    $acct = $cfg.STORAGE_ACCOUNT_NAME
    if (-not $acct) { throw "Set STORAGE_ACCOUNT_NAME in .env (3-24 lowercase letters/numbers, globally unique)." }
    az group create --name $cfg.RESOURCE_GROUP --location $cfg.REGION --only-show-errors | Out-Null
    if (-not (az storage account show --name $acct --resource-group $cfg.RESOURCE_GROUP -o json 2>$null)) {
        Write-Host "Creating storage account $acct..." -ForegroundColor Yellow
        az storage account create --name $acct --resource-group $cfg.RESOURCE_GROUP --location $cfg.REGION `
            --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --only-show-errors | Out-Null
    } else { Write-Host "[skip] storage account exists" -ForegroundColor DarkGray }
    $key = az storage account keys list --account-name $acct --resource-group $cfg.RESOURCE_GROUP --query "[0].value" -o tsv
    az storage container create --name $cfg.STORAGE_CONTAINER --account-name $acct --account-key $key --only-show-errors | Out-Null
    $prefix = $cfg.STORAGE_RAW_PREFIX
    Get-ChildItem $DataDir -Filter *.csv | ForEach-Object {
        $dest = if ($prefix) { "$prefix/$($_.Name)" } else { $_.Name }
        az storage blob upload --account-name $acct --account-key $key --container-name $cfg.STORAGE_CONTAINER `
            --name $dest --file $_.FullName --overwrite --only-show-errors | Out-Null
        Write-Host "[ok] uploaded $dest" -ForegroundColor Green
    }
    Write-Host "[ok] raw CSVs at https://$acct.blob.core.windows.net/$($cfg.STORAGE_CONTAINER)/$prefix/" -ForegroundColor Cyan
}

# ---------- event hub (Module 5 streaming source) ----------
function New-EventHub {
    $cfg = Import-DotEnv
    Write-Host "== Event Hubs (Module 5 streaming source) ==" -ForegroundColor Cyan
    $ns = $cfg.EVENTHUB_NAMESPACE; $hub = $cfg.EVENTHUB_NAME
    if (-not $ns) { throw "Set EVENTHUB_NAMESPACE in .env (globally unique)." }
    az group create --name $cfg.RESOURCE_GROUP --location $cfg.REGION --only-show-errors | Out-Null
    if (-not (az eventhubs namespace show --resource-group $cfg.RESOURCE_GROUP --name $ns -o json 2>$null)) {
        Write-Host "Creating Event Hubs namespace $ns..." -ForegroundColor Yellow
        az eventhubs namespace create --resource-group $cfg.RESOURCE_GROUP --name $ns --location $cfg.REGION --sku Standard --only-show-errors | Out-Null
    } else { Write-Host "[skip] namespace exists" -ForegroundColor DarkGray }
    if (-not (az eventhubs eventhub show --resource-group $cfg.RESOURCE_GROUP --namespace-name $ns --name $hub -o json 2>$null)) {
        az eventhubs eventhub create --resource-group $cfg.RESOURCE_GROUP --namespace-name $ns --name $hub --partition-count 2 --cleanup-policy Delete --retention-time 24 --only-show-errors | Out-Null
        Write-Host "[ok] event hub $hub" -ForegroundColor Green
    } else { Write-Host "[skip] event hub exists" -ForegroundColor DarkGray }
    $conn = az eventhubs namespace authorization-rule keys list --resource-group $cfg.RESOURCE_GROUP --namespace-name $ns --name RootManageSharedAccessKey --query primaryConnectionString -o tsv
    Set-DotEnvValue "EVENTHUB_CONNECTION_STRING" $conn
    Write-Host "[ok] connection string saved to .env (EVENTHUB_CONNECTION_STRING)" -ForegroundColor Green
    Write-Host "In Module 5, add an Eventstream source = Azure Event Hubs -> namespace '$ns', hub '$hub'." -ForegroundColor Cyan
}

# Build a Service Bus / Event Hubs SAS token from a connection string.
function Get-EventHubSas([string]$ConnectionString) {
    $ep = ($ConnectionString -split ";" | Where-Object { $_ -like "Endpoint=*" }) -replace "Endpoint=sb://","" -replace "/$",""
    $kn = (($ConnectionString -split ";" | Where-Object { $_ -like "SharedAccessKeyName=*" }) -split "=",2)[1]
    $kv = (($ConnectionString -split ";" | Where-Object { $_ -like "SharedAccessKey=*" }) -split "=",2)[1]
    $uri = [System.Web.HttpUtility]::UrlEncode("https://$ep")
    $exp = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s)) + 3600
    $sig = "$uri`n$exp"
    $h = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($kv))
    $hash = [Convert]::ToBase64String($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($sig)))
    $hashEnc = [System.Web.HttpUtility]::UrlEncode($hash)
    return @{ Host = $ep; Token = "SharedAccessSignature sr=$uri&sig=$hashEnc&se=$exp&skn=$kn" }
}

function Send-Events {
    Add-Type -AssemblyName System.Web
    $cfg = Import-DotEnv
    Write-Host "== Stream telemetry into Event Hub ==" -ForegroundColor Cyan
    if (-not $cfg.EVENTHUB_CONNECTION_STRING) { throw "No EVENTHUB_CONNECTION_STRING in .env. Run: setup.ps1 -Action eventhub" }
    if (-not (Test-Path (Join-Path $DataDir "telemetry.ndjson"))) { New-SampleData }
    $sas = Get-EventHubSas $cfg.EVENTHUB_CONNECTION_STRING
    $url = "https://$($sas.Host)/$($cfg.EVENTHUB_NAME)/messages?api-version=2014-01"
    $headers = @{ Authorization = $sas.Token; "Content-Type" = "application/json" }
    $n = 0; $fail = 0
    Get-Content (Join-Path $DataDir "telemetry.ndjson") | ForEach-Object {
        $line = $_
        for ($try = 0; $try -lt 3; $try++) {
            try { Invoke-WebRequest -Uri $url -Headers $headers -Method Post -Body $line | Out-Null; $n++; break }
            catch { Start-Sleep -Milliseconds 500; if ($try -eq 2) { $fail++ } }
        }
        if ($n % 100 -eq 0 -and $n -gt 0) { Write-Host "  sent $n events..." -ForegroundColor DarkGray }
    }
    Write-Host "[ok] sent $n events to $($cfg.EVENTHUB_NAME)$(if ($fail) { " ($fail failed)" })" -ForegroundColor Green
}

# ---------- blob connection (used by Module 1 Copy job) ----------
function New-BlobConnection {
    $cfg = Import-DotEnv
    Write-Host "== Fabric cloud connection to Blob ==" -ForegroundColor Cyan
    $h = Get-FabricHeaders
    $acct = $cfg.STORAGE_ACCOUNT_NAME
    if (-not $acct) { throw "Set STORAGE_ACCOUNT_NAME and run -Action storage first." }
    $name = "conn_$acct"
    $existing = (Invoke-RestMethod -Uri "$FabricBase/connections" -Headers $h).value | Where-Object { $_.displayName -eq $name }
    if ($existing) { Write-Host "[skip] connection exists ($($existing.id))" -ForegroundColor DarkGray; Set-DotEnvValue "BLOB_CONNECTION_ID" $existing.id; return }
    $key = az storage account keys list --account-name $acct --resource-group $cfg.RESOURCE_GROUP --query "[0].value" -o tsv
    $body = @{
        connectivityType  = "ShareableCloud"; displayName = $name
        connectionDetails = @{ type="AzureBlobs"; creationMethod="AzureBlobs"; parameters=@(
            @{ dataType="Text"; name="account"; value=$acct }, @{ dataType="Text"; name="domain"; value="blob.core.windows.net" }) }
        privacyLevel      = "Organizational"
        credentialDetails = @{ singleSignOnType="None"; connectionEncryption="NotEncrypted"; skipTestConnection=$false; credentials=@{ credentialType="Key"; key=$key } }
    }
    try {
        $r = Invoke-RestMethod -Uri "$FabricBase/connections" -Headers $h -Method Post -Body ($body | ConvertTo-Json -Depth 10)
        Write-Host "[ok] connection $name -> $($r.id)" -ForegroundColor Green; Set-DotEnvValue "BLOB_CONNECTION_ID" $r.id
    } catch { Write-Host "[warn] could not create connection via API: $($_.Exception.Message). Create it in the UI." -ForegroundColor Yellow }
}

# ---------- capacity billing ----------
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
    if ($DeleteResourceGroup) { Write-Host "Deleting resource group..." -ForegroundColor Yellow; az group delete --name $cfg.RESOURCE_GROUP --yes --no-wait }
    elseif ($DeleteCapacity) { Write-Host "Deleting capacity..." -ForegroundColor Yellow; az fabric capacity delete --resource-group $cfg.RESOURCE_GROUP --capacity-name $cfg.CAPACITY_NAME --yes }
    Write-Host "Teardown complete." -ForegroundColor Cyan
}

# ---------- dispatch ----------
switch ($Action) {
    "deps"        { Invoke-Deps }
    "capacity"    { New-Capacity | Out-Null }
    "workspace"   { New-Workspace | Out-Null }
    "storage"     { New-Storage }
    "eventhub"    { New-EventHub }
    "connection"  { New-BlobConnection }
    "data"        { New-SampleData }
    "send-events" { Send-Events }
    "infra"       { Invoke-Deps; New-Capacity | Out-Null; New-Workspace | Out-Null; New-SampleData; New-Storage; New-BlobConnection; New-EventHub; Write-Host "`nInfra ready. Now run each module's run.ps1 or follow its README. Pause when idle: setup.ps1 -Action pause" -ForegroundColor Magenta }
    "pause"       { Set-Capacity "pause" }
    "resume"      { Set-Capacity "resume" }
    "status"      { Set-Capacity "status" }
    "teardown"    { Invoke-Teardown }
}
