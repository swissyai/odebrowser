using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using OdeCore.Application;
using OdeCore.Contracts;

namespace OdeCore.Native;

public static unsafe partial class Exports {
    #region Variables

    /// One monotonic sequence for every handle table in this image, so a handle
    /// from one authority can never be mistaken for a live handle in another.
    private static long nextHandle;

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_core_abi_version", CallConvs = [typeof(CallConvCdecl)])]
    public static uint AbiVersion() => 1;

    #endregion
}
