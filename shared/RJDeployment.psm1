# RealmJoin Deployment Shared Module
# Common functions for RealmJoin infrastructure deployment scripts

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
            $sp = Get-AzADServicePrincipal -ObjectId $ServicePrincipalId -ErrorAction Stop -Verbose -Debug
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
    <#
    .SYNOPSIS
        Deploys a Bicep template to a resource group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$DeploymentName,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    Write-Verbose "Deploying '$DeploymentName'..."

    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -Name $DeploymentName `
        -TemplateFile $TemplatePath `
        -TemplateParameterObject $Parameters `
        -Verbose
        -Debug

    Write-Verbose "  Deployment succeeded."
    return $deployment.Outputs
}

function Invoke-RJApiRegistration {
    <#
    .SYNOPSIS
        Registers deployment information with the RealmJoin API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiUrl,

        [Parameter(Mandatory = $true)]
        [string]$ApiToken,

        [Parameter(Mandatory = $true)]
        [hashtable]$Payload
    )

    Write-Verbose "  Posting to RealmJoin API..."

    $headers = @{
        "Authorization" = "Bearer $ApiToken"
        "Content-Type"  = "application/json"
    }

    $body = $Payload | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -Body $body
        Write-Information "  API registration successful."
        if ($response) {
            Write-Verbose "  Response: $($response | ConvertTo-Json -Compress)"
        }
        return $true
    }
    catch {
        Write-Warning "Failed to register with RealmJoin API: $($_.Exception.Message)"
        Write-Warning "You may need to manually register in the RealmJoin portal."
        return $false
    }
}

function Initialize-RJDeployment {
    <#
    .SYNOPSIS
        Initializes a RealmJoin deployment session (auth, temp directory, template download).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitHubBaseUrl,

        [Parameter(Mandatory = $true)]
        [array]$Templates,

        [Parameter(Mandatory = $true)]
        [string]$TempPath
    )

    # Authenticate with device code flow
    Write-Information "Authenticating..."
    Connect-AzAccount -UseDeviceAuthentication -Verbose -Debug

    # Download templates
    Write-Verbose "Downloading Bicep templates..."
    foreach ($t in $Templates) {
        Write-Verbose "  $($t.Remote)"
        Invoke-WebRequest -Uri "$GitHubBaseUrl/$($t.Remote)" -OutFile (Join-Path $TempPath $t.Local)
    }

    return $TempPath
}

Export-ModuleMember -Function Wait-ServicePrincipalReplication, Deploy-BicepTemplate, Invoke-RJApiRegistration, Initialize-RJDeployment
