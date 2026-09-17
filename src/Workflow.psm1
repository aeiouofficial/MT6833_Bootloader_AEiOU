Set-StrictMode -Version Latest

function Normalize-Slot { [CmdletBinding()] param([Parameter(Mandatory)][string]$Slot) $s=$Slot.Trim().ToLowerInvariant().TrimStart('_'); if($s -notin @('a','b')){throw "Unsupported A/B slot: $Slot"}; return $s }
function Get-BootPartitionName { [CmdletBinding()] param([Parameter(Mandatory)][string]$Slot) return 'boot_' + (Normalize-Slot $Slot) }
function Get-Sha256 { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Artifact not found: $Path"}; return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Assert-ArtifactHash { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256) if($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw "Invalid SHA256: $ExpectedSha256"}; $actual=Get-Sha256 $Path; if($actual -ne $ExpectedSha256.ToLowerInvariant()){throw "SHA256 mismatch for $Path. Expected=$ExpectedSha256 Actual=$actual"}; return $true }

function Test-DeviceProfile {
 [CmdletBinding()] param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)]$Device,[Parameter(Mandatory)][ValidateSet('PreRom','PostRom')][string]$Phase)
 if(([string]$Profile.soc).ToUpperInvariant() -ne ([string]$Device.soc).ToUpperInvariant()){return $false}
 if($Phase -eq 'PreRom'){return (@($Profile.preRomModels) -contains [string]$Device.model) -and (@($Profile.preRomDevices) -contains [string]$Device.device)}
 return (@($Profile.postRomModels) -contains [string]$Device.model) -and (@($Profile.postRomDevices) -contains [string]$Device.device)
}
function Test-SideloadEvidence { [CmdletBinding()] param([Parameter(Mandatory)][AllowEmptyString()][string]$Output,[Parameter(Mandatory)][int]$ExitCode) return ($ExitCode -eq 0) -and ($Output -match '(?im)Total xfer:\s*1\.00x|serving:.*100%|^Success$') }
function Test-RootEvidence { [CmdletBinding()] param([Parameter(Mandatory)][string]$IdOutput,[Parameter(Mandatory)][string]$ProcessOutput,[Parameter(Mandatory)][string]$Selinux) return ($IdOutput -match '(?i)uid=0\(root\)') -and ($ProcessOutput -match '(?i)\bmagiskd\b') -and ($Selinux.Trim() -eq 'Enforcing') }

function Write-WorkflowState { [CmdletBinding()] param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$State) if(-not(Test-Path -LiteralPath $StateRoot)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}; $path=Join-Path $StateRoot 'state.json'; $tmp=Join-Path $StateRoot ('state.'+[guid]::NewGuid().ToString('N')+'.tmp'); $State|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $path -Force; return $path }
function Read-WorkflowState { [CmdletBinding()] param([Parameter(Mandatory)][string]$StateRoot) $path=Join-Path $StateRoot 'state.json'; if(-not(Test-Path -LiteralPath $path)){return $null}; return (Get-Content -LiteralPath $path -Raw|ConvertFrom-Json) }
function Assert-ResumeCompatible { [CmdletBinding()] param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Current) foreach($name in @('serial','product','slot')){$old=$State.PSObject.Properties[$name];$now=$Current.PSObject.Properties[$name];if($old -and $now -and ([string]$old.Value) -and ([string]$now.Value) -and (([string]$old.Value)-ne([string]$now.Value))){throw "Resume identity mismatch for $name. State=$($old.Value) Current=$($now.Value)"}}; return $true }

function Read-WorkflowManifest { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) if(-not(Test-Path -LiteralPath $Path)){throw "Manifest not found: $Path"}; $m=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json; foreach($n in 'profile','artifacts'){if(-not $m.PSObject.Properties[$n]){throw "Manifest missing $n"}}; return $m }
function Resolve-AndroidTool {
 [CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('adb','fastboot')][string]$Name,[string]$ExplicitPath,[string]$ArtifactsRoot)
 if($ExplicitPath){if(Test-Path -LiteralPath $ExplicitPath){return (Resolve-Path $ExplicitPath).Path};throw "Tool not found: $ExplicitPath"}
 if($ArtifactsRoot){foreach($rel in @("platform-tools\platform-tools\$Name.exe","platform-tools\$Name.exe","$Name.exe")){ $p=Join-Path $ArtifactsRoot $rel; if(Test-Path -LiteralPath $p){return (Resolve-Path $p).Path} }}
 $c=Get-Command $Name -ErrorAction SilentlyContinue; if($c){return $c.Source}; throw "Required tool not found: $Name"
}
function Invoke-NativeChecked {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$FilePath,[string[]]$ArgumentList=@(),[switch]$AllowFailure)
 $out=(& $FilePath @ArgumentList 2>&1|Out-String); $code=$LASTEXITCODE; if(-not $AllowFailure -and $code -ne 0){throw "Command failed ($code): $FilePath $($ArgumentList -join ' ')`n$out"}; return [pscustomobject]@{Output=$out.TrimEnd();ExitCode=$code}
}
function Get-AdbIdentity {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Adb)
 $serial=((& $Adb get-serialno 2>$null)|Out-String).Trim(); if(-not $serial -or $serial -eq 'unknown'){throw 'No authorized ADB device'}
 function P([string]$n){return ((& $Adb shell getprop $n 2>$null)|Out-String).Trim()}
 $soc=P 'ro.board.platform'; if(-not $soc){$soc=P 'ro.hardware'}
 return [pscustomobject]@{serial=$serial;product=(P 'ro.product.name');model=(P 'ro.product.model');device=(P 'ro.product.device');soc=$soc.ToUpperInvariant();slot=(Normalize-Slot (P 'ro.boot.slot_suffix'));bootCompleted=(P 'sys.boot_completed')}
}
function Wait-AdbState {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Adb,[Parameter(Mandatory)][ValidateSet('device','sideload','recovery','unauthorized')][string]$State,[int]$TimeoutSeconds=300)
 $stop=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds); do{$txt=(& $Adb devices 2>$null|Out-String); if($txt -match "(?m)^\S+\s+$([regex]::Escape($State))\s*$"){return $true}; Start-Sleep -Seconds 1}while([DateTime]::UtcNow -lt $stop); throw "Timed out waiting for ADB state: $State"
}
function Wait-AndroidBootCompleted { [CmdletBinding()] param([Parameter(Mandatory)][string]$Adb,[int]$TimeoutSeconds=180) Wait-AdbState -Adb $Adb -State device -TimeoutSeconds $TimeoutSeconds|Out-Null; $stop=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds); do{$v=((& $Adb shell getprop sys.boot_completed 2>$null)|Out-String).Trim();if($v -eq '1'){return $true};Start-Sleep 2}while([DateTime]::UtcNow -lt $stop);throw 'Android boot did not complete in time' }
function Get-FastbootVariable { [CmdletBinding()] param([Parameter(Mandatory)][string]$Fastboot,[Parameter(Mandatory)][string]$Name) $r=Invoke-NativeChecked -FilePath $Fastboot -ArgumentList @('getvar',$Name) -AllowFailure; if($r.Output -match "(?im)^$([regex]::Escape($Name)):\s*(.+?)\s*$"){return $Matches[1].Trim()}; throw "Fastboot variable not available: $Name`n$($r.Output)" }

function Get-MagiskAssetInfo {
 [CmdletBinding()] param([Parameter(Mandatory)]$Release)
 if($Release.draft -or $Release.prerelease){throw 'Magisk release is not stable'}
 $asset=@($Release.assets|Where-Object{$_.name -match '^Magisk-v.+\.apk$'})|Select-Object -First 1; if(-not $asset){throw 'Stable Magisk APK asset not found'}
 $digest=[string]$asset.digest; if($digest -notmatch '^sha256:([0-9a-fA-F]{64})$'){throw 'Magisk asset is missing a SHA256 digest'}
 $ver=([string]$Release.tag_name).TrimStart('v'); return [pscustomobject]@{Version=$ver;Name=$asset.name;Url=$asset.browser_download_url;Sha256=$Matches[1].ToLowerInvariant()}
}
function Get-LatestStableMagiskAsset { [CmdletBinding()] param([string]$ApiUrl='https://api.github.com/repos/topjohnwu/Magisk/releases/latest') $release=Invoke-RestMethod -UseBasicParsing -Uri $ApiUrl -Headers @{'User-Agent'='MT6833-Bootloader-AEiOU'}; return Get-MagiskAssetInfo -Release $release }
function Test-AndroidBootImage { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}; $fs=[IO.File]::OpenRead($Path);try{$b=New-Object byte[] 8;$n=$fs.Read($b,0,8);if($n-ne 8){return $false};return ([Text.Encoding]::ASCII.GetString($b)-eq'ANDROID!')}finally{$fs.Dispose()} }

Export-ModuleMember -Function Normalize-Slot,Get-BootPartitionName,Get-Sha256,Assert-ArtifactHash,Test-DeviceProfile,Test-SideloadEvidence,Test-RootEvidence,Write-WorkflowState,Read-WorkflowState,Assert-ResumeCompatible,Read-WorkflowManifest,Resolve-AndroidTool,Invoke-NativeChecked,Get-AdbIdentity,Wait-AdbState,Wait-AndroidBootCompleted,Get-FastbootVariable,Get-MagiskAssetInfo,Get-LatestStableMagiskAsset,Test-AndroidBootImage
