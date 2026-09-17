[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Manifest,
    [string]$ArtifactsRoot,
    [string]$AdbPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
if(-not $ArtifactsRoot){$ArtifactsRoot=$PSScriptRoot}
$m=Read-WorkflowManifest $Manifest
if($WhatIfPreference){Write-Host 'WHATIF: verify GApps hash; wait for recovery sideload mode; sideload exact GApps artifact';return}
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $ArtifactsRoot
$gapps=Join-Path $ArtifactsRoot $m.artifacts.gapps.file
Assert-ArtifactHash $gapps $m.artifacts.gapps.sha256 | Out-Null
Wait-AdbState -Adb $adb -State sideload -TimeoutSeconds 900 | Out-Null
$r=Invoke-NativeChecked $adb @('sideload',$gapps) -AllowFailure
Write-Host $r.Output
if(-not(Test-SideloadEvidence -Output $r.Output -ExitCode $r.ExitCode)){throw "GApps sideload failed or incomplete. Exit=$($r.ExitCode)"}
Write-Host 'GAPPS SIDELOAD VERIFIED.'