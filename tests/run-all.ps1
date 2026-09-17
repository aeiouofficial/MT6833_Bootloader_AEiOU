$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$files = @(
    'setup.ps1','preflight.ps1','unlock.ps1','verify.ps1','src\Toolkit.psm1',
    'tests\test-toolkit.ps1','tests\test-entrypoints.ps1','tests\test-public-safety.ps1'
)
foreach($file in $files){
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    if($errors.Count -gt 0){ throw "PowerShell parse failure in $file`: $($errors[0].Message)" }
    Write-Host "PARSE PASS: $file"
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-toolkit.ps1
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-entrypoints.ps1
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-public-safety.ps1
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
Write-Host 'ALL REPOSITORY TESTS PASSED'
