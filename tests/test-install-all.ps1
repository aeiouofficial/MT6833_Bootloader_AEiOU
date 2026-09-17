$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent;$p=Join-Path $root 'install-all.ps1';if(-not(Test-Path $p)){throw 'install-all.ps1 missing'};$t=Get-Content $p -Raw
foreach($token in 'preflight','unlock','verify','rom','gapps','root','postflight','Resume','WhatIf'){if($t -notmatch [regex]::Escape($token)){throw "orchestrator missing: $token"}}
Write-Host 'INSTALL-ALL TESTS PASSED'
