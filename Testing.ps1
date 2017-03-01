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

#********************************
# Check-PowerShellExecutionPolicy
#********************************
Function Check-PowerShellExecutionPolicy {
    $servers = Get-Content "$Global:WorkFolder\server.txt"
    
    forEach ($s in $servers) {
        
    }    


}
#********************************************
# EndFunction Check-PowerShellExecutionPolicy
#********************************************


#***************
# Execute Script
#***************
CLS

$Global:Creds = Get-Credential
#Get-VCenter
$Global:VCName = "142.145.180.35"
#Get-HostName
$Global:HostName = "142.145.180.68"
$Global:WorkFolder = "$Global:Folder\$Global:HostName"
ConnectVC
Add-VMXNet3
Sleep 10
#DisconnectVC
#Deploy VMNICSwitch Package
"Get Local Credentials for VM"
$Global:CredsLocal = Get-Credential
Deploy-VMNicChangePackage
Execute-VMNicChangePackage