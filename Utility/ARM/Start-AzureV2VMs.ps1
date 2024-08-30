<#PSScriptInfo

.VERSION 1.0

.GUID 275df928-7113-4130-a483-c2c95bb5b7ba

.AUTHOR AzureAutomationTeam

.COMPANYNAME Microsoft

.COPYRIGHT 

.TAGS AzureAutomation OMS VirtualMachines Utility

.LICENSEURI 

.PROJECTURI https://github.com/azureautomation/runbooks/blob/master/Utility/Start-AzureV2VMs.ps1

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

#>

#Requires -Module Az.Accounts
#Requires -Module Az.Compute

<#
.SYNOPSIS
  Connects to Azure and starts all VMs in the specified Azure subscription or resource group

.DESCRIPTION
  This runbook connects to Azure and starts all VMs in an Azure subscription or resource group.  
  You can attach a schedule to this runbook to run it at a specific time. Note that this runbook does not stop
  Azure classic VMs.

.PARAMETER ResourceGroupName
   Optional
   Allows you to specify the resource group containing the VMs to start.  
   If this parameter is included, only VMs in the specified resource group will be started, otherwise all VMs in the subscription will be started.  

.NOTES
   AUTHOR: Azure Automation Team 
   LASTEDIT: August 30, 2024
#>

# Returns strings with status messages
[OutputType([String])]

param (
    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName
)

try {
    # Log in to Azure using the Managed Identity of the Automation Account
    Write-Output "Logging in to Azure using Managed Identity..."
    $AzContext = Connect-AzAccount -Identity -ErrorAction Stop
}
catch {
    throw "Failed to log in to Azure using Managed Identity. Error: $_"
}

# If there is a specific resource group, then get all VMs in the resource group,
# otherwise get all VMs in the subscription.
if ($ResourceGroupName) { 
	$VMs = Get-AzVM -ResourceGroupName $ResourceGroupName
}
else { 
	$VMs = Get-AzVM
}

# Start each of the VMs
foreach ($VM in $VMs) {
	$StartRtn = $VM | Start-AzVM -ErrorAction Continue

	if (!$StartRtn.IsSuccessStatusCode) {
		# The VM failed to start, so send notice
        Write-Output ($VM.Name + " failed to start")
        Write-Error ($VM.Name + " failed to start. Error was:") -ErrorAction Continue
		Write-Error (ConvertTo-Json $StartRtn) -ErrorAction Continue
	}
	else {
		# The VM started, so send notice
		Write-Output ($VM.Name + " has been started")
	}
}
