class_name SnowCache
extends Node
## Persistent world-resolution colour and first-intersection depth. A small
## overwrite quad replaces changed pixels, including newly transparent pixels.

const SHADER = preload("res://assets/art/snow.gdshader")
const ORIGIN := Vector2(StairSurface.CENTER - StairSurface.BOTTOM_WIDTH / 2, StairSurface.TOP - SnowField.RENDER_PAD)
const EXTENT := Vector2(StairSurface.BOTTOM_WIDTH, StairSurface.BOTTOM - StairSurface.TOP + SnowField.RENDER_PAD)
const SIZE := Vector2i(ceili(EXTENT.x), ceili(EXTENT.y))
var color_view: SubViewport
var depth_view: SubViewport
var quads: Array[ColorRect] = []
var mask_texture: ImageTexture
var updates := 0
var last_region := Rect2i()

func _init() -> void:
	color_view = create_cache(false)
	depth_view = create_cache(true)

static func configure(material: ShaderMaterial) -> void:
	material.set_shader_parameter("stair_left", ORIGIN.x)
	material.set_shader_parameter("stair_width", EXTENT.x)
	material.set_shader_parameter("stair_top", StairSurface.TOP)
	material.set_shader_parameter("stair_height", StairSurface.BOTTOM - StairSurface.TOP)
	material.set_shader_parameter("tread_edges", PackedFloat32Array(StairSurface.TREAD_EDGES))
	material.set_shader_parameter("tread_left", PackedFloat32Array(StairSurface.TREAD_LEFT))
	material.set_shader_parameter("tread_right", PackedFloat32Array(StairSurface.TREAD_RIGHT))

func create_cache(depth: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "SnowDepth" if depth else "SnowColour"
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var quad := ColorRect.new()
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	configure(material)
	material.set_shader_parameter("output_depth", depth)
	quad.material = material
	viewport.add_child(quad)
	add_child(viewport)
	quads.append(quad)
	return viewport

func bind(field: SnowField) -> void:
	# Restores/test fixtures may replace cells directly. Binding is always full.
	field.dirty = true
	mask_texture = ImageTexture.create_from_image(field.image())
	for quad in quads:
		quad.material.set_shader_parameter("snow_mask", mask_texture)
	invalidate(SnowField.ALL_CELLS)

func refresh(field: SnowField) -> void:
	var changed := field.dirty_cells
	mask_texture.update(field.image())
	invalidate(changed)

static func region_for_cells(cells: Rect2i) -> Rect2i:
	if cells == SnowField.ALL_CELLS:
		return Rect2i(Vector2i.ZERO, SIZE)
	# Cubic smoothing and linear sampling reach beyond the changed cells.
	var area := cells.grow(3).intersection(SnowField.ALL_CELLS)
	var low := Vector2(area.position) / Vector2(SnowField.WIDTH, SnowField.HEIGHT)
	var high := Vector2(area.end) / Vector2(SnowField.WIDTH, SnowField.HEIGHT)
	var y0 := lerpf(StairSurface.TOP, StairSurface.BOTTOM, low.y)
	var y1 := lerpf(StairSurface.TOP, StairSurface.BOTTOM, high.y)
	var left := INF
	var right := -INF
	var levels: Array[float] = [y0, y1]
	for edge in StairSurface.TREAD_EDGES:
		if edge > y0 and edge < y1: levels.append(edge)
	for y in levels:
		var bounds := StairSurface.bounds_at(y)
		left = minf(left, lerpf(bounds.x, bounds.y, low.x))
		right = maxf(right, lerpf(bounds.x, bounds.y, high.x))
	var start := ((Vector2(left - 2, y0 - SnowField.RENDER_PAD - 2) - ORIGIN) / EXTENT * Vector2(SIZE)).floor()
	var finish := ((Vector2(right + 2, y1 + 2) - ORIGIN) / EXTENT * Vector2(SIZE)).ceil()
	return Rect2i(Vector2i(start), Vector2i(finish - start)).intersection(Rect2i(Vector2i.ZERO, SIZE))

func invalidate(cells: Rect2i) -> void:
	var region := region_for_cells(cells)
	# Multiple updates before rendering must be merged, not overwrite each other.
	if RenderingServer.viewport_get_update_mode(color_view.get_viewport_rid()) == RenderingServer.VIEWPORT_UPDATE_ONCE:
		region = region.merge(last_region)
	last_region = region
	for quad in quads:
		quad.position = Vector2(region.position)
		quad.size = Vector2(region.size)
		quad.material.set_shader_parameter("cache_uv_origin", Vector2(region.position) / Vector2(SIZE))
		quad.material.set_shader_parameter("cache_uv_size", Vector2(region.size) / Vector2(SIZE))
	color_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	depth_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	updates += 1
