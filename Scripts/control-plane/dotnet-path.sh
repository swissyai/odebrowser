# Sourced, from bash or zsh, by every script that runs dotnet.
# install-dotnet.sh installs the SDK that OdeCore/global.json pins in
# ${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet} and leaves PATH alone, so when no
# dotnet is on PATH this puts that directory first. A dotnet already on PATH
# is left in charge.

if ! command -v dotnet >/dev/null 2>&1; then
  if [ -x "${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet}/dotnet" ]; then
    PATH="${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet}:$PATH"
    export PATH
  else
    echo "error: no dotnet on PATH or in ${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet}; run Scripts/control-plane/install-dotnet.sh" >&2
    return 1 2>/dev/null || exit 1
  fi
fi
