param(
    [Parameter(Mandatory = $true)]
    [string]$FunctionUrl,

    [Parameter(Mandatory = $true)]
    [string]$Zone,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$ReqIp,

    [int]$TimeoutSec = 30
)

$separator = if ($FunctionUrl.Contains("?")) { "&" } else { "?" }
$query = "name=$([uri]::EscapeDataString($Name))&zone=$([uri]::EscapeDataString($Zone))&reqIP=$([uri]::EscapeDataString($ReqIp))"
$uri = "$FunctionUrl$separator$query"

Write-Host "Calling smoke test endpoint for record '$Name' in zone '$Zone'."

$invokeParams = @{
    Uri = $uri
    Method = 'Get'
    TimeoutSec = $TimeoutSec
}

if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('SkipHttpErrorCheck')) {
    # Available in PowerShell 7+: lets us inspect status/body without exception parsing.
    $invokeParams['SkipHttpErrorCheck'] = $true
}

try {
    $response = Invoke-WebRequest @invokeParams
}
catch {
    throw "Smoke test request failed. $($_.Exception.Message)"
}

$statusCode = [int]$response.StatusCode
$content = [string]$response.Content

if ($statusCode -eq 401) {
    throw "Smoke test received HTTP 401 Unauthorized. The function URL secret likely has a missing or invalid function key (code=...). Refresh PROD_IPV4_FUNCTION_URL / PROD_IPV6_FUNCTION_URL from Azure Portal > Functions > Get function URL."
}

if ($statusCode -eq 500) {
    $compactBody = ($content -replace "\s+", " ").Trim()
    if (-not $compactBody) {
        throw "Smoke test received HTTP 500 Internal Server Error with no response body."
    }

    if ($compactBody.Length -gt 500) {
        $compactBody = $compactBody.Substring(0, 500) + '...'
    }

    throw "Smoke test received HTTP 500 Internal Server Error. Response body: $compactBody"
}

if ($statusCode -ne 200) {
    $compactBody = ($content -replace "\s+", " ").Trim()
    if ($compactBody.Length -gt 500) {
        $compactBody = $compactBody.Substring(0, 500) + '...'
    }

    throw "Smoke test expected HTTP 200 but got $statusCode. Response body: $compactBody"
}

if ($content -notmatch "Updated DNS record|DNS Record created|no changes needed") {
    throw "Smoke test returned unexpected response body: $content"
}

Write-Host "Smoke test passed."
