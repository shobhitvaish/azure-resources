<#
.SYNOPSIS
    Deploys RealmJoin Automation Account infrastructure to Azure.

.DESCRIPTION
    This script orchestrates the deployment of RealmJoin Automation Account infrastructure.
    Bicep templates are downloaded from GitHub at runtime - no additional files needed.
    
    Uses device code authentication to ensure proper consent for Bicep Microsoft Graph 
    extension operations.

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
$GitHubBaseUrl = "https://raw.githubusercontent.com/shobhitvaish/azure-resources/main"

# Templates to download (excluding module - downloaded separately for bootstrapping)
$Templates = @(
    @{ Remote = "realmJoinServicePrincipal.bicep"; Local = "realmJoinServicePrincipal.bicep" },
    @{ Remote = "azure-automation-account/automationAccount.bicep"; Local = "automationAccount.bicep" },
    @{ Remote = "azure-automation-account/rjAutomationAccountPermissions.bicep"; Local = "rjAutomationAccountPermissions.bicep" },
    @{ Remote = "azure-automation-account/RJAutomationAccountPermissionsManifest.json"; Local = "RJAutomationAccountPermissionsManifest.json" },
    @{ Remote = "bicepconfig.json"; Local = "bicepconfig.json" }
)

# Bootstrap: Create temp directory and download shared module
$TempPath = Join-Path ([System.IO.Path]::GetTempPath()) "rj-deploy-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
Invoke-WebRequest -Uri "$GitHubBaseUrl/shared/RJDeployment.psm1" -OutFile (Join-Path $TempPath "RJDeployment.psm1")
Import-Module (Join-Path $TempPath "RJDeployment.psm1") -Force

# Main execution
try {
    Write-Information "`n========================================"
    Write-Information "RealmJoin Automation Account Deployment"
    Write-Information "========================================`n"

    # Initialize deployment (auth + download templates)
    Initialize-RJDeployment -GitHubBaseUrl $GitHubBaseUrl -Templates $Templates -TempPath $TempPath | Out-Null

    # Verify resource group exists
    Write-Verbose "Verifying resource group '$ResourceGroupName' exists..."
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    Write-Verbose "  Resource group found in '$($rg.Location)'."

    # Step 1: Deploy RealmJoin Service Principal template
    Write-Information "`n--- Step 1: RealmJoin Service Principal ---"
    $step1Outputs = Deploy-BicepTemplate -ResourceGroupName $ResourceGroupName -TemplatePath (Join-Path $TempPath "realmJoinServicePrincipal.bicep") -DeploymentName "rj-serviceprincipal-$(Get-Date -Format 'yyyyMMddHHmmss')"

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
    $step2Outputs = Deploy-BicepTemplate -ResourceGroupName $ResourceGroupName -TemplatePath (Join-Path $TempPath "automationAccount.bicep") -DeploymentName "rj-automationaccount-$(Get-Date -Format 'yyyyMMddHHmmss')" -Parameters $step2Params

    $automationAccountId = $step2Outputs["automationAccountId"].Value
    $automationAccountPrincipalId = $step2Outputs["automationAccountPrincipalId"].Value
    Write-Verbose "  Automation Account ID: $automationAccountId"
    Write-Verbose "  Managed Identity Principal ID: $automationAccountPrincipalId"

    # Wait for Managed Identity replication
    Wait-ServicePrincipalReplication -ServicePrincipalId $automationAccountPrincipalId

    # Step 3: Deploy Permissions template
    Write-Information "`n--- Step 3: Permissions Assignment ---"
    $step3Outputs = Deploy-BicepTemplate -ResourceGroupName $ResourceGroupName -TemplatePath (Join-Path $TempPath "rjAutomationAccountPermissions.bicep") -DeploymentName "rj-permissions-$(Get-Date -Format 'yyyyMMddHHmmss')" `
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
        
        $payload = @{
            automationAccountResourceId = $automationAccountId
        }

        Invoke-RJApiRegistration -ApiUrl $RJApiUrl -ApiToken $RJApiToken -Payload $payload
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
