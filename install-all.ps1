[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('preflight','unlock','verify','rom','gapps','root','postflight','optional-apps')][string]$FromStage='preflight',
    [ValidateSet('preflight','unlock','verify','rom','gapps','root','postflight','optional-apps')][string]$ToStage='postflight',
    [string]$Manifest,
    [string]$ArtifactsRoot,
    [string]$MtkRoot,
    [string]$AdbPath,
    [string]$FastbootPath,
    [switch]$AcknowledgeDataLoss,
    [switch]$InstallOptionalApps,
    [switch]$Resume
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
if(-not $ArtifactsRoot){$ArtifactsRoot=$PSScriptRoot}
if($InstallOptionalApps -and -not $PSBoundParameters.ContainsKey('ToStage')){$ToStage='optional-apps'}
$stateRoot=Join-Path $PSScriptRoot '.aeiou-state'
$stages=@('preflight','unlock','verify','rom','gapps','root','postflight','optional-apps')
$start=[array]::IndexOf($stages,$FromStage); $end=[array]::IndexOf($stages,$ToStage)
if($start -lt 0 -or $end -lt $start){throw 'Invalid stage range'}
if($Resume){
    $prior=Read-WorkflowState $stateRoot
    if(-not $prior){throw 'No resumable state exists'}
    $next=[array]::IndexOf($stages,[string]$prior.nextStage)
    if($next -ge 0){$start=$next}
}
function Save-Stage([string]$Done,[string]$Next){
    if($WhatIfPreference){Write-Host "WHATIF: state checkpoint $Done -> $Next"; return}
    Write-WorkflowState -StateRoot $stateRoot -State ([ordered]@{stage=$Done;nextStage=$Next;timestamp=(Get-Date).ToString('o')}) | Out-Null
}
function Manual-Boundary([string]$Message){
    Write-Host ''
    Write-Host "MANUAL DEVICE ACTION: $Message"
    if(-not $WhatIfPreference){[void](Read-Host 'Press Enter when the phone is ready')}
}
for($i=$start;$i -le $end;$i++){
    $stage=$stages[$i]
    $next=if($i -lt $stages.Count-1){$stages[$i+1]}else{''}
    if($stage -eq 'postflight' -and ((-not $InstallOptionalApps) -or $end -le $i)){$next=''}
    Write-Host "=== STAGE: $stage ==="
    switch($stage){
        'preflight' {
            if($WhatIfPreference){Write-Host 'WHATIF: preflight.ps1 read-only BROM/GPT gate'}
            else {& (Join-Path $PSScriptRoot 'preflight.ps1') -MtkRoot $MtkRoot}
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'Power-cycle, then enter a fresh BROM session for unlock.'}
        }
        'unlock' {
            if($WhatIfPreference){Write-Host 'WHATIF: unlock.ps1 seccfg unlock gate'}
            else {& (Join-Path $PSScriptRoot 'unlock.ps1') -MtkRoot $MtkRoot}
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'Power-cycle into Fastboot (Power + Volume Down).' }
        }
        'verify' {
            if($WhatIfPreference){Write-Host 'WHATIF: verify.ps1 Fastboot unlocked=yes gate'}
            else {
                $fb=Resolve-AndroidTool -Name fastboot -ExplicitPath $FastbootPath -ArtifactsRoot $ArtifactsRoot
                $oldPath=$env:PATH; try {$env:PATH=(Split-Path $fb -Parent)+';'+$env:PATH; & (Join-Path $PSScriptRoot 'verify.ps1')} finally {$env:PATH=$oldPath}
            }
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'Boot Android with USB debugging authorized before the ROM stage.'}
        }
        'rom' {
            $args=@{Manifest=$Manifest;ArtifactsRoot=$ArtifactsRoot;AdbPath=$AdbPath;FastbootPath=$FastbootPath;AcknowledgeDataLoss=$AcknowledgeDataLoss}
            if($WhatIfPreference){& (Join-Path $PSScriptRoot 'rom-install.ps1') @args -WhatIf}else{& (Join-Path $PSScriptRoot 'rom-install.ps1') @args}
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'In recovery choose Reboot to recovery, then Apply update -> Apply from ADB for GApps.'}
        }
        'gapps' {
            $args=@{Manifest=$Manifest;ArtifactsRoot=$ArtifactsRoot;AdbPath=$AdbPath}
            if($WhatIfPreference){& (Join-Path $PSScriptRoot 'gapps-install.ps1') @args -WhatIf}else{& (Join-Path $PSScriptRoot 'gapps-install.ps1') @args}
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'Reboot system, complete setup, and authorize USB debugging.'}
        }
        'root' {
            $args=@{Manifest=$Manifest;ArtifactsRoot=$ArtifactsRoot;AdbPath=$AdbPath;FastbootPath=$FastbootPath}
            if($WhatIfPreference){& (Join-Path $PSScriptRoot 'root-magisk.ps1') @args -WhatIf}else{& (Join-Path $PSScriptRoot 'root-magisk.ps1') @args}
            Save-Stage $stage $next
            if($i -lt $end){Manual-Boundary 'Unlock Android after Magisk reboot, open Magisk, and approve Shell in Magisk Superuser before postflight.'}
        }
        'postflight' {
            if($WhatIfPreference){Write-Host 'WHATIF: postflight.ps1 read-only health checks plus su root verification'}
            else {& (Join-Path $PSScriptRoot 'postflight.ps1') -ArtifactsRoot $ArtifactsRoot -AdbPath $AdbPath}
            Save-Stage $stage $next
        }
        'optional-apps' {
            if(-not $InstallOptionalApps){throw 'optional-apps stage requires explicit -InstallOptionalApps'}
            $args=@{Manifest=$Manifest;ArtifactsRoot=(Join-Path $ArtifactsRoot 'optional-apps');AdbPath=$AdbPath}
            if($WhatIfPreference){& (Join-Path $PSScriptRoot 'optional-apps-install.ps1') @args -WhatIf}else{& (Join-Path $PSScriptRoot 'optional-apps-install.ps1') @args}
            Save-Stage $stage $next
        }
    }
}
Write-Host 'INSTALL-ALL COMPLETE FOR REQUESTED STAGE RANGE.'
