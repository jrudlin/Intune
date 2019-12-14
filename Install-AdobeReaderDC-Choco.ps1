$ChocoPackage = "adobereader"
$Params = '"/NoUpdates"'


# Check if Chocolatey is installed and if not, install it.
If ( get-command -Name choco.exe -ErrorAction SilentlyContinue ){
    $ChocoExe = "choco.exe"
} elseif (test-path -Path (Join-Path -path $Env:ALLUSERSPROFILE -ChildPath "Chocolatey\bin\choco.exe")) {
    $ChocoExe = Join-Path -path $Env:ALLUSERSPROFILE -ChildPath "Chocolatey\bin\choco.exe"
} else {
    try {
        write-output "Starting to install chocolatey...."
        Invoke-Expression ((New-Object -TypeName net.webclient).DownloadString('https://chocolatey.org/install.ps1')) -ErrorAction Stop
        choco feature enable -n allowGlobalConfirmation
        $ChocoExe = Join-Path -path $Env:ALLUSERSPROFILE -ChildPath "Chocolatey\bin\choco.exe"
    }
    catch {
        Throw "Failed to install Chocolatey"
    } 
}

If ($ChocoExe){

    start-process -FilePath $ChocoExe -ArgumentList "upgrade $ChocoPackage --force --confirm --install-if-not-installed -params $Params" -Wait
    
} else {
    throw 'Could not find choco.exe'
    Exit 666
}
