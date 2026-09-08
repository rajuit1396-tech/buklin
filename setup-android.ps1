$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Install Flutter and add its bin directory to PATH, then run this script again. See README.md.'
}

# Generate Android tooling matched to the locally installed Flutter SDK.
# Flutter create preserves existing source files unless --overwrite is used.
flutter create --platforms=android --project-name=buklin --org=com.example --empty .
if ($LASTEXITCODE -ne 0) { throw 'Android project generation failed.' }

# Live requests need network access in release builds as well as debug builds.
$manifestPath = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$internetPermission = @($manifest.manifest.'uses-permission') | Where-Object {
    $_ -and $_.GetAttribute('name', $androidNamespace) -eq 'android.permission.INTERNET'
}
if (-not $internetPermission) {
    $permission = $manifest.CreateElement('uses-permission')
    $permission.SetAttribute('name', $androidNamespace, 'android.permission.INTERNET')
    $manifest.manifest.PrependChild($permission) | Out-Null
    $manifest.Save($manifestPath)
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency setup failed.' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }

Write-Host 'Setup complete. Start an Android emulator or connect your phone, then run: flutter run'
