# Fails if a Windows binary cannot load on Windows 7 SP1: it hard-imports an
# API set DLL or a known Windows 8+ function, or its PE header requires a newer
# OS. Functions that are only resolved via GetProcAddress are not imports and
# are fine.
#
# Usage: pwsh tools/check-legacy-windows-imports.ps1 out\Release\node.exe

param([Parameter(Mandatory = $true)][string]$Path)

$ErrorActionPreference = 'Stop'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -property installationPath
$dumpbin = Get-ChildItem "$vs\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" |
  Sort-Object FullName -Descending | Select-Object -First 1

# Windows 8 or later only. Extend this list when a new import shows up.
$denied = @(
  'CopyFile2', 'CreateFile2', 'CreatePseudoConsole', 'DiscardVirtualMemory',
  'EventSetInformation', 'GetCurrentThreadStackLimits', 'GetFileInformationByName',
  'GetFirmwareType', 'GetHostNameW', 'GetOverlappedResultEx',
  'GetProcessDefaultCpuSets', 'GetProcessInformation', 'GetProcessMitigationPolicy',
  'GetSystemCpuSetInformation', 'GetSystemTimePreciseAsFileTime', 'GetTempPath2A',
  'GetTempPath2W', 'GetThreadDescription', 'MapViewOfFile3', 'MapViewOfFileNuma2',
  'OfferVirtualMemory', 'PrefetchVirtualMemory', 'ProcessPrng',
  'QueryInterruptTime', 'QueryInterruptTimePrecise', 'QueryUnbiasedInterruptTimePrecise',
  'ReclaimVirtualMemory', 'SetProcessInformation', 'SetProcessMitigationPolicy',
  'SetThreadDescription', 'SetThreadInformation', 'SetThreadSelectedCpuSets',
  'VirtualAlloc2', 'WaitOnAddress', 'WakeByAddressAll', 'WakeByAddressSingle'
)
$deniedDlls = '^(api-ms-win-|ext-ms-win-|combase\.dll$|synchronization\.dll$)'

$imports = & $dumpbin.FullName /nologo /imports $Path
$headers = & $dumpbin.FullName /nologo /headers $Path

$problems = @()
$dll = $null
foreach ($line in $imports) {
  if ($line -match '^\s{4}(\S+\.dll)\s*$') {
    $dll = $Matches[1]
    if ($dll -match $deniedDlls) { $problems += "imports DLL $dll" }
  } elseif ($dll -and $line -match '^\s+[0-9A-F]+\s+(\w+)\s*$') {
    if ($denied -contains $Matches[1]) { $problems += "imports $dll!$($Matches[1])" }
  }
}

foreach ($line in $headers) {
  if ($line -match '^\s+(\d+)\.(\d+) (operating system|subsystem) version') {
    if ([version]"$($Matches[1]).$($Matches[2])" -gt [version]'6.1') {
      $problems += "$($Matches[3]) version is $($Matches[1]).$($Matches[2]) (> 6.1)"
    }
  }
}

if ($problems.Count -gt 0) {
  $problems | ForEach-Object { Write-Host "::error file=$Path::$_" }
  exit 1
}
Write-Host "$Path has no imports that require Windows 8 or newer."
