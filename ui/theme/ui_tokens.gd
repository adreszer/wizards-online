class_name UiTokens
extends RefCounted
## Design tokens for the whole UI ("candlelit oak and parchment", docs/ui.md): colours,
## spacing, radii, sizes and motion. tools/build_ui_theme.gd builds the themes from
## these; code that needs a colour or a size asks here instead of writing a literal.

# Oak & brass: chrome (HUD, menus, settings, chat, tools).
const OAK := Color("1e1712eb")
const OAK_SOLID := Color("1e1712")
const OAK_RAISED := Color("2c221a")
const OAK_HOVER := Color("3a2c20")
const OAK_PRESSED := Color("140f0b")
const OAK_INSET := Color("120d0ae6")
const OAK_LINE := Color("4a3a2a")
const BRASS := Color("c8a35a")
const BRASS_BRIGHT := Color("e8c77a")
const BRASS_DIM := Color("7a6240")
const CANDLE := Color("f2e6cc")
const CANDLE_SOFT := Color("b9a98c")
const CANDLE_DIM := Color("7d705c")

# Parchment & ink: reading surfaces (journal, books, notices, letters, small panels).
const PARCHMENT := Color("e9ddbf")
const PARCHMENT_DEEP := Color("d8c7a0")
const PARCHMENT_EDGE := Color("73502b")
const INK := Color("2b1d10")
const INK_SOFT := Color("5c4630")
const INK_FAINT := Color("5c463059")
const RUBRIC := Color("8a2e1c")

# States.
const DANGER := Color("c2523c")
const SUCCESS := Color("7fa35a")
const SHADOW := Color("00000080")

# Spacing scale (px) and radii.
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const SPACE_6 := 32
const SPACE_7 := 48
const RADIUS_SMALL := 3
const RADIUS := 4

# Font sizes (px at interface scale 1).
const SIZE_SMALL := 13
const SIZE_HINT := 14
const SIZE_BODY := 16
const SIZE_LARGE := 18
const SIZE_READING := 19
const SIZE_TITLE := 30
const SIZE_BANNER := 64

# Text in the world (Label3D: nameplates, speech bubbles, boards).
## Chalk on a slate board, and chalk on a board with nothing running.
const CHALK := Color("eeece2")
const CHALK_DIM := Color("bfc7b8bf")
## The dark rim that keeps floating text readable against a bright wall or sky.
const WORLD_OUTLINE := Color("0a0710d9")
## Nameplate tints by role: students in candlelight, professors in brass, the
## administrator in a cool green so staff are recognisable across a room.
const NAME_STUDENT := CANDLE
const NAME_PROFESSOR := BRASS_BRIGHT
const NAME_ADMIN := Color("a9d6a0")

# Motion (seconds); reduced motion turns these into instant changes.
const FAST := 0.12
const NORMAL := 0.2
const SLOW := 0.35

## The theme a parchment surface sets on its root control so everything inside it is
## drawn in ink on paper; written by tools/build_ui_theme.gd.
const PARCHMENT_THEME := "res://ui/theme/parchment_theme.tres"
