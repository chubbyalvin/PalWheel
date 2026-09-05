


local KEYBOARD_BINDING_KEYS = {
    "Escape", "Tab", "BackSpace", "CapsLock", "Enter", "SpaceBar",
    "LeftShift", "RightShift", "LeftControl", "RightControl",
    "LeftAlt", "RightAlt", "Pause", "ScrollLock", "NumLock", "PrintScreen",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24",
    "Left", "Right", "Up", "Down", "Home", "End", "PageUp", "PageDown", "Insert", "Delete",
    "NumPadZero", "NumPadOne", "NumPadTwo", "NumPadThree", "NumPadFour",
    "NumPadFive", "NumPadSix", "NumPadSeven", "NumPadEight", "NumPadNine",
    "Multiply", "Add", "Subtract", "Decimal", "Divide",
    "Semicolon", "Equals", "Comma", "Hyphen", "Period", "Slash", "Tilde",
    "LeftBracket", "Backslash", "RightBracket", "Apostrophe",
    "LeftMouseButton", "RightMouseButton", "MiddleMouseButton",
    "ThumbMouseButton", "ThumbMouseButton2",
}

local CONTROLLER_BINDING_KEYS = {
    "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right",
    "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder",
    "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down",
    "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "Gamepad_Special_Left", "Gamepad_Special_Right",
}

local CONTROLLER_CANCEL_KEYS = {
    "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right",
    "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder",
    "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down",
    "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "Gamepad_Special_Left", "Gamepad_Special_Right",
    "Gamepad_Touchpad_Button",
    "Gamepad_LeftBack", "Gamepad_RightBack",
    "Gamepad_LeftPaddle", "Gamepad_RightPaddle",
}

local KEYBOARD_SUPPORTED_SET = {}
local KEYBOARD_CANONICAL_BY_NORMALIZED = {}
local function normalizedKeyName(value)
    return string.lower(tostring(value or ""):gsub("[^%w]", ""))
end
for _, name in ipairs(KEYBOARD_BINDING_KEYS) do
    KEYBOARD_SUPPORTED_SET[name] = true
    KEYBOARD_CANONICAL_BY_NORMALIZED[normalizedKeyName(name)] = name
end

local UE4SS_KEY_ENUM_NAMES = {
    Tab = "TAB", SpaceBar = "SPACE", Enter = "RETURN", Escape = "ESCAPE",
    BackSpace = "BACKSPACE", CapsLock = "CAPS_LOCK",
    LeftShift = "LEFT_SHIFT", RightShift = "RIGHT_SHIFT",
    LeftControl = "LEFT_CONTROL", RightControl = "RIGHT_CONTROL",
    LeftAlt = "LEFT_ALT", RightAlt = "RIGHT_ALT",
    Pause = "PAUSE", ScrollLock = "SCROLL_LOCK", NumLock = "NUM_LOCK",
    PrintScreen = "PRINT_SCREEN",
    Zero = "ZERO", One = "ONE", Two = "TWO", Three = "THREE", Four = "FOUR",
    Five = "FIVE", Six = "SIX", Seven = "SEVEN", Eight = "EIGHT", Nine = "NINE",
    Left = "LEFT_ARROW", Right = "RIGHT_ARROW", Up = "UP_ARROW", Down = "DOWN_ARROW",
    Home = "HOME", End = "END", PageUp = "PAGE_UP", PageDown = "PAGE_DOWN",
    Insert = "INS", Delete = "DEL",
    NumPadZero = "NUMPADZERO", NumPadOne = "NUMPADONE", NumPadTwo = "NUMPADTWO",
    NumPadThree = "NUMPADTHREE", NumPadFour = "NUMPADFOUR", NumPadFive = "NUMPADFIVE",
    NumPadSix = "NUMPADSIX", NumPadSeven = "NUMPADSEVEN", NumPadEight = "NUMPADEIGHT",
    NumPadNine = "NUMPADNINE", Multiply = "MULTIPLY", Add = "ADD",
    Subtract = "SUBTRACT", Decimal = "DECIMAL", Divide = "DIVIDE",
    Semicolon = "SEMICOLON", Equals = "EQUALS", Comma = "COMMA", Hyphen = "HYPHEN",
    Period = "PERIOD", Slash = "SLASH", Tilde = "TILDE", LeftBracket = "LEFT_BRACKET",
    Backslash = "BACKSLASH", RightBracket = "RIGHT_BRACKET", Apostrophe = "APOSTROPHE",
    LeftMouseButton = "LEFT_MOUSE_BUTTON", RightMouseButton = "RIGHT_MOUSE_BUTTON",
    MiddleMouseButton = "MIDDLE_MOUSE_BUTTON", ThumbMouseButton = "XBUTTON_ONE",
    ThumbMouseButton2 = "XBUTTON_TWO",
}
local KEYBOARD_CANONICAL_BY_ENUM = {}
for canonical, enumName in pairs(UE4SS_KEY_ENUM_NAMES) do
    KEYBOARD_CANONICAL_BY_ENUM[normalizedKeyName(enumName)] = canonical
end

local Mappings = {
    
    
    openKey = "CapsLock",
    keyboardNextWheelButton = "MiddleMouseButton",
    settingsKey = "F7",
    mouseActivateButton = "LeftMouseButton",
    aimMouseButton = "RightMouseButton",

    keyboardMovementKeys = { "W", "A", "S", "D" },
    keyboardBindingKeys = KEYBOARD_BINDING_KEYS,
    keyboardCancelKeys = KEYBOARD_BINDING_KEYS,

    controllerOpenButton = "Gamepad_LeftShoulder",
    controllerNextWheelButton = "Gamepad_RightShoulder",
    controllerPalWheelMenuButton = "Gamepad_RightThumbstick",
    controllerSphereThrowButton = "Gamepad_RightShoulder",
    controllerSphereLauncherAimButton = "Gamepad_LeftTrigger",
    keyboardSphereThrowButton = "Q",
    keyboardSphereLauncherAimButton = "RightMouseButton",
    controllerAxisX = "Gamepad_RightX",
    controllerAxisY = "Gamepad_RightY",

    controllerBindingKeys = CONTROLLER_BINDING_KEYS,
    controllerCancelButtons = CONTROLLER_CANCEL_KEYS,

    controllerMovementKeys = {
        "Gamepad_LeftX", "Gamepad_LeftY", "Gamepad_Left2D",
        "Gamepad_LeftStick_Up", "Gamepad_LeftStick_Down",
        "Gamepad_LeftStick_Left", "Gamepad_LeftStick_Right",
    },
    controllerSelectionAxisKeys = {
        "Gamepad_RightX", "Gamepad_RightY", "Gamepad_Right2D",
        "Gamepad_RightStick_Up", "Gamepad_RightStick_Down",
        "Gamepad_RightStick_Left", "Gamepad_RightStick_Right",
    },
}

function Mappings.displayName(value)
    return tostring(value or "")
end

function Mappings.unrealFKeyName(value)
    return tostring(value or "")
end

function Mappings.ue4ssKeyName(value)
    local name = tostring(value or "")
    return UE4SS_KEY_ENUM_NAMES[name] or string.upper(name)
end

function Mappings.isCanonicalKeyboardBindingKey(value)
    return KEYBOARD_SUPPORTED_SET[tostring(value or "")] == true
end

function Mappings.canonicalKeyboardBindingKey(value)
    local name = tostring(value or ""):match("^%s*(.-)%s*$")
    if KEYBOARD_SUPPORTED_SET[name] then return name end
    local normalized = normalizedKeyName(name)
    return KEYBOARD_CANONICAL_BY_ENUM[normalized]
        or KEYBOARD_CANONICAL_BY_NORMALIZED[normalized]
end

return Mappings
