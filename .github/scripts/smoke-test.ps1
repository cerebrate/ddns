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

Write-Host "Calling smoke test endpoint: $uri"

try {
    $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec $TimeoutSec
}
catch {
    throw "Smoke test request failed for $FunctionUrl. $($_.Exception.Message)"
}

if ($response.StatusCode -ne 200) {
    throw "Smoke test expected HTTP 200 but got $($response.StatusCode)."
}

$content = [string]$response.Content
if ($content -notmatch "Updated DNS record|DNS Record created|no changes needed") {
    throw "Smoke test returned unexpected response body: $content"
}

Write-Host "Smoke test passed."
