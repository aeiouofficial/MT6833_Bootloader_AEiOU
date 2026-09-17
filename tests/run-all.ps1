$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Set-Location $root
$files=@(
    'setup.ps1','preflight.ps1','unlock.ps1','verify.ps1',
    'rom-install.ps1','gapps-install.ps1','root-magisk.ps1','postflight.ps1','optional-apps-install.ps1','install-all.ps1',
    'src\Toolkit.psm1','src\Workflow.psm1',
    'tests\test-toolkit.ps1','tests\test-entrypoints.ps1','tests\test-fork.ps1',
    'tests\test-public-safety.ps1','tests\test-workflow.ps1','tests\test-state.ps1',
    'tests\test-rom-gapps.ps1','tests\test-root-magisk.ps1','tests\test-postflight.ps1',
    'tests\test-install-all.ps1','tests\test-optional-apps.ps1','tests\test-dry-run.ps1','tests\test-write-boundaries.ps1'
)
foreach($file in $files){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){throw "PowerShell parse failure in $file`: $($errors[0].Message)"}
    Write-Host "PARSE PASS: $file"
}
$tests=@(
    'test-toolkit.ps1','test-entrypoints.ps1','test-fork.ps1','test-public-safety.ps1',
    'test-workflow.ps1','test-state.ps1','test-rom-gapps.ps1','test-root-magisk.ps1',
    'test-postflight.ps1','test-install-all.ps1','test-optional-apps.ps1','test-dry-run.ps1','test-write-boundaries.ps1'
)
foreach($test in $tests){
    Write-Host "=== $test ==="
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path '.\tests' $test)
    if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
}
Write-Host 'ALL REPOSITORY TESTS PASSED'
