Set-StrictMode -Version Latest

. "$PSScriptRoot/TestHelpers.ps1"

$repoRoot = Split-Path $PSScriptRoot -Parent

$cases = @(
    @{
        Name = 'IPv4 function'
        ScriptPath = 'UpdateStargateIPv4Address/run.ps1'
        ValidIp = '203.0.113.10'
        InvalidIp = '2001:db8::beef'
        InvalidMessage = 'Invalid reqIP format. Please pass a valid IPv4 address.'
        IpKind = 'IPv4'
    },
    @{
        Name = 'IPv6 function'
        ScriptPath = 'UpdateStargateIPv6Address/run.ps1'
        ValidIp = '2001:db8::beef'
        InvalidIp = '203.0.113.10'
        InvalidMessage = 'Invalid reqIP format. Please pass a valid IPv6 address.'
        IpKind = 'IPv6'
    }
)

foreach ($case in $cases) {
    Describe $case.Name {
        $caseScriptPath = Join-Path $repoRoot $case.ScriptPath
        $originalDdnsResourceGroup = $null
        $originalDdnsTtl = $null

        BeforeEach {
            Clear-TestFunctions
            $global:SetCalled = $false
            $global:NewCalled = $false
            $originalDdnsResourceGroup = $env:DDNS_RESOURCE_GROUP
            $originalDdnsTtl = $env:DDNS_TTL
            Remove-Item Env:DDNS_RESOURCE_GROUP -ErrorAction SilentlyContinue
            Remove-Item Env:DDNS_TTL -ErrorAction SilentlyContinue
        }

        AfterEach {
            Clear-TestFunctions

            if ($null -ne $originalDdnsResourceGroup) {
                $env:DDNS_RESOURCE_GROUP = $originalDdnsResourceGroup
            }
            else {
                Remove-Item Env:DDNS_RESOURCE_GROUP -ErrorAction SilentlyContinue
            }

            if ($null -ne $originalDdnsTtl) {
                $env:DDNS_TTL = $originalDdnsTtl
            }
            else {
                Remove-Item Env:DDNS_TTL -ErrorAction SilentlyContinue
            }
        }

        It 'returns 400 when required inputs are missing' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind

            $request = New-TestRequest -Query @{ Name = 'router'; Zone = 'example.com' } -Body @{}
            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::BadRequest)
            $response.Body | Should Be 'Please pass a name, zone, and reqIP on the query string or in the request body.'
            $global:SetCalled | Should Be $false
            $global:NewCalled | Should Be $false
        }

        It 'supports reqIP query/body fallback with trimming' {
            Set-TestAzMocks -LookupMode existing -CurrentIp $case.ValidIp -IpKind $case.IpKind

            $request = New-TestRequest -Query @{} -Body @{
                Name = '  router  '
                Zone = ' example.com '
                reqIP = " $($case.ValidIp) "
            }

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $response.Body | Should Be 'Requested IP and current DNS record match - no changes needed'
            $global:SetCalled | Should Be $false
            $global:NewCalled | Should Be $false
        }

        It 'returns 400 for invalid reqIP address family' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.InvalidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::BadRequest)
            $response.Body | Should Be $case.InvalidMessage
            $global:SetCalled | Should Be $false
            $global:NewCalled | Should Be $false
        }

        It 'updates existing record when requested IP differs' {
            Set-TestAzMocks -LookupMode existing -CurrentIp '198.51.100.1' -IpKind $case.IpKind

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $response.Body | Should Be "Updated DNS record with requested IP $($case.ValidIp)"
            $global:SetCalled | Should Be $true
            $global:NewCalled | Should Be $false
        }

        It 'creates record when lookup returns no record' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $response.Body | Should Be "DNS Record created with requested IP $($case.ValidIp)"
            $global:SetCalled | Should Be $false
            $global:NewCalled | Should Be $true
        }

        It 'returns 500 and does not create when dns lookup fails' {
            Set-TestAzMocks -LookupMode throw -IpKind $case.IpKind

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::InternalServerError)
            $response.Body | Should Be 'DNS lookup failed. No changes were applied.'
            $global:SetCalled | Should Be $false
            $global:NewCalled | Should Be $false
        }

        It 'uses default resource group and ttl when app settings are absent' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $global:NewCalled | Should Be $true
            $global:NewRecord.ResourceGroupName | Should Be 'Standard'
            $global:NewRecord.Ttl | Should Be 3600
        }

        It 'uses configured resource group and ttl when app settings are valid' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind
            $env:DDNS_RESOURCE_GROUP = 'DnsProd'
            $env:DDNS_TTL = '120'

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $global:NewCalled | Should Be $true
            $global:NewRecord.ResourceGroupName | Should Be 'DnsProd'
            $global:NewRecord.Ttl | Should Be 120
        }

        It 'falls back to default ttl when DDNS_TTL is invalid' {
            Set-TestAzMocks -LookupMode missing -IpKind $case.IpKind
            $env:DDNS_RESOURCE_GROUP = 'DnsProd'
            $env:DDNS_TTL = 'not-a-number'

            $request = New-TestRequest -Query @{
                Name = 'router'
                Zone = 'example.com'
                reqIP = $case.ValidIp
            } -Body @{}

            $response = Invoke-FunctionScript -ScriptPath $caseScriptPath -Request $request

            $response.StatusCode | Should Be ([System.Net.HttpStatusCode]::OK)
            $global:NewCalled | Should Be $true
            $global:NewRecord.ResourceGroupName | Should Be 'DnsProd'
            $global:NewRecord.Ttl | Should Be 3600
        }
    }
}
