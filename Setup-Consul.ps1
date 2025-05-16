<#
.SYNOPSIS
    Downloads and runs Consul for Windows as a service
.DESCRIPTION
    Downloads Consul version.
    Creates and starts a Consul Service using parameters specified.
    IMPORTANT: This script must be run as Administrator
.PARAMETER ConsulBinary
    Path to Consul Binary
.PARAMETER ConsulAdvertise
    Address Consul will be available for connections from other servers.
.PARAMETER EventsServer
    Set to $false if not running on Events Server, to stop Consul agent running in server mode.
    By default it assumes this is run on the Events server and the Consul agent will run in server mode.
.PARAMETER JoinAddress
    If not running as a server, specify address of server agent to join (as specified in ConsulAdvertise address on the EventsServer).
.PARAMETER InstallDirectory
    Optionally specify install directory for Consul, otherwise defaults to C:/Consul.
.PARAMETER InstallAsAccount
    Optionally specify account to use to run service.
.PARAMETER InstallAccountPassword
    If running service using non-default account, specify password with this parameter.
.PARAMETER NumberOfLogFilesToKeep
    Number of old log files to keep before deleting them. Default is 14.
.EXAMPLE
    PS> ./Setup-Consul.ps1 -ConsulAdvertise 192.168.0.1
.LINK
    https://github.com/displaydata/Setup-Consul-Lab
#>

#Requires -Version 5.0

[CmdletBinding()]
param(
  [string]$ConsulBinary,
  [Parameter(Mandatory=$true)][string]$ConsulAdvertise,
  [bool]$EventsServer = $true,
  [string]$JoinAddress,
  [string]$InstallDirectory = "C:/Consul",
  [string]$InstallAsAccount,
  [string]$InstallAccountPassword,
  [int]$NumberOfLogFilesToKeep  = 10
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Tested with 1.19.2 and later versions are known to have issues
$VersionNumber = "1.19.2"

if (!$EventsServer -and !$JoinAddress) {
  Write-Error "Please supply a join address for non Events server"
}

if ($InstallAsAccount -and !$InstallAccountPassword) {
  Write-Error "Please supply InstallAccountPassword when using InstallAsAccount"
}

$ConsulData = Join-Path -Path $InstallDirectory -ChildPath "data"
$ConsulInstall = Join-Path -Path $InstallDirectory -ChildPath "install"
$ConsulLogs = Join-Path -Path $InstallDirectory -ChildPath "logs"
$ConsulConfig = Join-Path -Path $InstallDirectory -ChildPath "config"

New-Item -Path $InstallDirectory   -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulData         -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulInstall      -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulLogs         -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulConfig       -ItemType Directory -ErrorAction "Ignore"

$configFile = @"
data_dir = $(ConvertTo-Json $ConsulData)
log_level = "info"
log_file = $(ConvertTo-Json (Join-Path -Path $ConsulLogs -ChildPath "consul.log"))
advertise_addr = "$ConsulAdvertise"
limits {
  http_max_conns_per_client=-1
}
log_rotate_max_files=10
ui_config {
  enabled = true
}
"@

$configFilePath = Join-Path -Path $ConsulConfig -ChildPath "config.hcl"
if (Test-Path -Path $configFilePath) {
  Write-Error "Config file already exists"
}

New-Item -Path $configFilePath -ItemType File -Force
Set-Content -Path $configFilePath -Value $configFile

$consulServiceName = 'ConsulService'
$existingService = Get-Service -Name $consulServiceName -ErrorAction Ignore
if ($existingService) {
  Write-Host "Removing existing Consul service"
  $existingService | Stop-Service
  sc.exe delete $consulServiceName
  if ($LASTEXITCODE) { Write-Error "Failed to remove service: $consulServiceName" }
}

if ($ConsulBinary) {
  Copy-Item $ConsulBinary $ConsulInstall
} else {
  #Enable TLS
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
    -bor [Net.SecurityProtocolType]::Tls11 `
    -bor [Net.SecurityProtocolType]::Tls12

  $zipFileName = "consul_$($VersionNumber)_windows_amd64.zip"
  $url = "https://releases.hashicorp.com/consul/$VersionNumber/$ZipFileName"

  $wc = New-Object System.Net.WebClient
  $wc.DownloadFile($url, "$ConsulInstall/$ZipFileName")

  Expand-Archive -Confirm:$false -Force:$true "$ConsulInstall/$zipFileName" "$ConsulInstall"
}

$ConsulBinaryPath=Join-Path $ConsulInstall "consul.exe"
$binPathWithArgs = "$ConsulBinaryPath agent -config-dir $ConsulConfig -bind 0.0.0.0"

if ($EventsServer) {
  $binPathWithArgs += " -server -bootstrap-expect=1"
} else {
  $binPathWithArgs += " -join $JoinAddress"
}

Write-Host "Creating Consul Service with command line $binPathWithArgs"

if (!$InstallAsAccount) {
    New-Service -Name "ConsulService" -Description "Consul Service" -BinaryPathName $binPathWithArgs -StartupType Automatic
}
else {
    #Ideally a credential should be passed in, but the credential is created here for ease of use
    $password = ConvertTo-SecureString $InstallAccountPassword -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential ($InstallAsAccount, $password)
    New-Service -Name "ConsulService" -Description "Consul Service" -BinaryPathName $binPathWithArgs -StartupType Automatic -Credential $Cred
}

Start-Service -Name "ConsulService"
Get-Service "ConsulService"
