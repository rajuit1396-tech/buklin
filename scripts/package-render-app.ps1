$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    flutter build web --release --base-href /app/ --no-web-resources-cdn --csp --dart-define=BACKEND_URL=https://buklin-1.onrender.com --output backend/public/app
    if ($LASTEXITCODE -ne 0) { throw 'Flutter production build failed.' }
} finally {
    Pop-Location
}
