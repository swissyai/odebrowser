// The engine host header declares these Objective-C names, and the prebuilt
// engine matches them by name at run time, so they keep the base product's
// spelling until the engine is rebuilt. Swift uses the Ode names.

#if ODE_CHROMIUM_HOST
    public typealias OdeEngineApplicationEvents = CrestEngineApplicationEvents
    public typealias OdeEngineApplicationHosting = CrestEngineApplicationHosting
    public typealias OdeEngineWindowPlacement = CrestEngineWindowPlacement
    public typealias OdeExtensionShortcut = CrestExtensionShortcut
    public typealias OdeMacShell = CrestMacShell
    public typealias OdeMacUI = CrestMacUI
#endif
