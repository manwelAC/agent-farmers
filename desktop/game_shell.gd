extends Control

signal navigate(destination: String)
signal crew_picked(worker_id: String)
const Arcade = preload("res://arcade_skin.gd")
const Icons = preload("res://hud_icons.gd")
const ROUTES = {"Farm":"Farm","Projects":"Projects","Workers":"Crew","Connections":"Accounts","Results":"Outputs","Memory":"Memory","Overview":"Guide"}
var farm
var focus_material = ShaderMaterial.new()
var reading_pane = PanelContainer.new()
var heading_icon = TextureRect.new()
var block_font = FontFile.new()
var shade = ColorRect.new()
var scroll = ScrollContainer.new()
var footer = VBoxContainer.new()
var page = VBoxContainer.new()
var status = Label.new()
var notice = Label.new()
var overlay = Control.new()
var window_panel = PanelContainer.new()
var title = Label.new()
var dock = HBoxContainer.new()
var hud = HBoxContainer.new()
var hint = Label.new()
var buttons = {}
var places = MenuButton.new()
var guided = false
var portrait = SubViewportContainer.new()
var portrait_world = SubViewport.new()
var narrator = {}
var narrator_mouth: MeshInstance3D
var spoken_label: RichTextLabel
var speaking_time = 0.0
var spoken_audio = false
var speaker_model: Node3D
var portrait_slot = -2
var speech = PanelContainer.new()
var speech_text = Label.new()
var speaking_worker = ""
var dispatch = Button.new()
var current = "Farm"

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sky = preload("res://sky.gd").new()
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	farm = preload("res://farm.gd").new()
	farm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(farm)
	farm.project_selected.connect(func(): navigate.emit("Projects"))
	farm.worker_selected.connect(func(id): crew_picked.emit(id))
	add_child(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var brand = VBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation",-13)
	hud.add_child(brand)
	var display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Arial Black","Segoe UI Black"])
	display_font.font_weight = 900
	for word in ["AGENT","FARMERS"]:
		var line = Label.new()
		line.text = word
		line.add_theme_font_size_override("font_size",28 if word == "AGENT" else 47)
		line.add_theme_font_override("font",display_font)
		line.add_theme_color_override("font_color",Color("ffde80") if word == "AGENT" else Color("fffcef"))
		line.add_theme_color_override("font_outline_color",Color("263e49"))
		line.add_theme_constant_override("outline_size",6)
		line.add_theme_color_override("font_shadow_color",Color("263e49"))
		line.add_theme_constant_override("shadow_offset_y",5)
		brand.add_child(line)
	places.text = "Explore farm ▾"
	places.flat = false
	places.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hud.add_child(places)
	var destinations = ["Whole farm","Homestead","West orchard","Grain fields","Horse paddock","Sheep pasture","Riverside market","Watermill","Apiary","Crew fields"]
	for place in destinations: places.get_popup().add_item(place)
	places.get_popup().id_pressed.connect(func(id): farm.visit(destinations[id]))
	status.text = "Starting…"
	status.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	status.add_theme_stylebox_override("normal",plate("284751"))
	status.add_theme_color_override("font_color",Color("e6f5cd"))
	hud.add_child(status)
	var fullscreen = action(hud,"⛶",toggle_fullscreen)
	fullscreen.tooltip_text = "Toggle fullscreen · F11"
	fullscreen.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_material.shader = preload("res://dialogue_backdrop.gdshader")
	shade.color = Color(0.08,0.18,0.21,0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	overlay.add_child(window_panel)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	var panel_row = HBoxContainer.new()
	window_panel.add_child(panel_row)
	panel_row.add_theme_constant_override("separation",20)
	panel_row.add_child(portrait)
	portrait.custom_minimum_size.x = 170
	portrait.stretch = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_world.own_world_3d = true
	portrait_world.transparent_bg = true
	portrait_world.msaa_3d = Viewport.MSAA_2X
	portrait.add_child(portrait_world)
	var camera = Camera3D.new()
	portrait_world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.position = Vector3(0,2.2,6)
	camera.look_at(Vector3(0,1.18,0))
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,24,0)
	portrait_world.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24,-136,0)
	fill.light_energy = 0.65
	portrait_world.add_child(fill)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_row.add_child(reading_pane)
	reading_pane.add_child(layout)
	block_font.load_dynamic_font("res://farm_block.ttf")
	block_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var banner = PanelContainer.new()
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	banner.add_theme_stylebox_override("panel",Arcade.box("4076ce","11294e","224b94","85b1f7"))
	layout.add_child(banner)
	var heading = HBoxContainer.new()
	banner.add_child(heading)
	heading.add_theme_constant_override("separation",12)
	heading_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	heading_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	heading.add_child(heading_icon)
	title.add_theme_font_size_override("font_size",24)
	title.add_theme_font_override("font",display_font)
	title.add_theme_color_override("font_color",Color("fffbed"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close = action(heading,"×",func(): navigate.emit("Farm"))
	close.tooltip_text = "Back to farm · Esc"
	close.custom_minimum_size = Vector2(44,40)
	close.add_theme_font_size_override("font_size",26)
	Arcade.button(close,"ed5046","a32730","ffffff")
	close.text = "X"
	close.add_theme_font_override("font",block_font)
	close.add_theme_font_size_override("font_size",30)
	title.add_theme_color_override("font_outline_color",Color("192b50"))
	title.add_theme_constant_override("outline_size",4)
	title.add_theme_color_override("font_shadow_color",Color("192b50"))
	title.add_theme_constant_override("shadow_offset_y",2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation",14)
	scroll.add_child(page)
	layout.add_child(footer)
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	dock.add_theme_constant_override("separation",6)
	add_child(dock)
	for route in ROUTES:
		var button = action(dock,ROUTES[route],func(): navigate.emit(route))
		button.icon = Icons.texture(route)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = Vector2(96,78)
		buttons[route] = button
	hint.text = "Planning table opens projects    ·    Select a farmer to manage crew"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(notice)
	speech.add_theme_stylebox_override("panel",Arcade.box("fff8db","233852","73909c","ffffff"))
	speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_text.custom_minimum_size.x = 288
	speech_text.add_theme_font_size_override("font_size",17)
	speech.add_child(speech_text)
	add_child(speech)
	speech.hide()
	dispatch.visible = false
	dispatch.theme_type_variation = "Primary"
	add_child(dispatch)
	resized.connect(arrange)
	show_view("Farm")

func plate(fill: String) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.set_corner_radius_all(5)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box

func action(parent: Node, caption: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func arrange():
	var w = size.x
	var h = size.y
	hud.position = Vector2(32,18)
	hud.size = Vector2(w-64,80)
	dock.position = Vector2(16,h-133)
	dock.size = Vector2(w-32,78)
	hint.position = Vector2(20,h-167)
	hint.size = Vector2(w-40,28)
	notice.position = Vector2(20,h-30)
	notice.size = Vector2(w-40,24)
	dispatch.position = Vector2((w-dispatch.size.x)/2,h-180)
	var side = 32 if w < 1150 else maxf(64,(w-1320)/2)
	window_panel.position = Vector2(side,108)
	window_panel.size = Vector2(w-side*2,h-255)
	if current=="Workers":
		window_panel.position = Vector2(side,78)
		window_panel.size = Vector2(w-side*2,h-222)
	if guided:
		var inset = Vector2(maxf(24,w*0.05),maxf(36,h*0.085))
		window_panel.position = inset
		window_panel.size = size-inset*2
		portrait.custom_minimum_size.x = maxf(window_panel.size.x*0.32,window_panel.size.y*0.45)
	elif current in ["Project","Projects"]:
		var width = clampf(w*0.43,480,640)
		window_panel.position = Vector2(w-width-20,72)
		window_panel.size = Vector2(width,h-218)

func speaker(slot: int):
	if portrait_slot==slot: return
	portrait_slot = slot
	if is_instance_valid(speaker_model): speaker_model.queue_free()
	var outfit = maxi(slot,0)
	var model = farm.farmer(Vector3.ZERO,farm.SHIRTS[outfit%farm.SHIRTS.size()],farm.SKINS[outfit%farm.SKINS.size()],outfit)
	narrator = model
	narrator_mouth = farm.cube(model.head,Vector3(0,0.16,0.39),Vector3(0.21,0.071,0.035),"492f30")
	narrator_mouth.hide()
	speaker_model = model.node
	speaker_model.reparent(portrait_world,false)
	speaker_model.rotation.y = 0.28
	model.arms[0].rotation.x = -0.72
	model.arms[0].rotation.z = -0.25
	for droplet in model.particles: droplet.hide()
	speaker_model.scale = Vector3.ONE*0.84
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(speaker_model,"scale",Vector3.ONE,0.32)

func end_narration():
	spoken_label=null
	spoken_audio=false
	if not narrator.is_empty():
		narrator.head.rotation=Vector3.ZERO
		narrator.chest.rotation=Vector3.ZERO
		narrator.arms[0].rotation=Vector3(-0.72,0,-0.25)
		narrator.tool.show()
		narrator_mouth.hide()

func narrate(label: RichTextLabel, audio_on: bool):
	spoken_label=label
	speaking_time=0
	spoken_audio=audio_on
	label.visible_characters=0
	narrator.tool.hide()
	narrator_mouth.show()

func show_view(destination: String):
	end_narration()
	var opening = destination != current and destination != "Farm"
	current = destination
	overlay.visible = current != "Farm"
	var chatting = current in ["Project","Projects"]
	shade.visible = guided or not chatting
	shade.material = focus_material if guided else null
	if guided:
		window_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
		reading_pane.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var paper = Arcade.box("fff5e7","102547","254882","8eb7fa",true)
		paper.content_margin_left = 24
		paper.content_margin_right = 24
		paper.content_margin_top = 22
		paper.content_margin_bottom = 22
		reading_pane.add_theme_stylebox_override("panel",paper)
	else:
		window_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		window_panel.add_theme_stylebox_override("panel",Arcade.box("fff5e7","102547","254882","8eb7fa",true))
		reading_pane.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	hud.visible = not guided
	if guided: scroll.scroll_vertical = 0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if chatting and not guided else Control.MOUSE_FILTER_STOP
	portrait.visible = guided
	dock.visible = not guided
	footer.visible = current in ["Project","Workers"] or guided
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if chatting or current=="Connections" else ScrollContainer.SCROLL_MODE_AUTO
	farm.dragging = false
	hint.visible = current == "Farm"
	places.visible = current == "Farm"
	title.text = {"Projects":"Planning table","Project":"Crew conversation","Workers":"Crew","Connections":"Accounts","Results":"Outputs","Overview":"Field guide"}.get(current,current)
	heading_icon.visible = not guided and buttons.has(current)
	if heading_icon.visible: heading_icon.texture = buttons[current].icon
	if not guided:
		title.text = title.text.to_upper()
		title.add_theme_font_override("font",block_font)
	else:
		title.remove_theme_font_override("font")
	title.add_theme_font_size_override("font_size",24 if guided else 30)
	for route in buttons:
		var active = route == current or (route == "Projects" and current == "Project")
		buttons[route].theme_type_variation = "Primary" if active else "Dock"
	arrange()
	if opening:
		window_panel.modulate.a = 0.3
		create_tween().tween_property(window_panel,"modulate:a",1,0.14)

func farm_line(worker_id: String, words: String):
	speaking_worker = worker_id
	speech_text.text = words
	speech.reset_size()
	speech.show()
	_position_speech()

func _process(delta):
	if speech.visible: _position_speech()
	if not is_instance_valid(spoken_label): return
	speaking_time+=delta
	var count=spoken_label.get_total_character_count()
	if spoken_label.visible_characters>=0 and spoken_label.visible_characters<count:
		spoken_label.visible_characters=mini(count,int(speaking_time*53))
	var talking = (spoken_label.visible_characters>=0 and spoken_label.visible_characters<count) or (spoken_audio and DisplayServer.tts_is_speaking())
	var t=speaking_time
	var weight=1.0-exp(-delta*10)
	var gesture=sin(t*2.4)
	var mouth=absf(sin(t*10.2)*cos(t*2.1)) if talking else 0.0
	narrator_mouth.scale.y=lerpf(narrator_mouth.scale.y,0.22+mouth*1.3,weight)
	narrator.head.rotation.x=lerpf(narrator.head.rotation.x,0.09*gesture if talking else 0.0,weight)
	narrator.head.rotation.y=lerpf(narrator.head.rotation.y,0.12*sin(t*1.7) if talking else 0.0,weight)
	narrator.arms[0].rotation.x=lerpf(narrator.arms[0].rotation.x,-0.95+0.39*gesture if talking else -0.35,weight)
	narrator.arms[0].rotation.z=lerpf(narrator.arms[0].rotation.z,-0.46-0.22*sin(t*1.5) if talking else -0.18,weight)
	narrator.chest.rotation.z=lerpf(narrator.chest.rotation.z,0.04*sin(t*1.3) if talking else 0.0,weight)

func _position_speech():
	if current!="Farm":
		speech.hide()
		return
	var point = size*Vector2(0.5,0.42)
	var farmer = farm.crew_by_id.get(speaking_worker)
	if farmer!=null:
		point = farm.camera.unproject_position(farmer.node.position+Vector3.UP*3.3)
	speech.position=Vector2(clampf(point.x-speech.size.x/2,12,size.x-speech.size.x-12),clampf(point.y-speech.size.y,96,maxf(96,size.y-190-speech.size.y)))

func toggle_fullscreen():
	get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _unhandled_key_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and current != "Farm":
			navigate.emit("Farm")
			get_viewport().set_input_as_handled()
		if event.keycode == KEY_F11: toggle_fullscreen()


