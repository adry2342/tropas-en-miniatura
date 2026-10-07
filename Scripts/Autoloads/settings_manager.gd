extends Node
## Configuración de PC (user://settings.cfg): modo de ventana, resolución, VSync y límite de FPS.
## Se aplica al arrancar y cada vez que se cambia algo en el panel de Configuración.

const SAVE_PATH := "user://settings.cfg"

enum WindowMode { VENTANA, PANTALLA_COMPLETA, SIN_BORDES }
const WINDOW_MODE_NAMES := ["Ventana", "Pantalla completa", "Ventana sin bordes"]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440),
]
const FPS_LIMITS: Array[int] = [30, 60, 120, 144, 0] # 0 = sin límite

var window_mode: int = WindowMode.VENTANA
var resolution: Vector2i = Vector2i(1280, 720)
var vsync: bool = true
var max_fps: int = 0
## false en los tests: no toca el disco ni la ventana.
var persist: bool = true


func _ready() -> void:
	load_settings()
	if persist and not _is_headless():
		apply()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func apply() -> void:
	Engine.max_fps = max_fps
	if _is_headless():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var win := get_window()
	match window_mode:
		WindowMode.PANTALLA_COMPLETA:
			win.borderless = false
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		WindowMode.SIN_BORDES:
			# Ventana sin bordes a pantalla completa (borderless fullscreen)
			win.mode = Window.MODE_FULLSCREEN
		_:
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			var size := Vector2i(mini(resolution.x, usable.size.x), mini(resolution.y, usable.size.y))
			win.size = size
			win.position = usable.position + (usable.size - size) / 2


func set_window_mode(m: int) -> void:
	window_mode = clampi(m, 0, WINDOW_MODE_NAMES.size() - 1)
	_commit()


func set_resolution(r: Vector2i) -> void:
	resolution = r
	_commit()


func set_vsync(on: bool) -> void:
	vsync = on
	_commit()


func set_max_fps(fps: int) -> void:
	max_fps = maxi(0, fps)
	_commit()


func _commit() -> void:
	if persist:
		apply()
		save_settings()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "window_mode", window_mode)
	cf.set_value("video", "resolution", resolution)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "max_fps", max_fps)
	cf.save(SAVE_PATH)


func load_settings() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	window_mode = clampi(int(cf.get_value("video", "window_mode", window_mode)), 0, WINDOW_MODE_NAMES.size() - 1)
	var r = cf.get_value("video", "resolution", resolution)
	if r is Vector2i:
		resolution = r
	vsync = bool(cf.get_value("video", "vsync", vsync))
	max_fps = maxi(0, int(cf.get_value("video", "max_fps", max_fps)))
