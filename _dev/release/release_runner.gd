@tool
extends Node
## Herramienta de releases (solo editor). Al abrir release_runner.tscn en el editor lee
## res://_dev/release/job.json y hace la acción pedida con el Godot de Windows del usuario:
##   {"action": "info"} → entorno (plantillas, Java, SDK de Android) en result.json
##   {"action": "export", "preset": "...", "out": "C:/...", "debug": false} → lanza una exportación headless
## No forma parte del juego.

const JOB := "res://_dev/release/job.json"
const RESULT := "res://_dev/release/result.json"


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if not FileAccess.file_exists(JOB):
		return
	var job = JSON.parse_string(FileAccess.get_file_as_string(JOB))
	if not job is Dictionary:
		return
	var out := {"job": job, "time": Time.get_datetime_string_from_system()}
	match str(job.get("action", "")):
		"info":
			out.merge(_info())
		"export":
			out.merge(_export(job))
		"cmd":
			out.merge(_cmd(job))
		"editor_setting":
			EditorInterface.get_editor_settings().set_setting(str(job.key), job.value)
			out["set"] = {job.key: job.value}
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(JOB)) # una sola vez


func _info() -> Dictionary:
	var es := EditorInterface.get_editor_settings()
	var paths := EditorInterface.get_editor_paths()
	var tdir := paths.get_data_dir().path_join("export_templates").path_join("4.7.2.stable")
	var templates: Array = []
	var d := DirAccess.open(tdir)
	if d:
		for fn in d.get_files():
			templates.append(fn)
	var r := {
		"godot_exe": OS.get_executable_path(),
		"version": Engine.get_version_info().string,
		"templates_dir": tdir,
		"templates": templates,
		"project_dir": ProjectSettings.globalize_path("res://"),
	}
	for k in ["export/android/java_sdk_path", "export/android/android_sdk_path", "export/android/debug_keystore",
			"export/android/debug_keystore_user", "export/android/shutdown_adb_on_exit"]:
		r[k] = str(es.get_setting(k)) if es.has_setting(k) else "(no existe)"
	# ¿Qué hay instalado?
	var java_home := OS.get_environment("JAVA_HOME")
	r["env_JAVA_HOME"] = java_home
	r["env_ANDROID_HOME"] = OS.get_environment("ANDROID_HOME")
	var o: Array = []
	OS.execute("cmd.exe", ["/c", "where java & where keytool & java -version"], o, true)
	r["where_java"] = o
	return r


func _export(job: Dictionary) -> Dictionary:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--export-debug" if bool(job.get("debug", false)) else "--export-release",
		str(job.preset), str(job.out)]
	var log_path: String = str(job.get("log", ""))
	var pid := -1
	if log_path != "":
		# Redirige la salida a un archivo con cmd.exe para poder leerla después
		var cmdline := "\"%s\" %s > \"%s\" 2>&1" % [OS.get_executable_path(), " ".join(args.map(func(a): return "\"%s\"" % a)), log_path]
		pid = OS.create_process("cmd.exe", ["/c", cmdline])
	else:
		pid = OS.create_process(OS.get_executable_path(), args)
	return {"pid": pid, "args": args}


## Ejecuta un comando de Windows. wait=true → espera y devuelve la salida; si no, en segundo plano
## volcando la salida a `log`.
func _cmd(job: Dictionary) -> Dictionary:
	var c: String = str(job.cmd)
	if bool(job.get("wait", true)):
		var o: Array = []
		var code := OS.execute("cmd.exe", ["/c", c], o, true)
		return {"exit_code": code, "output": o}
	var log_path: String = str(job.get("log", ""))
	var full := c if log_path == "" else "%s > \"%s\" 2>&1" % [c, log_path]
	return {"pid": OS.create_process("cmd.exe", ["/c", full])}
