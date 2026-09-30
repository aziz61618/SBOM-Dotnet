#!/bin/bash
export PATH="$PATH:$HOME/.dotnet/tools"
export PATH="$PATH:/root/.dotnet/tools"
dotnet tool install --global dotnet-outdated-tool --add-source https://api.nuget.org/v3/index.json
# dotnet outdated > outdated-dependencies.txt
dotnet list package --outdated > outdated-dependencies.txt
# Install dotnet-project-licenses tool globally
dotnet tool install --global dotnet-project-licenses
echo $HOME/.dotnet/tools/dotnet-project-licenses
# List installed global tools to verify installation
dotnet tool list -g
# Run dotnet-project-licenses to generate a licenses report including transitive dependencies
#$HOME/.dotnet/tools/dotnet-project-licenses -i "./" --include-transitive > sbom-licenses.txt
# Run dotnet-project-licenses to generate a licenses report dependencies
$HOME/.dotnet/tools/dotnet-project-licenses -i "./"  > sbom-licenses.txt