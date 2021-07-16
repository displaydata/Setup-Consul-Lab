[CmdletBinding()]
param(
  [string]$ConsulBinary, # if you want to supply the Consul binary, where is it on the file system?
  [string]$VersionNumber, # optionally download a Consul binary version from the Hashicorp site
  [string]$InstallDirectory = "c:/Consul", 
  [string]$ConsulAdvertise, 
  [bool]$EventsServer = $true,
  [string]$JoinAddress,  
  [string]$InstallAsAccount,
  [string]$InstallAccountPassword
)

$ErrorActionPreference = "Stop"

if (!$ConsulBinary -and !$VersionNumber) {
  Write-Error "Please supply a Consul binary or a Version of Consul to download"
}

if (!$EventsServer -and !$JoinAddress) {
  Write-Error "Please supply a join address for non Events server"
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
