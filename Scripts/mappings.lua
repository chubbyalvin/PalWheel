
local Mappings = {
    openKey = "CAPS_LOCK",
    keyboardPageButton = "RIGHT_MOUSE_BUTTON",
    settingsKey = "F7",
    mouseActivateButton = "LEFT_MOUSE_BUTTON",
    aimMouseButton = "RIGHT_MOUSE_BUTTON",

    keyboardToggleStateKey = "CAPS_LOCK",

    keyboardMovementKeys = { "W", "A", "S", "D" },

    keyboardCancelKeys = {
        "TAB", "SPACE", "RETURN", "ESCAPE", "BACKSPACE", "CAPS_LOCK",
        "LEFT_SHIFT", "RIGHT_SHIFT", "LEFT_CONTROL", "RIGHT_CONTROL",
        "LEFT_ALT", "RIGHT_ALT", "PAUSE", "SCROLL_LOCK", "NUM_LOCK",
        "PRINT_SCREEN",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "ZERO", "ONE", "TWO", "THREE", "FOUR",
        "FIVE", "SIX", "SEVEN", "EIGHT", "NINE",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10",
        "F11", "F12", "F13", "F14", "F15", "F16", "F17", "F18", "F19",
        "F20", "F21", "F22", "F23", "F24",
        "LEFT_ARROW", "RIGHT_ARROW", "UP_ARROW", "DOWN_ARROW",
        "HOME", "END", "PAGE_UP", "PAGE_DOWN", "INS", "DEL",
        "NUMPADZERO", "NUMPADONE", "NUMPADTWO", "NUMPADTHREE",
        "NUMPADFOUR", "NUMPADFIVE", "NUMPADSIX", "NUMPADSEVEN",
        "NUMPADEIGHT", "NUMPADNINE", "MULTIPLY", "ADD", "SUBTRACT",
        "DECIMAL", "DIVIDE", "SEMICOLON", "EQUALS", "COMMA", "HYPHEN",
        "PERIOD", "SLASH", "TILDE", "LEFT_BRACKET", "BACKSLASH",
        "RIGHT_BRACKET", "APOSTROPHE",
        "LEFT_MOUSE_BUTTON", "RIGHT_MOUSE_BUTTON", "MIDDLE_MOUSE_BUTTON",
        "XBUTTON_ONE", "XBUTTON_TWO", "MOUSE_WHEEL_UP", "MOUSE_WHEEL_DOWN",
    },

    controllerOpenButton = "Gamepad_LeftShoulder",
    controllerPageButton = "Gamepad_RightShoulder",
    controllerAxisX = "Gamepad_RightX",
    controllerAxisY = "Gamepad_RightY",

    controllerCancelButtons = {
        "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right",
        "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
        "Gamepad_LeftShoulder", "Gamepad_RightShoulder",
        "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
        "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick",
        "Gamepad_DPad_Up", "Gamepad_DPad_Down",
        "Gamepad_DPad_Left", "Gamepad_DPad_Right",
        "Gamepad_Special_Left", "Gamepad_Special_Right",
        "Gamepad_Touchpad_Button",
    },

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

    menuShortcutKeys = {
        character = "TAB",
        inventory = "I",
        technology = "T",
        party = "P",
        build = "B",
    },
}

local FRIENDLY_NAMES = {
    CAPS_LOCK = "Caps Lock",
    LEFT_MOUSE_BUTTON = "Left Mouse",
    RIGHT_MOUSE_BUTTON = "Right Mouse",
    MIDDLE_MOUSE_BUTTON = "Middle Mouse",
    XBUTTON_ONE = "Mouse 4",
    XBUTTON_TWO = "Mouse 5",
    SPACE = "Space",
    RETURN = "Enter",
    ESCAPE = "Esc",
    LEFT_ARROW = "Left Arrow",
    RIGHT_ARROW = "Right Arrow",
    UP_ARROW = "Up Arrow",
    DOWN_ARROW = "Down Arrow",

    Gamepad_LeftShoulder = "L1 / LB",
    Gamepad_RightShoulder = "R1 / RB",
    Gamepad_LeftTrigger = "L2 / LT",
    Gamepad_RightTrigger = "R2 / RT",
    Gamepad_FaceButton_Bottom = "Cross / A",
    Gamepad_FaceButton_Right = "Circle / B",
    Gamepad_FaceButton_Left = "Square / X",
    Gamepad_FaceButton_Top = "Triangle / Y",
    Gamepad_LeftThumbstick = "L3 / LS Press",
    Gamepad_RightThumbstick = "R3 / RS Press",
    Gamepad_DPad_Up = "D-pad Up",
    Gamepad_DPad_Down = "D-pad Down",
    Gamepad_DPad_Left = "D-pad Left",
    Gamepad_DPad_Right = "D-pad Right",
    Gamepad_Special_Left = "Share / View",
    Gamepad_Special_Right = "Options / Menu",
}

local UNREAL_KEYBOARD_NAMES = {
    CAPS_LOCK = "CapsLock",
    SPACE = "SpaceBar",
    RETURN = "Enter",
    ESCAPE = "Escape",
    BACKSPACE = "BackSpace",
    LEFT_SHIFT = "LeftShift",
    RIGHT_SHIFT = "RightShift",
    LEFT_CONTROL = "LeftControl",
    RIGHT_CONTROL = "RightControl",
    LEFT_ALT = "LeftAlt",
    RIGHT_ALT = "RightAlt",
    SCROLL_LOCK = "ScrollLock",
    NUM_LOCK = "NumLock",
    PRINT_SCREEN = "PrintScreen",
    LEFT_ARROW = "Left",
    RIGHT_ARROW = "Right",
    UP_ARROW = "Up",
    DOWN_ARROW = "Down",
    PAGE_UP = "PageUp",
    PAGE_DOWN = "PageDown",
    INS = "Insert",
    DEL = "Delete",
    LEFT_MOUSE_BUTTON = "LeftMouseButton",
    RIGHT_MOUSE_BUTTON = "RightMouseButton",
    MIDDLE_MOUSE_BUTTON = "MiddleMouseButton",
    XBUTTON_ONE = "ThumbMouseButton",
    XBUTTON_TWO = "ThumbMouseButton2",
    MOUSE_WHEEL_UP = "MouseScrollUp",
    MOUSE_WHEEL_DOWN = "MouseScrollDown",
    LEFT_BRACKET = "LeftBracket",
    RIGHT_BRACKET = "RightBracket",
}

local UE4SS_KEY_NAMES = {
    CapsLock = "CAPS_LOCK",
    SpaceBar = "SPACE",
    Enter = "RETURN",
    Escape = "ESCAPE",
    BackSpace = "BACKSPACE",
    LeftShift = "LEFT_SHIFT",
    RightShift = "RIGHT_SHIFT",
    LeftControl = "LEFT_CONTROL",
    RightControl = "RIGHT_CONTROL",
    LeftAlt = "LEFT_ALT",
    RightAlt = "RIGHT_ALT",
    ScrollLock = "SCROLL_LOCK",
    NumLock = "NUM_LOCK",
    PrintScreen = "PRINT_SCREEN",
    Left = "LEFT_ARROW",
    Right = "RIGHT_ARROW",
    Up = "UP_ARROW",
    Down = "DOWN_ARROW",
    PageUp = "PAGE_UP",
    PageDown = "PAGE_DOWN",
    Insert = "INS",
    Delete = "DEL",
    LeftMouseButton = "LEFT_MOUSE_BUTTON",
    RightMouseButton = "RIGHT_MOUSE_BUTTON",
    MiddleMouseButton = "MIDDLE_MOUSE_BUTTON",
    ThumbMouseButton = "XBUTTON_ONE",
    ThumbMouseButton2 = "XBUTTON_TWO",
}

function Mappings.displayName(value)
    local name = tostring(value or "")
    if FRIENDLY_NAMES[name] ~= nil then return FRIENDLY_NAMES[name] end
    return string.gsub(name, "_", " ")
end

function Mappings.unrealFKeyName(value)
    local name = string.upper(tostring(value or ""))
    return UNREAL_KEYBOARD_NAMES[name] or tostring(value or "")
end

function Mappings.ue4ssKeyName(value)
    local name = tostring(value or "")
    if UE4SS_KEY_NAMES[name] ~= nil then return UE4SS_KEY_NAMES[name] end
    if string.match(name, "^[A-Za-z]$") then return string.upper(name) end
    local digitNames = {
        Zero = "ZERO", One = "ONE", Two = "TWO", Three = "THREE",
        Four = "FOUR", Five = "FIVE", Six = "SIX", Seven = "SEVEN",
        Eight = "EIGHT", Nine = "NINE",
    }
    return digitNames[name] or string.upper(name)
end

return Mappings
