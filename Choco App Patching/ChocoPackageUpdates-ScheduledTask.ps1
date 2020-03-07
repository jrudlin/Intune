

# Create a Scheduled Task that runs a Invoke-ChocoPackageUpdates.ps1 script for Windows 10
# The ST runs a local script, which calls Chocolately to update all out-dated packages (that were originally installed by Chocolately)
# The ST will run only at specified schedules, in order stagger updates and group/stage pilot/test/UAT machines.
# The ST can run at computer startup to ensure that all apps are closed and that the update will be succesful

# By Jack Rudlin
# 14/12/19

[CmdletBinding()]
Param(
    [parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [alias("Release","Release Channel")]
    [ValidateSet('Monthly','Quarterly')]
    $ReleaseChannel = "Quarterly"
)


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

Function New-ScheduledTaskFolder {

     Param ($taskpath)

     $ErrorActionPreference = "stop"

     $scheduleObject = New-Object -ComObject schedule.service

     $scheduleObject.connect()

     $rootFolder = $scheduleObject.GetFolder("\")

        Try {$null = $scheduleObject.GetFolder($taskpath)}

        Catch { $null = $rootFolder.CreateFolder($taskpath) }

        Finally { 
          #$ErrorActionPreference = "continue" 
        }
}
    
#Script Version
$sScriptVersion = "0.2"

#Log File Info
$sLogPath = "$env:Temp"
$sLogName = "Choco Package Updates-ST.log"
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
$Section = "Choco Package Updates ST"

# Variables
$STPath = "JR IT"
$STName = "JRIT - Choco Package Updates - $ReleaseChannel"
$ScriptsFolder = "$env:ProgramFiles\JR IT\JRIT-AppPatching-$ReleaseChannel"
$PSADTFolder = "PSADT"
$PSADTexe = "Install.cmd"
$PSADTexeFullPath = Join-Path -Path $ScriptsFolder -ChildPath $PSADTexe
$STCommand = "`"$PSADTexeFullPath`""

 # Scheduled Task Triggers
 $STMonthlyTrigger = @("January","February","March","April","May","June","July","August","September","October","November","December") 
 $STQuarterlyTrigger = @("January","April","July","October")

# Script start
Write-Log -LogFile $sLogFile -Value "Starting script [$PSCommandPath] version: [$sScriptVersion]....." -Component $Section -Severity 1

# Create ST folder if it doesn't exist
Try {
    New-ScheduledTaskFolder -taskpath $STPath
    Write-Log -LogFile $sLogFile -Value "Created Scheduled Task folder [$STPath]" -Component $Section -Severity 1
} Catch {
    Write-Log -LogFile $sLogFile -Value "Error creating Scheduled Task folder [$STPath]. $_" -Component $Section -Severity 3
    break
}

# Create JR IT Scripts folder in case it doesn't already exist
$ScriptDir = $PSScriptRoot
Write-Log -LogFile $sLogFile -Value "Script dir: [$ScriptDir]" -Component $Section -Severity 1
New-Item -Path "$ScriptsFolder" -ItemType Directory -Force -Confirm:$false -ErrorAction SilentlyContinue

# Remove previous version
Remove-Item "$ScriptsFolder" -Force -Recurse -ErrorAction SilentlyContinue

# Copy PSADT contents locally
If ( test-path -Path ".\$PSADTFolder\" ) {
    Copy-Item -Path ".\$PSADTFolder\" -Recurse -Destination "$ScriptsFolder"
    Write-Log -LogFile $sLogFile -Value "Copied [$PSADTFolder] to [$("$ScriptsFolder")]" -Component $Section -Severity 1
} else {
    Write-Log -LogFile $sLogFile -Value "Could not find [$PSADTFolder]" -Component $Section -Severity 3
    break
}

[xml]$STxml = '<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2019-06-11T21:16:12.6350454</Date>
    <Author>NETWORKHG\JRudlin</Author>
    <Description>The ST runs a local script (PowerShell App Deployment Toolkit aka PSADT), which calls Chocolatey, on scheduled release channel basis (Monthly or Quarterly). Choco will then upgrade all apps that it manages.</Description>
    <URI></URI>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT6H</Interval>
        <Duration>P2D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2019-06-01T09:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>P2D</RandomDelay>
      <ScheduleByMonthDayOfWeek>
        <Weeks>
          <Week>2</Week>
        </Weeks>
        <DaysOfWeek>
          <Monday />
        </DaysOfWeek>
        <Months>
          <January />
          <February />
          <March />
          <April />
          <May />
          <June />
          <July />
          <August />
          <September />
          <October />
          <November />
          <December />
        </Months>
      </ScheduleByMonthDayOfWeek>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT4H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command></Command>
    </Exec>
  </Actions>
</Task>'

Write-Log -LogFile $sLogFile -Value "Creating Scheduled Task [$STPath] using XML...." -Component $Section -Severity 1

Try {
    $URI = "\$(Join-Path -Path $STPath -ChildPath $STName)"
    $STxml.Task.RegistrationInfo.URI = $URI
    Write-Log -LogFile $sLogFile -Value "Modified xml with URI: [$URI]" -Component $Section -Severity 1

    $STxml.Task.Actions.Exec.Command = $STCommand
    Write-Log -LogFile $sLogFile -Value "Modified xml with command: [$STCommand]" -Component $Section -Severity 1

    If($ReleaseChannel -ne 'Monthly'){
      Write-Log -LogFile $sLogFile -Value "Updating triggers as ReleaseChannel: [$ReleaseChannel] specified" -Component $Section -Severity 1
      
      ForEach($TriggerMonth in $STMonthlyTrigger){

        If($STQuarterlyTrigger -notcontains $TriggerMonth){
          
          $RemoveNode =  $STxml.Task.Triggers.CalendarTrigger.ScheduleByMonthDayOfWeek.Months.ChildNodes | ? Name -eq $TriggerMonth
          Write-Log -LogFile $sLogFile -Value "Removing trigger: [$TriggerMonth] from XML" -Component $Section -Severity 1
          $STxml.Task.Triggers.CalendarTrigger.ScheduleByMonthDayOfWeek.Months.RemoveChild($RemoveNode) | Out-Null

       }

      }
     
    } else {
      
      Write-Log -LogFile $sLogFile -Value "Removing random delay from ST as ReleaseChannel: [$ReleaseChannel] specified" -Component $Section -Severity 1
      $DelayChild = $STxml.Task.Triggers.CalendarTrigger.ChildNodes | ? Name -eq "RandomDelay"
      $STxml.Task.Triggers.CalendarTrigger.RemoveChild($DelayChild) | Out-Null

    }

    # Convert XML back to string
    $XML = $STxml.OuterXml
    
    # Remove previous versions of the ST
    $STtoDel = Get-ScheduledTask -TaskPath "\$STPath\" -TaskName "*Choco Package Updates*"
    $STtoDel | Unregister-ScheduledTask -Confirm:$false
    
    # Create the Scheduled Task
    Register-ScheduledTask -Xml $XML -TaskName $STName -TaskPath $STPath -Force -ErrorAction Stop
    Write-Log -LogFile $sLogFile -Value "Scheduled Task [$STPath] created" -Component $Section -Severity 1
} Catch {
    Write-Log -LogFile $sLogFile -Value "Error creating Scheduled Task [$STPath] using XML. $_" -Component $Section -Severity 3
}
