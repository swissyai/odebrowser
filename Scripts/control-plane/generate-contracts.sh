#!/bin/zsh
# Regenerates the contract codecs and models from the C# contract records, the
# core's OdeCore.Contracts namespace: the core's ContractCodec, the two Swift
# files under OdeShared/Infrastructure/Core/Generated,
# CrestContracts/include/crest_contracts.h and the C++ engine codec
# CrestContracts/include/crest_engine_contract.h. Pass --check to verify that
# they are current without writing anything.
set -euo pipefail

repository_root="${0:A:h:h:h}"
source "$repository_root/Scripts/control-plane/dotnet-path.sh"
dotnet run --project "$repository_root/OdeCore/tools/OdeCore.Generator" --nologo -- --root "$repository_root" "$@"
