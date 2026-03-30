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

try {
    $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec $TimeoutSec
}
catch {
    $statusCode = $null

    try {
        if ($null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
    }
    catch {
        # Ignore extraction failures and fall through to the generic error.
    }

    if ($statusCode -eq 401) {
        throw "Smoke test received HTTP 401 Unauthorized. The function URL secret likely has a missing or invalid function key (code=...). Refresh PROD_IPV4_FUNCTION_URL / PROD_IPV6_FUNCTION_URL from Azure Portal > Functions > Get function URL."
    }

    throw "Smoke test request failed. $($_.Exception.Message)"
}

if ($response.StatusCode -ne 200) {
    throw "Smoke test expected HTTP 200 but got $($response.StatusCode)."
}

$content = [string]$response.Content
if ($content -notmatch "Updated DNS record|DNS Record created|no changes needed") {
    throw "Smoke test returned unexpected response body: $content"
}

Write-Host "Smoke test passed."
