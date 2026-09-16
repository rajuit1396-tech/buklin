$ErrorActionPreference = 'Stop'
$url = 'https://dl.google.com/android/repository/android-ndk-r28c-windows.zip'
$total = 748118221L
$partsDir = Join-Path $PSScriptRoot 'ndk-parts'
New-Item -ItemType Directory -Force -Path $partsDir | Out-Null
$count = 8
$size = [long][math]::Ceiling($total / $count)
$jobs = @()
for ($i = 0; $i -lt $count; $i++) {
    $start = $i * $size
    $end = [math]::Min($total - 1, ($i + 1) * $size - 1)
    $part = Join-Path $partsDir ("part-{0:D2}.bin" -f $i)
    $expected = $end - $start + 1
    if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -eq $expected) { continue }
    $args = @('--range', "$start-$end", '--fail', '--retry', '5', '--retry-all-errors', '--silent', '--show-error', '--output', $part, $url)
    $process = Start-Process -FilePath 'curl.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    $jobs += [pscustomobject]@{ Process = $process; Path = $part; Expected = $expected }
}
foreach ($job in $jobs) {
    $job.Process.WaitForExit()
    if ($job.Process.ExitCode -ne 0 -or (Get-Item -LiteralPath $job.Path).Length -ne $job.Expected) {
        throw "Download failed: $($job.Path)"
    }
}
$archive = Join-Path $PSScriptRoot 'android-ndk-r28c-windows.zip'
$output = [System.IO.File]::Create($archive)
try {
    for ($i = 0; $i -lt $count; $i++) {
        $part = Join-Path $partsDir ("part-{0:D2}.bin" -f $i)
        $inputStream = [System.IO.File]::OpenRead($part)
        try { $inputStream.CopyTo($output) } finally { $inputStream.Dispose() }
    }
} finally { $output.Dispose() }
if ((Get-Item -LiteralPath $archive).Length -ne $total) { throw 'Archive size mismatch.' }
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA1).Hash.ToLowerInvariant()
if ($actual -ne '086bba43ff2f5eb0e387b15c8278bb4e0d89ba1d') { throw "Archive checksum mismatch: $actual" }
Write-Output "Verified NDK archive: $archive"
