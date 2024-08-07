<#
.AUTHOR     LegendEvent

.DESCRIPTION
    AAD:
    DELETE AAD devices that have a duplicate serial number (all except the latest by LastSyncDateTime) & if available the corresponding AD object by name 
    
	AD:
    Checks if an ad device matches with the name of any aad devices (device names like autopilot devices (CreateAutoPilotDevicePrefix). If they did not appear in AAD devicelist then it will be removed
	
	For deletion of autopilot devices you will need the prefix, so only these are deleted in this script that happens in CreateAutoPilotDevicePrefix, but if your AD and you Autopilotprefix guidelines is not build like mine it wont work

.PARAMETERS
    	-visual: shows an GridView for AAD Devices with duplicated serialnumbers
	-log: choose a path where you want to save the log file, if not used it will save it in $($ENV:SystemDrive)\CleanUp.log
	
.Version
	1.1
    
#>

param(
    [switch]$visual,
	[string]$script:log = "$($ENV:SystemDrive)"
)

#region MODULES
$neededModules = @(
    "Microsoft.Graph.Intune"
)

foreach ($module in $neededModules) {
    $checkModule = Get-Module -ListAvailable $module
    if ($checkModule) {
        Import-Module $module
    }
    else {
        Install-Module $module -Force
    }
}

# Check if the ActiveDirectory module is installed
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    # Attempt to install the ActiveDirectory module for Windows Client without user interaction
    try {
        # Install the RSAT-Active Directory tools feature
        Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -LimitAccess
    }
    catch {
        Write-Error "Failed to install the ActiveDirectory module: $_"
        Exit
    }
}
else {
    # Import the ActiveDirectory module
    Import-Module -Name ActiveDirectory
}

#endregion


#region FUNCTIONS
function Get-OUByFilter {
    param(
        $filter = '',
        $subdomain,
        $topDomain
    )
    
    $searchBase = "OU=Sites,DC=$subDomain,DC=$topDomain"
    try {
        $OUs = Get-ADOrganizationalUnit -SearchBase $searchBase -SearchScope Subtree -Filter { Name -eq $filter }
    }
    catch {
        $errorMsg = $_.Exception.Message
    }

    # Filtere nur die OUs, die "Computer" in ihrem DistinguishedName enthalten
    $OUs = $OUs | Where-Object { $_.DistinguishedName -like '*OU=Computer,*' }

    $OUs | ForEach-Object {
        $OU = $_.DistinguishedName
        # Entferne die Domänenkomponente ",DC=$subDomain,DC=$topDomain" aus dem DistinguishedName
        $domainComponent = ",DC=$subDomain,DC=$topDomain"
        $OU -replace [regex]::Escape($domainComponent), ''
    }
}

function ConnectMGGraphApp {
    param(
        $tenantId = "",
        $Client_Id = "",
        $Client_Secret = ""
    )

    try {
        $body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $($Client_Id)
            Client_Secret = $($Client_Secret)
        }

        $connection = Invoke-RestMethod `
            -Uri https://login.microsoftonline.com/$($tenantId)/oauth2/v2.0/token `
            -Method POST `
            -Body $body
            
        $token = $connection.access_token
        $secureToken = ConvertTo-SecureString -String $token -AsPlainText -Force
        Connect-MgGraph -AccessToken $secureToken -NoWelcome -ErrorAction Stop
    }
    catch {
        Write-Error "Error in ConnecctMGGraphApp: $($_.Exception)"
        break
    }
}


#add you own logic for your prefix, I have it like the AD structure dc,dc,ou=sites,ou=land(countrycode),ou=computer/systems or you can manually add them like $currentOffices += "BLABLA"
function CreateAutoPilotDevicePrefix {
    param(
        $subDomain,
        $topDomain
    )

    $computerOUs = Get-OUByFilter -filter "Computer" -subdomain $subDomain -topDomain $topDomain

    # Liste der aktuellen Offices im AD erstellen
    $currentOffices = @()
    foreach ($ouPath in $computerOUs) {
        $ouParts = $ouPath -split ','
        $office = $ouParts[1] -replace 'OU='
        $countryCode = $ouParts[2] -replace 'OU='
        if ($office -eq "Systems") {
            $office = $ouParts[2] -replace 'OU='
            $countryCode = $ouParts[3] -replace 'OU='
        }
        $currentOffices += "$($countryCode)$($office.Substring(0,$office.Length-1))-"
    }

    # Prefixe in der gewünschten Form zusammenfügen
    $filterParts = $currentOffices | ForEach-Object { "Name -like '$_*'" }
    $filterString = $filterParts -join ' -or '

    #Write-Host $filterString
    return $filterString
}

function CheckAAD {
    param(
        $aadDevices,
        $duplicates,
        $table
    )

    foreach ($group in $duplicates) {
        # Sortiere die Geräte nach LastSyncDateTime absteigend, um das neueste Gerät zu finden
        $sortedDevices = $group.Group | Sort-Object -Property LastSyncDateTime -Descending
        $latestDevice = $sortedDevices[0]
    
        # Behalte nur das neueste Gerät, lösche die anderen
        $devicesToDelete = $sortedDevices | Select-Object -Skip 1
    
        foreach ($device in $devicesToDelete) {
            # Lösche das Gerät in Intune
            Write-Log -message "AAD: Deleting Device: $($device.DeviceName) ID: $($device.Id) Serialnumber: $($device.SerialNumber)"
            try {
                Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id -confirm:$false -ErrorAction Stop -WhatIf
                Write-Log -type "INFO" -message "AAD: Deleting Device: $($device.DeviceName) is deleted"
            }
            catch {
                Write-Log -type "ERROR" -message "AAD: Deleting Device: $($device.DeviceName) was NOT deleted"
            }
            # Überprüfe, ob das Gerät auch im AD existiert und lösche es
            $computer = Get-ADComputer "$($device.DeviceName)" | Where-Object { $_.Name -eq $device.DeviceName } -ErrorAction SilentlyContinue
            if ($computer) {
                Write-Log -message "AD: Deleting Device: $($computer.Name) in $($computer.DistinguishedName)" -ErrorAction SilentlyContinue
                try {
                    Remove-ADComputer -Identity "$($computer.DistinguishedName)" -Confirm:$false -ErrorAction Stop -WhatIf
                }
                catch {
                    Remove-ADObject -Identity "$($computer.DistinguishedName)" -Recursive -Confirm:$false -ErrorAction Stop -WhatIf
                }
                finally {
                    try {
                        Get-Adcomputer -Identity $computer.DistinguishedName -ErrorAction Stop
                        Write-Log -type "ERROR" -message "AD: Device $($computer.Name) was NOT deleted" 
                    }
                    catch {
                        Write-Log -type "INFO" -message "AD: Device $($computer.Name) is deleted" 
                    }
                }
            }
        }
    }
    return "AAD Check completed"
}

function CheckAD {
    param(
        $adDevices,
        $aadDevices
    )

    foreach ($computer in $adDevices) {
        $computerName = $computer.Name
        $matchingDevice = $aadDevices | Where-Object { $_.DeviceName -eq $computerName }

        if ($matchingDevice) {
            #Write-Output "Match found for Computer ""$($computer.Name)"" matches Device ID $($matchingDevice.AzureAdDeviceId)"
        }
        else {
            Write-Log -message "AD: Deleting Device: $($computer.Name) in $($computer.DistinguishedName)"
            try {
                Remove-ADComputer -Identity "$($computer.DistinguishedName)" -Confirm:$false -ErrorAction Stop
            }
            catch {
                Remove-ADObject -Identity "$($computer.DistinguishedName)" -Recursive -Confirm:$false -ErrorAction Stop
            }
            finally {
                try {
                    Get-Adcomputer -Identity $computer.DistinguishedName -ErrorAction Stop
                    Write-Log -type "ERROR" -message "AD: Device $($computer.Name) was NOT deleted" 
                }
                catch {
                    Write-Log -type "INFO" -message "AD: Device $($computer.Name) is deleted" 
                }
            }
        }
    }
    return "AD Check completed"
}

function Write-Log {
    param (
        [string]$message,
        [string]$type = "Info"
    )
    $type = $type.ToUpper()
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$($type)]: $($timestamp) - $($message)"
    Add-Content -Path "$($script:log)\CleanUp.log" -Value $logMessage
    Write-Host $logMessage
}

#endregion


#region MAIN
ConnectMGGraphApp -tenantId "YOUR TENANT ID" -Client_Id "YOUR APP CLIENT_ID" -Client_Secret "YOUR APP CLIENT SECRET"

#region variables
$domain = Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem | Select-Object -Expand Domain
$subDomain = $domain.Split(".")[0]
$topDomain = $domain.Split(".")[1]
[string]$autoPilotPrefix = CreateAutoPilotDevicePrefix -subDomain $subDomain -topDomain $topDomain
$devices = Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq 'Windows'" -All #getting all windows devices from aad
$computers = Get-ADComputer -Filter $autoPilotPrefix -Properties objectGUID, whenCreated, lastLogon #getting all local AD devices with given autoPilotPrefix
$duplicates = $devices | Where-Object { $_.SerialNumber -ne "" } | Group-Object -Property SerialNumber | Where-Object { $_.Count -gt 1 } #ensure that only serial numbers with more than one device is saved into the variable
$table = @()
#endregion 

#region AZURE AD CHECK
Write-Log -message "Duplicates in AAD deleted: $(CheckAAD -aadDevices $devices -duplicates $duplicates)"

################ VISUALISERUNG ###################
if ($visual) {
    $duplicates | Select * 

    $duplicates | ForEach-Object {
        $table += "" | Select-Object @{Name = "DeviceName"; Expression = { "" } }, @{Name = "AzureAdDeviceId"; Expression = { "" } }, @{Name = "SerialNumber"; Expression = { $_.Group[0].SerialNumber } }, @{Name = "LastSyncDateTime"; Expression = { "" } }, @{Name = "UserDisplayName"; Expression = { "" } }
        $table += $_.Group | Select-Object DeviceName, AzureAdDeviceId, SerialNumber, LastSyncDateTime, UserDisplayName
    }

    # Display table in Out-GridView
    $table | Out-GridView -Title "Grouped Devices by Serial Number" 
}
##################################################
#endregion

#region ACTIVE DIRECTORY CHECK ONLY WITH AUTOPILOTPREFIX
Write-Log -message "AD Computer remnants: $(CheckAD -adDevices $computers -aadDevices $devices)"
#endregion

Disconnect-MgGraph > $null
#endregion
