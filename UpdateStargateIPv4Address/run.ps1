using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "UpdateStargateIPv4Address function processed a request."

# Interact with query parameters or the body of the request.
$name = $Request.Query.Name
$zone = $Request.Query.Zone
$reqIP = $Request.Query.reqIP

if (-not $name) {
    $name = $Request.Body.Name
}

if (-not $zone) {
    $name = $Request.Body.Zone
}

if (-not $name) {
    $name = $Request.Body.Name
}

If ($name -and $zone -and $reqIP) {
    #Check if name passed is already in DNS zone that was passed
    Try {$CurrentRec=Get-AzDnsRecordSet -Name $name -RecordType A -ZoneName $zone -ResourceGroupName Standard}
    Catch { write-host "Caught an exception:" -ForegroundColor Red
            write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
            write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red }

            If ($CurrentRec) {
                Write-Host "There is a current A record for $name in zone $zone"
                
                # Check current record IP against requested IP
                $CurrIP=$CurrentRec.Records.Ipv4Address
                if ($CurrIP -ne $reqIP) {
                    Write-Host "IP Address $reqIP passed - updating DNS record accordingly"
                    $CurrentRec.Records[0].Ipv4Address = $reqIP
                    Set-AzDnsRecordSet -RecordSet $CurrentRec
                    $body = "Updated DNS record with requested IP $reqIP"
                    $status = [HttpStatusCode]::OK
                    Write-Host $body
                } else {
                    $body = "Requested IP and current DNS record match - no changes needed"
                    $status = [HttpStatusCode]::OK
                    Write-Host $body
                }
            } else {
                Write-Host "No current A record for $name in zone $zone, adding now."
                New-AzDnsRecordSet -Name $name -RecordType A -ZoneName $zone -ResourceGroupName Standard -Ttl 3600 -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $reqIP)
                $status = [HttpStatusCode]::OK
                $body = "DNS Record created with requested IP $reqIP"
                Write-Host $body
            }
        } else {
            $status = [HttpStatusCode]::BadRequest
            $body = "Please pass a name, zone, and reqIP on the query string or in the request body."
            Write-Host $body
        }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
