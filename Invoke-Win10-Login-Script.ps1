$Azure_Blog_Storage_Script_Url= "https://storageintune.blob.core.windows.net/intune-scripts/Win10-Login-Script.ps1"

# Run login script only for specific users
    #$regKeyLocation="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# Run login script for all users
    $regKeyLocation="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"

$psCommand= "PowerShell.exe -ExecutionPolicy Bypass -windowstyle hidden -command $([char]34)& {(Invoke-RestMethod '$Azure_Blog_Storage_Script_Url').Replace('ï','').Replace('»','').Replace('¿','') | Invoke-Expression}$([char]34)"

if (-not(Test-Path -Path $regKeyLocation)){
    New-Item -Path $regKeyLocation -Force | Out-Null
}

Set-ItemProperty -Path $regKeyLocation -Name "LoginScript" -Value $psCommand -Force

# Run the login script immediately rather than waiting for the next login:
    #Invoke-Expression -Command $psCommand