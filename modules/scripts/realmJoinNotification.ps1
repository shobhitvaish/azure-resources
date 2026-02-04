# Read environment variables
$apiUrl = $env:API_URL
$authToken = $env:AUTH_TOKEN
$payloadJson = $env:PAYLOAD_JSON

# Initialize output object
$DeploymentScriptOutputs = @{}

try {
    # Call API with Authorization header
    $headers = @{
        'Authorization' = "Bearer $authToken"
    }
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $payloadJson -ContentType 'application/json' -Headers $headers -TimeoutSec 30
    
    $DeploymentScriptOutputs['status'] = 'Success'
    $DeploymentScriptOutputs['message'] = 'Workspace information successfully posted to RealmJoin API'
    $DeploymentScriptOutputs['timestamp'] = (Get-Date).ToUniversalTime().ToString('o')
    $DeploymentScriptOutputs['response'] = $response
}
catch {
    # Log warning but don't fail deployment
    Write-Warning "Failed to notify RealmJoin API: $($_.Exception.Message)"
    Write-Warning "Please manually enter this information in the RealmJoin portal or re-run the deployment."
    
    $DeploymentScriptOutputs['status'] = 'Failed'
    $DeploymentScriptOutputs['message'] = "Failed to notify RealmJoin API: $($_.Exception.Message)"
    $DeploymentScriptOutputs['timestamp'] = (Get-Date).ToUniversalTime().ToString('o')
}
