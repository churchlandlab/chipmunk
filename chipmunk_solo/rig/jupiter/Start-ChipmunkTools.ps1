param([switch]$WithPinpoint)
$ErrorActionPreference = 'Stop'
Start-Transcript -Path (Join-Path $PSScriptRoot 'launcher.log') -Append | Out-Null
$configPath = Join-Path $PSScriptRoot 'rig-tools.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Open desktop tools only. Bpod owns acquisition and recording start/stop.
$spike = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^SpikeGLX' }
if (-not $spike) {
    # Detect/Verify checks the saved name before Bpod can assign its next session.
    $daqPath = Join-Path (Split-Path $config.spikeGLX) '_Configs/daq.ini'
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $original = [IO.File]::ReadAllBytes($daqPath)
    $text = $encoding.GetString($original)
    $runName = [regex]::new('(?m)^snsRunName=[^\r\n]*')
    if ($runName.Matches($text).Count -ne 1) { throw 'Expected exactly one saved SpikeGLX run name; settings left unchanged.' }
    $readyName = 'Ready_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N')
    $backupDir = Join-Path $PSScriptRoot 'backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir ($readyName + '-daq.ini')
    Copy-Item -LiteralPath $daqPath -Destination $backup
    if ((Get-FileHash $daqPath).Hash -ne (Get-FileHash $backup).Hash) { throw 'SpikeGLX settings backup verification failed.' }
    $temporary = $daqPath + '.' + $readyName + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $encoding.GetBytes($runName.Replace($text, 'snsRunName=' + $readyName)))
        [IO.File]::Replace($temporary, $daqPath, $backup)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
    Write-Output "Startup name: $readyName; settings backup: $backup"
    Start-Process -FilePath $config.spikeGLX -WorkingDirectory (Split-Path $config.spikeGLX)
}
$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $connected = $tcp.ConnectAsync($config.host, [int]$config.port)
        if ($connected.Wait(500) -and $tcp.Connected) { $ready = $true; break }
    } catch { }
    finally { $tcp.Dispose() }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw 'SpikeGLX did not open its command server. Check its Command Server settings.' }
$si = New-Object System.Diagnostics.ProcessStartInfo
$si.FileName = $config.helloSGLX
$si.WorkingDirectory = Split-Path $config.helloSGLX
$si.Arguments = "-host=$($config.host) -port=$($config.port) -cmd=getVersion"
$si.UseShellExecute = $false
$si.CreateNoWindow = $true
$si.RedirectStandardOutput = $true
$bridge = New-Object System.Diagnostics.Process
$bridge.StartInfo = $si
$bridge.Start() | Out-Null
if (-not $bridge.WaitForExit(15000)) { throw 'HelloSGLX health check timed out.' }
$version = $bridge.StandardOutput.ReadToEnd().Trim()
if ($version -match '^error' -or $version -notmatch 'SpikeGLX') { throw $version }
Write-Output $version
if ($WithPinpoint -and -not (Get-Process -Name 'Pinpoint' -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $config.pinpoint -WorkingDirectory (Split-Path $config.pinpoint)
}
Write-Output 'Recording tools ready. In Bpod: Prepare recording, then Start session.'
Stop-Transcript | Out-Null
