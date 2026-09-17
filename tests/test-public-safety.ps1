$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$privateTokens=@(
    '4CA239D32A3093617760D54223FDCB5F',
    '2701D60352171400CB48A67DFE940BE80C3806C23F8AA3139BBAD49678E7401A',
    'JJY5SSNVIZ45D6K7',
    '2c014d54313238474153414f34553231'
)
$publicFiles=Get-ChildItem $root -Recurse -File | Where-Object {
    $_.Name -ne 'test-public-safety.ps1' -and
    $_.FullName -notlike "$root\.git\*" -and
    $_.FullName -notlike "$root\tools\*" -and
    $_.Extension -in @('.ps1','.psm1','.md','.yml','.yaml','.txt','.json','')
}
$failures=0
foreach($token in $privateTokens){
    $hits=$publicFiles|Select-String -SimpleMatch $token -ErrorAction SilentlyContinue
    if($hits){$failures++;Write-Host 'FAIL: private device identifier leaked'}
    else{Write-Host 'PASS: private device identifier absent'}
}
$production=Get-ChildItem $root -File -Filter '*.ps1' | Where-Object {$_.Name -ne 'setup.ps1'}
$production+=Get-ChildItem (Join-Path $root 'src') -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}
$forbiddenRegex=@(
    '(?i)fastboot(?:\.exe)?\s+(?:flashing|oem)\s+lock',
    '(?i)flash\s+vbmeta',
    '(?i)--disable-verity|--disable-verification',
    '(?i)fastboot(?:\.exe)?.*\bformat\b'
)
foreach($rx in $forbiddenRegex){
    $hits=$production|Select-String -Pattern $rx -ErrorAction SilentlyContinue
    if($hits){$failures++;Write-Host "FAIL: forbidden production command pattern: $rx"}
    else{Write-Host "PASS: forbidden production command absent: $rx"}
}
if($failures -gt 0){throw "$failures public-safety failure(s) found"}
Write-Host 'PUBLIC SAFETY TESTS PASSED'
