$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$forbidden = @(
    '4CA239D32A3093617760D54223FDCB5F',
    '2701D60352171400CB48A67DFE940BE80C3806C23F8AA3139BBAD49678E7401A',
    'JJY5SSNVIZ45D6K7',
    '2c014d54313238474153414f34553231'
)
$files = Get-ChildItem $root -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.git\\|\\tools\\|test-public-safety\.ps1$' -and
    $_.Extension -in @('.ps1','.psm1','.md','.yml','.yaml','.txt','')
}
$failures = 0
foreach($token in $forbidden){
    $hits = $files | Select-String -SimpleMatch $token -ErrorAction SilentlyContinue
    if($hits){ $failures++; Write-Host "FAIL: private device identifier leaked: $token" }
    else { Write-Host 'PASS: private device identifier absent' }
}
if($failures -gt 0){ throw "$failures privacy leak(s) found" }
Write-Host 'PUBLIC SAFETY TESTS PASSED'
