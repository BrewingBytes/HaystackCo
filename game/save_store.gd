class_name SaveStore
extends RefCounted
## The save files (eng D2, D11; G6). Godot has no fsync, so a write goes to a temp file that is
## then renamed over the primary (atomic on Android's filesystem), and the backup is a copy of
## the last good primary, made before each new write. A file that fails to load moves to
## quarantine/ (kept out of Android backups) and the other file is tried; a save from a newer
## app is never touched.
##
##   save/game.sav   primary          save/game.bak   copy of the last good primary
##   save/*.tmp      writes in flight save/quarantine/ files that failed to load (newest few)

enum Notice { NONE, RESTORED, FRESH, UPDATE_REQUIRED }

const PRIMARY := "game.sav"
const BACKUP := "game.bak"
const QUARANTINE := "quarantine"
const QUARANTINE_KEEP := 4

var dir: String
## False after a newer app's save was found: this session must not overwrite it.
var writable := true


func _init(p_dir := "user://save") -> void:
	dir = p_dir


## { state: GameState or null (start fresh), notice: Notice, detail: String }. Regenerates the
## pile: run it off the main thread.
func load_state(economy: Economy) -> Dictionary:
	var detail := ""
	for name in [PRIMARY, BACKUP]:
		var path := dir.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		var result := SaveCodec.decode(FileAccess.get_file_as_bytes(path), economy)
		if result.refusal == SaveCodec.Refusal.NONE:
			# Loading the backup means the primary was bad or missing: say so.
			return {state = result.state, notice = Notice.RESTORED if name == BACKUP else Notice.NONE, detail = detail}
		if result.refusal == SaveCodec.Refusal.NEWER_VERSION:
			writable = false
			return {state = null, notice = Notice.UPDATE_REQUIRED, detail = result.detail}
		detail += "%s: %s %s; " % [name, SaveCodec.Refusal.keys()[result.refusal], result.detail]
		_quarantine(name)
	return {state = null, notice = Notice.FRESH if detail != "" else Notice.NONE, detail = detail}


## Writes `state`. The previous primary becomes the backup first, if it's intact. Returns OK,
## or the error (disk full, …): the last good files stay as they were.
func save(state: GameState, now_unix: int) -> Error:
	if not writable:
		return ERR_UNAVAILABLE
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var primary := dir.path_join(PRIMARY)
	if FileAccess.file_exists(primary):
		var previous := FileAccess.get_file_as_bytes(primary)
		if SaveCodec.intact(previous):
			var backed_up := _write(BACKUP, previous)
			if backed_up != OK:
				return backed_up
	state.saved_at_unix = now_unix
	return _write(PRIMARY, SaveCodec.encode(state, now_unix))


## Temp file, then rename over `name`.
func _write(name: String, bytes: PackedByteArray) -> Error:
	var temp := dir.path_join(name + ".tmp")
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if not stored or error != OK:
		DirAccess.remove_absolute(temp)
		return error if error != OK else ERR_FILE_CANT_WRITE
	return DirAccess.rename_absolute(temp, dir.path_join(name))


func _quarantine(name: String) -> void:
	var into := dir.path_join(QUARANTINE)
	DirAccess.make_dir_recursive_absolute(into)
	DirAccess.rename_absolute(dir.path_join(name), into.path_join("%s.%d" % [name, Time.get_unix_time_from_system()]))
	var kept := Array(DirAccess.get_files_at(into))
	kept.sort_custom(func(a: String, b: String) -> bool: return a.get_extension().to_int() < b.get_extension().to_int())
	while kept.size() > QUARANTINE_KEEP:
		DirAccess.remove_absolute(into.path_join(kept.pop_front()))
