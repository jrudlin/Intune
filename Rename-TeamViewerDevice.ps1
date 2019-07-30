#Define Auth Token
$token = "5572078-oiaoGKRf1VrtYXD7UWRO"
$NamingPatternMatch = '\[(.+)\]' # \[ matches the character [ literally (case insensitive)
                                 # 1st Capturing Group (.+)
                                 # .+ matches any character (except for line terminators)
                                 # + Quantifier — Matches between one and unlimited times, as many times as possible, giving back as needed (greedy)
                                 # \] matches the character ] literally (case insensitive)

Function Get-TVDevice {

    #Download & Set DeviceList Variable

    $ContentType = 'application/json; charset=utf-8'
    $Uri = 'https://webapi.teamviewer.com/api/v1/devices/'
            
    Write-Verbose -Message "[GET] RestMethod: [$Uri]"                        

    $Result = Invoke-RestMethod -Method Get -Uri $Uri -Headers $header -ContentType $ContentType -ErrorVariable TVError -ErrorAction SilentlyContinue
                
    if ($TVError)
        {
        $JsonError = $TVError.Message | ConvertFrom-Json
        $HttpResponse = $TVError.ErrorRecord.Exception.Response
        Throw "Error: $($JsonError.error) `nDescription: $($JsonError.error_description) `nErrorCode: $($JsonError.error_code) `nHttp Status Code: $($HttpResponse.StatusCode.value__) `nHttp Description: $($HttpResponse.StatusDescription)"
        }
    else 
        {
        Write-Verbose -Message "Setting Device List to variable for use by other commands."
        }

        return $Result.devices

}

Function Rename-TVDevice {
    Param(
     [string]$DeviceID,
     [string]$NewAlias
    )

    #Define URL For Request.
    $ReqURI = 'https://webapi.teamviewer.com/api/v1/devices/' + $DeviceID

    #Define Body For Request.

    $Jsonbody= @{
        'alias' = $NewAlias
    } | ConvertTo-Json

    #Send Request
    try{
        $Response = Invoke-RestMethod -Header $header -Method PUT -ContentType 'application/json' -Uri $ReqURI -Body $Jsonbody -Verbose | fl *
        return $true
    } Catch{
        return "$_"
    }

}

Function  Get-IntuneDevicePrimaryUser {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()] 
        [string]$DeviceName
    )

    Try{
        $PrimaryUser = ($AllIntuneDevices | Where-Object {$_.devicename -eq $DeviceName} | Sort-Object -Descending -Property enrolledDateTime | select-object -First 1).userDisplayName
        $return = $PrimaryUser
    } Catch {
        write-error -Message "Problem retrieving info for device: [$DeviceName]. $_"
        $return = $false
    }
     
    return $return
}

Import-Module -Name Microsoft.Graph.Intune

# Connect to MS Graph API
Connect-MSGraph -PSCredential $creds -ErrorAction Stop

# TeamViewer Authentication
$bearer = "Bearer",$token
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("authorization", $bearer)

# Get all Teamviewer devices
$AllTVDevices = Get-TVDevice
Write-Output -InputObject "[$($AllTVDevices.Count)] devices retrieved from Teamviewer API"

# Get all Intune devices
$AllIntuneDevices = Get-IntuneManagedDevice -ErrorAction Stop


If($AllIntuneDevices.Count -gt 0){
    Write-Output -InputObject "[$($AllIntuneDevices.Count)] devices retrieved from Intune API"
    ForEach($TVDevice in $AllTVDevices){
        $NewAlias = $null
        $Alias = $TVDevice.alias
        $DeviceID = $TVDevice.device_id
        
        write-output -InputObject "`nGetting Intune primary user for TV Device: [$Alias]...."
        If($Alias -match $NamingPatternMatch){
            $TVDeviceName = $Alias.split(' ')[0]
        } else {
            $TVDeviceName = $Alias
        }

        $PrimaryUser = Get-IntuneDevicePrimaryUser -DeviceName $TVDeviceName
        If($PrimaryUser){
            Write-Information -MessageData "Primary user for device: [$TVDeviceName] retrieved: [$PrimaryUser]"
            
            If ($Alias -match $NamingPatternMatch){
                $CurrentAssignedUser = $Matches[1]
                write-output -InputObject "[$Alias] is currently assigned to: [$CurrentAssignedUser]. Will check if this is correct..."
                If($CurrentAssignedUser -eq $PrimaryUser){
                    write-output -InputObject "[$Alias] is set correctly."
                } else {
                    write-output -InputObject "[$Alias] needs updating with: [$PrimaryUser]."
                    $NewAlias = $Alias -replace $CurrentAssignedUser,$PrimaryUser
                }

            } else {
                write-output -InputObject "No username in device alias. Will modify TV device alias to include a username...."
                $NewAlias = $Alias + " [$PrimaryUser]"
            }

            # Device rename
            If($NewAlias){
                write-output -InputObject "New alias specified: [$NewAlias]. Will now update in Teamviewer."
                write-output -InputObject "Updating DeviceID: [$DeviceID]"
                Try {
                    Rename-TVDevice -DeviceID $DeviceID -NewAlias $NewAlias
                    Write-Information -MessageData "Succesfully updated [$Alias] to [$NewAlias]"
                } Catch {
                    write-error -Message "Failed to rename device [$Alias]. $_"
                }
            } else {
                write-warning -Message "No new alias defined. Moving to next device."
            }

        } else {
            write-warning -Message "Could not retrieve Intune primary user for device: [$Alias]"
            
        }

    }
} else {
    write-error -Message "Couldn't retrieve any devices from Intune. $_"
}
