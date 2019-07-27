

[CmdletBinding()]
param
(
    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$True)]
    [String]$SourceFolder,
    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$True)]
    [String]$SetupFile,
    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$False)]
    [String]$OutPutFolder = "$(Split-path -Path $SourceFolder -Parent)\_Output\$(Split-path -Path $SourceFolder -Leaf)"
)

If ( -not (test-path -Path $SourceFolder)){
    throw "Cannot find sourcefolder: [$SourceFolder]"
    return
}

If ( -not (test-path -Path "$SourceFolder\$SetupFile")){
    throw "Cannot find setupfile: [$SetupFile]"
    return
}

If ( -not (test-path -Path $OutPutFolder)){
    New-Item -Path $OutPutFolder -ItemType Directory -Force | Out-Null
}

If (-not (test-path -Path "$PSScriptRoot\IntuneWinAppUtil.exe")){
    throw "Cannot find IntuneWinAppUtil.exe at: [$PSScriptRoot]"
    return
}

Start-Process -FilePath "$PSScriptRoot\IntuneWinAppUtil.exe" -ArgumentList "-c $SourceFolder -s $SetupFile -o $OutPutFolder -q" -Wait

$SetupFilePath = (get-item -Path "$SourceFolder\$SetupFile").FullName
$fileNameOnly = [System.IO.Path]::GetFileNameWithoutExtension($SetupFilePath)
$intunewinfile = $("$fileNameOnly.intunewin")

If ( Test-Path -Path "$OutPutFolder\$intunewinfile" ) {
    Write-output -InputObject "[$intunewinfile] file succesfully created"
} else {
    throw "File [$intunewinfile] not created"
    return
}