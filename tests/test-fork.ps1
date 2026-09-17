$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fork = Join-Path $root 'vendor\mtkclient'
$handler = Join-Path $fork 'mtkclient\Library\DA\mtk_da_handler.py'
$meta = Join-Path $fork 'AEIOU_FORK.md'
$license = Join-Path $fork 'LICENSE'
$loaderRoot = Join-Path $fork 'mtkclient\Loader'

$failures = 0
function Check([bool]$ok,[string]$msg){ if($ok){Write-Host "PASS: $msg"} else {$script:failures++; Write-Host "FAIL: $msg"} }

Check (Test-Path (Join-Path $fork 'mtk.py')) 'vendored mtkclient entry point exists'
Check (Test-Path $handler) 'vendored DA handler exists'
Check (Test-Path $meta) 'AEiOU fork metadata exists'
Check (Test-Path $license) 'upstream GPL license is preserved'

$requiredLoaders = @(
    'MTK_DA_V5.bin','MTK_DA_V6.bin','MTK_AllInOne_DA_mt6590.bin',
    'MTK_AllInOne_DA_iot.bin','MTK_AllInOne_DA_7687.bin','MTK_AllInOne_DA_2625.bin'
)
foreach($loader in $requiredLoaders){
    Check (Test-Path (Join-Path $loaderRoot $loader)) "bundled loader exists: $loader"
}

$source = Get-Content $handler -Raw
Check ($source -match 'MTKCLIENT_ALLOW_STATE_REINIT') 'fork exposes explicit state-reinit opt-in'
Check ($source -match 'Ignoring persisted \.state for safety') 'fork warns when stale state is ignored'
Check ($source -match 'if allow_state_reinit:') 'automatic reinit is gated'

$setup = Get-Content (Join-Path $root 'setup.ps1') -Raw
$preflight = Get-Content (Join-Path $root 'preflight.ps1') -Raw
$unlock = Get-Content (Join-Path $root 'unlock.ps1') -Raw
Check ($setup -match 'vendor\\mtkclient') 'setup uses bundled fork'
Check ($preflight -match 'vendor\\mtkclient') 'preflight uses bundled fork'
Check ($unlock -match 'vendor\\mtkclient') 'unlock uses bundled fork'

if($failures -gt 0){ throw "$failures fork test(s) failed" }
Write-Host 'FORK TESTS PASSED'