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

#************************
# Monitor VMTools Upgrade
#************************
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
        Start-Sleep -Seconds 5
    }
    ""
    "VMware-Tools Upgrades are complete"
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
