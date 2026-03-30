# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#

$maxAttempts = 12
$retryDelaySeconds = 15
$lastErrorMessage = $null

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Import-Module Az.Accounts -ErrorAction Stop
        Disable-AzContextAutosave -Scope Process | Out-Null
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Write-Host "Azure account connected via managed identity."
        return
    }
    catch {
        $lastErrorMessage = $_.Exception.Message
        Write-Host "Managed identity initialization attempt $attempt/$maxAttempts failed: $lastErrorMessage"

        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
}

Write-Error "Failed to connect to Azure with managed identity after $maxAttempts attempts: $lastErrorMessage"
throw
