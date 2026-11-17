class_name MenuIcons
extends RefCounted
## Original monochrome symbols, tinted to match each button's text.

const PLAY = preload("res://assets/art/menu_icons/play.svg")
const NEW_GAME = preload("res://assets/art/menu_icons/new_game.svg")
const TROPHY = preload("res://assets/art/menu_icons/trophy.svg")
const SETTINGS = preload("res://assets/art/menu_icons/settings.svg")
const HOME = preload("res://assets/art/menu_icons/home.svg")
const RETRY = preload("res://assets/art/menu_icons/retry.svg")
const NEXT = preload("res://assets/art/menu_icons/next.svg")
const BACK = preload("res://assets/art/menu_icons/back.svg")
const CHECK = preload("res://assets/art/menu_icons/check.svg")
const PEOPLE = preload("res://assets/art/menu_icons/people.svg")
const TOUCH = preload("res://assets/art/menu_icons/touch.svg")
const PAD = preload("res://assets/art/menu_icons/pad.svg")
const MUSIC = preload("res://assets/art/menu_icons/music.svg")
const SOUND = preload("res://assets/art/menu_icons/sound.svg")
const LANGUAGE = preload("res://assets/art/menu_icons/language.svg")
const CLOSE = preload("res://assets/art/menu_icons/close.svg")
const UNCHECKED = preload("res://assets/art/menu_icons/unchecked.svg")
const SNOW = preload("res://assets/art/menu_icons/snow.svg")
const PLUS = preload("res://assets/art/menu_icons/plus.svg")
const MINUS = preload("res://assets/art/menu_icons/minus.svg")
const FULLSCREEN = preload("res://assets/art/menu_icons/fullscreen.svg")
const LICENSE = preload("res://assets/art/menu_icons/license.svg")
const PRIVACY = preload("res://assets/art/menu_icons/privacy.svg")

const ACTIONS := {
	"settings.privacy": PRIVACY,
	"settings.fullscreen": FULLSCREEN,
	"custom.more": SETTINGS, "custom.title": SETTINGS,
	"custom.reset": RETRY,
	"custom.landingWarnings": CHECK,
	"menu.play": PLAY, "menu.continue": PLAY, "menu.newGame": NEW_GAME,
	"common.scores": TROPHY, "common.settings": SETTINGS,
	"common.credits": PEOPLE, "common.mainMenu": HOME,
	"confirm.continue": PLAY, "confirm.start": NEW_GAME,
	"pause.resume": PLAY,
	"result.save": TROPHY, "result.retry": RETRY, "result.next": NEXT,
	"credits.back": BACK,
	"credits.licenses": LICENSE,
	"settings.done": CHECK, "settings.screen": TOUCH, "settings.pad": PAD,
	"difficulty.back": BACK, "difficulty.start": PLAY,
	"difficulty.noTime": CHECK, "difficulty.noIce": CHECK,
	"difficulty.easy": SNOW, "difficulty.medium": SNOW, "difficulty.hard": SNOW, "difficulty.extreme": TROPHY,
	"scores.personal": PEOPLE,
}
