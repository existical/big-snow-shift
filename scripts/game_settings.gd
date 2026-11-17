class_name GameSettings
extends RefCounted

## Built-in defaults for new games. Saved runs retain their recorded rules.
const DEFAULT_SPEED := 1.75
const DEFAULT_IDLE_SPEED := 1.0
const MIN_SPEED := .25
const MAX_SPEED := 3.0
const DEFAULT_SCOOP := 255
const MAX_SCOOP := 765 # Full base (255) plus the largest impact pile (510).
const DEFAULT_HIT_RECOVERY := 6.0
const MIN_HIT_RECOVERY := 1.0
const MAX_HIT_RECOVERY := 10.0

var player_speed_multiplier := DEFAULT_SPEED
var idle_animation_multiplier := DEFAULT_IDLE_SPEED
var snow_per_scoop := DEFAULT_SCOOP
var hit_recovery_seconds := DEFAULT_HIT_RECOVERY
