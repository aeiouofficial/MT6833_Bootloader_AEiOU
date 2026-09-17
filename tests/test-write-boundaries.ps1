$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$files=@(
    (Get-ChildItem $root -File -Filter '*.ps1'),
    (Get-ChildItem (Join-Path $root 'src') -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}),
    (Get-Item (Join-Path $root 'tests\run-all.ps1'))
) | ForEach-Object {$_}
$patterns=@(
    '\)foreach\(',
    '\}function\s',
    'Out-Null\$[A-Za-z_]',
    'Write-Host\s+\$r\.Output[ \t]+\$[A-Za-z_]+\s*=',
    '\}\$[A-Za-z_]',
    '\}[ \t]{2,}(?:Save-Stage|\$[A-Za-z_]+\s*=)'
)
$failures=0
foreach($file in $files){
    foreach($line in (Get-Content $file.FullName)){
        foreach($rx in $patterns){
            if($line -match $rx){$failures++;Write-Host "FAIL: suspicious write-boundary in $($file.Name): $rx"}
        }
    }
}
if($failures){throw "$failures suspicious write-boundary pattern(s) found"}
Write-Host 'WRITE-BOUNDARY TESTS PASSED'