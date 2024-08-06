
# PowerShell Script: AAD and AD Device Cleanup

## Author

**LegendEvent**

## Description

This PowerShell script is designed to manage and clean up devices in both Azure Active Directory (AAD) and Active Directory (AD). It performs the following tasks:

- **AAD Cleanup**: Deletes duplicate AAD devices with the same serial number, keeping only the latest by `LastSyncDateTime`. If available, it also deletes the corresponding AD object by name.
- **AD Cleanup**: Identifies AD devices that match the naming convention of AAD devices (e.g., autopilot devices). Devices not appearing in the AAD device list are removed from AD.
- **Autopilot Devices**: Requires a prefix to ensure only relevant devices are deleted. This is configured in `CreateAutoPilotDevicePrefix`. Ensure your AD and Autopilot prefix guidelines match your setup.

## Motivation

Due to the lack of writeback capabilities for devices from AAD to AD, there can be a buildup of duplicate or outdated computer accounts in AD over time. This poses a security risk as these computer accounts can be used to authenticate against the domain. 

This script was created to mitigate such risks by comparing both systems and ensuring that only the necessary and up-to-date computer accounts are retained in AD.

## Parameters

- `-visual`: Displays a GridView for AAD devices with duplicated serial numbers.
- `-log`: Specifies a path to save the log file. If not provided, logs are saved to `$($ENV:SystemDrive)\CleanUp.log`.

## Prerequisites

This script requires the following PowerShell modules:

- `Microsoft.Graph.Intune`
- `ActiveDirectory`

## Installation

To use this script, ensure you have the required modules installed. The script will attempt to install them if they are not present.

## Usage

Run the script with the necessary permissions. Here’s an example of how to execute the script:

```powershell
.\EnviromentCleanUp.ps1 [-visual] [-log] "DRIVE:"
```

### Example Commands

1. **View Duplicates in AAD with GridView**:
    ```powershell
    .\EnviromentCleanUp.ps1 -visual
    ```

2. **Log Cleanup Activities to a Specific Path**:
    ```powershell
    .\EnviromentCleanUp.ps1 -log "C:\Logs"
    ```

## Functionality Overview

### Modules

- **Microsoft.Graph.Intune**: Used to interact with Intune and manage AAD devices.
- **ActiveDirectory**: Provides functions for interacting with on-premises AD.

### Key Functions

- **Get-OUByFilter**: Retrieves Organizational Units (OUs) based on specific filters.
- **ConnectMGGraphApp**: Establishes a connection to the Microsoft Graph API using application credentials.
- **CreateAutoPilotDevicePrefix**: Generates prefixes for autopilot devices based on AD structure.
- **CheckAAD**: Cleans up duplicate AAD devices, removing all but the latest synchronized device.
- **CheckAD**: Checks for AD devices not present in AAD and deletes them if they don't match the autopilot naming convention.
- **Write-Log**: Logs messages to a specified file for auditing purposes.

## Logging

The script logs its operations to a specified file or defaults to the system drive if no path is provided.

## License

This project is licensed under the [Custom License](LICENSE). Redistribution of this script in a commercial product or paid software is not permitted.

## Disclaimer

Use this script at your own risk. The author is not responsible for any damage caused by this script.
