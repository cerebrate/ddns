using namespace System.Net
using namespace System.Net.Sockets

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "UpdateStargateIPv6Address function processed a request."

# Resolve runtime settings with safe defaults.
$defaultResourceGroupName = "Standard"
$resourceGroupName = $env:DDNS_RESOURCE_GROUP

if ($null -ne $resourceGroupName) {
    $resourceGroupName = $resourceGroupName.ToString().Trim()
}

if (-not $resourceGroupName) {
    $resourceGroupName = $defaultResourceGroupName
}

$defaultTtl = 3600
$ttl = $defaultTtl
$ttlSetting = $env:DDNS_TTL

if ($null -ne $ttlSetting) {
    $ttlSetting = $ttlSetting.ToString().Trim()
}

if ($ttlSetting) {
    $parsedTtl = 0
    $isValidTtl = [int]::TryParse($ttlSetting, [ref]$parsedTtl) -and ($parsedTtl -gt 0)

    if ($isValidTtl) {
        $ttl = $parsedTtl
    } else {
        Write-Host "Invalid DDNS_TTL app setting '$ttlSetting' - using default TTL $defaultTtl"
    }
}

# Parse from query string first, then fall back to request body.
$name = $Request.Query.Name
$zone = $Request.Query.Zone
$reqIP = $Request.Query.reqIP

if (-not $name) {
    $name = $Request.Body.Name
}

if (-not $zone) {
    $zone = $Request.Body.Zone
}

if (-not $reqIP) {
    $reqIP = $Request.Body.reqIP
}

# Normalize values to avoid whitespace-only input issues.
if ($null -ne $name) {
    $name = $name.ToString().Trim()
}

if ($null -ne $zone) {
    $zone = $zone.ToString().Trim()
}

if ($null -ne $reqIP) {
    $reqIP = $reqIP.ToString().Trim()
}

if (-not ($name -and $zone -and $reqIP)) {
    $status = [HttpStatusCode]::BadRequest
    $body = "Please pass a name, zone, and reqIP on the query string or in the request body."
    Write-Host $body
}
else {
    # Validate reqIP is specifically an IPv6 address for AAAA records.
    [IPAddress]$parsedReqIP = $null
    $isParsableIP = [System.Net.IPAddress]::TryParse($reqIP, [ref]$parsedReqIP)
    $isValidReqIP = $isParsableIP -and ($parsedReqIP.AddressFamily -eq [AddressFamily]::InterNetworkV6)

    if (-not $isValidReqIP) {
        $status = [HttpStatusCode]::BadRequest
        $body = "Invalid reqIP format. Please pass a valid IPv6 address."
        Write-Host $body
    }
    else {
        # Lookup current record and then decide between update, no-op, or create.
        $currentRecord = $null
        $lookupFailed = $false

        try {
            $currentRecord = Get-AzDnsRecordSet -Name $name -RecordType AAAA -ZoneName $zone -ResourceGroupName $resourceGroupName -ErrorAction Stop
        }
        catch {
            Write-Host "Caught an exception:" -ForegroundColor Red
            Write-Host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
            Write-Host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
            $lookupFailed = $true
            $status = [HttpStatusCode]::InternalServerError
            $body = "DNS lookup failed. No changes were applied."
            Write-Host $body
        }

        if (-not $lookupFailed) {
            if ($currentRecord) {
                Write-Host "There is a current AAAA record for $name in zone $zone"

                $currentIp = $currentRecord.Records.Ipv6Address
                if ($currentIp -ne $reqIP) {
                    Write-Host "IP Address $reqIP passed - updating DNS record accordingly"
                    $currentRecord.Records[0].Ipv6Address = $reqIP
                    Set-AzDnsRecordSet -RecordSet $currentRecord
                    $body = "Updated DNS record with requested IP $reqIP"
                    $status = [HttpStatusCode]::OK
                    Write-Host $body
                }
                else {
                    $body = "Requested IP and current DNS record match - no changes needed"
                    $status = [HttpStatusCode]::OK
                    Write-Host $body
                }
            }
            else {
                Write-Host "No current AAAA record for $name in zone $zone, adding now."
                New-AzDnsRecordSet -Name $name -RecordType AAAA -ZoneName $zone -ResourceGroupName $resourceGroupName -Ttl $ttl -DnsRecords (New-AzDnsRecordConfig -Ipv6Address $reqIP)
                $status = [HttpStatusCode]::OK
                $body = "DNS Record created with requested IP $reqIP"
                Write-Host $body
            }
        }
    }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
