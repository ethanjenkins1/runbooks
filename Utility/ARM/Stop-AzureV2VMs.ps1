<#PSScriptInfo

.VERSION 1.0

.GUID 6f24a778-a8f8-43ff-9b74-721bc21bf571

.AUTHOR AzureAutomationTeam

.COMPANYNAME Microsoft

.COPYRIGHT 

.TAGS AzureAutomation OMS VirtualMachines Utility

.LICENSEURI 

.PROJECTURI https://github.com/azureautomation/runbooks/blob/master/Utility/Stop-AzureV2VMs.ps1

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
  Connects to Azure and stops all VMs in the specified Azure subscription or resource group

.DESCRIPTION
  This runbook connects to Azure and stops all VMs in an Azure subscription or resource group.  
  You can attach a schedule to this runbook to run it at a specific time. Note that this runbook does not stop
  Azure classic VMs.

.PARAMETER ResourceGroupName
   Optional
   Allows you to specify the resource group containing the VMs to stop.  
   If this parameter is included, only VMs in the specified resource group will be stopped, otherwise all VMs in the subscription will be stopped.  

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

# Stop each of the VMs
foreach ($VM in $VMs) {
	$StopRtn = $VM | Stop-AzVM -Force -ErrorAction Continue

	if (!$StopRtn.IsSuccessStatusCode) {
		# The VM failed to stop, so send notice
        Write-Output ($VM.Name + " failed to stop")
        Write-Error ($VM.Name + " failed to stop. Error was:") -ErrorAction Continue
		Write-Error (ConvertTo-Json $StopRtn) -ErrorAction Continue
	}
	else {
		# The VM stopped, so send notice
		Write-Output ($VM.Name + " has been stopped")
	}
}
