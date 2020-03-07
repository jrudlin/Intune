$ReleaseChannel = "Monthly"
$STName = "JRIT - Choco Package Updates - $ReleaseChannel"

If((Get-ScheduledTask -TaskName $STName -ErrorAction SilentlyContinue)-and(test-path -Path "$env:ProgramFiles\JR IT\JRIT-AppPatching-$ReleaseChannel\Install.cmd")){
	write-output -InputObject "Installed"
} else {
	Throw "Failed to find Scheduled Task: [$STName]"
	Exit 666
}