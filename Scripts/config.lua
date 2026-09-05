local AuxData = require("auxiliary_data")

return {
    enabled = true,
    version = "2.0",
    auxWheelRuntime = AuxData,

    screenWidth = 1920,
    screenHeight = 1080,
    centerX = 960,
    centerY = 540,

    palWheel1SlotCount = 8,
    palWheel2SlotCount = 8,
    palWheel3SlotCount = 8,
    palWheelCount = 3,
    sphereWheelSlotCount = 10,
    sphereFollowTargetEnabled = true,
    sphereWheelBackgroundTransparencyPercent = 70,
    wheelInnerRadius = 88,
    wheelOuterRadius = 270,
    wheelSkin = "wheel_02.png",
    wheelBackgroundOpacity = 0.92,
    wheelDividerThickness = 2,
    wheelDividerHighlightThickness = 3,
    wheelOuterMarkerSize = 30,
    wheelOuterMarkerAspect = 1.0,
    wheelOuterMarkerBorderPadding = 4,
    wheelSelectedMarkerScale = 1.18,
    wheelSlotOneAngleDegrees = 180,
    centerSize = 136,

    wheelBorderOpacity = 0.72,
    wheelSelectedOpacity = 0.92,
    wheelCenterOpacity = 0.60,
    wheelDividerOpacity = 0.42,

    wheelOpenAnimationSeconds = 0.15,
    wheelPageFadeSeconds = 0.11,
    wheelSlotCascadeSeconds = 0.11,
    wheelSelectedContentScale = 1.58,
    wheelRuntimeIconSize = 55,
    wheelRuntimeLabelRadiusFactor = 0.25,

    editorBuildUnitsPerTick = 2,

    keyboardNextWheelButtonSwitchesWheel = true,
    releaseGraceSeconds = 0.10,

    controllerEnabled = true,
    controllerZoomEnabled = true,
    openWheelBehavior = "hold",
    controllerInvertY = true,
    controllerStickDeadzone = 0.60,
    controllerEarlyReturnSelect = true,
    controllerEarlyReturnDistance = 0.15,
    controllerCancelAnalogThreshold = 0.18,
    controllerHighlightHapticsLevel = 3,
    controllerHighlightHapticsDurationSeconds = 0.035,
    controllerHighlightHapticsMinIntervalSeconds = 0.025,
    controllerGlyphFamily = "auto",
    controllerGlyphFallbackFamily = "xbox",
    controllerUiStickThreshold = 0.62,
    controllerUiRepeatDelay = 0.38,
    controllerUiRepeatRate = 0.11,
    controllerUiMouseThreshold = 3.0,

    hideHardwareCursorWhileOpen = true,
    blockPageMouseAim = true,

    uiStackFallbackBaseline = 1,
    uiStackPollMs = 200,
    uiCalibrationMoveDistance = 25,
    uiCalibrationTeleportDistance = 20000,

    mouseDeadzone = 48,
    mouseMaxRadius = 250,

    weaponSelectionEnabled = true,
    palSelectionEnabled = true,
    mercyAccessoryToggleEnabled = true,
    sphereSelectionEnabled = true,

    notificationDurationSeconds = 3.0,
    notificationScreenYRatio = 0.333,
    notificationWidth = 760,
    notificationHeight = 58,
    notificationFontSize = 24,

    pollIntervalMs = 40,

    cameraLockIntervalMs = 16,

    slowMotionEnabled = true,
    wheelTimeDilation = 0.08,

    verboseLogging = false,
}
