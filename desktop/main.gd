extends Control

const Arcade = preload("res://arcade_skin.gd")

var base = ""
var token = ""
var socket = WebSocketPeer.new()
var snapshot = {"workers": [], "connections": [], "projects": [], "busy": false}
var detail = {}
var view = "Farm"
var farm_scene
var farm_backdrop
var game_shell
var selected_project = ""
var expanded_accounts = {}
var selected_worker = ""
var new_farm_worker = ""
var page: VBoxContainer
var status_label: Label
var notice_label: Label
var live_label: Label
var chat_drafts = {}
var transcript: VBoxContainer
var transcript_key = ""
var progress_label: Label
var last_core_seen = 0
var progress_clock = 0.0
var heartbeat_clock = 0.0
var pending_refresh = false
var refresh_clock = 0.0
var closing = false
var session_path = ""
var screenshot_path = ""
var connected = false
var worker_form = {}
var task_rows = []
var plan_dirty = false
var approve_button: Button
var start_button: Button
var plan_brief_field: TextEdit
var approval_hint: Label
var save_near_approval: Button
var reviewer_picker: OptionButton
var approval_settings_dirty = false
var navigation = {}
var guide_step = "welcome"
var guide_idea = ""
var guide_planner = ""
var guide_folder = ""
var guide_pending = false
var journal_open = false
var journal_section = "Contents"
var review = {}
var reply_mode = false
var report_index = -1
var preview_doc = {}
var preview_serial = 0
var voice_enabled = false
var tracked_project = ""
var farm_run = {}
var delivery = {}
var return_from_hiring = false

func _ready():
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(960, 640)
	var args = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--session": session_path = args[i + 1]
		if args[i] == "--screenshot": screenshot_path = args[i + 1]
		if args[i] == "--view": view = args[i + 1]
		if args[i] == "--window-size":
			var dimensions = args[i + 1].split("x")
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = Vector2i(int(dimensions[0]),int(dimensions[1]))
	if not FileAccess.file_exists(session_path):
		push_error("Launch Agent Farmers through its launcher.")
		get_tree().quit(1)
		return
	var session = JSON.parse_string(FileAccess.get_file_as_string(session_path))
	base = "http://127.0.0.1:" + str(int(session.port))
	token = str(session.token)
	socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + token])
	socket.connect_to_url(base.replace("http://", "ws://") + "/v1/events")
	_build_shell()
	_reload(true)
	if "--smoke" in args:
		await get_tree().create_timer(4).timeout
		if not connected:
			push_error("Smoke test could not connect to the core.")
			get_tree().quit(2)
			return
		for name in ["Farm", "Overview", "Workers", "Connections", "Projects", "Results", "Memory"]:
			view = name
			_render()
			await get_tree().process_frame
		# UI-only checks: layout, world navigation and movement; no agent work.
		for dimensions in [Vector2i(960,640),Vector2i(1280,860),Vector2i(1600,900)]:
			get_window().size = dimensions
			await get_tree().process_frame
			await get_tree().process_frame
			game_shell.arrange()
			if game_shell.dock.get_combined_minimum_size().x > dimensions.x - 32 or game_shell.window_panel.position.x + game_shell.window_panel.size.x > dimensions.x:
				push_error("Game shell overflow at " + str(dimensions))
				get_tree().quit(2)
				return
		view = "Farm"
		_render()
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = farm_backdrop.camera.unproject_position(Vector3(-4,0,3.6))
		farm_backdrop._gui_input(click)
		if view != "Projects" or not game_shell.overlay.visible:
			push_error("World project-table navigation failed.")
			get_tree().quit(2)
			return
		var escape = InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		game_shell._unhandled_key_input(escape)
		if view != "Farm" or game_shell.overlay.visible:
			push_error("Escape did not return to the world.")
			get_tree().quit(2)
			return
		# Exercise roster growth and worker selection without writing fixture workers.
		var fixture = []
		for i in range(11): fixture.append({"id":"fixture-%d"%i,"name":"Farmhand %d"%i})
		farm_backdrop.sync_state({"workers":fixture})
		var actor = farm_backdrop.crew_by_id["fixture-10"].node
		var prior = actor.position
		farm_backdrop._process(0.2)
		fixture[10].name = "Renamed farmhand"
		farm_backdrop.sync_state({"workers":fixture,"busy":true,"activeWorker":{"workerId":"fixture-10","stage":"execution"}})
		if not farm_backdrop.crew_by_id["fixture-10"].tag.text.ends_with("Working") or farm_backdrop.farmers[0].on_duty:
			push_error("Crew assignment status is inaccurate.")
			get_tree().quit(2)
			return
		if farm_backdrop.farmers.size()!=11 or farm_backdrop.plots.size()<3 or actor.position==prior or farm_backdrop.crew_by_id["fixture-10"].node!=actor:
			push_error("Farm roster expansion or movement failed.")
			get_tree().quit(2)
			return
		click.position = farm_backdrop.camera.unproject_position(actor.position+Vector3.UP*1.3)
		farm_backdrop._gui_input(click)
		if view!="Workers" or selected_worker!="fixture-10":
			push_error("Farm crew selection failed.")
			get_tree().quit(2)
			return
		selected_worker = ""
		farm_backdrop.sync_state(snapshot)
		if not snapshot.projects.is_empty():
			selected_project = str(snapshot.projects[0].id)
			view = "Project"
			journal_open = true
			journal_section = "Plan"
			_reload(true)
			await get_tree().create_timer(1).timeout
			if detail.is_empty():
				push_error("Project detail did not load.")
				get_tree().quit(2)
				return
			if detail.project.status in ["awaiting_approval", "ready"] and not snapshot.get("busy", false):
				_mark_plan_dirty()
				if approve_button.disabled:
					push_error("A loaded saved plan was incorrectly marked dirty.")
					get_tree().quit(2)
					return
				var original = plan_brief_field.text
				plan_brief_field.text += "\nUI regression edit"
				_mark_plan_dirty()
				if not approve_button.disabled:
					push_error("An edited unsaved plan remained approvable.")
					get_tree().quit(2)
					return
				plan_brief_field.text = original
				_mark_plan_dirty()
				if approve_button.disabled:
					push_error("Reverting the edit did not restore approval.")
					get_tree().quit(2)
					return
			if not detail.get("artifacts", []).is_empty():
				_preview(str(detail.artifacts[0].id))
				await get_tree().create_timer(0.6).timeout
				if view=="Preview": _close_preview()
			# Presentation regression only; no backend state or real task is changed.
			detail["live"] = {"worker": "UI fixture", "stage": "review", "elapsedSeconds": 65, "eventAgeSeconds": 12, "processRunning": true, "lastActivity": "Waiting for runtime output"}
			_update_progress()
			if not progress_label.text.contains("Elapsed 01:05") or not progress_label.text.contains("Runtime process active"):
				push_error("Live progress presentation failed.")
				get_tree().quit(2)
				return
			detail["live"] = null
			_update_progress()
		get_tree().quit()
		return
	if screenshot_path != "":
		await get_tree().create_timer(5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not closing:
		if snapshot.get("busy", false):
			var dialog = ConfirmationDialog.new()
			dialog.dialog_text = "Work is still active. Closing stops the current task and preserves partial results. Close?"
			add_child(dialog)
			dialog.confirmed.connect(_exit)
			dialog.popup_centered()
		else: _exit()

func _exit():
	closing = true
	get_tree().quit()

func _process(delta):
	socket.poll()
	_tick_handoffs(delta)
 
	progress_clock += delta
	heartbeat_clock += delta
	if progress_clock > 0.2:
		progress_clock = 0
		_update_progress()
	if heartbeat_clock > 2 and (snapshot.get("busy",false) or (view=="Project" and not detail.is_empty() and detail.project.status in ["planning","running","reviewing","queued"])):
		heartbeat_clock = 0
		_reload(false)
	if connected and socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and is_instance_valid(status_label): status_label.text = "Core connection lost · restart the app to recover saved history"
	while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		var event = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if event is Dictionary:
			pending_refresh = true
			if event.get("kind", "") in ["planning_finished", "workflow_finished"]:
				_reload(true)
	refresh_clock += delta
	if pending_refresh and refresh_clock > 0.7:
		pending_refresh = false
		refresh_clock = 0
		_reload(false)

func _api(path: String, method: int, body: Dictionary, callback: Callable, failed: Callable = Callable()):
	var request = HTTPRequest.new()
	request.timeout = 30
	add_child(request)
	request.request_completed.connect(func(result, code, _headers, bytes):
		var value = JSON.parse_string(bytes.get_string_from_utf8())
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or not value is Dictionary:
			if failed.is_valid(): failed.call()
			_notice("The local core could not be reached. Check data/runtime.log.")
			return
		if code >= 400:
			if failed.is_valid(): failed.call()
			_notice(str(value.get("error", "Request failed")))
			return
		callback.call(value)
	)
	var error = request.request(base + path, PackedStringArray(["Authorization: Bearer " + token, "Content-Type: application/json"]), method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		request.queue_free()
		if failed.is_valid(): failed.call()
		_notice("Could not send the request to the local core.")

func _command(action: String, payload: Dictionary, callback: Callable = Callable()):
	_api("/v1/command", HTTPClient.METHOD_POST, {"action": action, "payload": payload}, func(value):
		if callback.is_valid(): callback.call(value.get("result", {}))
		_reload(true)
	)

func _reload(redraw: bool):
	_api("/v1/state", HTTPClient.METHOD_GET, {}, func(value):
		snapshot = value
		connected = true
		last_core_seen = Time.get_ticks_msec()
		if selected_project == "" and view == "Project" and not snapshot.projects.is_empty(): selected_project = str(snapshot.projects[0].id)
		status_label.text = "Working" if value.get("busy", false) else "Checking connections…" if value.get("checking", false) else "Ready"
		if is_instance_valid(farm_scene): farm_scene.sync_state(snapshot)
		if is_instance_valid(farm_backdrop):
			farm_backdrop.sync_state(snapshot)
			_farm_dispatch()
			game_shell.hint.text = "Open Crew to add your first farmhand" if snapshot.workers.is_empty() else "Planning table opens projects    ·    Select a farmer to manage crew"
			if farm_backdrop.crew_by_id.has(new_farm_worker):
				farm_backdrop.pan = farm_backdrop.crew_by_id[new_farm_worker].home
				new_farm_worker = ""
		if selected_project != "" and view == "Project":
			_api("/v1/projects/" + selected_project, HTTPClient.METHOD_GET, {}, func(project_value):
				if view != "Project" or str(project_value.project.id) != selected_project: return
				detail = project_value
				if redraw: _render()
				else: _update_live()
			)
		elif view!="Preview" and (redraw or view in ["Overview", "Connections", "Results"]): _render()
	)

func _style():
	var theme = Theme.new()
	theme.default_font_size = 15
	for type in ["Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "RichTextLabel"]:
		theme.set_color("font_color", type, Color("2e372d"))
		theme.set_color("font_hover_color", type, Color("172b21"))
		theme.set_color("font_pressed_color", type, Color("172b21"))
		theme.set_color("font_focus_color", type, Color("172b21"))
		theme.set_color("font_placeholder_color", type, Color("8b8c7d"))
		theme.set_color("font_readonly_color", type, Color("354132"))
		theme.set_color("font_uneditable_color", type, Color("354132"))
	for type in ["TabBar", "TabContainer"]:
		for color_name in ["font_selected_color", "font_unselected_color", "font_hovered_color", "font_focus_color"]: theme.set_color(color_name, type, Color("2e372d"))
		for state in ["panel", "tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
			var box = StyleBoxFlat.new()
			box.bg_color = Color("f7f8f5") if state == "panel" else Color("e0e8dd") if state == "tab_selected" else Color("f3f5f0")
			box.border_color = Color("bdc4ae")
			box.set_border_width_all(1)
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 10
			box.content_margin_bottom = 10
			theme.set_stylebox(state, type, box)
	_control_defaults(theme)
	_farm_theme(theme)

func _farm_box(fill: String, edge: String, depth: int = 3) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.border_color = Color(edge)
	box.set_border_width_all(2)
	box.border_width_bottom = depth
	box.set_corner_radius_all(0)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _farm_theme(theme: Theme):
	# One shared, square-edged game UI across every functional screen.
	for type in ["Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "RichTextLabel"]:
		theme.set_color("font_color", type, Color("433b2b"))
		theme.set_color("font_disabled_color", type, Color("82755e"))
		theme.set_color("font_placeholder_color", type, Color("887d64"))
	theme.set_color("default_color", "RichTextLabel", Color("433b2b"))
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var fill = "f0d599" if state == "normal" else "ffe9b7" if state in ["hover", "focus"] else "d6b879" if state == "pressed" else "d7cbb0"
			theme.set_stylebox(state, type, _farm_box(fill,"8b663f",5 if state != "pressed" else 2))
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "focus", "read_only"]:
			theme.set_stylebox(state,type,_farm_box("fff8e6","728b45" if state == "focus" else "b6a47c",2))
		for color_name in ["caret_color", "caret_background_color"]: theme.set_color(color_name,type,Color("433b2b"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state,"Primary",_farm_box("65863e" if state == "normal" else "789b4c" if state in ["hover","focus"] else "506d32" if state == "pressed" else "b9b79c","405b2c",5))
	for type in ["Nav", "NavSelected"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(state,type,_farm_box("66893f" if type == "NavSelected" else "f1d599" if state == "normal" else "ffe8b1","4e6633" if type == "NavSelected" else "a77d48",4))
		for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			theme.set_color(color_name,type,Color("fff8e5") if type == "NavSelected" else Color("493c29"))
	for type in ["TabContainer","TabBar"]:
		for state in ["panel","tab_selected","tab_unselected","tab_hovered","tab_focus"]:
			theme.set_stylebox(state,type,_farm_box("fff5db" if state == "panel" else "e8c47d" if state == "tab_selected" else "f4e3bb","b29a6b",2))
	for type in ["PanelContainer","PopupMenu","AcceptDialog"]:
		theme.set_stylebox("panel",type,_farm_box("fff2d3","a17c4b",5))
	theme.set_stylebox("grabber","VScrollBar",_farm_box("b99b63","967d4f",2))
	theme.set_stylebox("grabber_highlight","VScrollBar",_farm_box("8da650","6b813c",2))
	theme.set_stylebox("scroll","VScrollBar",_farm_box("ebdcbc","ebdcbc",0))
	for type in ["VScrollBar", "HScrollBar"]:
		for state in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
			var bar = StyleBoxFlat.new()
			bar.bg_color = Color("eadcba") if state == "scroll" else Color("a78a54") if state == "grabber" else Color("718e44")
			bar.content_margin_left = 5 if type == "VScrollBar" else 0
			bar.content_margin_right = 5 if type == "VScrollBar" else 0
			bar.content_margin_top = 5 if type == "HScrollBar" else 0
			bar.content_margin_bottom = 5 if type == "HScrollBar" else 0
			theme.set_stylebox(state,type,bar)

func _control_defaults(theme: Theme):
	for type in ["Button", "LineEdit", "TextEdit", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "read_only"]:
			var box = StyleBoxFlat.new()
			box.bg_color = Color("ffffff") if type in ["LineEdit", "TextEdit"] else Color("eff2eb")
			box.border_color = Color("55765a") if state in ["hover", "focus"] else Color("bdc4ae")
			box.set_border_width_all(1)
			box.set_corner_radius_all(3)
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 9
			box.content_margin_bottom = 9
			theme.set_stylebox(state, type, box)
	self.theme = theme
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	for checked in [false, true]:
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><rect x="1" y="1" width="16" height="16" rx="2" fill="' + ('#355b43' if checked else '#ffffff') + '" stroke="#7d8d7a"/>' + ('<path d="M4 9l3 3 7-7" fill="none" stroke="white" stroke-width="2"/>' if checked else '') + '</svg>'
		var image = Image.new()
		image.load_svg_from_string(svg)
		theme.set_icon("checked" if checked else "unchecked", "CheckBox", ImageTexture.create_from_image(image))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: theme.set_color(color_name, "Primary", Color.WHITE)
	theme.set_type_variation("Primary", "Button")
	for state in ["normal", "hover", "pressed", "focus"]:
		var box = StyleBoxFlat.new()
		box.bg_color = Color("355b43") if state == "normal" else Color("284b35")
		box.set_corner_radius_all(3)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 9
		box.content_margin_bottom = 9
		theme.set_stylebox(state, "Primary", box)
	for type in ["Nav", "NavSelected"]:
		theme.set_type_variation(type, "Button")
		for state in ["normal", "hover", "pressed", "focus"]:
			var box = StyleBoxFlat.new()
			box.bg_color = Color("dce7d9") if type == "NavSelected" else Color("eaf0e6") if state == "hover" else Color.TRANSPARENT
			box.set_corner_radius_all(3)
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 10
			box.content_margin_bottom = 10
			theme.set_stylebox(state, type, box)

func _build_shell():
	_style()
	_game_theme()
	game_shell = load("res://game_shell.gd").new()
	add_child(game_shell)
	page = game_shell.page
	status_label = game_shell.status
	notice_label = game_shell.notice
	farm_backdrop = game_shell.farm
	game_shell.crew_picked.connect(func(id): selected_worker = id; view = "Workers"; _render())
	game_shell.dispatch.pressed.connect(func(): _open_dialogue(str(game_shell.dispatch.get_meta("project_id",""))))
	game_shell.navigate.connect(func(destination):
		if view=="Preview":
			_close_preview()
			return
		journal_open = false
		reply_mode = false
		report_index = -1
		review.clear()
		if destination=="Projects": guide_step = "welcome"
		view = destination
		_render())
	_render()

func _game_theme():
	var ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Segoe UI","Arial"])
	ui_font.font_weight = 600
	theme.default_font = ui_font
	theme.set_type_variation("Dock","Button")
	for kind in ["Button","OptionButton","Dock","Primary"]:
		var dark = kind == "Dock"
		var face = "284751" if dark else "ffce27" if kind=="Primary" else "c2e4f4" if kind=="OptionButton" else "ebedf5"
		var depth = "172f39" if dark else "c58915" if kind=="Primary" else "7ea4bf" if kind=="OptionButton" else "9ba9c8"
		for state in ["normal","hover","pressed","disabled"]:
			var fill = Color(face)
			if state=="hover": fill=fill.lightened(0.16)
			if state=="pressed": fill=fill.darkened(0.12)
			if state=="disabled": fill=Color("c9ced6")
			theme.set_stylebox(state,kind,Arcade.box(fill.to_html(false),"192c4a",depth,fill.lightened(0.48).to_html(false)))
		if not dark: theme.set_font_size("font_size",kind,17)
		var focus = StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(2)
		focus.border_color = Color("10887e")
		focus.set_corner_radius_all(0)
		theme.set_stylebox("focus",kind,focus)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			theme.set_color(key,kind,Color("fffbed") if dark else Color("223f48"))
		theme.set_color("font_disabled_color",kind,Color("5b6c6b"))
	for kind in ["Label","LineEdit","TextEdit","CheckBox","RichTextLabel","PopupMenu"]:
		theme.set_color("font_color",kind,Color("263f47"))
		theme.set_color("font_placeholder_color",kind,Color("657774"))
	theme.set_color("font_hover_color","PopupMenu",Color("173639"))
	theme.set_stylebox("hover","PopupMenu",_farm_box("d7eadf","d7eadf",1))
	theme.set_color("default_color","RichTextLabel",Color("263f47"))
	for kind in ["PanelContainer","PopupMenu","AcceptDialog"]:
		var box = _farm_box("fcfaed","435f62",6)
		box.set_border_width_all(3)
		box.border_width_right = 5
		box.border_width_bottom = 6
		box.shadow_color = Color("18343855")
		box.shadow_size = 2
		box.shadow_offset = Vector2(3,4)
		theme.set_stylebox("panel",kind,box)
	for kind in ["TextEdit","LineEdit"]:
		for state in ["normal","focus","read_only"]:
			theme.set_stylebox(state,kind,Arcade.box("f9faff","2873c0" if state=="focus" else "607593","bdc8d9","ffffff"))
	for kind in ["TabBar","TabContainer"]:
		for state in ["panel","tab_selected","tab_unselected","tab_hovered","tab_focus"]:
			theme.set_stylebox(state,kind,_farm_box("fbfcf4" if state == "panel" else "ffdc88" if state == "tab_selected" else "e4eee7","c5d4ca",2))
		for key in ["font_selected_color","font_unselected_color","font_hovered_color","font_focus_color"]:
			theme.set_color(key,kind,Color("263f47"))
	for kind in ["VScrollBar","HScrollBar"]:
		for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
			var bar = theme.get_stylebox(state,kind)
			bar.bg_color = Color("e2eae3" if state == "scroll" else "9bb8ad" if state == "grabber" else "609989")

func _legacy_shell_unused():
	_style()
	farm_backdrop = load("res://farm.gd").new()
	farm_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	farm_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(farm_backdrop)
	var veil = ColorRect.new()
	veil.color = Color(0.19,0.29,0.13,0.25)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	var top_board = PanelContainer.new()
	root.add_child(top_board)
	var top = HBoxContainer.new()
	top_board.add_child(top)
	var brand = _label(top, "Agent Farmers", 23)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = _label(top, "Starting…", 13)
	status_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_label.custom_minimum_size.x = 180
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(HSeparator.new())
	var content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 26)
	root.add_child(content)
	var nav_board = PanelContainer.new()
	content.add_child(nav_board)
	var nav = VBoxContainer.new()
	nav.custom_minimum_size.x = 160
	nav.add_theme_constant_override("separation", 10)
	nav_board.add_child(nav)
	for label in ["Farm", "Projects", "Workers", "Connections", "Results", "Memory", "Overview"]:
		var button = _button(nav, "Getting started" if label == "Overview" else "Outputs" if label == "Results" else label, func(): view = label; _render())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		navigation[label] = button
	_label(nav, "THE HOMESTEAD\nLocal-first workspace", 12)
	var workbench = PanelContainer.new()
	workbench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workbench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workbench)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workbench.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	root.add_child(HSeparator.new())
	var footer_board = PanelContainer.new()
	root.add_child(footer_board)
	notice_label = _label(footer_board, "Projects and history are stored locally. Work requires your approval.", 13)
	_render()

func _notice(message: String):
	if is_instance_valid(notice_label): notice_label.text = message

func _label(parent: Node, text: String, size: int = 16) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _primary(button: Button) -> Button:
	button.theme_type_variation = "Primary"
	return button

func _actions(parent: Node) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row

func _readable(parent: Node, text: String) -> RichTextLabel:
	var reader = RichTextLabel.new()
	reader.text = text
	reader.add_theme_color_override("default_color", Color("2e372d"))
	reader.bbcode_enabled = false
	reader.selection_enabled = true
	reader.fit_content = true
	reader.scroll_active = false
	reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(reader)
	return reader

func _line(parent: Node, title: String, text: String = "", hint: String = "") -> LineEdit:
	_label(parent, title, 14)
	var field = LineEdit.new()
	field.text = text
	field.placeholder_text = hint
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _text(parent: Node, title: String, text: String = "", height: int = 120) -> TextEdit:
	_label(parent, title, 14)
	var field = TextEdit.new()
	field.text = text
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.custom_minimum_size.y = height
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _options(parent: Node, title: String, values: Array, current: String = "", empty: bool = false) -> OptionButton:
	_label(parent, title, 14)
	var picker = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(picker)
	if empty:
		picker.add_item("None")
		picker.set_item_metadata(0, "")
	for value in values:
		picker.add_item(str(value.get("name", value.get("title", value.get("id", "")))))
		var i = picker.item_count - 1
		picker.set_item_metadata(i, str(value.id))
		if str(value.id) == current: picker.select(i)
	return picker

func _choice(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""

func _clear():
	live_label = null
	transcript = null
	transcript_key = ""
	for node in game_shell.footer.get_children():
		game_shell.footer.remove_child(node)
		node.queue_free()
	progress_label = null
	for node in page.get_children():
		page.remove_child(node)
		node.queue_free()

func _render():
	_clear()
	if view != "Farm" and notice_label.text.begins_with("Scroll to zoom"): notice_label.text = ""
	game_shell.guided = view in ["Projects","Project","Delivery","Preview"]
	game_shell.show_view(view)
	_farm_dispatch()
	for key in navigation:
		var selected = key == view or (view == "Project" and key == "Projects")
		navigation[key].button_pressed = selected
		navigation[key].theme_type_variation = "NavSelected" if selected else "Nav"
	match view:
		"Preview": _preview_screen()
		"Delivery": _delivery_notice()
		"Farm": _farm()
		"Overview": _overview()
		"Workers": _workers()
		"Connections": _connections()
		"Projects": _projects()
		"Project": _project()
		"Results": _results()
		"Memory": _memory()

func _farm():
	_notice("Scroll to zoom    ·    Right-drag to pan    ·    F11 fullscreen")

func _menu_card(parent: Control, icon_route: String, heading: String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",Arcade.box("fffdf6","42577b","adb8cb","ffffff"))
	parent.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation",8)
	panel.add_child(content)
	var row = _actions(content)
	var icon = TextureRect.new()
	icon.texture = game_shell.buttons[icon_route].icon
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	_label(row,heading,22)
	return content

func _overview():
	for chapter in [
		["Connections","Connect your tools","Sign in to the runtime you want your crew to use.","Open accounts"],
		["Workers","Meet your crew","Give each worker a connection, a role and the skills their tasks need.","Set up crew"],
		["Projects","Take an idea to the planning table","Choose a planner, assign each task, then review permissions before starting work.","Meet Rowan"],
		["Results","Collect the crew’s work","Read worker reports, preview delivered files and ask follow-up questions.","View outputs"]
	]:
		var card = _menu_card(page,chapter[0],chapter[1])
		_label(card,chapter[2],17)
		_button(card,chapter[3],func(): game_shell.navigate.emit(chapter[0]))

func _memory():
	var vault = _menu_card(page,"Memory","Project memory vault")
	_label(vault,"Save a completed project’s brief and results as a Markdown note. You choose which projects to archive.",18)
	var location = _readable(vault,str(snapshot.get("vault","")))
	location.tooltip_text = "Open this folder as a vault in Obsidian."
	_label(vault,"Open this folder in Obsidian to read your notes.",16)
	for project in snapshot.projects:
		if project.status!="completed": continue
		var id = str(project.id)
		var card = _menu_card(page,"Results",str(project.title))
		_button(card,"Open journal files",func(): _open_dialogue(id,true))

func _connections():
	var grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	var heading = _actions(page)
	var title = _label(heading,"Agent connections",32)
	var refresh = _button(heading,"Refresh",func(): _command("refresh",{}))
	var intro = _label(page,"Verify sends a small test request using your account allowance.",18)
	page.add_child(grid)
	var fonts = {title:32,refresh:18,intro:18}
	var order = ["codex","antigravity","claude","opencode"]
	var connections = snapshot.connections.duplicate()
	connections.sort_custom(func(a,b): return order.find(str(a.id))<order.find(str(b.id)))
	if connections.is_empty(): _label(page,"Checking available connections…",19)
	for connection in connections:
		var id = str(connection.id)
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card = Arcade.box("fffdf6","42577b","adb8cb","ffffff")
		card.content_margin_left = 18
		card.content_margin_right = 18
		card.content_margin_top = 15
		card.content_margin_bottom = 15
		panel.add_theme_stylebox_override("panel",card)
		grid.add_child(panel)
		var body = VBoxContainer.new()
		body.add_theme_constant_override("separation",12)
		panel.add_child(body)
		var row = _actions(body)
		row.add_theme_constant_override("separation",12)
		var badge = Label.new()
		badge.text = {"codex":"CX","antigravity":"AG","claude":"CL","opencode":"OC"}.get(id,str(connection.name).left(2).to_upper())
		badge.add_theme_font_override("font",game_shell.block_font)
		badge.add_theme_font_size_override("font_size",20)
		badge.add_theme_color_override("font_color",Color("fff9df"))
		var color = {"codex":"37675e","antigravity":"63587b","claude":"945c41","opencode":"45667a"}.get(id,"395a60")
		badge.add_theme_stylebox_override("normal",Arcade.box(color,"192c4a","273858",Color(color).lightened(0.4).to_html(false)))
		row.add_child(badge)
		var name_label = _label(row,str(connection.name),25)
		fonts[name_label]=25
		var status = Label.new()
		status.text = str(connection.auth)
		status.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		var ready = status.text in ["Signed in","Session verified"]
		var status_style = _farm_box("e0efdb" if ready else "f0eadd","c5d8bb" if ready else "d6ccba",2)
		status_style.content_margin_top = 3
		status_style.content_margin_bottom = 3
		status_style.content_margin_left = 9
		status_style.content_margin_right = 9
		status.add_theme_stylebox_override("normal",status_style)
		body.add_child(status)
		fonts[status]=18
		var metadata = PackedStringArray()
		for key in ["version","environment"]:
			var value = str(connection.get(key,""))
			if value not in ["","Unknown"]: metadata.append(value)
		metadata.append("%d models reported"%connection.get("models",[]).size())
		var specs = _label(body,"  ·  ".join(metadata),18)
		fonts[specs]=18
		var actions = HFlowContainer.new()
		actions.add_theme_constant_override("h_separation",8)
		body.add_child(actions)
		if connection.get("installed",false):
			var login = _button(actions,"Sign in",func(): _command("connection.login",{"id":id}))
			var verify = _primary(_button(actions,"Verify",func(): _command("connection.verify",{"id":id})))
			verify.disabled = snapshot.get("busy",false)
			fonts[login]=18
			fonts[verify]=18
		var toggle = Button.new()
		toggle.text = "Details"
		actions.add_child(toggle)
		toggle.toggle_mode = true
		toggle.button_pressed = expanded_accounts.get(id,false)
		fonts[toggle]=18
		var details = VBoxContainer.new()
		details.add_theme_constant_override("separation",8)
		body.add_child(details)
		var note = str(connection.get("note",""))
		if not note.is_empty():
			var note_label = _label(details if connection.get("installed",false) else body,note,18)
			fonts[note_label]=18
		var caps = connection.get("capabilities",{})
		var capabilities = _label(details,"Files: %s\nWeb: %s\nImages: %s\nSubscription allowance: Unknown"%[caps.get("files","Unknown"),caps.get("web","Unknown"),caps.get("images","Unknown")],18)
		fonts[capabilities]=18
		details.visible = toggle.button_pressed
		toggle.toggled.connect(func(open):
			expanded_accounts[id]=open
			details.visible=open)
	var fit = func():
		var wide = grid.size.x>=1060
		grid.columns = 2 if wide else 1
		for control in fonts:
			var desired = int(fonts[control]) + (2 if wide else 0)
			if control.get_theme_font_size("font_size")!=desired:
				control.add_theme_font_size_override("font_size",desired)
	grid.resized.connect(fit)
	fit.call()

func _workers():
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",20)
	page.add_child(columns)
	var rail = PanelContainer.new()
	rail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rail.custom_minimum_size.x = 205
	rail.add_theme_stylebox_override("panel",Arcade.box("284575","142846","142e58","5877a8"))
	columns.add_child(rail)
	var roster = VBoxContainer.new()
	roster.add_theme_constant_override("separation",7)
	rail.add_child(roster)
	var roster_title = _label(roster,"ROSTER",20)
	roster_title.add_theme_font_override("font",game_shell.block_font)
	roster_title.add_theme_color_override("font_color",Color("fff9ef"))
	var add_worker = _button(roster,"+ New worker",func(): selected_worker=""; _render())
	add_worker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Arcade.button(add_worker,"ffcf32","c78c12")
	var worker = {}
	for slot in snapshot.workers.size():
		var member = snapshot.workers[slot]
		var id = str(member.id)
		var pick = _button(roster,str(member.name),func(): selected_worker=id; _render())
		var palette = {"t":farm_backdrop.SHIRTS[slot%farm_backdrop.SHIRTS.size()],"w":farm_backdrop.SKINS[slot%farm_backdrop.SKINS.size()]}
		if slot%2==1: palette.merge({"y":"d87578","o":"af4d60"})
		pick.icon = game_shell.Icons.texture("Workers",palette)
		pick.add_theme_constant_override("icon_max_width",24)
		pick.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pick.tooltip_text = str(member.name)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Arcade.button(pick,"ffd045" if id==selected_worker else "edecf3","c38c22" if id==selected_worker else "9ba9c8")
		if id==selected_worker: worker=member
	var form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation",4)
	columns.add_child(form)
	var name_field = _line(form, "Name", worker.get("name", ""), "e.g. Research lead")
	var connections = []
	for c in snapshot.connections: connections.append({"id": c.id, "name": c.name})
	var connection_picker = _options(form, "Connection", connections, worker.get("provider", "codex"))
	var models = _actions(form)
	var model_cells = []
	for i in range(2):
		var cell = VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		models.add_child(cell)
		model_cells.append(cell)
	var model_picker = _options(model_cells[0],"Discovered models",[])
	model_picker.fit_to_longest_item = false
	var model_field = _line(model_cells[1],"Model ID",worker.get("model",""),"Runtime default")
	var fill_models = func():
		model_picker.clear()
		model_picker.add_item("Runtime default")
		model_picker.set_item_metadata(0, "")
		for c in snapshot.connections:
			if str(c.id) == _choice(connection_picker):
				for model in c.get("models", []):
					model_picker.add_item(str(model))
					model_picker.set_item_metadata(model_picker.item_count - 1, str(model))
					if str(model) == model_field.text: model_picker.select(model_picker.item_count - 1)
	fill_models.call()
	connection_picker.item_selected.connect(func(_i): model_field.text = ""; fill_models.call())
	model_picker.item_selected.connect(func(_i): model_field.text = _choice(model_picker))
	var role_field = _text(form, "Role and responsibility", worker.get("role", ""), 82)
	_label(form, "Skills · reusable instructions, not installed tools", 19)
	var skills_box = VBoxContainer.new()
	skills_box.add_theme_constant_override("separation", 8)
	form.add_child(skills_box)
	var skill_rows = []
	var add_skill = func(skill):
		var box = VBoxContainer.new()
		skills_box.add_child(box)
		var enabled = CheckBox.new()
		enabled.text = "Enabled"
		enabled.button_pressed = skill.get("enabled", true)
		box.add_child(enabled)
		var skill_name = _line(box, "Skill name", skill.get("name", ""))
		var instructions = _text(box, "Instructions", skill.get("instructions", ""), 85)
		var entry = {"box": box, "name": skill_name, "instructions": instructions, "enabled": enabled}
		skill_rows.append(entry)
		_button(box, "Remove skill", func(): skill_rows.erase(entry); box.queue_free())
	for skill in worker.get("skills", []): add_skill.call(skill)
	var add_skill_button = _button(form, "+ Add skill", func(): add_skill.call({}))
	Arcade.button(add_skill_button,"92d656","4a842e")
	var worker_id = selected_worker
	var save_row = _actions(game_shell.footer)
	save_row.alignment = BoxContainer.ALIGNMENT_END
	var save_worker = _button(save_row, "Save worker", func():
		var skills = []
		for entry in skill_rows:
			skills.append({"name": entry.name.text, "instructions": entry.instructions.text, "enabled": entry.enabled.button_pressed})
		_command("worker.save", {"id": worker_id, "name": name_field.text, "provider": _choice(connection_picker), "model": model_field.text, "role": role_field.text, "skills": skills}, func(saved):
			selected_worker = str(saved.id)
			if worker_id.is_empty(): new_farm_worker = selected_worker
			if return_from_hiring:
				return_from_hiring = false
				guide_planner = selected_worker
				view = "Projects"
				guide_step = "confirm"
			_notice("Worker saved."))
	)
	save_worker.icon = game_shell.Icons.texture("Save")
	save_worker.add_theme_constant_override("icon_max_width",24)
	save_worker.custom_minimum_size.x=156
	Arcade.button(save_worker,"ffce27","c58915")
	for label in form.find_children("*","Label",true,false):
		if label.get_theme_font_size("font_size")<17: label.add_theme_font_size_override("font_size",17)
	for field in [name_field,model_field,role_field]:
		field.add_theme_font_size_override("font_size",17)
		field.add_theme_stylebox_override("normal",Arcade.box("f9faff","607593","bdc8d9","ffffff"))
		field.add_theme_stylebox_override("focus",Arcade.box("ffffff","2873c0","83aada","e1edff"))
	for picker in [connection_picker,model_picker]:
		Arcade.button(picker,"c2e4f4","7ea4bf")

func _say(who: String, words: String, worker_id: String="", report: bool=false):
	game_shell.title.text = who
	var slot = 0
	for i in snapshot.workers.size():
		if str(snapshot.workers[i].id)==worker_id: slot=i; break
	game_shell.speaker(slot)
	if report: _report_text(page,words)
	else: _label(page,words,20)

func _report_text(parent: Node, words: String):
	var report = preload("res://report_text.gd").new()
	parent.add_child(report)
	report.display(words)

func _step(next: String):
	guide_step = next
	_render()
	game_shell.scroll.scroll_vertical = 0

func _projects():
	match guide_step:
		"welcome":
			_say("Rowan · Farm steward","Welcome to the planning table. I’m Rowan. Shall we start something with your crew?")
			var choices = _actions(game_shell.footer)
			_primary(_button(choices,"Start a project",func(): _step("idea")))
			if not snapshot.projects.is_empty(): _button(choices,"Visit a project",func(): _step("list"))
		"list":
			_say("Rowan · Farm steward","Which project shall we check on?")
			for project in snapshot.projects:
				var id = str(project.id)
				var choice = _button(page,str(project.title),func(): _open_dialogue(id))
				choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				choice.tooltip_text = str(project.title)
		"idea":
			_say("Rowan · Farm steward","What would you like the crew to make or find out?")
			var idea = TextEdit.new()
			idea.placeholder_text = "Tell Rowan your idea…"
			idea.custom_minimum_size.y = 65
			idea.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			idea.text = guide_idea
			page.add_child(idea)
			var next = _primary(_button(game_shell.footer,"Choose my planner →",func(): _step("planner")))
			next.disabled = idea.text.strip_edges().is_empty()
			idea.text_changed.connect(func(): guide_idea = idea.text; next.disabled = idea.text.strip_edges().is_empty())
			idea.grab_focus.call_deferred()
		"planner":
			_say("Rowan · Farm steward","Who should plan this with you?" if not snapshot.workers.is_empty() else "A planner turns your idea into a proposal. Let’s add your first crew member. I’ll keep your idea here.")
			if snapshot.workers.is_empty():
				_primary(_button(page,"Add my first crew member",func():
					return_from_hiring = true
					selected_worker = ""
					view = "Workers"
					_render()))
			for w in snapshot.workers:
				var id = str(w.id)
				_button(page,str(w.name),func(): guide_planner = id; _step("confirm"))
			_button(page,"Back to my idea",func(): _step("idea"))
		"confirm":
			var name = _worker_name(guide_planner)
			_say(name,"I’ll read your idea and bring back a proposal. You’ll get to review it before the crew starts.",guide_planner)
			var summary = _label(page,guide_idea,15)
			summary.max_lines_visible = 2
			summary.tooltip_text = guide_idea
			var row = _actions(game_shell.footer)
			var begin = _primary(_button(row,"Ask for a proposal",_create_from_guide))
			begin.disabled = guide_pending or snapshot.get("busy",false)
			_button(row,"Edit idea",func(): _step("idea"))
			_button(row,"Change planner",func(): _step("planner"))
			var options = _fold(page,"Project folder")
			var path = _line(options,"Leave blank for a new project folder",guide_folder)
			path.text_changed.connect(func(value): guide_folder=value)
			_button(options,"Browse…",func():
				var picker = FileDialog.new()
				picker.use_native_dialog = true
				picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
				picker.access = FileDialog.ACCESS_FILESYSTEM
				add_child(picker)
				picker.dir_selected.connect(func(value): guide_folder=value; path.text=value; picker.queue_free())
				picker.canceled.connect(picker.queue_free)
				picker.popup_centered_ratio(0.7))

func _create_from_guide():
	if guide_pending: return
	guide_pending = true
	_api("/v1/command",HTTPClient.METHOD_POST,{"action":"project.create","payload":{"idea":guide_idea,"plannerId":guide_planner,"folder":guide_folder}},func(value):
		selected_project = str(value.result.id)
		guide_idea = ""
		guide_folder = ""
		guide_step = "welcome"
		view = "Project"
		detail = {}
		guide_pending = false
		_send_to_farm("project.discuss",{"id":selected_project,"initial":true})
		_render(),_guide_failed)

func _guide_failed():
	guide_pending = false
	_reload(true)

func _send_to_farm(action: String, payload: Dictionary):
	if guide_pending: return
	guide_pending = true
	_api("/v1/command",HTTPClient.METHOD_POST,{"action":action,"payload":payload},func(_value):
		guide_pending = false
		tracked_project = str(payload.id)
		_begin_handoffs(action,tracked_project)
		chat_drafts.erase(tracked_project)
		journal_open = false
		reply_mode = false
		report_index = -1
		view = "Farm"
		_render()
		_reload(true),_guide_failed)

func _begin_handoffs(action: String, id: String):
	var seen = {}
	var report_offset = 0
	if detail.get("project",{}).get("id","")==id:
		for attempt in detail.get("attempts",[]):
			seen[attempt.id]=true
			if attempt.stage!="planning" and not str(attempt.get("summary","")).is_empty(): report_offset+=1
	farm_run={"id":id,"planning":action=="project.discuss","seen":seen,"lines":[],"poll":0.0,"reading":0.0,"pending":false,"done":{},"offset":report_offset,"last_worker":"","last_report":""}
	delivery={}
	game_shell.speech.hide()
	if action=="project.start" and detail.get("plan") is Dictionary:
		var first = detail.plan.tasks[0]
		var planner = str(detail.project.plannerId)
		var handoff = "I’ll take the first task." if planner==str(first.workerId) else _worker_name(str(first.workerId))+", the first task is yours."
		farm_run.lines.append([planner,_worker_name(planner),handoff])

func _tick_handoffs(delta: float):
	if farm_run.is_empty(): return
	var run = farm_run
	run.poll-=delta
	if run.done.is_empty() and not run.pending and run.poll<=0:
		run.pending=true
		run.poll=1.2
		_api("/v1/projects/"+str(run.id),HTTPClient.METHOD_GET,{},func(value):
			run.pending=false
			if is_same(run,farm_run): _collect_handoffs(run,value),func(): run.pending=false)
	if view!="Farm": return
	run.reading=maxf(0,run.reading-delta)
	if run.reading>0: return
	if not run.lines.is_empty():
		var line = run.lines.pop_front()
		game_shell.farm_line(line[0],line[1]+"\n"+line[2])
		run.reading = clampf(line[2].length()/20.0,2.2,4.8)
		return
	game_shell.speech.hide()
	if run.done.is_empty(): return
	detail=run.done
	selected_project=run.id
	journal_open=false
	reply_mode=false
	report_index=-1
	review.clear()
	farm_run={}
	if run.planning:
		view="Project"
		if detail.project.status=="awaiting_approval" and detail.get("plan") is Dictionary:
			_begin_assignment_review()
	else:
		delivery={"id":run.id,"status":detail.project.status,"offset":run.offset}
		view="Delivery"
	_render()

func _collect_handoffs(run: Dictionary, value: Dictionary):
	if not run.planning:
		for attempt in value.get("attempts",[]):
			if run.seen.has(attempt.id): continue
			run.seen[attempt.id]=true
			var words = "I’m on it."
			match str(attempt.stage):
				"planning": continue
				"review":
					words="I’ll check the work against the approved plan."
					if run.last_worker!="": words="Thanks, "+str(run.last_worker)+". I’ll check the work against the plan."
				"correction": words="I’ll make the changes requested in review."
				_:
					for task in value.plan.tasks:
						if task.id==attempt.stage:
							var job = str(task.instructions).strip_edges().replace("\n"," ")
							words="My task: "+job.left(110)+("…" if job.length()>110 else "")
							break
			if attempt.stage!="review": run.last_worker=attempt.workerName
			run.last_report=attempt.id
			run.lines.append([str(attempt.workerId),str(attempt.workerName),words])
	if value.project.status not in ["planning","queued","running","reviewing"]:
		run.done=value
		if not run.planning and value.project.status=="completed":
			for attempt in value.attempts:
				if attempt.id!=run.last_report: continue
				var result = str(attempt.get("summary","")).strip_edges().replace("\n"," ")
				if not result.is_empty():
					run.lines.append([str(attempt.workerId),str(attempt.workerName),result.left(125)+("…" if result.length()>125 else "")])

func _delivery_notice():
	var completed = delivery.status=="completed"
	_say("Rowan · Farm steward","The crew’s report is ready. Would you like to hear what they found?" if completed else "The crew stopped before finishing. Let’s look at their update.")
	_label(page,str(detail.project.title),17)
	var choices = _actions(game_shell.footer)
	_primary(_button(choices,"Open report" if completed else "Read update",func():
		report_index=int(delivery.offset)
		view="Project"
		_render()))
	_button(choices,"Later",func(): view="Farm"; _render())


func _farm_dispatch():
	var button = game_shell.dispatch
	button.hide()
	game_shell.hint.visible = view=="Farm"
	if view!="Farm": return
	var active = snapshot.get("activeWorker")
	var id = str(active.projectId) if active is Dictionary else tracked_project
	for project in snapshot.projects:
		if str(project.id)!=id: continue
		var label = "Read crew update"
		match str(project.status):
			"queued","running","reviewing","planning":
				label = str(active.worker)+" · "+str({"planning":"Planning","review":"Reviewing"}.get(active.stage,"Working")) if active is Dictionary else "Crew starting"
			"completed": label = "Collect the crew’s report"
			"awaiting_approval","ready": label = "Meet your planner"
		button.text = label+"  →"
		button.set_meta("project_id",id)
		button.reset_size()
		button.visible = true
		game_shell.hint.hide()
		game_shell.arrange()
		break

func _open_dialogue(id: String, open_files: bool=false):
	if id.is_empty(): return
	selected_project = id
	review.clear()
	detail = {}
	journal_open = open_files
	if open_files: journal_section="Files"
	reply_mode = false
	report_index = -1
	view = "Project"
	_render()
	_reload(true)

func _project():
	if detail.is_empty() or str(detail.project.id)!=selected_project:
		_label(page,"Finding your planner…")
		return
	if journal_open:
		_journal()
		return
	var project = detail.project
	var id = str(project.id)
	var planner = str(project.plannerId)
	var speaker = _worker_name(planner)
	var active = project.status in ["planning","queued","running","reviewing"]
	if active:
		_say(speaker,str(project.activity),planner)
		progress_label = _label(page,"",14)
		_update_progress()
		var actions = _actions(game_shell.footer)
		_primary(_button(actions,"Back to farm",func(): tracked_project=id; view="Farm"; _render()))
		_button(actions,"Stop work",func(): _command("stop",{}))
		return
	if not review.is_empty():
		if detail.get("plan") is Dictionary and review.plan_id==detail.plan.id and project.status in ["awaiting_approval","ready"]:
			_review_turn(detail.plan,project)
			return
		review.clear()
	if reply_mode:
		_say(speaker,"What would you like to ask or change?",planner)
		var msg = _text(page,"Your reply",chat_drafts.get(id,""),62)
		var row = _actions(game_shell.footer)
		var submit = _primary(_button(row,"Send to planner",func(): _send_to_farm("project.discuss",{"id":id,"message":msg.text})))
		submit.disabled = msg.text.strip_edges().is_empty() or snapshot.get("busy",false)
		msg.text_changed.connect(func(): chat_drafts[id]=msg.text; submit.disabled=msg.text.strip_edges().is_empty() or snapshot.get("busy",false))
		_button(row,"Back",func(): reply_mode=false; _render())
		return
	var reports = []
	for attempt in detail.get("attempts",[]):
		if attempt.stage!="planning" and not str(attempt.get("summary","")).is_empty(): reports.append(attempt)
	var recent = project.conversation.back() if not project.conversation.is_empty() else {}
	var fresh_reply = recent.get("role","")=="assistant" and (reports.is_empty() or str(recent.get("at",""))>str(reports.back().get("finishedAt","")))
	var choices = _actions(game_shell.footer)
	if not reports.is_empty() and (report_index>=0 or (not fresh_reply and project.status in ["completed","blocked","needs_input","failed","cancelled","interrupted"])):
		report_index = clampi(report_index,0,reports.size()-1)
		var report = reports[report_index]
		_say(str(report.workerName),str(report.summary),str(report.workerId),true)
		for file in detail.get("artifacts",[]):
			if file.get("attemptId")==report.id:
				var fid = str(file.id)
				_button(page,"Preview "+str(file.relative),func(): _preview(fid))
		if report_index+1<reports.size():
			_primary(_button(choices,"Hear the next report →",func(): report_index+=1; _render()))
	else:
		var words = str(recent.get("text","")) if recent.get("role","") in ["assistant","system"] else "I have your idea. Shall I draw up a proposal?"
		if project.status=="ready": words="Your plan is approved. Shall I send the crew to work?"
		elif project.status=="awaiting_approval" and recent.get("role","")!="assistant": words="Your proposal is ready. Choose who will carry out each task, then we’ll review access."
		_say(speaker,words,planner,recent.get("role","")=="assistant")
	if project.status=="draft" and project.conversation.size()==1:
		_primary(_button(choices,"Ask for a proposal",func(): _send_to_farm("project.discuss",{"id":id,"initial":true}))).disabled = snapshot.get("busy",false)
	elif project.status=="ready":
		_primary(_button(choices,"Start approved work",func(): _send_to_farm("project.start",{"id":id,"approvalId":project.approvalId})))
	if project.status in ["awaiting_approval","ready"]:
		var assign = _button(choices,"Choose task workers" if project.status=="awaiting_approval" else "Change assignments",func():
			_begin_assignment_review()
			_render())
		if project.status=="awaiting_approval": _primary(assign)
	_button(choices,"Reply",func(): reply_mode=true; _render())
	_button(choices,"Project journal",func(): journal_open=true; _journal_turn("Contents"))

func _begin_assignment_review():
	var policy = detail.approval.payload if detail.get("approval") is Dictionary else {}
	review={"plan_id":detail.plan.id,"turn":0,"assignments":{},"write":policy.get("write",false),"web":policy.get("web",false),"reviewer":policy.get("reviewerId","")}

func _review_turn(plan: Dictionary, project: Dictionary):
	var tasks = plan.tasks
	var turn = int(review.turn)
	var planner = str(project.plannerId)
	var who = _worker_name(planner)
	var worker_picker: OptionButton
	if turn<tasks.size():
		var task = tasks[turn]
		_say(who,"Who should do task %d of %d?"%[turn+1,tasks.size()],planner)
		_readable(page,str(task.instructions))
		if not task.get("outputs",[]).is_empty(): _label(page,"Files: "+", ".join(task.outputs),14)
		if task.get("acceptance","")!="": _label(page,"We’ll check: "+str(task.acceptance),14)
		worker_picker = _options(page,"Task worker",snapshot.workers,review.assignments.get(task.id,""),true)
		worker_picker.set_item_text(0,"Choose a crew member…")
		worker_picker.set_item_disabled(0,true)
		if snapshot.workers.size()==1: _label(page,"Your planner can also do this task. Select them to assign it.",14)
	elif turn==tasks.size():
		_say(who,"What access may the crew use for this plan?",planner)
		for choice in [["write","Allow edits in the project folder"],["web","Allow web research for Codex workers"]]:
			var key = choice[0]
			var box = CheckBox.new()
			box.text = choice[1]
			box.button_pressed = review[key]
			page.add_child(box)
			box.toggled.connect(func(value): review[key]=value)
	elif turn==tasks.size()+1:
		_say(who,"Would you like a second crew member to review the work?",planner)
		var assigned = []
		for task in tasks: assigned.append(str(review.assignments[task.id]))
		var eligible = []
		for w in snapshot.workers:
			if str(w.id) not in assigned: eligible.append(w)
		if review.reviewer in assigned: review.reviewer=""
		var picker = _options(page,"Independent reviewer",eligible,review.reviewer,true)
		picker.item_selected.connect(func(_index): review.reviewer=_choice(picker))
	else:
		_say(who,"Ready to send the crew? Approving starts this version with the assignments and access below.",planner)
		_label(page,str(plan.brief),16)
		_label(page,"Planner · "+who,15)
		for i in tasks.size():
			_label(page,"Task %d · %s"%[i+1,_worker_name(str(tasks[i].workerId))],15)
		_label(page,"Version %d · %d tasks · File edits %s · Web %s · Reviewer: %s"%[int(plan.revision),tasks.size(),"on" if review.write else "off","on" if review.web else "off",_worker_name(review.reviewer) if review.reviewer!="" else "None"],14)
	var row = _actions(game_shell.footer)
	if turn<tasks.size():
		var task_id = tasks[turn].id
		var next = _primary(_button(row,"Next →",func():
			if guide_pending or _choice(worker_picker).is_empty(): return
			if turn==tasks.size()-1: _save_assignments(plan,project)
			else: review.turn+=1; _render()))
		next.disabled = _choice(worker_picker).is_empty() or guide_pending
		worker_picker.item_selected.connect(func(_index):
			review.assignments[task_id] = _choice(worker_picker)
			next.disabled = false)
	elif turn<tasks.size()+2:
		_primary(_button(row,"Next →",func(): review.turn+=1; _render()))
	else:
		var approve = _primary(_button(row,"Approve & start work",func():
			if guide_pending: return
			guide_pending=true
			_api("/v1/command",HTTPClient.METHOD_POST,{"action":"plan.approve","payload":{"id":project.id,"planId":review.plan_id,"write":review.write,"web":review.web,"reviewerId":review.reviewer}},func(value):
				guide_pending=false
				review.clear()
				_send_to_farm("project.start",{"id":project.id,"approvalId":value.result.id}),_guide_failed)))
		approve.disabled=snapshot.get("busy",false)
	_button(row,"Back",func():
		if turn==0: review.clear()
		else: review.turn-=1
		_render())
	_button(row,"Ask for a change",func(): review.clear(); reply_mode=true; _render())
	game_shell.scroll.scroll_vertical=0

func _save_assignments(plan: Dictionary, project: Dictionary):
	var tasks = plan.tasks.duplicate(true)
	var changed = false
	for task in tasks:
		var chosen = review.assignments.get(task.id,"")
		if chosen=="": return
		if chosen!=task.workerId: changed=true
		task.workerId=chosen
	if not changed:
		review.turn=tasks.size()
		_render()
		return
	guide_pending=true
	var payload = {"id":project.id,"basePlanId":plan.id,"brief":plan.brief,"tasks":tasks}
	_api("/v1/command",HTTPClient.METHOD_POST,{"action":"plan.save","payload":payload},func(value):
		guide_pending=false
		if not review.is_empty() and review.plan_id==plan.id and selected_project==project.id:
			review.plan_id=value.result.id
			review.turn=tasks.size()
		_reload(true),_guide_failed)

func _journal():
	if detail.is_empty():
		_label(page, "Loading project…")
		return
	var project = detail.project
	plan_dirty = false
	approval_settings_dirty = false
	approve_button = null
	start_button = null
	approval_hint = null
	reviewer_picker = null
	save_near_approval = null
	var id = str(project.id)
	var planner = str(project.plannerId)
	var who = _worker_name(planner)
	game_shell.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var choices = HFlowContainer.new()
	choices.add_theme_constant_override("h_separation",8)
	game_shell.footer.add_child(choices)
	if journal_section=="Contents":
		_say(who,"Here’s your project journal. What would you like to look at?",planner)
		_readable(page,str(project.title))
		live_label = _label(page,_status_summary(),15)
		for section in ["Conversation","Plan","Files","Activity"]:
			var button = _button(page,section,func(): _journal_turn(section))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(choices,"Back to dialogue",func(): journal_open=false; _render())
	else:
		_say(who,{"Conversation":"Here’s the conversation so far.","Plan":"Let’s review the tasks and the access your crew needs.","Files":"Here’s what your crew has delivered.","Activity":"Here’s the work history for this project."}[journal_section],planner)
		_button(choices,"← Journal",func(): _journal_turn("Contents"))
	progress_label = _label(page,"",14)
	_update_progress()
	if project.status in ["planning","running","reviewing","queued"]: _button(choices,"Stop work",func(): _command("stop",{}))
	match journal_section:
		"Conversation":
			transcript = VBoxContainer.new()
			transcript.add_theme_constant_override("separation",10)
			page.add_child(transcript)
			_refresh_transcript()
			_primary(_button(choices,"Reply",func(): journal_open=false; reply_mode=true; _render()))
		"Plan":
			_journal_plan(project)
		"Files":
			if detail.get("artifacts",[]).is_empty(): _label(page,"Delivered files will appear here.",15)
			for file in detail.get("artifacts",[]):
				var fid = str(file.id)
				_label(page,str(file.relative),16)
				var row = _actions(page)
				_button(row,"Preview",func(): _preview(fid))
				_button(row,"Open file",func(): _command("open.artifact",{"id":fid}))
			_button(choices,"Open workspace",func(): _command("open.folder",{"id":id}))
			if project.status=="completed":
				_button(choices,"Save memory note",func(): _command("memory.save",{"id":id},func(saved): _notice("Saved to "+str(saved.path))))
		"Activity":
			_journal_activity()

func _journal_turn(section: String):
	journal_section = section
	_render()

func _journal_plan(project: Dictionary):
	var id = str(project.id)
	var review_box = page
	var plan_box = _fold(review_box,"Edit tasks and assignments")
	var approval_box = review_box
	var plan = detail.get("plan", {})
	if not plan is Dictionary: plan = {}
	if not plan.is_empty():
		_label(review_box,str(plan.get("brief","")),16)
		for task in plan.get("tasks",[]):
			_label(review_box,_worker_name(str(task.workerId))+" · "+str(task.instructions),15)
			if not task.get("outputs",[]).is_empty(): _label(review_box,"Deliver: "+", ".join(task.outputs),13)
			if task.get("acceptance","")!="": _label(review_box,"Check: "+str(task.acceptance),13)
	var brief = _text(plan_box, "Goal & scope", plan.get("brief", project.brief), 120)
	plan_brief_field = brief
	brief.text_changed.connect(_mark_plan_dirty)
	_label(plan_box, "Saved plan version: " + str(int(plan.get("revision", 0))), 14)
	_label(plan_box, "Tasks · listed in dependency order", 20)
	task_rows = []
	var task_box = VBoxContainer.new()
	task_box.add_theme_constant_override("separation", 12)
	plan_box.add_child(task_box)
	var add_task = func(task):
		var box = VBoxContainer.new()
		task_box.add_child(box)
		var instructions = _text(box, "Task " + str(task_rows.size() + 1), task.get("instructions", ""), 110)
		var worker = _options(box, "Assigned worker", snapshot.workers, task.get("workerId", project.plannerId))
		var outputs = _line(box, "Files to deliver · optional, comma-separated", ", ".join(task.get("outputs", [])), "e.g. report.md")
		var acceptance = _line(box, "How should this be checked?", task.get("acceptance", ""))
		instructions.text_changed.connect(_mark_plan_dirty)
		outputs.text_changed.connect(func(_text): _mark_plan_dirty())
		acceptance.text_changed.connect(func(_text): _mark_plan_dirty())
		worker.item_selected.connect(func(_index): _mark_plan_dirty())
		var entry = {"box": box, "id": task.get("id", "t" + str(Time.get_ticks_usec())), "instructions": instructions, "worker": worker, "outputs": outputs, "acceptance": acceptance}
		task_rows.append(entry)
		_button(box, "Remove task", func(): task_rows.erase(entry); box.queue_free(); _mark_plan_dirty())
	for task in plan.get("tasks", []): add_task.call(task)
	_button(plan_box, "+ Add task", func(): add_task.call({}); _mark_plan_dirty())
	_button(plan_box, "Save new plan version", _save_current_plan)
	_label(approval_box, "Approval freezes this saved plan, its assignments and access settings.", 13)
	var approved = detail.get("approval", {})
	if not approved is Dictionary: approved = {}
	var policy = approved.get("payload", {})
	var write = CheckBox.new()
	write.text = "Allow file edits"
	write.button_pressed = policy.get("write", false)
	approval_box.add_child(write)
	var web = CheckBox.new()
	web.text = "Allow web research"
	web.button_pressed = policy.get("web", false)
	approval_box.add_child(web)
	_label(approval_box, "Web access applies to Codex workers. Other workers use project files.", 12)
	var assigned = []
	for task in plan.get("tasks", []): assigned.append(str(task.workerId))
	var eligible_reviewers = []
	for worker in snapshot.workers:
		if str(worker.id) not in assigned: eligible_reviewers.append(worker)
	var reviewer = _options(approval_box, "Independent reviewer · optional", eligible_reviewers, policy.get("reviewerId", ""), true)
	reviewer_picker = reviewer
	_label(approval_box, "Choose an unassigned worker, or leave None. Review allows one correction at most.", 12)
	approval_hint = _label(approval_box, "", 13)
	save_near_approval = _button(approval_box, "Save edits", _save_current_plan)
	save_near_approval.visible = false
	approve_button = _primary(_button(approval_box, "Approve saved plan", func(): _command("plan.approve", {"id": id, "planId": plan.get("id", ""), "write": write.button_pressed, "web": web.button_pressed, "reviewerId": _choice(reviewer)},func(_saved): journal_open=false)))
	approve_button.disabled = plan.is_empty() or snapshot.get("busy", false)
	if project.get("approvalId") != null and project.status == "ready":
		_label(approval_box, "Approved · ready to start", 15)
		start_button = _primary(_button(approval_box, "Start work", func(): _send_to_farm("project.start", {"id": id, "approvalId": project.approvalId})))
		approve_button.text = "Replace approval"
	var show_assignments = CheckBox.new()
	show_assignments.text = "Worker settings"
	approval_box.add_child(show_assignments)
	var assignments = VBoxContainer.new()
	assignments.visible = false
	approval_box.add_child(assignments)
	show_assignments.toggled.connect(func(enabled): assignments.visible = enabled)
	for worker in snapshot.workers:
		var used = false
		for task in plan.get("tasks", []):
			if str(task.workerId) == str(worker.id): used = true
		if used:
			var enabled = []
			for skill in worker.get("skills", []):
				if skill.get("enabled", true): enabled.append(str(skill.name))
			_label(assignments, str(worker.name) + "\n" + str(worker.provider) + " · " + (str(worker.model) if str(worker.model) != "" else "Runtime default") + "\nRole: " + str(worker.role) + "\nSkills: " + (", ".join(enabled) if not enabled.is_empty() else "None"), 12)
	write.toggled.connect(func(_enabled): _approval_settings_changed())
	web.toggled.connect(func(_enabled): _approval_settings_changed())
	reviewer.item_selected.connect(func(_index): _approval_settings_changed())
	_label(plan_box, "Workspace: " + str(project.folder), 12)
	call_deferred("_mark_plan_dirty")

func _journal_activity():
	var lines = []
	for attempt in detail.get("attempts", []): lines.append(str(attempt.workerName) + " · " + str(attempt.stage) + " · " + str(attempt.status) + "\n" + str(attempt.get("summary", "")))
	for event in detail.get("events", []): lines.append(str(event.at) + " · " + str(event.kind) + "\n" + JSON.stringify(event.data))
	for attempt in detail.get("attempts", []): lines.append("Usage · " + str(attempt.workerName) + " · " + JSON.stringify(attempt.get("usage", "Unknown")))
	var log = _text(page, "Redacted diagnostics · last 100 events", "\n\n".join(lines), 400)
	log.editable = false
func _scroll_to_latest(id: String):
	await get_tree().process_frame
	if view=="Project" and journal_open and journal_section=="Conversation" and selected_project==id:
		game_shell.scroll.scroll_vertical = int(game_shell.scroll.get_v_scroll_bar().max_value)

func _worker_name(id: String) -> String:
	for worker in snapshot.workers:
		if str(worker.id)==id: return str(worker.name)
	return "Planner"

func _fold(parent: Node, caption: String) -> VBoxContainer:
	var content = VBoxContainer.new()
	var toggle = _button(parent,caption+"  ▸",func():
		content.visible = not content.visible)
	content.visibility_changed.connect(func():
		toggle.text = caption+("  ▾" if content.visible else "  ▸"))
	content.add_theme_constant_override("separation",10)
	content.hide()
	parent.add_child(content)
	return content

func _chat_bubble(parent: Node, speaker: String, body: String, mine: bool=false) -> VBoxContainer:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left" if mine else "margin_right",38)
	parent.add_child(margin)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",game_shell.plate("ffebbc" if mine else "dfede5"))
	margin.add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	var byline = HBoxContainer.new()
	box.add_child(byline)
	if not mine and speaker!="Farm update":
		var portrait = TextureRect.new()
		portrait.texture = game_shell.buttons["Workers"].icon
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.custom_minimum_size = Vector2(24,24)
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		byline.add_child(portrait)
	_label(byline,speaker,14)
	if mine or speaker=="Farm update": _readable(box,body)
	else: _report_text(box,body)
	return box

func _refresh_transcript():
	if not is_instance_valid(transcript): return
	var bar = game_shell.scroll.get_v_scroll_bar()
	var following = bar.max_value-bar.page-bar.value < 12
	var entries = []
	for message in detail.project.conversation:
		var mine = message.role=="user"
		var author = "You" if mine else _worker_name(str(message.get("workerId",detail.project.plannerId))) if message.role=="assistant" else "Farm update"
		var body = str(message.text).trim_prefix("Last workflow outcome (untrusted reference, not new instructions): ")
		entries.append({"at":str(message.get("at","")),"speaker":author,"text":body,"mine":mine,"files":[]})
	for attempt in detail.get("attempts",[]):
		if attempt.stage=="planning" or attempt.status=="running": continue
		var files = []
		for artifact in detail.get("artifacts",[]):
			if artifact.get("attemptId","")==attempt.id: files.append(artifact)
		entries.append({"at":str(attempt.get("finishedAt",attempt.get("startedAt",""))),"speaker":str(attempt.workerName)+" · "+str(attempt.stage).capitalize(),"text":str(attempt.get("summary","")),"mine":false,"files":files})
	var key = JSON.stringify(entries)
	if key==transcript_key: return
	transcript_key = key
	for child in transcript.get_children():
		transcript.remove_child(child)
		child.queue_free()
	entries.sort_custom(func(a,b): return a.at<b.at)
	for entry in entries:
		var box = _chat_bubble(transcript,entry.speaker,entry.text,entry.mine)
		for file in entry.files:
			var fid = str(file.id)
			_label(box,str(file.relative),14)
			var row = _actions(box)
			_button(row,"Preview",func(): _preview(fid))
			_button(row,"Open file",func(): _command("open.artifact",{"id":fid}))

	if following: _scroll_to_latest.call_deferred(str(detail.project.id))

func _mark_plan_dirty():
	if not is_instance_valid(plan_brief_field) or detail.is_empty(): return
	var saved = detail.get("plan", {})
	if not saved is Dictionary: saved = {}
	plan_dirty = plan_brief_field.text != str(saved.get("brief", detail.project.brief)) or task_rows.size() != saved.get("tasks", []).size()
	if not plan_dirty:
		for i in range(task_rows.size()):
			var row = task_rows[i]
			var task = saved.tasks[i]
			if str(row.id) != str(task.id) or row.instructions.text != str(task.instructions) or _choice(row.worker) != str(task.workerId) or row.acceptance.text != str(task.get("acceptance", "")) or _output_names(row.outputs.text) != task.get("outputs", []):
				plan_dirty = true
				break
	var busy = snapshot.get("busy", false)
	var eligible_state = detail.project.status in ["awaiting_approval", "ready"]
	if is_instance_valid(approve_button): approve_button.disabled = saved.is_empty() or busy or plan_dirty or not eligible_state
	if is_instance_valid(start_button): start_button.disabled = busy or plan_dirty or approval_settings_dirty
	if is_instance_valid(save_near_approval): save_near_approval.visible = plan_dirty
	if is_instance_valid(approval_hint):
		approval_hint.text = "Unsaved edits: save this version before approval." if plan_dirty else "Wait for current work to finish, or stop it." if busy else "Request or save a plan first." if saved.is_empty() else "Save a new plan version before another approval." if not eligible_state else "Settings changed. Review them, then approve." if approval_settings_dirty else "Saved version " + str(int(saved.get("revision", 0))) + " is ready for your approval."
	if plan_dirty: _notice("Unsaved plan changes. Save a new version before approval or execution.")

func _output_names(text: String) -> Array:
	var outputs = []
	for output in text.split(",", false):
		if output.strip_edges() != "": outputs.append(output.strip_edges())
	return outputs

func _save_current_plan():
	var tasks = []
	var previous = ""
	for row in task_rows:
		tasks.append({"id": row.id, "instructions": row.instructions.text, "workerId": _choice(row.worker), "outputs": _output_names(row.outputs.text), "acceptance": row.acceptance.text, "dependsOn": [previous] if previous != "" else []})
		previous = row.id
	_command("plan.save", {"id": str(detail.project.id), "brief": plan_brief_field.text, "tasks": tasks})

func _approval_settings_changed():
	approval_settings_dirty = true
	_mark_plan_dirty()
	_notice("Permissions or reviewer changed. Approve these settings again before starting.")

func _update_live():
	if is_instance_valid(live_label): live_label.text = _status_summary()
	_refresh_transcript()
	_update_progress()

func _status_summary() -> String:
	var status = str(detail.project.status)
	if status == "awaiting_approval": return "Needs your approval · review the saved plan and access settings."
	if status == "ready": return "Approved · ready to start."
	if status == "completed": return "Work delivered · reply to discuss the results."
	if status in ["cancelled", "interrupted"]: return "Work stopped · previous responses and partial files are preserved."
	if status in ["blocked", "needs_input", "failed"]: return "Needs your attention · " + str(detail.project.get("activity", "See the crew’s reply.")).left(140)
	return status.capitalize() + " · " + str(detail.project.get("activity", "")).left(140)

func _update_progress():
	if not is_instance_valid(progress_label) or detail.is_empty(): return
	var active = detail.get("live")
	progress_label.visible = active is Dictionary or detail.project.status in ["queued", "running", "planning", "reviewing"]
	if not active is Dictionary:
		progress_label.text = "No task is currently running." if detail.project.status not in ["queued", "running", "planning", "reviewing"] else "Waiting for the runtime to start…"
		return
	if Time.get_ticks_msec() - last_core_seen > 6000:
		progress_label.text = "Connection stale · runtime status is unknown. Checking the local core…"
		return
	var elapsed = int(active.get("elapsedSeconds", 0))
	var spinner = ["|", "/", "—", "\\"][int(Time.get_ticks_msec() / 200) % 4]
	var phase = "Runtime process active" if active.get("processRunning", false) else "Starting runtime"
	progress_label.text = spinner + " " + str(active.worker) + " · " + str(active.stage) + " · " + phase + "\nElapsed %02d:%02d · last output %ds ago\n" % [elapsed / 60, elapsed % 60, int(active.get("eventAgeSeconds", 0))] + str(active.get("lastActivity", "Waiting for output"))

func _results():
	if snapshot.projects.is_empty():
		var empty = _menu_card(page,"Results","Crew deliveries")
		_label(empty,"Start a project at the planning table. Your crew’s replies and files will appear here.",18)
		_primary(_button(empty,"Meet Rowan",func(): game_shell.navigate.emit("Projects")))
	for project in snapshot.projects:
		var id = str(project.id)
		var card = _menu_card(page,"Results",str(project.title))
		_label(card,str(project.status).replace("_"," ").capitalize(),17)
		var actions = _actions(card)
		_primary(_button(actions,"Read conversation",func(): _open_dialogue(id)))
		_button(actions,"Journal files",func(): _open_dialogue(id,true))

func _preview(identifier: String):
	preview_serial+=1
	var request_id=preview_serial
	var origin=view
	var project_id=selected_project
	_api("/v1/artifacts/"+identifier+"/preview",HTTPClient.METHOD_GET,{},func(value):
		if request_id!=preview_serial or view!=origin or selected_project!=project_id: return
		var doc={"name":str(value.name),"origin":origin,"scroll":game_shell.scroll.scroll_vertical,"index":0,"mode":"reader"}
		if value.kind=="text":
			doc.text=str(value.text)
			doc.prose=doc.name.get_extension().to_lower() in ["md","txt"]
			if doc.prose and not doc.text.strip_edges().is_empty():
				doc.mode="choose"
		else:
			var image=Image.new()
			var bytes=Marshalls.base64_to_raw(str(value.base64))
			var error=image.load_png_from_buffer(bytes) if value.format=="png" else image.load_webp_from_buffer(bytes) if value.format=="webp" else image.load_jpg_from_buffer(bytes)
			if error!=OK:
				_notice("The image could not be decoded.")
				return
			doc.texture=ImageTexture.create_from_image(image)
		preview_doc=doc
		view="Preview"
		_render())

func _preview_mode(mode: String):
	if voice_enabled: DisplayServer.tts_stop()
	voice_enabled=false
	preview_doc.mode=mode
	if mode=="story" and not preview_doc.has("passages"):
		preview_doc.passages=preload("res://story_pages.gd").passages(preview_doc.text)
	_render()

func _close_preview():
	if voice_enabled: DisplayServer.tts_stop()
	voice_enabled=false
	preview_serial+=1
	view=preview_doc.origin
	var position=int(preview_doc.scroll)
	preview_doc={}
	_render()
	game_shell.scroll.set_deferred("scroll_vertical",position)

func _preview_screen():
	var doc=preview_doc
	var choices=HFlowContainer.new()
	choices.add_theme_constant_override("h_separation",8)
	game_shell.footer.add_child(choices)
	game_shell.portrait.visible=doc.mode in ["choose","story"]
	if doc.mode=="choose":
		_say("Rowan · Farm steward","Shall I walk you through this report, or would you like to read it yourself?")
		_label(page,doc.name,18)
		_primary(_button(choices,"Tell me the story",func(): _preview_mode("story")))
		_button(choices,"Read it myself",func(): _preview_mode("reader"))
	elif doc.mode=="story":
		var passage=doc.passages[doc.index]
		game_shell.speaker(0)
		game_shell.title.text="Rowan · Story time"
		_label(page,"%s   ·   %d / %d"%[doc.name,int(doc.index)+1,doc.passages.size()],15)
		var previous = str(doc.passages[doc.index-1].heading) if doc.index>0 else ""
		var words=preload("res://story_pages.gd").dialogue(passage,doc.index,previous)
		var speech_row=HBoxContainer.new()
		speech_row.add_theme_constant_override("separation",0)
		page.add_child(speech_row)
		var tail=Control.new()
		tail.custom_minimum_size.x=22
		speech_row.add_child(tail)
		tail.draw.connect(func():
			tail.draw_colored_polygon(PackedVector2Array([Vector2(22,30),Vector2(0,39),Vector2(22,55)]),Color("243951"))
			tail.draw_colored_polygon(PackedVector2Array([Vector2(23,33),Vector2(6,40),Vector2(23,51)]),Color("fffdfa")))
		var bubble=PanelContainer.new()
		bubble.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var paper=Arcade.box("fffdfa","243951","aebec9","ffffff",true)
		paper.content_margin_left=22
		paper.content_margin_right=22
		bubble.add_theme_stylebox_override("panel",paper)
		speech_row.add_child(bubble)
		var line=RichTextLabel.new()
		line.text=words
		line.fit_content=true
		line.scroll_active=false
		line.selection_enabled=true
		line.add_theme_font_size_override("normal_font_size",22)
		line.add_theme_color_override("default_color",Color("203c45"))
		line.add_theme_constant_override("line_separation",5)
		bubble.add_child(line)
		game_shell.narrate(line,voice_enabled)
		line.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
				line.visible_characters=-1)
		if doc.index>0: _button(choices,"Previous",func(): _story_step(-1))
		if doc.index+1<doc.passages.size(): _primary(_button(choices,"Continue →",func(): _story_step(1)))
		else: _primary(_button(choices,"Finish",_close_preview))
		var voices=DisplayServer.tts_get_voices()
		if not voices.is_empty():
			var voice_button=_button(choices,"Stop voice" if voice_enabled else "Read aloud",func():
				voice_enabled=not voice_enabled
				DisplayServer.tts_stop()
				_render())
			voice_button.tooltip_text="Use the system reading voice"
			if voice_enabled and not DisplayServer.tts_is_speaking():
				DisplayServer.tts_speak(words,voices[0].id)
		_button(choices,"Read full report",func(): _preview_mode("reader"))
	else:
		game_shell.title.text=doc.name.get_file()
		game_shell.title.tooltip_text=doc.name
		if doc.has("texture"):
			var picture=TextureRect.new()
			picture.texture=doc.texture
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			page.add_child(picture)
			var fit=func(): picture.custom_minimum_size.y=maxf(160,game_shell.scroll.size.y-8)
			game_shell.scroll.resized.connect(fit)
			picture.tree_exiting.connect(func(): game_shell.scroll.resized.disconnect(fit))
			fit.call()
		elif doc.prose and doc.text.length()<=24000 and doc.text.count("\n")<350 and not doc.text.strip_edges().is_empty():
			_report_text(page,doc.text)
		else:
			var raw=TextEdit.new()
			raw.editable=false
			raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
			raw.text=doc.text
			page.add_child(raw)
			var fit=func(): raw.custom_minimum_size.y=maxf(160,game_shell.scroll.size.y-8)
			game_shell.scroll.resized.connect(fit)
			raw.tree_exiting.connect(func(): game_shell.scroll.resized.disconnect(fit))
			fit.call()
		_primary(_button(choices,"Done",_close_preview))
		if doc.get("prose",false) and not str(doc.text).strip_edges().is_empty():
			_button(choices,"Let Rowan tell it",func(): _preview_mode("story"))

func _story_step(direction: int):
	if voice_enabled: DisplayServer.tts_stop()
	preview_doc.index+=direction
	_render()
