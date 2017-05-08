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
$Global:TaskTab = @{}

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
    Write-Host "Enter the FQHN of the ESXi Host that was upgraded: " -ForegroundColor "Yellow" -NoNewLine
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
    "Connecting to $Global:VCName"
    Connect-VIServer $Global:VCName -Credential $Global:Creds > $null
}
#**********************
# EndFunction ConnectVC
#**********************

#********
# StartVM
#********
Function StartVM($s) {
    "Starting VM $s"
    Start-VM -RunAsync -VM $s | Out-Null
}
#********************
# EndFunction StartVM
#********************

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
Function UpgradeVMTools($s) {
    $Global:tasktab[(Update-Tools $s -RunAsync).Id] = $s
    "VMware Tools upgrade started on $s"
    #Update-Tools $s
}
#***************************
# EndFunction UpgradeVMTools
#***************************

#***********************
# Monitor-VMToolsUpgrade
#***********************
Function Monitor-VMToolsUpgrade {
    $RunningTasks = $Global:TaskTab.Count
    "VMware-Tools Upgrades are running"
    While($RunningTasks -gt 0){
        Get-Task | % {
            if($Global:TaskTab.ContainsKey($_.Id) -and $_.State -eq "Success"){
                #"$Global:TaskTab.Item($_.Id) has completed with status of Success"
                $Global:TaskTab.Remove($_.Id)
                $RunningTasks-- 
            }
        elseif($Global:TaskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
                #"$Global:TaskTab.Item($_.Id) has completed with status of Error"
                $Global:TaskTab.Remove($_.Id)
                $RunningTasks-- 
            }
        }
        Write-host -NoNewLine "."
        Start-Sleep -Seconds 7
    }
    ""
    "VMware-Tools Upgrades are complete"
}
#***********************************
# EndFunction Monitor-VMToolsUpgrade
#***********************************

#**************************
# Deploy-VMNicChangePackage
#**************************
Function Deploy-VMNicChangePackage($s){
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
#**************************************
# EndFunction Deploy-VMNicChangePackage
#**************************************

#***************************
# Execute-VMNicChangePackage
#***************************
Function Execute-VMNicChangePackage($s){
    "Starting VMNicChangeAdapter.ps1 on $s"
    invoke-wmimethod -computer $s -path Win32_process -name Create -ArgumentList "cmd /c c:\temp\CheckExecutionPolicy.bat"
    Sleep 3
    invoke-wmimethod -computer $s -path Win32_process -name Create -ArgumentList "Powershell c:\temp\VMNicChangeAdapter.ps1" -Credential $Global:CredsLocal    
}
#**************************************
# EndFunction ExecuteVMNicChangePackage
#**************************************

#************
# Add-VMXNet3
#************
Function Add-VMXNet3($s) {
    "Getting NetworkName for $s"
    $NetworkInfo = Get-NetworkAdapter -vm $s
    $NetworkName = $NetworkInfo.NetworkName
    "Adding New VMXNet3 Adapter to $s"
    New-NetworkAdapter -VM $s -NetworkName $NetworkName -Type VMXNet3 -StartConnected -Confirm:$false
}
#************************
# EndFunction Add-VMXNet3
#************************

#***********
# ShutdownVM
#***********
Function ShutdownVM($s) {
    "Shutdown VM $s"
    Shutdown-VMGuest -VM $s -Confirm:$false
}
#***********************
# EndFunction ShutdownVM
#***********************

#**************
# WaitVMStartup
#**************
Function WaitVMStartup($s){
    "Waiting to confirm startup of $s"
    Do {
        $VMToolsStatus = Check-ToolsStatus $server
        Write-host -NoNewLine "."
        sleep 5
    } until ($VMtoolsStatus -ne "NotRunning")
    "VMware Tools Status $VMtoolsStatus"
}
#**************************
# EndFunction WaitVMStartup
#**************************

#***************
# WaitVMShutdown
#***************
Function WaitVMShutdown($s) {
    "Waiting to confirm shutdown of $s"
    Do {
        $PowerStatus = (Get-VM $s).PowerState
        Write-host -NoNewLine "."
        sleep 3
        } until ($PowerStatus -eq 'Poweredoff')
        "Powered Off"
}
#***************************
# EndFunction WaitVMShutdown
#***************************

#*************
# Remove-E1000
#*************
Function Remove-E1000($s) {
    "Removing the E1000 adapter on $s"
    Get-VM "$s" | Get-NetworkAdapter | Where {$_.Type -eq "E1000"} | Remove-NetworkAdapter -Confirm:$false
}
#*************************
# EndFunction Remove-E1000
#*************************

#**************
# Take-Snapshot
#**************
Function Take-Snapshot($s) {
    "Taking Snapshot of $s"
    Get-VM $s | New-Snapshot -Name "Hardware" -Description "Snapshot before Virtual Hardware Upgrade"
}
#**************************
# EndFunction Take-Snapshot
#**************************

#****************
# Delete-Snapshot
#****************
Function Delete-Snapshot($s) {
    "Deleting Hardware Snapshot of $s"
    Get-Snapshot -Name "Hardware" -vm $s | Remove-Snapshot -confirm:$false
}
#****************************
# EndFunction Delete-Snapshot
#****************************

#*******************
# Upgrade-VMHardware
#*******************
Function Upgrade-VMHardware($s) {
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
    $vmview = Get-VM $s | Get-View
    $vmVersion = $vmView.Config.Version
 
    if ($vmVersion -ne $upgradeTo){
        "Harware level on $s requires upgrading... "
        "Upgrading Now."
        Get-View ($vmView.UpgradeVM_Task($upgradeTo)) | Out-Null
        }
}
#*******************************
# EndFunction Upgrade-VMHardware
#*******************************

#*************************
# Verify-VMHardwareUpgrade
#*************************
Function Verify-VMHardwareUpgrade($s) {
    $Global:VerifyHardware = $false

    "Waiting for VM Tools to Start on $s"
    $VMToolsStatus = Check-ToolsStatus $s
    Do {
        $VMToolsStatus = Check-ToolsStatus $s
        Write-host -NoNewline "."
        sleep 5
    } until ($VMtoolsStatus -ne "NotRunning")
    "VMware Tool status $VMtoolsStatus"
    if ($VMToolsStatus -eq "OK"){
        "VM has Started Successfully"
        $Global:VerifyHardware = $true
        }
        else{
            "There seems to be an Issue verifying the status of VMwareTools on $s.  Please Manually check the status of the VM and remove the Snapshot if requred."  
            Read-Host "Press <Enter> to Continue"
            }
}
#*************************************
# EndFunction Verify-VMHardwareUpgrade
#*************************************

#****************
# Open-RDPSession
#****************
Function Open-RDPSession($s) {
    "Starting RDP Session for $s"

    $username = $Global:CredsLocal.Username
    #unencrypting $credsLocal.Password so that we can send it to PSExec
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Global:CredsLocal.Password)
    $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    cmdkey /generic:"$s" /user:"$username" /Pass:"$pass" | Out-Null
    mstsc /v:$s /w:1024 /h:768
    #Clear unencrypted password from memory
    $pass = $null              
}
#****************************
# EndFunction Open-RDPSession
#****************************

#*************
# DisconnectVC
#*************
Function DisconnectVC {
    #Disconnect from VC
    "Disconnecting $Global:VCName"
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
#*********************
# EndFunction Clean-Up
#*********************

#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference="Continue"
$ExDate = Get-Date
Start-Transcript -path $Global:Folder\VMUpgradesLog-$ExDate.txt
"================================================="
" "
Write-Host "Get credentials for vCenter Logon" -ForegroundColor Yellow
$Global:Creds = Get-Credential -Credential $null
Get-VCenter
Get-HostName
$Global:WorkFolder = "$Global:Folder\$Global:HostName"
ConnectVC
"-------------------------------------------------"
# Get Server List from HostInformation
$servers = Get-Content "$Global:WorkFolder\server.txt"

#Start VMs
forEach ($server in $servers) {
    StartVM $server
}
"-------------------------------------------------"
#Wait for Start
forEach ($server in $servers) {
    WaitVMStartup $Server
}
"-------------------------------------------------"
#Upgrade VM Tools
forEach ($server in $servers) {
    UpgradeVMTools $server
}
"-------------------------------------------------"
#Monitor Tools Upgrade Tasks
Monitor-VMToolsUpgrade
""
"-------------------------------------------------"
#Verify, wait for VMs to start
forEach ($server in $servers) {
    WaitVMStartup $Server
}
"-------------------------------------------------"
#Add new VMXNet3 to each VM
forEach ($server in $servers) {
    Add-VMXNet3 $server
}
"-------------------------------------------------"
#Deploy VMNICChange Package
Write-Host "Get Local Credentials for VMs" -ForegroundColor Yellow
$Global:CredsLocal = Get-Credential -Credential $null
forEach ($server in $servers) {
    Deploy-VMNicChangePackage $server
}
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "* The NicChange Package has been deployed to the servers *" -ForegroundColor Yellow
Write-Host "* Opening RDP Sessions to each one                       *" -ForegroundColor Yellow
Write-Host "*--------------------------------------------------------*" -ForegroundColor Yellow 
Write-Host "*   Please Manually run the script on each one now!      *" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
forEach ($server in $servers) {
    Open-RDPSession $server
}
#Wait for aknowledgement that script has been run on each VM
Read-Host "Press <Enter> to Continue when complete." 
"-------------------------------------------------"
#Shutdown VMs
forEach ($server in $servers) {
    ShutdownVM $server
}
"-------------------------------------------------"
#Verify, wait for VMs to shutdown
forEach ($server in $servers) {
    WaitVMShutdown $server
}
"-------------------------------------------------"
#Remove E1000 Networt adapter
forEach ($server in $servers) {
    Remove-E1000 $server
}
"-------------------------------------------------"
#Take snapshot before Virtual Hardware Upgrade
forEach ($server in $servers) {
    Take-Snapshot $server
}
"-------------------------------------------------"
#Upgrade Virtual Hardware
forEach ($server in $servers) {
    Upgrade-VMHardware $server
}
"-------------------------------------------------"
#Start VMs
forEach ($server in $servers) {
    StartVM $server
}
"-------------------------------------------------"
#Verify Virtual Hardware upgrade successful
forEach ($server in $servers) {
    Verify-VMHardwareUpgrade $server
    if ($Global:VerifyHardware){
        Delete-Snapshot $server
    }
}
"-------------------------------------------------"
DisconnectVC
"-------------------------------------------------"
Write-Host "               VM Upgrades Complete" -ForegroundColor Green
"================================================="
Stop-Transcript