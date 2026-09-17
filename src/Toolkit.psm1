Set-StrictMode -Version Latest

function Backup-MtkState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MtkRoot)
    $state = Join-Path $MtkRoot '.state'
    if (-not (Test-Path -LiteralPath $state)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $MtkRoot ".state.stale-$stamp"
    Move-Item -LiteralPath $state -Destination $backup -Force
    return $backup
}

function Test-Mt6833Evidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Output)
    return [bool]($Output -match '(?im)\bMT6833\b|Dimensity\s*700\s*5G\s*k6833')
}

function Test-ReadOnlyGateEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Output)
    $required = @('BROM mode detected.','DRAM setup passed.','Successfully uploaded stage 2','GPT Table:')
    foreach($marker in $required){ if($Output -notmatch [regex]::Escape($marker)){ return $false } }
    return (Test-Mt6833Evidence $Output)
}
function Test-UnlockEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][int]$ExitCode
    )
    if($ExitCode -ne 0){ return $false }
    $explicit = @('Device is already unlocked','Successfully wrote seccfg.')
    foreach($marker in $explicit){ if($Output -match [regex]::Escape($marker)){ return $true } }
    return $false
}

Export-ModuleMember -Function Backup-MtkState,Test-Mt6833Evidence,Test-ReadOnlyGateEvidence,Test-UnlockEvidence
