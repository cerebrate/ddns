Set-StrictMode -Version Latest

if (-not ('HttpResponseContext' -as [type])) {
    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
}

function New-TestRequest {
    param(
        [hashtable]$Query = @{},
        [hashtable]$Body = @{}
    )

    $queryObject = [pscustomobject]@{
        Name = $null
        Zone = $null
        reqIP = $null
    }

    foreach ($key in $Query.Keys) {
        $queryObject.$key = $Query[$key]
    }

    $bodyObject = [pscustomobject]@{
        Name = $null
        Zone = $null
        reqIP = $null
    }

    foreach ($key in $Body.Keys) {
        $bodyObject.$key = $Body[$key]
    }

    [pscustomobject]@{
        Query = $queryObject
        Body = $bodyObject
    }
}

function Set-TestAzMocks {
    param(
        [ValidateSet('existing', 'missing', 'throw')]
        [string]$LookupMode = 'missing',

        [string]$CurrentIp = '',

        [ValidateSet('IPv4', 'IPv6')]
        [string]$IpKind
    )

    $global:SetCalled = $false
    $global:NewCalled = $false
    $global:SetRecord = $null
    $global:NewRecord = $null
    $global:TestLookupMode = $LookupMode
    $global:TestCurrentIp = $CurrentIp
    $global:TestIpKind = $IpKind

    function global:Get-AzDnsRecordSet {
        param($Name, $RecordType, $ZoneName, $ResourceGroupName, $ErrorAction)

        if ($global:TestLookupMode -eq 'throw') {
            throw 'Simulated DNS lookup failure'
        }

        if ($global:TestLookupMode -eq 'missing') {
            return $null
        }

        if ($global:TestIpKind -eq 'IPv4') {
            $record = [pscustomobject]@{ Ipv4Address = $global:TestCurrentIp }
        }
        else {
            $record = [pscustomobject]@{ Ipv6Address = $global:TestCurrentIp }
        }

        return [pscustomobject]@{ Records = @($record) }
    }

    function global:Set-AzDnsRecordSet {
        param($RecordSet)
        $global:SetCalled = $true
        $global:SetRecord = $RecordSet
    }

    function global:New-AzDnsRecordConfig {
        param($Ipv4Address, $Ipv6Address)
        return [pscustomobject]@{
            Ipv4Address = $Ipv4Address
            Ipv6Address = $Ipv6Address
        }
    }

    function global:New-AzDnsRecordSet {
        param(
            $Name,
            $RecordType,
            $ZoneName,
            $ResourceGroupName,
            $Ttl,
            $DnsRecords
        )

        $global:NewCalled = $true
        $global:NewRecord = [pscustomobject]@{
            Name = $Name
            RecordType = $RecordType
            ZoneName = $ZoneName
            ResourceGroupName = $ResourceGroupName
            Ttl = $Ttl
            DnsRecords = $DnsRecords
        }
    }
}

function Invoke-FunctionScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        $Request
    )

    $global:CapturedResponse = $null

    function global:Push-OutputBinding {
        param($Name, $Value)
        $global:CapturedResponse = $Value
    }

    $null = & $ScriptPath -Request $Request -TriggerMetadata @{}

    if ($null -eq $global:CapturedResponse) {
        throw 'Push-OutputBinding did not capture a response.'
    }

    $statusCode = $null
    $body = $null

    if ($global:CapturedResponse -is [hashtable]) {
        $statusCode = $global:CapturedResponse['StatusCode']
        $body = $global:CapturedResponse['Body']
    }
    else {
        $statusCode = $global:CapturedResponse.StatusCode
        $body = $global:CapturedResponse.Body
    }

    return [pscustomobject]@{
        StatusCode = $statusCode
        Body = $body
    }
}

function Clear-TestFunctions {
    $functionNames = @(
        'Get-AzDnsRecordSet',
        'Set-AzDnsRecordSet',
        'New-AzDnsRecordConfig',
        'New-AzDnsRecordSet',
        'Push-OutputBinding'
    )

    foreach ($name in $functionNames) {
        if (Test-Path "Function:\global:$name") {
            Remove-Item "Function:\global:$name" -Force
        }
    }

    $global:CapturedResponse = $null
    $global:SetCalled = $false
    $global:NewCalled = $false
    $global:SetRecord = $null
    $global:NewRecord = $null
    $global:TestLookupMode = $null
    $global:TestCurrentIp = $null
    $global:TestIpKind = $null
}
