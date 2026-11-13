#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h:h}"
source "$repository_root/Scripts/control-plane/dotnet-path.sh"
cd "$repository_root/OdeCore"

project="tests/OdeCore.Tests/OdeCore.Tests.csproj"
generator="tools/OdeCore.Generator/OdeCore.Generator.csproj"
dotnet restore "$project" --nologo
dotnet restore "$generator" --nologo

for project in src/OdeCore/OdeCore.csproj src/OdeCore.Native/OdeCore.Native.csproj "$generator" "$project"; do
  dotnet format analyzers "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format style "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format whitespace "$project" --verify-no-changes --no-restore --verbosity quiet
done

"$repository_root/Scripts/control-plane/generate-contracts.sh" --check
