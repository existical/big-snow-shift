extends Control


func _ready() -> void:
	print("BIG_SNOW_SHIFT_TOOLCHAIN_OK platform=%s renderer=%s" % [
		OS.get_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method")
	])
	if "--smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit()
