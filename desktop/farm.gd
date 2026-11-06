extends SubViewportContainer
## Original procedural voxel diorama. No external art or provider calls.
signal project_selected
signal worker_selected(worker_id: String)
var world: Node3D
var camera: Camera3D
var farmers: Array = []
var crew_by_id = {}
var plots: Array[Node3D] = []
var north_edge = -6.5
var max_zoom = 40.0
const CREW_PER_PLOT = 4
const SHIRTS = ["367d9b","b86345","a06b41","95667c","657c48","58708e"]
const SKINS = ["eacb85","a57b54","c98d68","96684c","dba47e"]
var hens = []
var ripples = []
var rotor: Node3D
var chore_time = 0.0
var clock = 0.0
var working = false
var status = "No active job"
var materials = {}
var zoom_target = 53.0
var pan = Vector3(-0.7,0,1.5)
var dragging = false

func cube(parent: Node3D, pos: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	if not materials.has(color):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = 1.0
		materials[color] = mat
	mesh.material_override = materials[color]
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func _ready():
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("56c6e9")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("ffffff")
	env.environment.ambient_light_energy = 0.35
	world.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("ffffff")
	sun.light_energy = 0.63
	sun.shadow_enabled = true
	world.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom_target
	camera.position = Vector3(16, 19, 22)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	cube(world, Vector3(0, -0.65, 0), Vector3(17, 1.1, 13), "a97748")
	cube(world, Vector3(0, -0.08, 0), Vector3(17.1, 0.18, 13.1), "76a04e")
	# Exposed topsoil and a few stones give the island a cut-earth edge.
	cube(world,Vector3(0,-0.26,0),Vector3(17.02,0.17,13.02),"8e6848")
	for i in range(13):
		var x = -7.8+i*1.26
		var y = -0.66+0.21*sin(i*4.6)
		cube(world,Vector3(x,y,6.50),Vector3(0.16+0.20*absf(sin(i*2.3)),0.12,0.035),"b39771")
	for i in range(8):
		cube(world,Vector3(8.50,-0.66+0.22*cos(i*2.8),-5.7+i*1.53),Vector3(0.035,0.13,0.29),"b39771")
	for patch in [Vector3(-6,0,5.25),Vector3(-3.8,0,5.59),Vector3(0.65,0,5.72),Vector3(7.38,0,-1.20),Vector3(7.48,0,3.6),Vector3(1.45,0,3.32)]:
		for i in range(5):
			var blade = cube(world,patch+Vector3(sin(i*2.1)*0.43,0.10,cos(i*3.6)*0.26),Vector3(0.08,0.23,0.08),"679745")
			blade.rotation.z = sin(i*2.7)*0.31
	# Walkways join the entrance, noticeboard, beds and farmhouse.
	cube(world, Vector3(0, 0.035, 1.8), Vector3(16.4, 0.08, 1.7), "cbb583")
	cube(world, Vector3(-1.4, 0.04, 0), Vector3(1.7, 0.09, 12.4), "cbb583")
	for x in [-7.2, -5.8, -4.4, -3.0, 1.5, 3.0, 4.5, 6.0, 7.3]:
		fence(Vector3(x, 0, -5.7))
	for pos in [Vector3(-7,0,-4.6), Vector3(6.9,0,-4.6), Vector3(7,0,4.9), Vector3(-7,0,4.8)]: tree(pos)
	# Small barn, stepped roof and white trim.
	cube(world, Vector3(-4.6, 1.35, -3.4), Vector3(3.7, 2.7, 2.6), "c85b47")
	for i in range(4): cube(world, Vector3(-4.6, 2.8+i*0.2, -3.4), Vector3(4.1-i*0.8, 0.22, 3.1), "42515b")
	cube(world, Vector3(-4.6, 0.95, -2.07), Vector3(1.3, 1.9, 0.12), "643e30")
	for x in [-5.3,-3.9]: cube(world, Vector3(x, 1, -1.97), Vector3(0.12,2.1,0.13), "f5dfb5")
	cube(world, Vector3(-4.6, 2, -1.97), Vector3(1.5,0.12,0.13), "f5dfb5")
	cube(world, Vector3(-5.8,1.65,-2.05), Vector3(0.6,0.65,0.12), "8ed1df")
	# Door bracing, clapboards and a little stack of bound hay.
	for angle in [-31,31]:
		var brace = cube(world,Vector3(-4.6,1,-1.96),Vector3(0.10,2.02,0.10),"eedcc4")
		brace.rotation_degrees.z = angle
	for z in [-4.45,-3.9,-3.35,-2.8,-2.35]:
		cube(world,Vector3(-2.73,1.34,z),Vector3(0.06,2.58,0.06),"af513d")
	for bale in [Vector3(-7.1,0.31,-1.95),Vector3(-7.1,0.31,-2.76),Vector3(-7.1,0.89,-2.38)]:
		cube(world,bale,Vector3(1.22,0.58,0.78),"dba644")
		for dx in [-0.36,0.36]:
			cube(world,bale+Vector3(dx,0,0),Vector3(0.07,0.60,0.80),"966a39")
	wind_pump(Vector3(-0.3,0,-5.25))
	# Three real geometry garden beds, distinct crop silhouettes.
	for row in range(3):
		var z = -3.9 + row*1.55
		cube(world, Vector3(3.3,0.12,z), Vector3(5.1,0.26,1.16), "825137")
		for x in [1.3,2.3,3.3,4.3,5.3]:
			var root = Vector3(x,0.26,z)
			if row == 0:
				for dx in [-0.2,0.0,0.19]:
					var stalk = root+Vector3(dx,0,dx*0.6)
					cube(world,stalk+Vector3.UP*0.32,Vector3(0.08,0.65,0.08),"b4913e")
					cube(world,stalk+Vector3.UP*(0.68+dx*0.4),Vector3(0.17,0.38,0.16),"efbb4e")
			elif row == 1:
				cube(world,root+Vector3.UP*0.39,Vector3(0.09,0.82,0.09),"916143")
				cube(world,root+Vector3.UP*0.42,Vector3(0.57,0.40,0.49),"487c44")
				for offset in [Vector3(-0.2,0.35,0.23),Vector3(0.17,0.48,0.23)]:
					cube(world,root+offset,Vector3(0.23,0.22,0.19),"d85539")
			else:
				cube(world,root+Vector3.UP*0.14,Vector3(0.55,0.27,0.52),"49895c")
				cube(world,root+Vector3.UP*0.32,Vector3(0.38,0.23,0.37),"83b266")
		for side in [-0.59,0.59]:
			cube(world,Vector3(3.3,0.19,z+side),Vector3(5.25,0.19,0.10),"a77b52")
	# Pond with flat water and stepping stones.
	cube(world, Vector3(4.7,0.03,4.3), Vector3(4.2,0.09,2.5), "55b9d3")
	for p in [Vector3(2.5,0.14,3.5),Vector3(3.7,0.14,5.6),Vector3(6.9,0.14,4.8)]: cube(world,p,Vector3(0.65,0.25,0.5),"a9a58d")
	for bank in [Vector3(2.95,0.05,5.55),Vector3(6.55,0.05,3.18)]:
		cube(world,bank,Vector3(1.05,0.13,0.45),"939c6a")
		for i in range(4):
			var reed = bank + Vector3(i*0.17-0.27,0,(i%2)*0.15)
			var height = 0.56+0.10*(i%3)
			cube(world,reed+Vector3.UP*height/2,Vector3(0.065,height,0.065),"64864b")
			cube(world,reed+Vector3.UP*height,Vector3(0.105,0.23,0.105),"865a37")
	for pad in [Vector3(3.1,0.10,4.92),Vector3(3.45,0.10,5.17),Vector3(5.92,0.10,3.5)]:
		cube(world,pad,Vector3(0.40,0.05,0.31),"67a360")
	cube(world,Vector3(3.1,0.18,4.92),Vector3(0.16,0.12,0.16),"f0aec0")
	# Surface details break up the broad blocks while preserving the hotspots.
	for ripple in [Vector3(3.5,0.089,4.1),Vector3(4.1,0.089,4.8),Vector3(5.8,0.089,3.8)]:
		ripples.append(cube(world,ripple,Vector3(0.48,0.016,0.08),"9de1de"))
	for patch in [Vector3(-6,0,2.7),Vector3(-3,0,5.1),Vector3(1.2,0,4.6),Vector3(6.7,0,-2.8)]:
		for offset in [Vector3.ZERO,Vector3(0.35,0,0.22),Vector3(-0.28,0,0.16)]:
			cube(world,patch+offset+Vector3(0,0.11,0),Vector3(0.08,0.23,0.08),"508740")
			cube(world,patch+offset+Vector3(0,0.25,0),Vector3(0.19,0.11,0.17),"edbc55")
	# Planning table / project hotspot.
	for x in [-4.9,-3.1]: cube(world,Vector3(x,0.45,3.6),Vector3(0.18,0.9,0.18),"785032")
	cube(world,Vector3(-4,0.95,3.6),Vector3(2.6,0.18,1.4),"bd8b51")
	cube(world,Vector3(-4,1.07,3.6),Vector3(1.1,0.05,0.8),"f5e9c6")
	world.add_child(preload("res://countryside.gd").new())
	expand_to(1)
	for i in range(4):
		chicken([Vector3(-5.6,0,-0.68),Vector3(-3.9,0,-0.37),Vector3(-6.9,0,0.05),Vector3(-4.65,0,0.27)][i],i)
	for i in range(10):
		cube(world,Vector3(-5.35+sin(i*2.4)*0.7,0.045,-0.35+cos(i*1.8)*0.40),Vector3(0.10,0.06,0.09),"d6ad5d")
	var board = Label3D.new()
	board.text = "PROJECT TABLE"
	board.font_size = 38
	board.pixel_size = 0.008
	board.position = Vector3(-4,2.15,3.6)
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.modulate = Color("fff4d8")
	world.add_child(board)

func fence(p: Vector3):
	cube(world,p+Vector3(0,0.55,0),Vector3(0.16,1.1,0.16),"e6cb8d")
	cube(world,p+Vector3(0.6,0.65,0),Vector3(1.4,0.16,0.12),"d3ae70")

func tree(p: Vector3):
	cube(world,p+Vector3(0,0.9,0),Vector3(0.42,1.8,0.42),"825434")
	cube(world,p+Vector3(0,2,0),Vector3(1.8,1.5,1.6),"5c8936")
	cube(world,p+Vector3(-0.2,2.9,0),Vector3(1.35,0.6,1.25),"7caa40")

	if p.z > 0:
		cube(world,p+Vector3(0.57,2.3,0.16),Vector3(0.95,0.92,1.28),"689849")
		for offset in [Vector3(-0.57,2.12,0.83),Vector3(0.32,1.85,0.83),Vector3(1.03,2.26,0.32)]:
			cube(world,p+offset,Vector3(0.26,0.26,0.22),"c75f37")

func wind_pump(p: Vector3):
	for dx in [-0.46,0.46]:
		var brace = cube(world,p+Vector3(dx*0.72,1.5,0),Vector3(0.16,3.05,0.21),"7f644f")
		brace.rotation.z = dx*0.20
	for h in [0.68,1.48,2.24]:
		cube(world,p+Vector3(0,h,0),Vector3(0.94-h*0.13,0.13,0.21),"a18460")
	rotor = Node3D.new()
	world.add_child(rotor)
	rotor.position = p+Vector3(0,3.03,0.22)
	for i in range(8):
		var blade = Node3D.new()
		rotor.add_child(blade)
		blade.rotation.z = TAU*i/8
		cube(blade,Vector3(0,0.55,0),Vector3(0.09,1.0,0.08),"77888a")
		cube(blade,Vector3(0.06,0.88,0),Vector3(0.31,0.62,0.10),"c0cacc")
		cube(blade,Vector3(0.06,1.15,0.01),Vector3(0.31,0.12,0.11),"c65a4b")
	cube(rotor,Vector3(0,0,0.08),Vector3(0.30,0.30,0.21),"a65340")

func chicken(home: Vector3, index: int):
	var bird = Node3D.new()
	world.add_child(bird)
	var body = Node3D.new()
	bird.add_child(body)
	body.position.y = 0.39
	var plumage = "c4874c" if index == 2 else "f1e6cc"
	cube(body,Vector3.ZERO,Vector3(0.43,0.38,0.64),plumage)
	cube(body,Vector3(0,0.25,0.24),Vector3(0.33,0.36,0.32),plumage)
	cube(body,Vector3(0,0.46,0.23),Vector3(0.12,0.16,0.22),"d4533e")
	cube(body,Vector3(0,0.22,0.44),Vector3(0.16,0.12,0.16),"eea03c")
	for dx in [-0.17,0.17]:
		cube(body,Vector3(dx,0.31,0.31),Vector3(0.03,0.07,0.07),"30383a")
		cube(body,Vector3(dx*1.3,0,-0.03),Vector3(0.12,0.23,0.38),"ab7045" if index==2 else "decfb1")
		cube(bird,Vector3(dx*0.70,0.11,0),Vector3(0.08,0.23,0.10),"c18b43")
	cube(body,Vector3(0,0.16,-0.32),Vector3(0.25,0.25,0.18),plumage)
	hens.append({"bird":bird,"body":body,"home":home,"phase":index*1.51})

func joint(parent: Node3D, at: Vector3) -> Node3D:
	var pivot = Node3D.new()
	parent.add_child(pivot)
	pivot.position = at
	return pivot

func farmer(p: Vector3, shirt: String, skin: String, index: int) -> Dictionary:
	var actor = joint(world,p)
	var grower = index % 2 == 0
	var denim = "345665" if grower else "496b60"
	var boots = "674a37" if grower else "403c46"
	var hair = "714934" if grower else "4b3436"
	var legs = []
	var arms = []
	for side in [-1,1]:
		var leg = joint(actor,Vector3(side*0.22,0.60,0))
		legs.append(leg)
		cube(leg,Vector3(0,-0.16,0),Vector3(0.36,0.34,0.39),denim)
		cube(leg,Vector3(0,-0.39,0.015),Vector3(0.38,0.21,0.40),boots)
		cube(leg,Vector3(0,-0.50,0.075),Vector3(0.39,0.16,0.52),boots)
		cube(leg,Vector3(0,-0.57,0.075),Vector3(0.40,0.06,0.53),"353c3d")
	var chest = joint(actor,Vector3(0,0.63,0))
	cube(chest,Vector3(0,0.32,0),Vector3(0.80,0.68,0.55),shirt)
	cube(chest,Vector3(0,0.12,0),Vector3(0.83,0.26,0.58),denim)
	cube(chest,Vector3(0,0.33,0.286),Vector3(0.56,0.36,0.07),denim)
	cube(chest,Vector3(0,0.29,0.335),Vector3(0.30,0.16,0.04),"567f86" if grower else "719080")
	for side in [-1,1]:
		for z in [-0.267,0.267]:
			cube(chest,Vector3(side*0.23,0.53,z),Vector3(0.13,0.29,0.085),denim)
		cube(chest,Vector3(side*0.23,0.47,0.324),Vector3(0.075,0.075,0.04),"e6b563")
		var arm = joint(chest,Vector3(side*0.49,0.53,0))
		arms.append(arm)
		cube(arm,Vector3(0,-0.11,0),Vector3(0.28,0.29,0.37),shirt)
		cube(arm,Vector3(0,-0.25,0),Vector3(0.29,0.10,0.38),"b8caba" if grower else "e8a074")
		cube(arm,Vector3(0,-0.38,0.04),Vector3(0.24,0.23,0.28),skin)
	var head = joint(chest,Vector3(0,0.66,0))
	cube(head,Vector3(0,0.36,0),Vector3(0.83,0.73,0.68),skin)
	cube(head,Vector3(0,0.42,-0.27),Vector3(0.85,0.59,0.22),hair)
	cube(head,Vector3(0,0.67,0.02),Vector3(0.85,0.20,0.67),hair)
	for side in [-1,1]:
		cube(head,Vector3(side*0.424,0.34,0),Vector3(0.11,0.21,0.19),skin)
		cube(head,Vector3(side*0.40,0.49,0),Vector3(0.09,0.27,0.44),hair)
		cube(head,Vector3(side*0.21,0.44,0.352),Vector3(0.088,0.115,0.038),"303136")
		cube(head,Vector3(side*0.21,0.54,0.354),Vector3(0.15,0.055,0.04),hair)
	cube(head,Vector3(0,0.32,0.37),Vector3(0.16,0.115,0.13),skin)
	if grower:
		cube(head,Vector3(0,0.12,0.055),Vector3(0.80,0.24,0.64),hair)
		cube(head,Vector3(0,0.241,0.369),Vector3(0.34,0.095,0.07),hair)
		var hat = joint(head,Vector3(0,0.73,-0.035))
		hat.rotation.z = -0.065
		cube(hat,Vector3.ZERO,Vector3(1.22,0.105,0.99),"d9ad60")
		cube(hat,Vector3(0,0.17,-0.03),Vector3(0.82,0.30,0.72),"e7c77c")
		cube(hat,Vector3(0,0.11,-0.03),Vector3(0.84,0.10,0.74),"426f70")
		cube(hat,Vector3(0,0.34,-0.03),Vector3(0.68,0.09,0.59),"e7c77c")
	else:
		cube(head,Vector3(0,0.13,0.35),Vector3(0.17,0.045,0.04),"87584e")
		cube(head,Vector3(0,0.70,0),Vector3(0.91,0.18,0.74),"aa4454")
		cube(head,Vector3(0,0.84,-0.045),Vector3(0.78,0.16,0.65),"bf5660")
		cube(head,Vector3(0,0.95,-0.09),Vector3(0.60,0.08,0.49),"bf5660")
		cube(head,Vector3(0,0.58,-0.40),Vector3(0.50,0.39,0.37),hair)
		for side in [-1,1]:
			var tie = cube(head,Vector3(side*0.14,0.59,-0.50),Vector3(0.16,0.28,0.16),"aa4454")
			tie.rotation.z = side*0.42
	var tool = joint(arms[1],Vector3(0,-0.42,0.12))
	if grower:
		cube(tool,Vector3(0,-0.10,0.17),Vector3(0.43,0.37,0.40),"38848d")
		var spout = cube(tool,Vector3(0,-0.08,0.49),Vector3(0.13,0.13,0.38),"61acac")
		spout.rotation.x = -0.33
		cube(tool,Vector3(0,-0.015,0.67),Vector3(0.22,0.15,0.12),"498b92")
	else:
		cube(tool,Vector3(0,-0.065,0.15),Vector3(0.38,0.30,0.37),"a47948")
		cube(tool,Vector3(0,0.09,0.15),Vector3(0.41,0.09,0.40),"d4af75")
	var particles = []
	for i in range(5):
		particles.append(cube(actor,Vector3.ZERO,Vector3(0.07,0.11,0.07),"75d0e0" if grower else "d6a74a"))
	return {"node":actor,"home":p,"index":index,"tool":tool,"particles":particles,
		"head":head,"chest":chest,"legs":legs,"arms":arms}

func plot_center(index: int) -> Vector3:
	# Extend the east field first, then pair successive fields behind the farm.
	if index==0: return Vector3(14.55,0,0)
	var row = ceili(index/2.0)
	return Vector3(14.55 if index%2==0 else 2.55,0,-10.5-13.0*row)

func expand_to(count: int):
	while plots.size() < count:
		var index = plots.size()
		var plot = joint(world,plot_center(index))
		plots.append(plot)
		cube(plot,Vector3(0,-0.65,0),Vector3(12,1.1,13),"a97748")
		cube(plot,Vector3(0,-0.08,0),Vector3(12,0.18,13),"79a45a")
		cube(plot,Vector3(0,-0.26,0),Vector3(12,0.17,13),"8e6848")
		cube(plot,Vector3(0,0.035,1.8),Vector3(12,0.08,1.68),"cbb583")
		cube(plot,Vector3(0,0.04,0),Vector3(1.38,0.09,13),"cbb583")
		for station in CREW_PER_PLOT:
			var x = -2.95 if station%2==0 else 2.95
			var z = -2.9 if station<2 else 3.45
			if station%2==0:
				# Propagation benches with seed trays under a slatted shade roof.
				for dx in [-1.75,1.75]:
					for dz in [-0.59,0.59]:
						cube(plot,Vector3(x+dx,0.84,z+dz),Vector3(0.13,1.68,0.13),"946f4a")
				for slat in range(6):
					cube(plot,Vector3(x-1.68+slat*0.67,1.72,z),Vector3(0.46,0.13,1.56),"aac796")
				cube(plot,Vector3(x,0.45,z),Vector3(3.8,0.15,1.35),"b38453")
				for pot in range(5):
					var pos = Vector3(x-1.48+pot*0.74,0.67,z)
					cube(plot,pos,Vector3(0.46,0.34,0.49),"bb7453")
					cube(plot,pos+Vector3.UP*0.28,Vector3(0.36,0.27,0.33),"538253")
			else:
				# Nesting shelters and feed troughs on the opposite side of the lane.
				cube(plot,Vector3(x+0.84,0.60,z-0.66),Vector3(1.50,1.20,1.28),"be8358")
				cube(plot,Vector3(x+0.84,1.28,z-0.66),Vector3(1.76,0.20,1.56),"53878a")
				cube(plot,Vector3(x+0.84,0.39,z),Vector3(0.58,0.70,0.12),"695342")
				cube(plot,Vector3(x-0.75,0.19,z),Vector3(1.70,0.36,0.65),"98704b")
				cube(plot,Vector3(x-0.75,0.39,z),Vector3(1.45,0.10,0.44),"dab456")
	north_edge = plot_center(plots.size()-1).z-6.5
	max_zoom = 64.0+absf(north_edge+6.5)*1.4

func station_home(slot: int) -> Vector3:
	if slot==0: return Vector3(1.35,0,0.42)
	if slot==1: return Vector3(-5.8,0,0.77)
	var station = (slot-2)%CREW_PER_PLOT
	return plot_center(floori((slot-2)/float(CREW_PER_PLOT))) + Vector3(
		-4.45 if station%2==0 else 1.45,0,-1.56 if station<2 else 4.79)

func sync_state(data: Dictionary):
	working = data.get("busy", false)
	status = "Job active" if working else "No active job"

	var roster = data.get("workers",[])
	expand_to(maxi(1,ceili((roster.size()-2)/float(CREW_PER_PLOT))))
	var present = {}
	farmers.clear()
	for slot in roster.size():
		var worker = roster[slot]
		var id = str(worker.id)
		present[id] = true
		var item = crew_by_id.get(id)
		if item == null:
			item = farmer(station_home(slot),SHIRTS[slot%SHIRTS.size()],SKINS[slot%SKINS.size()],slot)
			item.id = id
			var tag = Label3D.new()
			tag.position.y = 2.84
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.font_size = 48
			tag.pixel_size = 0.011
			tag.outline_size = 7
			item.node.add_child(tag)
			item.tag = tag
			crew_by_id[id] = item
		item.home = station_home(slot)
		item.slot = slot
		item.tag.text = str(worker.name).left(19) + ("…" if str(worker.name).length()>19 else "")
		var active = data.get("activeWorker")
		item.on_duty = active is Dictionary and active.get("workerId","")==id
		item.tag.modulate = Color("ffdb76") if item.on_duty else Color.WHITE
		if item.on_duty:
			var duty = {"planning":"Planning","review":"Reviewing"}.get(active.stage,"Working")
			item.tag.text += " · "+duty
		farmers.append(item)
	for id in crew_by_id.keys():
		if not present.has(id):
			crew_by_id[id].node.queue_free()
			crew_by_id.erase(id)

func _process(delta):
	clock += delta
	camera.size = lerpf(camera.size,zoom_target,1.0-exp(-delta*9))
	camera.v_offset = -1.35 if size.y < 740 else -0.45
	camera.position = Vector3(16,19,22) + pan
	chore_time += delta
	rotor.rotation.z = fmod(clock*0.62,TAU)
	for i in ripples.size():
		ripples[i].scale.x = 0.85+0.40*sin(clock*1.8+i*2)
	for hen in hens:
		var t = clock*0.78 + hen.phase
		# Pause at each end of a short foraging run, then dip for grain.
		var stride = clampf(sin(t)*1.6,-1,1)
		var walking = absf(stride)<0.999
		var facing = (1.0 if cos(t)>0 else -1.0)
		hen.bird.position = hen.home+Vector3(stride*0.44,absf(sin(t*13))*0.065 if walking else 0.0,stride*0.18)
		hen.bird.rotation.y = lerp_angle(hen.bird.rotation.y,atan2(facing*0.44,facing*0.18),1-exp(-delta*6))
		hen.body.rotation.x = 0.15 if walking else 0.50+0.5*sin(t*10)
	for item in farmers:
		var actor = item.node
		var phase = fmod(chore_time*(1.45 if item.on_duty else 1.0)+item.index*4,12.0)
		var walking = phase<3 or (phase>=6 and phase<9)
		var progress = minf(phase/3,1) if phase<6 else maxf(1-(phase-6)/3,0)
		var distance = 3.0 if item.slot>=2 else 3.92 if item.slot==0 else 1.55
		var facing = PI/2 if phase<3 else -PI/2 if walking else PI
		actor.rotation.y = lerp_angle(actor.rotation.y,facing,1-exp(-delta*7))
		actor.position = item.home+Vector3(progress*distance,absf(sin(chore_time*7))*0.075 if walking else 0.012*sin(chore_time*3),0)
		var stride = sin(chore_time*7+item.index)
		var blend = 1-exp(-delta*12)
		for j in range(2):
			var swing = stride*(1 if j==0 else -1)
			var leg = item.legs[j]
			var arm = item.arms[j]
			leg.rotation.x = lerpf(leg.rotation.x,swing*0.48 if walking else 0.0,blend)
			var gesture = -0.18 if j==0 else -0.66-0.28*sin(chore_time*4)
			arm.rotation.x = lerpf(arm.rotation.x,-swing*0.34 if walking else gesture,blend)
		item.chest.rotation.z = lerpf(item.chest.rotation.z,0.055*stride if walking else 0.035,blend)
		item.head.rotation.y = lerpf(item.head.rotation.y,0.16*sin(chore_time*1.4) if walking else -0.22,blend)
		item.head.rotation.x = lerpf(item.head.rotation.x,0.035*cos(chore_time*7) if walking else 0.15,blend)
		item.tool.rotation.x = 0.14 if walking else 0.97+0.18*sin(chore_time*4)
		for i in item.particles.size():
			var fleck = item.particles[i]
			fleck.visible = not walking
			var t = fmod(chore_time*1.8+i*0.2,1)
			var tip = Vector3(0,-0.015,0.67) if item.index%2==0 else Vector3(0,0.09,0.32)
			var origin = actor.to_local(item.tool.to_global(tip))
			var reach = t*(0.50 if item.index%2==0 else 0.86)
			fleck.position = origin+Vector3(sin(i*3.1)*t*0.22,-origin.y*t*t+sin(t*PI)*(0.08 if item.index%2==0 else 0.38),reach)

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			accept_event()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_target = clampf(zoom_target + (-0.10 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.10)*zoom_target,12,max_zoom)
			accept_event()
	if event is InputEventMouseMotion and dragging:
		pan += Vector3(-event.relative.x-event.relative.y,0,event.relative.x-event.relative.y)*0.00075*camera.size
		pan.x = clampf(pan.x,-22,21)
		pan.z = clampf(pan.z,minf(-17,north_edge)-1.5,19)
		accept_event()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Test the projected silhouette first so hats and torsos are clickable too.
		for item in farmers:
			var feet = camera.unproject_position(item.node.position)
			var top = camera.unproject_position(item.node.position+Vector3.UP*2.38)
			var radius = feet.distance_to(top)*0.26
			var nearest = Geometry2D.get_closest_point_to_segment(event.position,feet,top)
			if nearest.distance_to(event.position) <= radius:
				worker_selected.emit(item.id)
				accept_event()
				return
		var origin = camera.project_ray_origin(event.position)
		var direction = camera.project_ray_normal(event.position)
		var hit = Plane(Vector3.UP,0).intersects_ray(origin,direction)
		if hit == null: return
		if Vector2(hit.x+4,hit.z-3.6).length() < 2: project_selected.emit()
		else:
			for item in farmers:
				if Vector2(hit.x-item.node.position.x,hit.z-item.node.position.z).length() < 1.2:
					worker_selected.emit(item.id)
		accept_event()





func visit(place: String):
	match place:
		"Whole farm":
			var far_bank = minf(-17,north_edge)
			pan = Vector3(-0.7,0,(18.4+far_bank)/2)
			zoom_target = 53.0+(-17-far_bank)*0.85
		"Homestead": pan = Vector3.ZERO; zoom_target = 23
		"West orchard": pan = Vector3(-15.3,0,0); zoom_target = 20
		"Grain fields": pan = Vector3(-12.7,0,-11.7); zoom_target = 22
		"Horse paddock": pan = Vector3(8.5,0,-11.8); zoom_target = 25
		"Sheep pasture": pan = Vector3(-14,0,15); zoom_target = 19
		"Riverside market": pan = Vector3(-0.7,0,14); zoom_target = 18
		"Apiary": pan = Vector3(12,0,15.7); zoom_target = 17
		"Watermill": pan = Vector3(11.5,0,10.4); zoom_target = 16
		"Crew fields": pan = plot_center(plots.size()-1); zoom_target = 23
