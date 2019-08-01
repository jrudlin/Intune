#requires -version 5
<#
.SYNOPSIS
  Windows 10 Login script that is run directly from Azure Blob storage:
    https://storageintune.blob.core.windows.net/intune-scripts/Win10-Login-Script.ps1
.DESCRIPTION
    For the Modern Desktop design - where devices are joined to Azure Active Directory, the login script configures the following:
    - Configures on-premises drive mappings to file shares
    - Configures on-premises print queues
    - Create user Registry settings
    - Many other tweaks and settings
.INPUTS
  Invoke-Win10-Login-Script.ps1 will create a Run key value in the HKLM reg hive, calling this script from Azure Blob storage.
.OUTPUTS
  <Log file stored in $sLogName>
.NOTES
  Version:        0.1
  Author:         Jack Rudlin
  Creation Date:  27/03/19
  Purpose/Change: Initial script development

  Version:        0.2
  Author:         Jack Rudlin
  Creation Date:  28/03/19
  Purpose/Change: Async print queue mapping. More drive mappings. Outlook Reg settings.

  Version:        0.3
  Author:         Jack Rudlin
  Creation Date:  26/04/19
  Purpose/Change: Switch new-psdrive to new-smbmapping so that drives remain mapped even when no network connection is available.
                  Also, increased maxretries on the drive mappings from 3 to 5

  Version:        0.4
  Author:         Jack Rudlin
  Creation Date:  14/06/19
  Purpose/Change: Fixed bug in Write-Registry function where value was always '1'

  Version:        0.5
  Author:         Jack Rudlin
  Creation Date:  17/06/19
  Purpose/Change: Added keyboard lang cleanup after 1903 upgrade

#>

# .Net methods for hiding/showing the console in the background
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
function Hide-Console
{
    $consolePtr = [Console.Window]::GetConsoleWindow()
    #0 hide
    [Console.Window]::ShowWindow($consolePtr, 0)
}
Hide-Console


#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
#$ErrorActionPreference = "SilentlyContinue"


#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = "0.5"

#Log File Info
$sLogPath = "$env:Temp"
$sLogName = "Win10-Login-Script.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Global Variables
$dnsDomainName = $env:USERDNSDOMAIN
$samAccountName = $env:USERNAME
$OneDriveFolder = "OneDrive - Org Name"
$CustomHKCU = "HKCU:\Software\Org Name"
$PreferredLang = "en-GB"

#-----------------------------------------------------------[Functions]------------------------------------------------------------


Function Write-Log {
    #Define and validate parameters
    [CmdletBinding()]
    Param(
        #Path to the log file
        [parameter(Mandatory=$True)]
        [String]$LogFile,

        #The information to log
        [parameter(Mandatory=$True)]
        [String]$Value,

        #The source of the error
        [parameter(Mandatory=$True)]
        [String]$Component,

        #The severity (1 - Information, 2- Warning, 3 - Error)
        [parameter(Mandatory=$True)]
        [ValidateRange(1,3)]
        [Single]$Severity
        )


    #Obtain UTC offset
    $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime
    $DateTime.SetVarDate($(Get-Date))
    $UtcValue = $DateTime.Value
    $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)

    # Delete large log file
    If(test-path -Path $LogFile -ErrorAction SilentlyContinue)
    {
        $LogFileDetails = Get-ChildItem -Path $LogFile
        If ( $LogFileDetails.Length -gt 5mb )
        {
            Remove-item -Path $LogFile -Force -Confirm:$false
        }
    }

    #Create the line to be logged
    $LogLine =  "<![LOG[$Value]LOG]!>" +`
                "<time=`"$(Get-Date -Format HH:mm:ss.fff)$($UtcOffset)`" " +`
                "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                "component=`"$Component`" " +`
                "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                "type=`"$Severity`" " +`
                "thread=`"$($pid)`" " +`
                "file=`"`">"

    #Write the line to the passed log file
    Out-File -InputObject $LogLine -Append -NoClobber -Encoding Default -FilePath $LogFile -WhatIf:$False

    Switch ($component) {

        1 { Write-Information -MessageData $Value }
        2 { Write-Warning -Message $Value }
        3 { Write-Error -Message $Value }

    }

    write-output -InputObject $Value

}

Function Get-ADGroups {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
        [String]$SamAccountName,
        [parameter(Mandatory=$True)]
        [String]$Domain
    )

    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $domain)
    $userContext = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($context, $samAccountName);
    $userGroups = New-Object System.Collections.Generic.HashSet[string]

    Function Get-GroupsMemberOf {
        param(
            [System.DirectoryServices.AccountManagement.GroupPrincipal]$Group
        )

        if (!($userGroups.Add($Group))) { 
            return 
        }

        foreach ($group in $Group.GetGroups()) {
            Get-GroupsMemberOf -Group $group
        }
    }

    if ($userContext) {
        $groups = $userContext.GetGroups()

        foreach ($group in $groups) {
            Get-GroupsMemberOf -Group $group
        }

        $userGroups

    }

}

Function Write-Registry {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
        [String]$RegKeyPath,
        [parameter(Mandatory=$True)]
        [String]$ValueName,
        [parameter(Mandatory=$False)]
        [ValidateSet('String','ExpandString','Binary','DWord','MultiString','Qword')]
        [String]$ValueType = "DWord",
        [parameter(Mandatory=$True)]
        [String]$Value

    )

    If ( -not(test-path -Path $RegKeyPath)){
        Try{
            New-Item -Path $RegKeyPath -Force | Out-Null
            Write-Log -LogFile $sLogFile -Value "Reg path [$RegKeyPath] created" -Component $Section -Severity 1
        } Catch {
            Write-Log -LogFile $sLogFile -Value "Error: Reg path [$RegKeyPath] could not be written" -Component $Section -Severity 3
            return
        }
    }

    Try{
        Set-ItemProperty -Path $RegKeyPath -Name $ValueName -Value $Value -Force -Type $ValueType
        Write-Log -LogFile $sLogFile -Value "Reg value name [$ValueName] created in [$RegKeyPath] with value [$Value]" -Component $Section -Severity 1
    } Catch {
        Write-Log -LogFile $sLogFile -Value "Error: Reg value [$ValueName] could not be written" -Component $Section -Severity 3
        return
    }

    return
}

Function Map-Drive {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
        [String]$LocalPath,
        [parameter(Mandatory=$True)]
        [String]$RemotePath,
        [parameter(Mandatory=$True)]
        [String]$Description,
        [parameter(Mandatory=$false)]
        [Switch]$Overwrite
    )
    $return = $false

    If(-not($LocalPath -match '.+?:$')){
        $LocalPath = "$LocalPath`:"
    }

    Write-Log -LogFile $sLogFile -Value "Starting Map-Drive function..." -Component $Section -Severity 1
    If($Overwrite){
        Write-Log -LogFile $sLogFile -Value "Overwrite set to: [$Overwrite]" -Component $Section -Severity 1
        Try{
            Remove-SmbMapping -LocalPath $LocalPath -Force -UpdateProfile -Confirm:$false
            Write-Log -LogFile $sLogFile -Value "Force removed: [$LocalPath]" -Component $Section -Severity 1
        } Catch {
            Write-Log -LogFile $sLogFile -Value "Error removing: [$LocalPath]. $_" -Component $Section -Severity 1
        }

    }

    
    Try{
        #New-PSDrive -PSProvider FileSystem -Name $Drive.DriveLetter -Root $Drive.UNCPath -Description $Drive.Description -Persist -Scope global
        New-SmbMapping -LocalPath $LocalPath -RemotePath $RemotePath -Persistent:$true
        Write-Log -LogFile $sLogFile -Value "Mapped network drive [$LocalPath] to: [$RemotePath]" -Component $Section -Severity 1
        (New-Object -ComObject Shell.Application).NameSpace("$LocalPath").Self.Name=$Description
        Write-Log -LogFile $sLogFile -Value "Changed description to: [$Description]" -Component $Section -Severity 1
        $return = $true
    } Catch {
        Write-Log -LogFile $sLogFile -Value "Error mapping drive [$LocalPath] to: [$RemotePath]. $_" -Component $Section -Severity 3
    }
       
    return $return
}

#-----------------------------------------------------------[Script]------------------------------------------------------------
$Section = "Script"
Write-Log -LogFile $sLogFile -Value "Starting script..." -Component $Section -Severity 1

#----------------------[User Registry]-----------------------
$Section = "Registry"
# Print
$path = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
write-registry -RegKeyPath $path -ValueName "LegacyDefaultPrinterMode" -Value 1

# Office 365 ProPlus
$path = "HKCU:\Software\Microsoft\Office\16.0\Common\General"
write-registry -RegKeyPath $path -ValueName "ShownFileFmtPrompt" -Value 1

# https://support.microsoft.com/en-gb/help/4010175/disable-the-get-and-set-up-outlook-mobile-app-on-my-phone-option
$path = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General"
write-registry -RegKeyPath $path -ValueName "DisableOutlookMobileHyperlink" -Value 1
#----------------------[Drive Mappings]-----------------------
$Section = "Drive Mappings"
$driveMappingConfig=@()

Write-Log -LogFile $sLogFile -Value "Starting Drive Mappings...." -Component $Section -Severity 1

#region drive mappings
$driveMappingConfig+= [PSCUSTOMOBJECT]@{
    DriveLetter = "S"
    UNCPath= "\\fs1.$dnsDomainName\Shared"
    Description="shared (\\fs1)"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "J"
    UNCPath= "\\fs1.$dnsDomainName\data"
    Description="data (\\fs1)"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "O"
    UNCPath= "\\SUNSRV.$dnsDomainName\saf"
    Description="saf (\\SUNSRV)"
    Group="SUN SRV USERS"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "O"
    UNCPath= "\\SUNSRV.$dnsDomainName\saf"
    Description="saf (\\SUNSRV)"
    Group="SUN SRV Admin Users"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "U"
    UNCPath= "\\fs3.$dnsDomainName\users\$env:USERNAME"
    Description="$env:USERNAME (\\fs3\users)"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "I"
    UNCPath= "\\fs1.$dnsDomainName\medialibrary"
    Description="medialibrary (\\fs1)"
    Group="medialibrary"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "I"
    UNCPath= "\\suntestsrv.$dnsDomainName\saf"
    Description="saf (\\suntestsrv)"
    Group="finance test users group"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "L"
    UNCPath= "\\fs1.$dnsDomainName\istreampay"
    Description="istreampay (\\fs1)"
    Group="IstreamPAY"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "L"
    UNCPath= "\\fs1.$dnsDomainName\istreamhr"
    Description="istreamhr (\\fs1)"
    Group="IstreamHR"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "L"
    UNCPath= "\\fs1.$dnsDomainName\istream"
    Description="istream (\\fs1)"
    Group="IStream"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "X"
    UNCPath= "\\web1.$dnsDomainName\DMapWeb"
    Description="DMapWeb (\\web1)"
    Group="DataMap Drives"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "Y"
    UNCPath= "\\web1.$dnsDomainName\DataMap"
    Description="DataMap (\\web1)"
    Group="DataMap Drives"
}

$driveMappingConfig+=  [PSCUSTOMOBJECT]@{
    DriveLetter = "G"
    UNCPath= "\\mediasrv.$dnsDomainName\Apex Documents"
    Description="Media Documents (\\mediasrv)"
    Group="Media Documents"
}
#endregion

$connected=$false
$retries=0
$maxRetries=5

do {
    
    if (Resolve-DnsName $dnsDomainName -ErrorAction SilentlyContinue){
    
        $connected=$true

    } else{
 
        $retries++
        
        Write-Log -LogFile $sLogFile -Value "Cannot resolve: $dnsDomainName, assuming no connection to fileserver" -Component $Section -Severity 2
 
        Start-Sleep -Seconds 3
 
        if ($retries -eq $maxRetries){
            
            Write-Log -LogFile $sLogFile -Value "Exceeded maximum numbers of retries ($maxRetries) to resolve dns name ($dnsDomainName)" -Component $Section -Severity 3
            return
        }
    }
 
}while( -not ($Connected))

#Get users' on-premises Active Directory group membership
Write-Log -LogFile $sLogFile -Value "Getting AD Groups for [$samAccountName] from domain [$dnsDomainName]" -Component $Section -Severity 1
$ADGroups = Get-ADGroups -SamAccountName $samAccountName -Domain $dnsDomainName -ErrorAction SilentlyContinue

If ( $ADGroups.Count -lt 1) {
    Write-Log -LogFile $sLogFile -Value "[$($ADGroups.Count)] AD Groups retrieved for [$samAccountName]. This could indicate a failure to connect to domain [$dnsDomainName]" -Component $Section -Severity 2
} else {
    Write-Log -LogFile $sLogFile -Value "[$($ADGroups.Count)] AD Groups retrieved for [$samAccountName]." -Component $Section -Severity 1
}

#Get currently mapped drives
#$CurrentlyMappedDrives = Get-PSDrive
$CurrentlyMappedDrives = Get-SmbMapping
$MappedDriveProperties = Get-CimInstance -Namespace "root\cimv2" -ClassName "Win32_NetworkConnection"
#$CurrentlyMappedDrives = $CurrentlyMappedDrives | Where-Object -Property "Root" -Match '[a-z]:\\'

#Map drives
ForEach ( $Drive in $driveMappingConfig ){

    $MapDriveForUser = $true
    $splat = @{
                Overwrite = $false
            }

    # Check if drive is already mapped
    If ( $CurrentlyMappedDrives.LocalPath -contains "$($Drive.DriveLetter):"){

        Write-Log -LogFile $sLogFile -Value "Drive mapping [$($Drive.DriveLetter):\] already exists, will now check if it's a PSDrive mapping..." -Component $Section -Severity 1
        $MapDriveForUser = $false

        If ($MappedDriveProperties | Where-Object {($_.LocalName -like "$($Drive.DriveLetter):*")-and($_.ResourceType -ne 'Disk') }){
            Write-Log -LogFile $sLogFile -Value "Existing mapped drive is not the correct ResourceType, so will remap [$($Drive.DriveLetter):\]" -Component $Section -Severity 2
            $splat = @{
                Overwrite = $true
            }
            $MapDriveForUser = $true
        } else {
            Write-Log -LogFile $sLogFile -Value "No need to remap drive." -Component $Section -Severity 1
        }
    }
    
    If($MapDriveForUser)
    {   
        If ( $Drive.Group ){
        
            $MapDriveForUser = $false

            If ( $ADGroups -contains $Drive.Group ){
                Write-Log -LogFile $sLogFile -Value "User [$samAccountName] is a member of AD group [$($Drive.Group)]" -Component $Section -Severity 1
                $MapDriveForUser = $true
            }

        }
        
        If($MapDriveForUser){
            
            Try{
                Map-Drive -LocalPath $Drive.DriveLetter -RemotePath $Drive.UNCPath -Description $Drive.Description @splat               
            } Catch {
                Write-Log -LogFile $sLogFile -Value "Error mapping network drive [$($Drive.DriveLetter):\] [$($Drive.UNCPath)] $_" -Component $Section -Severity 3
            }

            
        }

    }

}

#----------------------[Print Queues]-----------------------
$Section = "Printers"
Try{
    Write-Log -LogFile $sLogFile -Value "Mapping printer [\\printsrv1.$dnsDomainName\Follow-Me-Mono]" -Component $Section -Severity 1
    Add-Printer -ConnectionName "\\printsrv1.$dnsDomainName\Follow-Me-Mono"
    
    Write-Log -LogFile $sLogFile -Value "Mapping printer [\\printsrv2.$dnsDomainName\Follow-Me-Colour]" -Component $Section -Severity 1
    Add-Printer -ConnectionName "\\printsrv2.$dnsDomainName\Follow-Me-Colour"
}
Catch{
    Write-Log -LogFile $sLogFile -Value "Error when trying to map to printers [$_]" -Component $Section -Severity 3
}

#----------------------[Printer Default]-----------------------
# Deffered to last in the script to give the printers a chance to map first time round (they need to download drivers on first install from the print server)
$Section = "Printer default"
Try{
    Write-Log -LogFile $sLogFile -Value "Setting printer [Follow-Me-Mono] to default" -Component $Section -Severity 1

    $Printer = Get-WmiObject -Class Win32_Printer -Filter "ShareName = 'Follow-Me-Mono'"
    $Printer.SetDefaultPrinter() | Out-Null

    #$wsObject = New-Object -COM WScript.Network
    #$wsObject.SetDefaultPrinter("Follow-Me-Mono")   
}
Catch{
    Write-Log -LogFile $sLogFile -Value "Error when trying to set default printer [$_]" -Component $Section -Severity 3
}

#----------------------[Short Cuts]-----------------------
$Section = "Shortcuts"
# Remove Teams shortcut from users' desktop so that OneDrive KFM doesn't create a duplicate when it copies the desktop contents
$ShortcutsVersion = "0.2"
$ShortcutsReg = "Shortcut Cleanup"
$RemoveShortcuts = ("Microsoft Edge","Microsoft Teams","NetHelpDesk - Copy")

#If ( (Get-ItemPropertyValue -Path "$CustomHKCU\$ShortcutsReg" -Name "Version") -ne $ShortcutsVersion ) {
    Try{
        ForEach ($ShortCut in $RemoveShortcuts){
            Write-Log -LogFile $sLogFile -Value "Cleaning up desktop shortcut [$Shortcut]" -Component $Section -Severity 1
            Get-ChildItem -Path "$Env:USERPROFILE\$OneDriveFolder\Desktop\$Shortcut*.lnk" | Remove-Item -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
       
        #Write-Registry -RegKeyPath "$CustomHKCU\$ShortcutsReg" -ValueName "Version" -ValueType String -Value $ShortcutsVersion

    } Catch {
        Write-Log -LogFile $sLogFile -Value "Error whilst cleaning up user desktop shortcuts [$_]" -Component $Section -Severity 3
    }
#} else {

#}

#----------------------[Regional Settings]-----------------------
# Remove US language after 1903 upgrade
$Win10CleanupVersion = "0.1"
$Win10CleanupReg = "Win10 1903 HKCU Cleanup"

$Win10Release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).ReleaseId

If($Win10Release -eq "1903"){
    
    If ( (Get-ItemPropertyValue -Path "$CustomHKCU\$Win10CleanupReg" -Name "Version" -ErrorAction SilentlyContinue) -ne $Win10CleanupVersion ) {
        Set-WinUserLanguageList -LanguageList $PreferredLang -Force
        Write-Registry -RegKeyPath "$CustomHKCU\$Win10CleanupReg" -ValueName "Version" -ValueType String -Value $Win10CleanupVersion
    }

}