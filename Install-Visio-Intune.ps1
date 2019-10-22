# Install Visio for O365 ProPlus interactively so that users can see progress, errors and apps that need closing
# By Jack Rudlin
# 05/05/19

$O365XML = "Visio-with-Office-365-PP.xml"

$ODT_URL = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=49117"
$Setupexe = "setup.exe"
$ServiceUIexe = "serviceui.exe"

$ScriptDir = $PSScriptRoot
$O365XMLPath = "$ScriptDir\$O365XML"

#Script Version
$sScriptVersion = "0.1"

#Log File Info
$sLogPath = "$env:Temp"
$sLogName = "Visio-Install.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
$Section = "Visio Install"


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

    #write-output -InputObject $Value

}


function Get-ODTUri {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [ValidateNotNullOrEmpty()] 
        [string]$URL
    )

    
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $URL -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log -LogFile $sLogFile -Value "Failed to connect to ODT: $url with error $_." -Component $Section -Severity 3
        Break
    }
    finally {
        $ODTUri = $response.links | Where-Object {$_.outerHTML -like "*click here to download manually*"}
        Write-Output $ODTUri.href
    }
}

# Script start
Write-Log -LogFile $sLogFile -Value "Starting script [$PSCommandPath] version: [$sScriptVersion]....." -Component $Section -Severity 1

Try{
    $URL = $(Get-ODTUri -URL $ODT_URL)
    Remove-Item -Path "$ScriptDir\officedeploymenttool.exe" -Force -Recurse -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile "$ScriptDir\officedeploymenttool.exe"
    Write-Log -LogFile $sLogFile -Value "officedeploymenttool.exe downloaded to: [$ScriptDir]" -Component $Section -Severity 1
} Catch {
    Write-Log -LogFile $sLogFile -Value "Downloading latest ODT failed. $_" -Component $Section -Severity 1
}

If((Test-Path -Path "$ScriptDir\officedeploymenttool.exe")-and(Test-Path -Path "$ScriptDir\$Setupexe")){
    Try{
        $LatestODTVersion = (Get-Command "$ScriptDir\officedeploymenttool.exe").FileVersionInfo.FileVersion
        $SetupVersion = (Get-Command "$ScriptDir\$Setupexe").FileVersionInfo.FileVersion

        If($LatestODTVersion -gt $SetupVersion){
            Write-Log -LogFile $sLogFile -Value "Newer version of ODT setup exists: [$LatestODTVersion]. Extracting setup.exe...." -Component $Section -Severity 1
            remove-item -Path "$ScriptDir\$Setupexe" -Force -Recurse
            & "$ScriptDir\officedeploymenttool.exe" /quiet /extract:"$ScriptDir"

        }
    } Catch {
        Write-Log -LogFile $sLogFile -Value "Error working with setup exe's. $_" -Component $Section -Severity 3
    }
} else {
    Write-Log -LogFile $sLogFile -Value "Could not find all files needed for comparison." -Component $Section -Severity 3
}

Try{
    Write-Log -LogFile $sLogFile -Value "Starting: [$("$ScriptDir\$ServiceUIexe")]" -Component $Section -Severity 1

    & "$ScriptDir\$ServiceUIexe" -process:explorer.exe $Setupexe /configure $O365XML
    
} Catch {
    Write-Log -LogFile $sLogFile -Value "serviceui exited with error: $_" -Component $Section -Severity 3
}