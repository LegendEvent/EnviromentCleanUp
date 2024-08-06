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
.\YourScriptName.ps1 [-visual] [-log] "DRIVE:"
