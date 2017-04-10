<# 
*******************************************************************************************************************
Authored Date:    Feb 2017
Original Author:  Graham Jensen
*******************************************************************************************************************
Purpose of Script:

    Automate the Switch from E1000 network adapter to VMXNet3
    - Capture Current IP Configuration of E1000 adatper
    - Uninstall the E1000 adapter using the DevCon.exe utility
    - Apply the IP configuration to the new VMXNet3 adapter
    - Disable IPv6 on the new VMXNet3 adapter using the nvspbind.exe utility

    This script is sent to the VM to be upgraded via the VMUpgrades Master Script.  And Scheduled for execution.

    Prompted inputs:  

    Outputs:          

*******************************************************************************************************************  
Prerequisites:

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

# -----------------------
# Define Global Variables
# -----------------------
$Global:IPAddress  = $null            
$Global:SubnetMask  = $null          
$Global:DefaultGateway = $null           
$Global:DNSServers  = $null            
$Global:IsDHCPEnabled = $null
$Global:Folder = "c:\temp"

#*************
# Get-IpConfig
#*************
Function Get-IpConfig {
    $Networks = Get-WmiObject Win32_NetworkAdapterConfiguration -EA Stop | Where {$_.Description -like "Intel(R)*"}
           
foreach ($Network in $Networks) {            
    $Global:IPAddress  = $Network.IpAddress[0]            
    $Global:SubnetMask  = $Network.IPSubnet[0]            
    $Global:DefaultGateway = $Network.DefaultIPGateway            
    $Global:DNSServers  = $Network.DNSServerSearchOrder            
    $Global:IsDHCPEnabled = $false            
    If($network.DHCPEnabled) {            
     $Global:IsDHCPEnabled = $true            
    }            
}
}
#*************************
# EndFunction Get-IpConfig
#*************************

#*****************
# Display-IPConfig
#*****************
Function Display-IPConfig {
    "     IP Information"
    "     =============="
    "     IP Address = $Global:IPAddress"
    "     SubnetMask = $Global:SubnetMask"
    "     DefaultGateway = $Global:DefaultGateway"
    "     DNSServers = $Global:DNSServers"
    "     DHCP Enabled = $Global:IsDHCPEnabled"
    " "
}
#*****************************
# EndFunction Display-IPConfig
#*****************************

#***********************
# UnInstall-IntelAdapter
#***********************
Function UnInstall-IntelAdapter {
    Set-Location -Path c:\temp
    .\devcon.exe remove =net PCI\VEN_8086
    " "
}
#***********************************
# EndFunction UnInstall-IntelAdapter
#***********************************

#*********************
# Set-VMXNetProperties
#*********************
Function Set-VMXNetProperties {
    $VMXNet = Get-WmiObject Win32_NetworkAdapterConfiguration -EA Stop | Where {$_.Description -like "vmxnet3*"}
    "Setting IP Address and SubnetMask"
    $VMXNet.EnableStatic($Global:IPAddress, $Global:SubnetMask) | Out-Null
    "Setting Gateway"
    $VMXNet.SetGateways($Global:DefaultGateway) | Out-Null
    "Applying DNS Servers"
    $VMXNet.SetDNSServerSearchOrder($Global:DNSServers) | Out-Null
    #Enable NetBios
    "Enabling NetBios"
    $VMXNet.SetTCPIPNetBios(1) | Out-Null
    #Rename NetworkConnection
    "Renaming Adapter to User-Facing"
    $VMXAdapter = Get-WmiObject Win32_NetworkAdapter | Where {$_.Name -like "vmxnet3*"}
    $VMXAdapter.NetConnectionID = "User-Facing"
    $VMXAdapter.Put() | Out-Null

    #Disable IPv6
    "Disabling IPv6 on the VMXNet3 adapter"
    Set-Location -Path c:\temp
    .\nvspbind.exe -d "User-Facing" ms_tcpip6 |Out-Null
}
#*********************************
# EndFunction Set-VMXNetProperties
#*********************************

#***************************
# TurnOff-NicPowerManagement
#***************************
Function TurnOff-NicPowerManagement {
    "Disable `"Allow the computer to turn off this device to save power`""
    $VMXNet = Get-WmiObject Win32_NetworkAdapter | Where {$_.Name -like "vmxnet3*"}
    $strNetworkAdapterID=$VMXNet.PNPDeviceID.ToUpper()
    Get-WmiObject -Class MSPower_DeviceEnable -Namespace "root\WMI" | % {
        if($_.InstanceName.ToUpper().startsWith($strNetworkAdapterID)){
            $_.Enable = $false
            $_.Put() | Out-Null
            }
        }
    
    "Disable `"Allow this device to wake the computer`""
    Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace "root\WMI" | % {
        if($_.InstanceName.ToUpper().startsWith($strNetworkAdapterID)){
            $_.Enable = $false
            $_.Put() | Out-Null
            }
        }

    "Disable `"Only allow a magic packet to wake the computer`""
    Get-WmiObject -Class MSNdis_DeviceWakeOnMagicPacketOnly -Namespace "root\WMI" | % {
        if($_.InstanceName.ToUpper().startsWith($strNetworkAdapterID)){
            $_.EnableWakeOnMagicPacketOnly = $false
            $_.Put() | Out-Null
            }
        }

}
#***************************************
# EndFunction TurnOff-NicPowerManagement
#***************************************

#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference="Continue"
Start-Transcript -path $Global:Folder\VMSwitchAdapterLog.txt
"================================================="
" "

"Getting IP Info for the Legacy Adapter"
"======================================"
" "
Get-IpConfig

Display-IpConfig

"UnInstalling the E1000 adapter from Device Manager"
"=================================================="
UnInstall-IntelAdapter

"Configuring the new VMXNet3 Adapter"
"==================================="
Set-VMXNetProperties
TurnOff-NicPowerManagement


""
"Switch Adapter Complete"
"======================="
Stop-Transcript
