local KeyboardGlyphs = {}
KeyboardGlyphs.__index = KeyboardGlyphs

local NativeGlyphLoader = require("native_glyph_loader")

local KEYBOARD_DIR = "/Game/Pal/Texture/UI/KeyGuide/keyboard/"
local MOUSE_DIR = "/Game/Pal/Texture/UI/KeyGuide/mouse/"

local function keyboard(asset)
    return KEYBOARD_DIR .. asset .. "." .. asset
end

local function mouse(asset)
    return MOUSE_DIR .. asset .. "." .. asset
end


local KEY_PATHS = {
    Tab = keyboard("T_KeyGuide_Keyboard_Tab"),
    SpaceBar = keyboard("T_KeyGuide_Keyboard_Space"),
    Enter = keyboard("T_KeyGuide_Keyboard_Enter"),
    Escape = keyboard("T_KeyGuide_Keyboard_Esc"),
    BackSpace = keyboard("T_KeyGuide_Keyboard_BackSpace"),
    CapsLock = keyboard("T_KeyGuide_Keyboard_CapsLock"),
    LeftShift = keyboard("T_KeyGuide_Keyboard_shift"),
    RightShift = keyboard("T_KeyGuide_Keyboard_Shift_R"),
    LeftControl = keyboard("T_KeyGuide_Keyboard_Ctrl"),
    RightControl = keyboard("T_KeyGuide_Keyboard_Ctrl_R"),
    LeftAlt = keyboard("T_KeyGuide_Keyboard_Alt"),
    RightAlt = keyboard("T_KeyGuide_Keyboard_Alt_R"),
    Pause = keyboard("T_KeyGuide_Keyboard_Pause"),
    ScrollLock = keyboard("T_KeyGuide_Keyboard_ScrollLock"),

    Zero = keyboard("T_KeyGuide_Keyboard_0"),
    One = keyboard("T_KeyGuide_Keyboard_1"),
    Two = keyboard("T_KeyGuide_Keyboard_2"),
    Three = keyboard("T_KeyGuide_Keyboard_3"),
    Four = keyboard("T_KeyGuide_Keyboard_4"),
    Five = keyboard("T_KeyGuide_Keyboard_5"),
    Six = keyboard("T_KeyGuide_Keyboard_6"),
    Seven = keyboard("T_KeyGuide_Keyboard_7"),
    Eight = keyboard("T_KeyGuide_Keyboard_8"),
    Nine = keyboard("T_KeyGuide_Keyboard_9"),

    F1 = keyboard("T_KeyGuide_Keyboard_F1"),
    F2 = keyboard("T_KeyGuide_Keyboard_F2"),
    F3 = keyboard("T_KeyGuide_Keyboard_F3"),
    F4 = keyboard("T_KeyGuide_Keyboard_F4"),
    F5 = keyboard("T_KeyGuide_Keyboard_F5"),
    F6 = keyboard("T_KeyGuide_Keyboard_F6"),
    F7 = keyboard("T_KeyGuide_Keyboard_F7"),
    F8 = keyboard("T_KeyGuide_Keyboard_F8"),
    F9 = keyboard("T_KeyGuide_Keyboard_F9"),
    F10 = keyboard("T_KeyGuide_Keyboard_F10"),
    F11 = keyboard("T_KeyGuide_Keyboard_F11"),
    F12 = keyboard("T_KeyGuide_Keyboard_F12"),

    Left = keyboard("T_KeyGuide_Keyboard_Left"),
    Right = keyboard("T_KeyGuide_Keyboard_Right"),
    Up = keyboard("T_KeyGuide_Keyboard_Up"),
    Down = keyboard("T_KeyGuide_Keyboard_Down"),
    Home = keyboard("T_KeyGuide_Keyboard_Home"),
    End = keyboard("T_KeyGuide_Keyboard_End"),
    PageUp = keyboard("T_KeyGuide_Keyboard_PageUp"),
    PageDown = keyboard("T_KeyGuide_Keyboard_PageDown"),
    Insert = keyboard("T_KeyGuide_Keyboard_Insert"),
    Delete = keyboard("T_KeyGuide_Keyboard_Delete"),

    NumPadZero = keyboard("T_KeyGuide_Keyboard_Num0"),
    NumPadOne = keyboard("T_KeyGuide_Keyboard_Num1"),
    NumPadTwo = keyboard("T_KeyGuide_Keyboard_Num2"),
    NumPadThree = keyboard("T_KeyGuide_Keyboard_Num3"),
    NumPadFour = keyboard("T_KeyGuide_Keyboard_Num4"),
    NumPadFive = keyboard("T_KeyGuide_Keyboard_Num5"),
    NumPadSix = keyboard("T_KeyGuide_Keyboard_Num6"),
    NumPadSeven = keyboard("T_KeyGuide_Keyboard_Num7"),
    NumPadEight = keyboard("T_KeyGuide_Keyboard_Num8"),
    NumPadNine = keyboard("T_KeyGuide_Keyboard_Num9"),
    Multiply = keyboard("T_KeyGuide_Keyboard_NumAsterisk"),
    Add = keyboard("T_KeyGuide_Keyboard_NumPlus"),
    Subtract = keyboard("T_KeyGuide_Keyboard_NumMinus"),
    Decimal = keyboard("T_KeyGuide_Keyboard_NumPeriod"),
    Divide = keyboard("T_KeyGuide_Keyboard_NumSlash"),

    Semicolon = keyboard("T_KeyGuide_Keyboard_Semicolon"),
    Comma = keyboard("T_KeyGuide_Keyboard_Comma"),
    Hyphen = keyboard("T_KeyGuide_Keyboard_Hyphen"),
    Period = keyboard("T_KeyGuide_Keyboard_Period"),
    Slash = keyboard("T_KeyGuide_Keyboard_Slash"),
    Tilde = keyboard("T_KeyGuide_Keyboard_Tilde"),
    LeftBracket = keyboard("T_KeyGuide_Keyboard_LeftBracket"),
    Backslash = keyboard("T_KeyGuide_Keyboard_Backslash"),
    RightBracket = keyboard("T_KeyGuide_Keyboard_RightBracket"),
    Apostrophe = keyboard("T_KeyGuide_Keyboard_Apostrophe"),

    LeftMouseButton = mouse("T_MenuKeyGuide_MouseButtonLeft"),
    RightMouseButton = mouse("T_MenuKeyGuide_MouseButtonRight"),
    MiddleMouseButton = mouse("T_MenuKeyGuide_MouseWheelButton"),
    MouseWheelAxis = mouse("T_MenuKeyGuide_MouseWheelButton"),
    MouseScrollUp = mouse("T_MenuKeyGuide_MouseWheelButton"),
    MouseScrollDown = mouse("T_MenuKeyGuide_MouseWheelButton"),
    ThumbMouseButton = mouse("T_MenuKeyGuide_MouseButton4"),
    ThumbMouseButton2 = mouse("T_MenuKeyGuide_MouseButton5"),
}

for code = string.byte("A"), string.byte("Z") do
    local name = string.char(code)
    KEY_PATHS[name] = keyboard("T_KeyGuide_Keyboard_" .. name)
end


local KNOWN_KEYBOARD_ASSETS = {
    "T_KeyGuide_Keyboard_0","T_KeyGuide_Keyboard_1","T_KeyGuide_Keyboard_2","T_KeyGuide_Keyboard_3",
    "T_KeyGuide_Keyboard_4","T_KeyGuide_Keyboard_5","T_KeyGuide_Keyboard_6","T_KeyGuide_Keyboard_7",
    "T_KeyGuide_Keyboard_8","T_KeyGuide_Keyboard_9","T_KeyGuide_Keyboard_a_grave","T_KeyGuide_Keyboard_A",
    "T_KeyGuide_Keyboard_Alt_R","T_KeyGuide_Keyboard_Alt","T_KeyGuide_Keyboard_And","T_KeyGuide_Keyboard_Apostrophe",
    "T_KeyGuide_Keyboard_Asterisk","T_KeyGuide_Keyboard_atto","T_KeyGuide_Keyboard_B","T_KeyGuide_Keyboard_Backslash",
    "T_KeyGuide_Keyboard_BackSpace","T_KeyGuide_Keyboard_C","T_KeyGuide_Keyboard_CapsLock","T_KeyGuide_Keyboard_CaretHat",
    "T_KeyGuide_Keyboard_Cedilla","T_KeyGuide_Keyboard_Colon","T_KeyGuide_Keyboard_Comma","T_KeyGuide_Keyboard_Ctrl_R",
    "T_KeyGuide_Keyboard_Ctrl","T_KeyGuide_Keyboard_D","T_KeyGuide_Keyboard_Delete","T_KeyGuide_Keyboard_Dollar",
    "T_KeyGuide_Keyboard_DoubleQuotation","T_KeyGuide_Keyboard_Down","T_KeyGuide_Keyboard_e_grave","T_KeyGuide_Keyboard_E",
    "T_KeyGuide_Keyboard_End","T_KeyGuide_Keyboard_Enter","T_KeyGuide_Keyboard_Esc","T_KeyGuide_Keyboard_Exclamation",
    "T_KeyGuide_Keyboard_F","T_KeyGuide_Keyboard_F1","T_KeyGuide_Keyboard_F10","T_KeyGuide_Keyboard_F11",
    "T_KeyGuide_Keyboard_F12","T_KeyGuide_Keyboard_F2","T_KeyGuide_Keyboard_F3","T_KeyGuide_Keyboard_F4",
    "T_KeyGuide_Keyboard_F5","T_KeyGuide_Keyboard_F6","T_KeyGuide_Keyboard_F7","T_KeyGuide_Keyboard_F8",
    "T_KeyGuide_Keyboard_F9","T_KeyGuide_Keyboard_G","T_KeyGuide_Keyboard_H","T_KeyGuide_Keyboard_Home",
    "T_KeyGuide_Keyboard_Hyphen","T_KeyGuide_Keyboard_I","T_KeyGuide_Keyboard_Insert","T_KeyGuide_Keyboard_J",
    "T_KeyGuide_Keyboard_K","T_KeyGuide_Keyboard_L","T_KeyGuide_Keyboard_Left","T_KeyGuide_Keyboard_LeftBracket",
    "T_KeyGuide_Keyboard_LeftParenthesis","T_KeyGuide_Keyboard_M","T_KeyGuide_Keyboard_N","T_KeyGuide_Keyboard_Num0",
    "T_KeyGuide_Keyboard_Num1","T_KeyGuide_Keyboard_Num2","T_KeyGuide_Keyboard_Num3","T_KeyGuide_Keyboard_Num4",
    "T_KeyGuide_Keyboard_Num5","T_KeyGuide_Keyboard_Num6","T_KeyGuide_Keyboard_Num7","T_KeyGuide_Keyboard_Num8",
    "T_KeyGuide_Keyboard_Num9","T_KeyGuide_Keyboard_NumAsterisk","T_KeyGuide_Keyboard_NumMinus","T_KeyGuide_Keyboard_NumPeriod",
    "T_KeyGuide_Keyboard_NumPlus","T_KeyGuide_Keyboard_NumSlash","T_KeyGuide_Keyboard_O","T_KeyGuide_Keyboard_P",
    "T_KeyGuide_Keyboard_PageDown","T_KeyGuide_Keyboard_PageUp","T_KeyGuide_Keyboard_Pause","T_KeyGuide_Keyboard_Period",
    "T_KeyGuide_Keyboard_Q","T_KeyGuide_Keyboard_R","T_KeyGuide_Keyboard_Right","T_KeyGuide_Keyboard_RightBracket",
    "T_KeyGuide_Keyboard_RightParenthesis","T_KeyGuide_Keyboard_S","T_KeyGuide_Keyboard_ScrollLock","T_KeyGuide_Keyboard_Semicolon",
    "T_KeyGuide_Keyboard_Shift_R","T_KeyGuide_Keyboard_shift","T_KeyGuide_Keyboard_Slash","T_KeyGuide_Keyboard_Space",
    "T_KeyGuide_Keyboard_T","T_KeyGuide_Keyboard_Tab","T_KeyGuide_Keyboard_Tilde","T_KeyGuide_Keyboard_u_grave",
    "T_KeyGuide_Keyboard_U","T_KeyGuide_Keyboard_Underscore","T_KeyGuide_Keyboard_Up","T_KeyGuide_Keyboard_V",
    "T_KeyGuide_Keyboard_W","T_KeyGuide_Keyboard_X","T_KeyGuide_Keyboard_Y","T_KeyGuide_Keyboard_Z",
}

function KeyboardGlyphs.new(options)
    return setmetatable({ o = options or {}, logged = false }, KeyboardGlyphs)
end

function KeyboardGlyphs:prepare()
    if not self.logged and type(self.o.log) == "function" then
        self.logged = true
        self.o.log("Native keyboard/mouse glyph resolver ready: 112 keyboard + 11 mouse assets known; exact-load cache active", true)
    end
    return true
end

function KeyboardGlyphs:pathForKey(key)
    return KEY_PATHS[tostring(key or "")]
end

function KeyboardGlyphs:textureForKey(key)
    self:prepare()
    local path = self:pathForKey(key)
    if path == nil then return nil end
    return NativeGlyphLoader.texture(path)
end

function KeyboardGlyphs:knownKeyboardAssets()
    return KNOWN_KEYBOARD_ASSETS
end

return KeyboardGlyphs
