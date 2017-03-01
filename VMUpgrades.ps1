<# 
*******************************************************************************************************************
Authored Date:    Feb 2017
Original Author:  Graham Jensen
*******************************************************************************************************************
Purpose of Script:

    Automate the Upgrade of VMs after Host Upgrades
    - Power on VMs
    - Upgrade VMTools
    - Uninstall Intel Network Adapter
    - Remove Intel adapters in vsphere
    - add VMnet3 adapters disconnected in vsphere
    - reconfigure Nic setting IP, enable netbios over tcp
    - shutdown
    - snapshot
    - Upgrade virtual Hardware
    - Reconnect nic
    - Power on VM

    Prompted inputs:  

    Outputs:          

*******************************************************************************************************************  
Prerequisites:

    #1  This script uses the VMware modules installed by the installation of VMware PowerCLI
        ENSURE that VMware PowerCLI has been installed.  
    
        Installation media can be found here: 
        \\cihs.ad.gov.on.ca\tbs\Groups\ITS\DCO\RHS\RHS\Software\VMware

    #2  To complete necessary tasks this script will require C3 account priviledges
        you will be prompted for your C3 account and password.  The Get-Credential method
        is used for this, so credentials are maintained securely.

===================================================================================================================
Update Log:   Please use this section to document changes made to this script
===================================================================================================================
-----------------------------------------------------------------------------
Update <Date>
   Author:    <Name>
   Description of Change:
      <Description>
-----------------------------------------------------------------------------
*******************************************************************************************************************
#>

# +------------------------------------------------------+
# |        Load VMware modules if not loaded             |
# +------------------------------------------------------+
"Loading VMWare Modules"
$ErrorActionPreference="SilentlyContinue" 
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
       
    } else {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
    }
    . (join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
$ErrorActionPreference="Continue"

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\HostUpgradeInfo" 
$Global:WorkFolder = $null
$Global:VCName = $null
$Global:HostName = $null
$Global:RunDate = Get-Date
$Global:RunAgain = $null
$Global:Creds = $null
$Global:CredsLocal = $null
$Global:VerifyHardware = $null

#*****************
# Get VC from User
#*****************
Function Get-VCenter {
    #Prompt User for vCenter
    Write-Host "Enter the FQHN of the vCenter that the host currently resides in: " -ForegroundColor "Yellow" -NoNewline
    $Global:VCName = Read-Host 
}
#*******************
# EndFunction Get-VC
#*******************

#*************
# Get HostName
#*************
Function Get-HostName {
    #Prompt User for ESXi Host
    Write-Host "Enter the FQHN of the ESXi Host you want to collect data from: " -ForegroundColor "Yellow" -NoNewLine
    $Global:HostName = Read-Host
}
#*************************
# EndFunction Get-HostName
#*************************

#**********
# ConnectVC
#**********
Function ConnectVC {
    #Connect to VC using collected info
    "----------------------------------"
    "Connecting to $Global:VCName"
    Connect-VIServer $Global:VCName -Credential $Global:Creds > $null
}
#**********************
# EndFunction ConnectVC
#**********************

#*****************
# StartVMs
#*****************
Function StartVMs {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Starting VM $s"
        Start-VM -RunAsync -VM $s
    }
    $servers = $null
}
#*********************
# EndFunction StartVMs
#*********************

#*****************
# WaitVMToolsStart
#*****************
Function WaitVMToolsStart {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Waiting for VM Tools to Start on $s"
        Do {
            $toolsStatus = (Get-VM $s).extensiondata.Guest.ToolsStatus
            Write-host $toolsStatus
            sleep 10
        } until ($toolsStatus -ne 'toolsNotRunning')
    }
    $servers = $null
}
#*****************************
# EndFunction WaitVMToolsStart
#*****************************

#******************
# Check-ToolsStatus
#******************
Function Check-ToolsStatus($vm){
   $vmview = get-VM $vm | Get-View
   $status = $vmview.Guest.ToolsStatus
 
   if ($status -match "toolsOld"){
      $vmTools = "Old"}
   elseif($status -match "toolsNotRunning"){
      $vmTools = "NotRunning"}
   elseif($status -match "toolsNotInstalled"){
      $vmTools = "NotInstalled"}
   elseif($status -match "toolsOK"){
      $vmTools = "OK"}
   else{
      $vmTools = "ERROR"
	  Read-Host "The ToolsStatus of $vm is $vmTools. Press <CTRL>+C to quit the script or press <ENTER> to continue"
	  }
   return $vmTools
}
#******************************
# EndFunction Check-ToolsStatus
#******************************

#***************
# UpgradeVMTools
#***************
Function UpgradeVMTools {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Updating VMTools on $s"
        Update-Tools $s
    }
    $servers = $null
}
#***************************
# EndFunction UpgradeVMTools
#***************************

#**************************
# Deploy-VMNicChangePackage
#**************************
Function Deploy-VMNicChangePackage{
    $servers = Get-Content "$Global:WorkFolder\server.txt"
    
    forEach ($s in $servers) {
        "Connecting to C$ on $s"
        New-PSDrive REMOTE -PSProvider FileSystem -Root \\$s\c$ -Credential $Global:CredsLocal > $null
        "Check for Temp directory on $s"
        If (!(Test-Path REMOTE:\temp)) {
            New-Item REMOTE:\temp -type Directory > $Null
            "Folder Structure built"
        }
        "Copying VMSwitchAdapter package to $s"
        copy-item -path $Global:Folder\VMNicChangeAdapter\*.* REMOTE:\temp\ -force

        "Disconnect $s" 
        Remove-PSDrive REMOTE
    }    
}
#**************************************
# EndFunction Deploy-VMNicChangePackage
#**************************************

#***************************
# Execute-VMNicChangePackage
#***************************
Function Execute-VMNicChangePackage{
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Starting VMNicChangeAdapter.ps1 on $s"
        invoke-wmimethod -computer $s -path Win32_process -name Create -ArgumentList "cmd /c c:\temp\CheckExecutionPolicy.bat"
        Sleep 3
        invoke-wmimethod -computer $s -path Win32_process -name Create -ArgumentList "Powershell c:\temp\VMNicChangeAdapter.ps1" -Credential $Global:CredsLocal    
    }
}
#**************************************
# EndFunction ExecuteVMNicChangePackage
#**************************************

#************
# Add-VMXNet3
#************
Function Add-VMXNet3 {
    $servers = Get-Content "$Global:WorkFolder\server.txt"
    
    forEach ($s in $servers) {
        "Getting NetworkName for $s"
        $NetworkInfo = Get-NetworkAdapter -vm $s
        $NetworkName = $NetworkInfo.NetworkName
        "Adding New VMXNet3 Adapter to $s"
        New-NetworkAdapter -VM $s -NetworkName $NetworkName -Type VMXNet3 -StartConnected -Confirm:$false
    }
    $servers = $null  
}
#************************
# EndFunction Add-VMXNet3
#************************

#************
# ShutdownVMs
#************
Function ShutdownVMs {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Shutdown VM $s"
        Shutdown-VMGuest -VM $s -Confirm:$false
    }
    $servers = $null    
}
#************************
# EndFunction ShutdownVMs
#************************

#***************
# WaitVMShutdown
#***************
Function WaitVMShutdown {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers) {
        "Waiting to confirm shutdown of $s"
        Do {
           $PowerStatus = (Get-VM $s).PowerState
            Write-host $PowerStatus
            sleep 3
        } until ($PowerStatus -eq 'Poweredoff')
    }
    $servers = $null
}
#***************************
# EndFunction WaitVMShutdown
#***************************

#*************
# Remove-E1000
#*************
Function Remove-E1000 {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers){
        "Removing the E1000 adapter on $s"
        Get-VM "$s" | Get-NetworkAdapter | Where {$_.Type -eq "E1000"} | Remove-NetworkAdapter -Confirm:$false
    }
    $servers = $null

}
#*************************
# EndFunction Remove-E1000
#*************************

#**************
# Take-Snapshot
#**************
Function Take-Snapshot {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers){
        "Taking Snapshot of $s"
        Get-VM $s | New-Snapshot -Name "Hardware" -Description "Snapshot before Virtual Hardware Upgrade"
    }
    $servers = $null
}
#**************************
# EndFunction Take-Snapshot
#**************************

#****************
# Delete-Snapshot
#****************
Function Delete-Snapshot {
    $servers = Get-Content "$Global:WorkFolder\server.txt"

    forEach ($s in $servers){
        "Deleting Hardware Snapshot of $s"
        Get-Snapshot -Name "Hardware" -vm $s | Remove-Snapshot -confirm:$false
    }
    $servers = $null
}
#****************************
# EndFunction Delete-Snapshot
#****************************

#*******************
# Upgrade-VMHardware
#*******************
Function Upgrade-VMHardware {
    $servers = Get-Content "$Global:WorkFolder\server.txt"
    $v11 = "vmx-11"
    $v10 = "vmx-10"
    
    #Get Host Version to determine which Hardware Version to upgrade to
    $vmhost = Get-VMHost $Global:HostName
    if ($vmhost.Version -eq "6.0.0"){
        $upgradeTo = $v11
        }
        ElseIf ($vmhost.Version -eq "5.5.0"){
            $upgradeTo = $v10
            }
            Else{
                $upgradeTo = "ERROR"
                Read-Host "The Host is not version 5.5.0 or 6.0.0.  This is unusual. Press <CTRL>+C to quit the script or press <ENTER> to continue"
            }
    
    #Perform Hardware Upgrade
    forEach ($s in $servers){
        $vmview = Get-VM $s | Get-View
        $vmVersion = $vmView.Config.Version

 
        if ($vmVersion -ne $upgradeTo){
            "Harware level on $s requires upgrading... "
            "Upgrading Now."
            Get-View ($vmView.UpgradeVM_Task($upgradeTo)) | Out-Null
            }
        }
}
#*******************************
# EndFunction Upgrade-VMHardware
#*******************************

#*************************
# Verify-VMHardwareUpgrade
#*************************
Function Verify-VMHardwareUpgrade {
    $servers = Get-Content "$Global:WorkFolder\server.txt"
    $Global:VerifyHardware = $false
    forEach ($s in $servers){
        "Waiting for VM Tools to Start on $s"
        $VMToolsStatus = Check-ToolsStatus $s
        Do {
            $VMToolsStatus = Check-ToolsStatus $s
            Write-host $VMToolsStatus
            sleep 10
        } until ($VMtoolsStatus -ne "NotRunning")
        if ($VMToolsStatus -eq "OK"){
            "VM has Started Successfully"
            $Global:VerifyHardware = $true
        }
            else{
                "There seems to be an Issue verifying the status of VMwareTools on $s.  Please Manually check the status of the VM and remove the Snapshot if requred."  
                Read-Host "Press <Enter> to Continue"
            }
    }
        $servers = $null
}
#*************************************
# EndFunction Verify-VMHardwareUpgrade
#*************************************


#*************
# DisconnectVC
#*************
Function DisconnectVC {
    #Disconnect from VC
    "Disconnecting $Global:VCName"
    "-----------------------------------------"
    Disconnect-VIServer -Server $Global:VCName -Confirm:$false
}
#*************************
# EndFunction DisconnectVC
#*************************

#*********************
# Clean Up after Run
#*********************
Function Clean-Up {
    $Global:Folder = $null
    $Global:WorkFolder = $null
    $Global:VCName = $null
    $Global:HostName = $null
    $Global:RunDate = $null
    $Global:Creds = $null
    $Global:CredsLocal = $null
    $Global:VerifyHardware = $null
}

#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference="Continue"
Start-Transcript -path $Global:Folder\VMUpgradesLog.txt
"================================================="
" "
$Global:Creds = Get-Credential
Get-VCenter
Get-HostName
$Global:WorkFolder = "$Global:Folder\$Global:HostName"
ConnectVC

StartVMs
WaitVMToolsStart
UpgradeVMTools
WaitVMToolsStart
Add-VMXNet3

#Deploy VMNICSwitch Package
"Get Local Credentials for VM"
$Global:CredsLocal = Get-Credential
Deploy-VMNicChangePackage
#Execute-VMNicChangePackage
#Sleep 10
"The NicChange Package has been deployed to the servers.  Please Manually the script on each one now!"  
Read-Host "Press <Enter> to Continue when complete."

ShutdownVMs
WaitVMShutdown
Remove-E1000
Take-Snapshot
Upgrade-VMHardware
StartVMs
Verify-VMHardwareUpgrade
if ($Global:VerifyHardware){
    Delete-Snapshot
}
DisconnectVC
Stop-Transcript