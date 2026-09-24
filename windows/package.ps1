$ErrorActionPreference = "Stop"

$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$output = Join-Path $PSScriptRoot "artifacts\Klik-Windows-preview"

dotnet publish .\Klik.Windows\Klik.Windows.csproj `
  -c Release `
  -r win-x64 `
  -p:Platform=x64 `
  --self-contained true `
  -p:PublishSingleFile=false `
  -o $output

Copy-Item .\THIRD-PARTY-NOTICES.md $output
Write-Host "Klik preview package: $output"
