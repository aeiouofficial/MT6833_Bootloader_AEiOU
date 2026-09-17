$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$cases=@(
    @('rom-install.ps1',@('-AcknowledgeDataLoss','-WhatIf')),
    @('gapps-install.ps1',@('-WhatIf')),
    @('root-magisk.ps1',@('-WhatIf')),
    @('optional-apps-install.ps1',@('-WhatIf')),
    @('install-all.ps1',@('-FromStage','rom','-ToStage','postflight','-AcknowledgeDataLoss','-WhatIf')),
    @('install-all.ps1',@('-FromStage','postflight','-InstallOptionalApps','-WhatIf'))
)
foreach($case in $cases){
    $script=Join-Path $root $case[0]
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script)+@($case[1])
    $output=(& powershell @args 2>&1 | Out-String)
    if($LASTEXITCODE -ne 0){throw "Dry-run failed for $($case[0]):`n$output"}
    if($output -notmatch 'WHATIF'){throw "Dry-run emitted no WHATIF plan for $($case[0])"}
    Write-Host "PASS: $($case[0]) dry-run is hardware-free"
}
Write-Host 'DRY-RUN TESTS PASSED'