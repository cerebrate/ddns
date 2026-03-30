Set-StrictMode -Version Latest

# BeforeAll loads helpers into the run-phase scope, where BeforeEach/It/AfterEach execute.
# Dot-sourcing at script level only covers discovery phase and is not visible during run.
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
}

# $cases is used during the discovery phase to generate Describe blocks, so it stays at script level.
$cases = @(
    @{
        Name           = 'IPv4 function'
        ScriptPath     = 'UpdateStargateIPv4Address/run.ps1'
        ValidIp        = '203.0.113.10'
        InvalidIp      = '2001:db8::beef'
        InvalidMessage = 'Invalid reqIP format. Please pass a valid IPv4 address.'
        IpKind         = 'IPv4'
    },
    @{
        Name           = 'IPv6 function'
        ScriptPath     = 'UpdateStargateIPv6Address/run.ps1'
        ValidIp        = '2001:db8::beef'
        InvalidIp      = '203.0.113.10'
        InvalidMessage = 'Invalid reqIP format. Please pass a valid IPv6 address.'
        IpKind         = 'IPv6'
    }
)

# -ForEach safely exposes each hashtable's keys as named variables ($Name, $ValidIp, $IpKind etc.)
# inside all child blocks during the run phase, avoiding the foreach-loop closure-capture problem.
Describe '<Name>' -ForEach $cases {
    BeforeAll {
        $script:caseScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) $ScriptPath
    }

    BeforeEach {
        Clear-TestFunctions
        $global:SetCalled = $false
        $global:NewCalled = $false
        $savedDdnsResourceGroup  = $env:DDNS_RESOURCE_GROUP
        $savedDdnsTtl            = $env:DDNS_TTL
        $savedAllowedZones       = $env:DDNS_ALLOWED_ZONES
        $savedAllowedRecordNames = $env:DDNS_ALLOWED_RECORD_NAMES
        Remove-Item Env:DDNS_RESOURCE_GROUP  -ErrorAction SilentlyContinue
        Remove-Item Env:DDNS_TTL             -ErrorAction SilentlyContinue
        Remove-Item Env:DDNS_ALLOWED_ZONES   -ErrorAction SilentlyContinue
        Remove-Item Env:DDNS_ALLOWED_RECORD_NAMES -ErrorAction SilentlyContinue
    }

    AfterEach {
        Clear-TestFunctions

        if ($null -ne $savedDdnsResourceGroup) {
            $env:DDNS_RESOURCE_GROUP = $savedDdnsResourceGroup
        }
        else {
            Remove-Item Env:DDNS_RESOURCE_GROUP -ErrorAction SilentlyContinue
        }

        if ($null -ne $savedDdnsTtl) {
            $env:DDNS_TTL = $savedDdnsTtl
        }
        else {
            Remove-Item Env:DDNS_TTL -ErrorAction SilentlyContinue
        }

        if ($null -ne $savedAllowedZones) {
            $env:DDNS_ALLOWED_ZONES = $savedAllowedZones
        }
        else {
            Remove-Item Env:DDNS_ALLOWED_ZONES -ErrorAction SilentlyContinue
        }

        if ($null -ne $savedAllowedRecordNames) {
            $env:DDNS_ALLOWED_RECORD_NAMES = $savedAllowedRecordNames
        }
        else {
            Remove-Item Env:DDNS_ALLOWED_RECORD_NAMES -ErrorAction SilentlyContinue
        }
    }

    It 'returns 400 when required inputs are missing' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind

        $request = New-TestRequest -Query @{ Name = 'router'; Zone = 'example.com' } -Body @{}
        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body | Should -Be 'Please pass a name, zone, and reqIP on the query string or in the request body.'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'supports reqIP query/body fallback with trimming' {
        Set-TestAzMocks -LookupMode existing -CurrentIp $ValidIp -IpKind $IpKind

        $request = New-TestRequest -Query @{} -Body @{
            Name  = '  router  '
            Zone  = ' example.com '
            reqIP = " $ValidIp "
        }

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -Be 'Requested IP and current DNS record match - no changes needed'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'returns 400 for invalid reqIP address family' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $InvalidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body | Should -Be $InvalidMessage
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'allows requests when zone and record name are in the allowlists' {
        Set-TestAzMocks -LookupMode existing -CurrentIp $ValidIp -IpKind $IpKind
        $env:DDNS_ALLOWED_ZONES = 'example.com, other.example'
        $env:DDNS_ALLOWED_RECORD_NAMES = 'router, backup'

        $request = New-TestRequest -Query @{
            Name  = 'Router'
            Zone  = 'Example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -Be 'Requested IP and current DNS record match - no changes needed'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'returns 403 for disallowed zone' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind
        $env:DDNS_ALLOWED_ZONES = 'allowed.example'

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        $response.Body | Should -Be 'Zone is not allowed. No changes were applied.'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'returns 403 for disallowed record name' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind
        $env:DDNS_ALLOWED_RECORD_NAMES = 'allowed-router'

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        $response.Body | Should -Be 'Record name is not allowed. No changes were applied.'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'updates existing record when requested IP differs' {
        Set-TestAzMocks -LookupMode existing -CurrentIp '198.51.100.1' -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -Be "Updated DNS record with requested IP $ValidIp"
        $global:SetCalled | Should -BeTrue
        $global:NewCalled | Should -BeFalse
    }

    It 'returns 200 and does not update when requested IP matches existing record' {
        Set-TestAzMocks -LookupMode existing -CurrentIp $ValidIp -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -Be 'Requested IP and current DNS record match - no changes needed'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'creates record when lookup returns no record' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -Be "DNS Record created with requested IP $ValidIp"
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeTrue
    }

    It 'returns 500 and does not create when dns lookup fails' {
        Set-TestAzMocks -LookupMode throw -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body | Should -Be 'DNS lookup failed. No changes were applied.'
        $global:SetCalled | Should -BeFalse
        $global:NewCalled | Should -BeFalse
    }

    It 'uses default resource group and ttl when app settings are absent' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $global:NewCalled | Should -BeTrue
        $global:NewRecord.ResourceGroupName | Should -Be 'Standard'
        $global:NewRecord.Ttl | Should -Be 3600
    }

    It 'uses configured resource group and ttl when app settings are valid' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind
        $env:DDNS_RESOURCE_GROUP = 'DnsProd'
        $env:DDNS_TTL = '120'

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $global:NewCalled | Should -BeTrue
        $global:NewRecord.ResourceGroupName | Should -Be 'DnsProd'
        $global:NewRecord.Ttl | Should -Be 120
    }

    It 'falls back to default ttl when DDNS_TTL is invalid' {
        Set-TestAzMocks -LookupMode missing -IpKind $IpKind
        $env:DDNS_RESOURCE_GROUP = 'DnsProd'
        $env:DDNS_TTL = 'not-a-number'

        $request = New-TestRequest -Query @{
            Name  = 'router'
            Zone  = 'example.com'
            reqIP = $ValidIp
        } -Body @{}

        $response = Invoke-FunctionScript -ScriptPath $script:caseScriptPath -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $global:NewCalled | Should -BeTrue
        $global:NewRecord.ResourceGroupName | Should -Be 'DnsProd'
        $global:NewRecord.Ttl | Should -Be 3600
    }
}
