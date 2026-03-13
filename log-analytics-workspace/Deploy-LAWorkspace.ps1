<#
.SYNOPSIS
    Deploys RealmJoin Log Analytics Workspace infrastructure to Azure.

.DESCRIPTION
    This script orchestrates the deployment of RealmJoin Log Analytics Workspace infrastructure.
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

.PARAMETER WorkspaceName
    Optional. The name of the Log Analytics Workspace. If not provided, a unique name is generated.

.PARAMETER DeployAuditLogsDCR
    Optional. Whether to deploy the audit logs DCR and custom table. Default is $true.

.PARAMETER DeployRunbookLogsDCR
    Optional. Whether to deploy the runbook logs DCR and custom table. Default is $false.

.PARAMETER RJApiUrl
    Optional. The RealmJoin API endpoint URL. If not provided, API registration is skipped.

.PARAMETER RJApiToken
    Optional. The RealmJoin API authentication token. Required if RJApiUrl is provided.

.EXAMPLE
    ./Deploy-LAWorkspace.ps1 -ResourceGroupName "rg-realmjoin"

.EXAMPLE
    ./Deploy-LAWorkspace.ps1 -ResourceGroupName "rg-realmjoin" -WorkspaceName "la-rj-auditlogs" -RJApiUrl "https://api.realmjoin.com/..." -RJApiToken "your-token"

.EXAMPLE
    ./Deploy-LAWorkspace.ps1 -ResourceGroupName "rg-realmjoin" -DeployAuditLogsDCR $true -DeployRunbookLogsDCR $true
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName = "",

    [Parameter(Mandatory = $false)]
    [bool]$DeployAuditLogsDCR = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DeployRunbookLogsDCR = $false,

    [Parameter(Mandatory = $false)]
    [string]$RJApiUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$RJApiToken = ""
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# Configuration - GitHub raw content URL
$GitHubBaseUrl = "https://raw.githubusercontent.com/shobhitvaish/azure-resources/main"

# Templates to download (excluding module - downloaded separately for bootstrapping)
$Templates = @(
    @{ Remote = "realmJoinServicePrincipal.bicep"; Local = "realmJoinServicePrincipal.bicep" },
    @{ Remote = "log-analytics-workspace/logAnalyticsWorkspace.bicep"; Local = "logAnalyticsWorkspace.bicep" },
    @{ Remote = "log-analytics-workspace/modules/customTableDcr.bicep"; Local = "modules/customTableDcr.bicep" },
    @{ Remote = "bicepconfig.json"; Local = "bicepconfig.json" }
)

# Bootstrap: Create temp directory and download shared module
$TempPath = Join-Path ([System.IO.Path]::GetTempPath()) "rj-deploy-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TempPath "modules") -Force | Out-Null
Invoke-WebRequest -Uri "$GitHubBaseUrl/shared/RJDeployment.psm1" -OutFile (Join-Path $TempPath "RJDeployment.psm1")
Import-Module (Join-Path $TempPath "RJDeployment.psm1") -Force

# Main execution
try {
    Write-Information "`n============================================"
    Write-Information "RealmJoin Log Analytics Workspace Deployment"
    Write-Information "============================================`n"

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

    # Step 2: Deploy Log Analytics Workspace template
    Write-Information "`n--- Step 2: Log Analytics Workspace ---"
    $step2Params = @{
        servicePrincipalId = $rjServicePrincipalId
        deployAuditLogsDCR = $DeployAuditLogsDCR
        deployRunbookLogsDCR = $DeployRunbookLogsDCR
    }
    if ($WorkspaceName) {
        $step2Params.workspaceName = $WorkspaceName
    }
    $step2Outputs = Deploy-BicepTemplate -ResourceGroupName $ResourceGroupName -TemplatePath (Join-Path $TempPath "logAnalyticsWorkspace.bicep") -DeploymentName "rj-laworkspace-$(Get-Date -Format 'yyyyMMddHHmmss')" -Parameters $step2Params

    $workspaceName = $step2Outputs["workspaceName"].Value
    $workspaceId = $step2Outputs["workspaceId"].Value
    $customerId = $step2Outputs["customerId"].Value
    
    # Audit Logs DCR outputs (conditional)
    $tableName = $step2Outputs["tableName"].Value
    $streamName = $step2Outputs["streamName"].Value
    $logsIngestionEndpoint = $step2Outputs["logsIngestionEndpoint"].Value
    $dcrImmutableId = $step2Outputs["dcrImmutableId"].Value
    $dcrId = $step2Outputs["dcrId"].Value
    
    # Runbook Logs DCR outputs (conditional)
    $runbookLogsTableName = $step2Outputs["runbookLogsTableName"].Value
    $runbookLogsStreamName = $step2Outputs["runbookLogsStreamName"].Value
    $runbookLogsIngestionEndpoint = $step2Outputs["runbookLogsIngestionEndpoint"].Value
    $runbookLogsDcrImmutableId = $step2Outputs["runbookLogsDcrImmutableId"].Value
    $runbookLogsDcrId = $step2Outputs["runbookLogsDcrId"].Value

    Write-Verbose "  Workspace ID: $workspaceId"
    Write-Verbose "  Customer ID: $customerId"
    if ($DeployAuditLogsDCR) {
        Write-Verbose "  Audit Logs Table Name: $tableName"
        Write-Verbose "  Audit Logs Ingestion Endpoint: $logsIngestionEndpoint"
        Write-Verbose "  Audit Logs DCR Immutable ID: $dcrImmutableId"
    }
    if ($DeployRunbookLogsDCR) {
        Write-Verbose "  Runbook Logs Table Name: $runbookLogsTableName"
        Write-Verbose "  Runbook Logs Ingestion Endpoint: $runbookLogsIngestionEndpoint"
        Write-Verbose "  Runbook Logs DCR Immutable ID: $runbookLogsDcrImmutableId"
    }

    # Step 3: Register with RealmJoin API (optional)
    if ($RJApiUrl -and $RJApiToken) {
        Write-Information "`n--- Step 3: RealmJoin API Registration ---"
        
        $payload = @{
            tenantId              = (Get-AzContext).Tenant.Id
            subscriptionId        = (Get-AzContext).Subscription.Id
            resourceGroupName     = $ResourceGroupName
            workspaceName         = $workspaceName
            workspaceId           = $workspaceId
            customerId            = $customerId
        }
        
        # Add audit logs DCR info if deployed
        if ($DeployAuditLogsDCR) {
            $payload.auditLogs = @{
                tableName             = $tableName
                streamName            = $streamName
                dcrImmutableId        = $dcrImmutableId
                logsIngestionEndpoint = $logsIngestionEndpoint
            }
        }
        
        # Add runbook logs DCR info if deployed
        if ($DeployRunbookLogsDCR) {
            $payload.runbookLogs = @{
                tableName             = $runbookLogsTableName
                streamName            = $runbookLogsStreamName
                dcrImmutableId        = $runbookLogsDcrImmutableId
                logsIngestionEndpoint = $runbookLogsIngestionEndpoint
            }
        }

        Invoke-RJApiRegistration -ApiUrl $RJApiUrl -ApiToken $RJApiToken -Payload $payload
    }
    else {
        Write-Information "`n--- Step 3: RealmJoin API Registration (Skipped) ---"
    }

    # Summary
    Write-Information "`n============================================"
    Write-Information "Deployment Complete!"
    Write-Information "============================================"
    Write-Information "Workspace Name: $workspaceName"
    Write-Information "Workspace ID: $workspaceId"
    Write-Information "Customer ID: $customerId"
    Write-Information ""
    
    if ($DeployAuditLogsDCR) {
        Write-Information "--- Audit Logs DCR ---"
        Write-Information "Table Name: $tableName"
        Write-Information "Logs Ingestion Endpoint: $logsIngestionEndpoint"
        Write-Information "DCR Immutable ID: $dcrImmutableId"
        Write-Information ""
    }
    
    if ($DeployRunbookLogsDCR) {
        Write-Information "--- Runbook Logs DCR ---"
        Write-Information "Table Name: $runbookLogsTableName"
        Write-Information "Logs Ingestion Endpoint: $runbookLogsIngestionEndpoint"
        Write-Information "DCR Immutable ID: $runbookLogsDcrImmutableId"
        Write-Information ""
    }
    
    if (-not $DeployAuditLogsDCR -and -not $DeployRunbookLogsDCR) {
        Write-Information "Note: No DCRs were deployed (both deployAuditLogsDCR and deployRunbookLogsDCR are false)"
        Write-Information ""
    }

}
finally {
    # Cleanup temp directory
    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
