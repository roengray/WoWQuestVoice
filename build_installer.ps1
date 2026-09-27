param(
    [string]$OutputName = 'WoWQuestVoiceSetup-UNSIGNED-QA',
    [string]$CertificateThumbprint = '',
    [switch]$SkipAgentBuild,
    [string]$PythonCommand = 'python',
    [string]$InnoCompiler = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $root 'release\installer'
$agentDist = Join-Path $root 'build\dist'
$agentWork = Join-Path $root 'build\pyinstaller'
$publicConfig = Join-Path $root 'collector_public_config.json'
$versionInfo = Join-Path $root 'installer\windows_version_info.txt'

if (-not $SkipAgentBuild) {
    if (-not (Test-Path -LiteralPath $publicConfig)) {
        throw 'collector_public_config.json is missing; copy the example and configure it first'
    }
    & $PythonCommand -m PyInstaller --noconfirm --clean --windowed --onedir `
        --name WoWQuestVoiceAgent --distpath $agentDist --workpath $agentWork `
        --specpath (Join-Path $root 'build') --version-file $versionInfo `
        --add-data ($publicConfig + ';.') `
        (Join-Path $root 'wowquestvoice_background_agent.pyw')
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller build failed' }
}

$candidates = @(
    $InnoCompiler,
    (Join-Path $root 'tools\InnoSetup\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { $_ }
$iscc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup compiler was not found' }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
& $iscc "/DOutputName=$OutputName" (Join-Path $root 'installer\WoWQuestVoice.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup build failed' }

$setup = Join-Path $outputDir ($OutputName + '.exe')
if ($CertificateThumbprint) {
    $signtool = (Get-Command signtool.exe -ErrorAction Stop).Source
    & $signtool sign /sha1 $CertificateThumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $setup
    if ($LASTEXITCODE -ne 0) { throw 'Code signing failed' }
}

$signature = Get-AuthenticodeSignature -LiteralPath $setup
[pscustomobject]@{
    Path = $setup
    Bytes = (Get-Item -LiteralPath $setup).Length
    SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $setup).Hash
    Signature = $signature.Status
}
