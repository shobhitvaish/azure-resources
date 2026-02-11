<#
.SYNOPSIS
    Deploys RealmJoin Automation Account infrastructure to Azure.

.DESCRIPTION
    This script orchestrates the deployment of RealmJoin Automation Account infrastructure.
    Bicep templates are downloaded from GitHub at runtime - no additional files needed.
    
    Designed for Azure Cloud Shell. The script automatically acquires Graph API tokens
    required by the Bicep Microsoft Graph extension.

    Prerequisites:
    - Azure PowerShell module (Az)
    - Bicep CLI
    - Resource group must already exist
    - Internet access (to download Bicep templates)

.PARAMETER ResourceGroupName
    The name of the resource group to deploy to (must exist).

.PARAMETER AutomationAccountName
    Optional. The name of the Automation Account. If not provided, Bicep generates a unique name.

.PARAMETER RJApiUrl
    Optional. The RealmJoin API endpoint URL. If not provided, API registration is skipped.

.PARAMETER RJApiToken
    Optional. The RealmJoin API authentication token. Required if RJApiUrl is provided.

.EXAMPLE
    ./Deploy-RJAutomationAccount.ps1 -ResourceGroupName "rg-realmjoin"

.EXAMPLE
    ./Deploy-RJAutomationAccount.ps1 -ResourceGroupName "rg-realmjoin" -AutomationAccountName "my-aa" -RJApiUrl "https://api.realmjoin.com/..." -RJApiToken "your-token"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName = "",

    [Parameter(Mandatory = $false)]
    [string]$RJApiUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$RJApiToken = ""
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# Configuration - GitHub raw content URL (update this to your repo)
$GitHubBaseUrl = "https://raw.githubusercontent.com/realmjoin/yourrepo/main"

# Create temp directory for downloaded templates
$TempPath = Join-Path ([System.IO.Path]::GetTempPath()) "rj-deploy-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempPath -Force | Out-Null

# Templates to download
$Templates = @(
    @{ Remote = "realmJoinServicePrincipal.bicep"; Local = "realmJoinServicePrincipal.bicep" },
    @{ Remote = "azure-automation-account/automationAccount.bicep"; Local = "automationAccount.bicep" },
    @{ Remote = "azure-automation-account/rjAutomationAccountPermissions.bicep"; Local = "rjAutomationAccountPermissions.bicep" },
    @{ Remote = "azure-automation-account/RJAutomationAccountPermissionsManifest.json"; Local = "RJAutomationAccountPermissionsManifest.json" },
    @{ Remote = "bicepconfig.json"; Local = "bicepconfig.json" }
)

function Wait-ServicePrincipalReplication {
    <#
    .SYNOPSIS
        Waits for a service principal to replicate across Azure AD with exponential backoff.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 4,

        [Parameter(Mandatory = $false)]
        [int]$BaseDelaySeconds = 8
    )

    Write-Verbose "Waiting for service principal '$ServicePrincipalId' to replicate..."

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 2)  # 8, 16, 32
            Write-Verbose "  Attempt $attempt/$MaxAttempts - Waiting $delay seconds..."
            Start-Sleep -Seconds $delay
        }

        try {
            $sp = Get-AzADServicePrincipal -ObjectId $ServicePrincipalId -ErrorAction Stop
            if ($sp) {
                Write-Verbose "  Service principal replicated successfully."
                return $true
            }
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Warning "Service principal not found after $MaxAttempts attempts. Proceeding anyway..."
                return $false
            }
            Write-Verbose "  Service principal not yet available. Retrying..."
        }
    }

    return $false
}

function Deploy-BicepTemplate {
    param(
        [string]$TemplatePath,
        [string]$DeploymentName,
        [hashtable]$Parameters = @{}
    )

    Write-Verbose "Deploying '$DeploymentName'..."

    $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplatePath -TemplateParameterObject $Parameters

    Write-Verbose "  Deployment succeeded."
    return $deployment.Outputs
}

# Main execution
try {
    Write-Information "`n========================================"
    Write-Information "RealmJoin Automation Account Deployment"
    Write-Information "========================================`n"

    # Acquire Graph API token for Bicep Microsoft Graph extension
    # This is required in Azure Cloud Shell to switch from the portal's app identity to Azure CLI's app identity
    Write-Verbose "Acquiring Graph API token for Bicep deployments..."
    az login --scope https://graph.microsoft.com/.default | Out-Null

    # Download templates from GitHub
    Write-Verbose "Downloading Bicep templates..."
    foreach ($t in $Templates) {
        Write-Verbose "  $($t.Remote)"
        Invoke-WebRequest -Uri "$GitHubBaseUrl/$($t.Remote)" -OutFile (Join-Path $TempPath $t.Local)
    }

    # Verify resource group exists
    Write-Verbose "Verifying resource group '$ResourceGroupName' exists..."
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    Write-Verbose "  Resource group found in '$($rg.Location)'."

    # Step 1: Deploy RealmJoin Service Principal template
    Write-Information "`n--- Step 1: RealmJoin Service Principal ---"
    $step1Outputs = Deploy-BicepTemplate -TemplatePath (Join-Path $TempPath "realmJoinServicePrincipal.bicep") -DeploymentName "rj-serviceprincipal-$(Get-Date -Format 'yyyyMMddHHmmss')"

    $rjServicePrincipalId = $step1Outputs["servicePrincipalId"].Value
    Write-Verbose "  RJ Service Principal ID: $rjServicePrincipalId"

    # Wait for RJ Service Principal replication
    Wait-ServicePrincipalReplication -ServicePrincipalId $rjServicePrincipalId

    # Step 2: Deploy Automation Account template
    Write-Information "`n--- Step 2: Automation Account ---"
    $step2Params = @{
        rjServicePrincipalId = $rjServicePrincipalId
    }
    if ($AutomationAccountName) {
        $step2Params.automationAccountName = $AutomationAccountName
    }
    $step2Outputs = Deploy-BicepTemplate -TemplatePath (Join-Path $TempPath "automationAccount.bicep") -DeploymentName "rj-automationaccount-$(Get-Date -Format 'yyyyMMddHHmmss')" -Parameters $step2Params

    $automationAccountId = $step2Outputs["automationAccountId"].Value
    $automationAccountPrincipalId = $step2Outputs["automationAccountPrincipalId"].Value
    Write-Verbose "  Automation Account ID: $automationAccountId"
    Write-Verbose "  Managed Identity Principal ID: $automationAccountPrincipalId"

    # Wait for Managed Identity replication
    Wait-ServicePrincipalReplication -ServicePrincipalId $automationAccountPrincipalId

    # Step 3: Deploy Permissions template
    Write-Information "`n--- Step 3: Permissions Assignment ---"
    $step3Outputs = Deploy-BicepTemplate -TemplatePath (Join-Path $TempPath "rjAutomationAccountPermissions.bicep") -DeploymentName "rj-permissions-$(Get-Date -Format 'yyyyMMddHHmmss')" `
        -Parameters @{
            principalId = $automationAccountPrincipalId
        }

    Write-Verbose "  Permissions assigned:"
    Write-Verbose "    - Microsoft Graph: $($step3Outputs["graphPermissionsCount"].Value)"
    Write-Verbose "    - Exchange Online: $($step3Outputs["exchangePermissionsCount"].Value)"
    Write-Verbose "    - Defender ATP: $($step3Outputs["defenderPermissionsCount"].Value)"
    Write-Verbose "    - SharePoint Online: $($step3Outputs["sharePointPermissionsCount"].Value)"

    # Step 4: Register with RealmJoin API (optional)
    if ($RJApiUrl -and $RJApiToken) {
        Write-Information "`n--- Step 4: RealmJoin API Registration ---"
        
        $rjPayload = @{
            automationAccountResourceId = $automationAccountId
        } | ConvertTo-Json

        Write-Verbose "  Posting to RealmJoin API..."
        
        $headers = @{
            "Authorization" = "Bearer $RJApiToken"
            "Content-Type"  = "application/json"
        }

        try {
            $response = Invoke-RestMethod -Uri $RJApiUrl -Method Post -Headers $headers -Body $rjPayload

            Write-Information "  API registration successful."
            if ($response) {
                Write-Verbose "  Response: $($response | ConvertTo-Json -Compress)"
            }
        }
        catch {
            Write-Warning "Failed to register with RealmJoin API: $($_.Exception.Message)"
            Write-Warning "You may need to manually register the Automation Account."
        }
    }
    else {
        Write-Information "`n--- Step 4: RealmJoin API Registration (Skipped) ---"
    }

    # Summary
    Write-Information "`n========================================"
    Write-Information "Deployment Complete!"
    Write-Information "========================================"
    Write-Information "Automation Account: $($step2Outputs["automationAccountName"].Value)"
    Write-Information "Resource ID: $automationAccountId"
    Write-Information "Managed Identity: $automationAccountPrincipalId"
    Write-Information ""

}
finally {
    # Cleanup temp directory
    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
