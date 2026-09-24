$ErrorActionPreference = "Stop"

$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"

dotnet restore .\Klik.Windows.sln
dotnet build .\Klik.Windows.sln -c Release --no-restore -p:Platform=x64
dotnet test .\Klik.Windows.Tests\Klik.Windows.Tests.csproj -c Release
