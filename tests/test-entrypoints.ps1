$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$required = @('setup.ps1','preflight.ps1','unlock.ps1','verify.ps1')
$failures = 0
function Check([bool]$ok,[string]$msg){ if($ok){Write-Host "PASS: $msg"} else {$script:failures++; Write-Host "FAIL: $msg"} }

foreach($name in $required){ Check (Test-Path (Join-Path $root $name)) "$name exists" }
if($failures -gt 0){ throw "$failures test(s) failed before content checks" }

$setup = Get-Content (Join-Path $root 'setup.ps1') -Raw
$preflight = Get-Content (Join-Path $root 'preflight.ps1') -Raw
$unlock = Get-Content (Join-Path $root 'unlock.ps1') -Raw
$verify = Get-Content (Join-Path $root 'verify.ps1') -Raw
Check ($setup -match 'cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3') 'setup pins verified mtkclient commit'
Check ($preflight -match 'printgpt') 'preflight uses read-only printgpt gate'
Check ($unlock -match 'Backup-MtkState') 'unlock backs up stale state'
Check ($unlock -match 'da\s+seccfg\s+unlock') 'unlock invokes only seccfg unlock mutation'
Check ($verify -match 'fastboot') 'verify supports fastboot verification'
Check ($setup.Contains('if(-not $InstallDir)')) 'setup resolves default path after param binding'
Check ($preflight.Contains('if(-not $MtkRoot)')) 'preflight resolves default path after param binding'
Check ($unlock.Contains('if(-not $MtkRoot)')) 'unlock resolves default path after param binding'

$scriptText = $setup + "`n" + $preflight + "`n" + $unlock + "`n" + $verify
$forbidden = @('mtk.py e ','mtk.py es ','mtk.py ess ','formatflash','erase_rpmb','write_rpmb')
foreach($token in $forbidden){ Check ($scriptText -notmatch [regex]::Escape($token)) "scripts exclude destructive token: $token" }
if($failures -gt 0){ throw "$failures test(s) failed" }
Write-Host 'ALL ENTRYPOINT TESTS PASSED'
