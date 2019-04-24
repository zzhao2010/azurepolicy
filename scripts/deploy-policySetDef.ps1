#Requires -Modules 'az.resources'
<#
======================================================================================================================================
AUTHOR:  Tao Yang
DATE:    24/04/2019
Version: 1.0
Comment: Alternative method to deploy Azure policy set (Initiative) definitions to a management group or a subscription
Note: This script supports deploying initiative definitions that contains custom policy definitions without hardcoding definition Ids
======================================================================================================================================
#>
[CmdLetBinding()]
Param (
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub', HelpMessage = 'Specify the file paths for the policy initiative  definition files.')]
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG', HelpMessage = 'Specify the file paths for the policy initiative definition files.')]
  [ValidateScript({test-path $_})][String]$definitionFile,

  [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'deployToSub', HelpMessage = 'Specify the file paths for the policy initiative  definition files.')]
  [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'deployToMG', HelpMessage = 'Specify the file paths for the policy initiative definition files.')]
  [hashtable]$PolicyLocations,

  [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')]
  [ValidateScript({try {[guid]::parse($_)} catch {$false}})][String]$subscriptionId,

  [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')]
  [ValidateNotNullOrEmpty()][String]$managementGroupName
)

#region functions
Function ProcessAzureSignIn
{
    $null = Connect-AzAccount
    $context = Get-AzContext -ErrorAction Stop
    $Script:currentTenantId = $context.Tenant.Id
    $Script:currentSubId = $context.Subscription.Id
    $Script:currentSubName = $context.Subscription.Name
}

Function DeployPolicySetDefinition
{
    [CmdLetBinding()]
    Param (
      [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToSub')]
      [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'deployToMG')]
      [object]$Definition,
      [Parameter(Mandatory = $true, ParameterSetName = 'deployToSub')][String]$subscriptionId,
      [Parameter(Mandatory = $true, ParameterSetName = 'deployToMG')][String]$managementGroupName
    )
    #Extract from policy definition
    $policySetName = $Definition.name
    $policySetDisplayName = $Definition.displayName
    $policySetDescription = $Definition.description
    $policySetParameters = $Definition.parameters | convertTo-Json
    $policySetDefinition = $Definition.policyDefinitions | convertTo-Json -Depth 15
    $policySetMetaData = $Definition.metadata | convertTo-Json
    If ($PSCmdlet.ParameterSetName -eq 'deployToSub')
    {
        Write-Verbose "Deploying Policy Initiative '$policySetName' to subscription '$subscriptionId'"
    } else {
        Write-Verbose "Deploying Policy Initiative '$policySetName' to management group '$managementGroupName'"
    }
    
    $deployParams = @{
      Name = $policySetName
      DisplayName = $policySetDisplayName
      Description = $policySetDescription
      Parameter = $policySetParameters
      PolicyDefinition = $policySetDefinition
      Metadata = $policySetMetaData
    }
    Write-Verbose "  - 'DeployPolicySetDefinition' function parameter set name: '$($PSCmdlet.ParameterSetName)'"
    If ($PSCmdlet.ParameterSetName -eq 'deployToSub')
    {
      Write-Verbose "  - Adding SubscriptionId to the input parameters for New-AzPolicySetDefinition cmdlet"
      $deployParams.Add('SubscriptionId', $subscriptionId)
    } else {
      Write-Verbose "  - Adding ManagementGroupName to the input parameters for New-AzPolicySetDefinition cmdlet"
      $deployParams.Add('ManagementGroupName', $managementGroupName)
    }
    Write-Verbose "Initiative Definition:"
    Write-Verbose $policySetDefinition
    $deployResult = New-AzPolicySetDefinition @deployParams
    $deployResult
}
#endregion

#region main
#ensure signed in to Azure
Try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    $currentTenantId = $context.Tenant.Id
    $currentSubId = $context.Subscription.Id
    $currentSubName = $context.Subscription.Name
    Write-output "You are currently signed to to tenant '$currentTenantId', subscription '$currentSubName'  using account '$($context.Account.Id).'"
    Write-Output '', "Press any key to continue using current sign-in session or Esc to login using another user account."
    $KeyPress = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    If ($KeyPress.virtualKeyCode -eq 27)
    {
      #sign out first
      Disconnect-AzAccount -AzureContext $context
      #sign in
      ProcessAzureSignIn
    }
} Catch {
    #sign in
    ProcessAzureSignIn
}

#Read initiative definition
Write-Verbose "Processing '$definitionFile'..."
$DefFileContent = Get-Content -path $definitionFile -Raw

#replace policy definition resource Ids
If ($PSBoundParameters.ContainsKey('PolicyLocations'))
{
    Write-Verbose "Replacing policy definition locations in the initiative definition file."
    Foreach ($key in $PolicyLocations.Keys)
    {
        $DefFileContent = $DefFileContent.Replace("{$key}", $PolicyLocations.$key)
    }
}
$objDef = Convertfrom-Json -InputObject $DefFileContent

#Validate definition content
If ($objDef.properties.policyDefinitions)
{
    Write-Verbose "'$definitionFile' is a policy initiative definition. It will be deployed."
    $bProceed = $true
} elseif ($objDef.properties.policyRule) {
    Write-Warning "'$definitionFile' contains a policy definition. policy definitions are not supported by this script. please use deploy-policyDef.ps1 to deploy policy definitions."
    $bProceed = $false
} else {
    Write-Error "Unable to parse '$definitionFile'. It is not a policy or initiative definition file. Content unrecognised."
    $bProceed = $false
}

#Deploy definitions
if ($bProceed -eq $true)
{
    $params = @{
        Definition = $($objDef.properties)
    }
    If ($PSCmdlet.ParameterSetName -eq 'deployToSub')
    {
        $params.Add('subscriptionId', $subscriptionId)
    } else {
        $params.Add('managementGroupName', $managementGroupName)
    }
    $deployResult = DeployPolicySetDefinition @params
}
$deployResult
#endregion