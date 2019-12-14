$ChocoPackage = "adobereader"

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

    try{
        start-process -FilePath $ChocoExe -ArgumentList "uninstall $ChocoPackage --confirm --all-versions" -Wait

    } Catch {
        throw "Could not uninstall $ChocoPackage"
        Exit 667
    }

} else {
    throw 'Could not find choco.exe'
    Exit 666
}
