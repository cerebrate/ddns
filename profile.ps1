# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#

try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Host "Azure account connected via managed identity."
}
catch {
    Write-Error "Failed to connect to Azure with managed identity: $($_.Exception.Message)"
    throw
}
