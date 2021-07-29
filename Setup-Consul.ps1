<#
.SYNOPSIS
    Downloads and runs Consul for Windows as a service
.DESCRIPTION
    Downloads Consul version (as specified by VersionNumber) or use binary (as specified by ConsulBinary path).
    Creates and starts a Consul Service using parameters specified.
.PARAMETER VersionNumber
    Version of Consul to download 
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
.EXAMPLE
    PS> ./Setup-Consul.ps1 -VersionNumber 1.9.7 -ConsulAdvertise 192.168.0.1
.LINK
    https://github.com/displaydata/Setup-Consul-Lab
#>

#Requires -Version 5.0

[CmdletBinding()]
param(
  [string]$VersionNumber,
  [string]$ConsulBinary,
  [Parameter(Mandatory=$true)][string]$ConsulAdvertise,
  [bool]$EventsServer = $true,
  [string]$JoinAddress,
  [string]$InstallDirectory = "C:/Consul",
  [string]$InstallAsAccount,
  [string]$InstallAccountPassword
)

$ErrorActionPreference = "Stop"

if (!$ConsulBinary -and !$VersionNumber) {
  Write-Error "Please supply a Consul binary or a Version of Consul to download"
}

if ($ConsulBinary -and $VersionNumber) {
  Write-Error "Please supply either a Consul binary or a Version of Consul to download"
}

if (!$EventsServer -and !$JoinAddress) {
  Write-Error "Please supply a join address for non Events server"
}

if ($InstallAsAccount -and !$InstallAccountPassword) {
  Write-Error "Please supply InstallAccountPassword when using InstallAsAccount"
}

$ConsulData = "$InstallDirectory/data"
$ConsulInstall = "$InstallDirectory/install"
$ConsulLogs = "$InstallDirectory/logs/"
$ConsulConfig = "$InstallDirectory/config"

New-Item -Path $InstallDirectory   -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulData         -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulInstall      -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulLogs         -ItemType Directory -ErrorAction "Ignore"
New-Item -Path $ConsulConfig       -ItemType Directory -ErrorAction "Ignore"

if ($ConsulBinary) {
  Copy-Item $ConsulBinary $ConsulInstall
}
else {
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
$binPathWithArgs = "$ConsulBinaryPath agent -ui -data-dir $ConsulData -config-dir $ConsulConfig -log-file $ConsulLogs -log-level DEBUG -bind 0.0.0.0 -advertise $ConsulAdvertise"

if ($EventsServer) {
  $binPathWithArgs += " -server -bootstrap-expect=1"
} else {
  $binPathWithArgs += " -join $JoinAddress"
}

Write-Host "\nCreating Consul Service with command line $binPathWithArgs\n"

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

