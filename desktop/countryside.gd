extends Node3D
## The countryside wraps around the homestead and meets the expandable crew fields along its northern boundary.
var blocks = {}
var animal_mesh = BoxMesh.new()
var materials = {}
var sheep = []
var horses = []
var bees = []
var wheel = Node3D.new()
var elapsed = 0.0

func block(x,y,z,w,h,d,color,turn=0.0):
	var pose = Transform3D(Basis(Vector3.RIGHT,turn).scaled_local(Vector3(w,h,d)),Vector3(x,y,z))
	if not blocks.has(color): blocks[color] = []
	blocks[color].append(pose)

func material(color):
	if not materials.has(color):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = 1
		materials[color] = mat
	return materials[color]

func part(parent,position_: Vector3,dimensions: Vector3,color: String):
	var piece = MeshInstance3D.new()
	piece.mesh = animal_mesh
	piece.material_override = material(color)
	piece.position = position_
	piece.scale = dimensions
	parent.add_child(piece)
	return piece

func _ready():
	land(-15.275,0,13.45,13.1,"87ab60")
	land(-12.75,-11.775,18.5,10.45,"98ad65")
	land(-0.725,13.825,42.55,9.15,"85ad60")
	block(-0.725,-0.73,7.9,42.55,0.94,2.70,"74a6a1")
	block(-0.725,-0.20,7.9,42.55,0.14,2.70,"56adbf")
	for i in range(32):
		var x = -21.3+i*1.28
		var z = 7.9+0.91*sin(i*2.4)
		block(x,-0.115,z,0.46+0.45*absf(sin(i)),0.02,0.09,"99d7d1")
	for x in [-16.2,-1.4,14.55]: bridge(x)
	# The same lanes meet the homestead, the footbridges, and the south bank.
	block(-15.27,0.046,1.8,13.45,0.075,1.65,"cbb583")
	block(-16.2,0.054,-3.85,1.4,0.08,20.80,"cbb583")
	block(-0.72,0.042,12.13,42.5,0.08,1.55,"cbb583")
	for x in [-16.2,-1.4,14.55]: block(x,0.052,10.67,1.42,0.08,2.9,"cbb583")
	orchard()
	grain_fields()
	horse_yard()
	pasture()
	market()
	watermill()
	apiary()
	# Batch stationary blocks by pigment, including their shadows.
	for color in blocks:
		var batch = MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = animal_mesh
		batch.instance_count = blocks[color].size()
		for i in batch.instance_count: batch.set_instance_transform(i,blocks[color][i])
		var node = MultiMeshInstance3D.new()
		node.multimesh = batch
		node.material_override = material(color)
		add_child(node)
	blocks.clear()

func land(x,z,w,d,grass):
	block(x,-0.65,z,w,1.1,d,"a97748")
	block(x,-0.24,z,w,0.24,d,"8e6848")
	block(x,-0.07,z,w,0.18,d,grass)

func bridge(x):
	for i in range(10):
		block(x,0.11,6.48+i*0.32,1.84,0.18,0.30,"ac7c50" if i%3 else "bc8e5e")
	for side in [-0.94,0.94]:
		block(x+side,0.72,7.92,0.10,0.13,3.11,"c3a073")
		for z in [6.52,7.95,9.29]: block(x+side,0.41,z,0.15,0.98,0.15,"967143")

func orchard():
	for x in [-20.1,-13.7,-10.5]:
		for z in [-4.6,-1.1,4.28]:
			block(x,0.70,z,0.42,1.4,0.46,"845733")
			block(x,1.98,z,2.12,1.42,1.82,"59894a")
			block(x+0.18,2.92,z-0.06,1.52,0.63,1.47,"7ba64e")
			for fruit in [Vector3(-0.68,2.22,0.91),Vector3(0.53,1.80,0.93),Vector3(1.05,2.15,0.36)]:
				block(x+fruit.x,fruit.y,z+fruit.z,0.32,0.34,0.32,"c65d36")
	for x in [-19.6,-18.1]:
		block(x,0.34,0.9,1.22,0.65,0.83,"a57c4d")
		block(x,0.69,0.9,1.05,0.14,0.68,"cb6941")

func grain_fields():
	# Parallel furrows of dense, stepped barley heads.
	for lane in range(7):
		var x = -14.62+lane*1.52
		block(x,0.07,-11.75,1.08,0.12,8.4,"ae8d48")
		for j in range(13):
			var z = -15.55+j*0.64
			block(x,0.38,z,0.72,0.62,0.45,"c5a348")
			block(x+0.08*sin(j+lane),0.84,z,0.66,0.37,0.43,"dfbb56" if (j+lane)%3 else "d3a243")
	for z in [-13.5,-9.6]:
		block(-19.32,1.95,z,2.46,3.90,2.46,"abb8ac")
		for h in [0.45,1.55,2.70,3.71]: block(-19.32,h,z,2.58,0.14,2.58,"74888a")
		for i in range(3): block(-19.32,4.0+i*0.22,z,2.76-i*0.64,0.24,2.76-i*0.64,"627d81")

func horse_yard():
	# Close the rectangle between the grain field, homestead and eastern nursery.
	land(8.525,-11.775,24.05,10.45,"88ad68")
	block(8.525,0.046,-7.47,24.05,0.08,1.58,"cbb583")
	block(2.55,0.049,-12.20,1.36,0.08,9.60,"cbb583")
	block(14.55,0.05,-6.98,1.38,0.08,0.96,"cbb583")
	# Three open stalls under a long sage roof, with cream fascias and half doors.
	block(0.04,1.12,-15.82,5.80,2.24,0.17,"aa7751")
	for i in range(4):
		var x = -2.86+i*1.93
		block(x,1.10,-14.40,0.16,2.20,2.90,"b2835c")
		block(x,1.18,-12.94,0.19,2.36,0.21,"e6d5af")
	for i in range(3):
		var x = -1.90+i*1.93
		block(x,0.43,-12.95,1.72,0.86,0.14,"98633e")
		for y in [0.20,0.78]: block(x,y,-12.86,1.70,0.09,0.08,"dfc99d")
		block(x,1.86,-15.68,0.87,0.48,0.13,"655744")
	block(0.04,2.28,-12.93,5.99,0.18,0.23,"e9d8b4")
	for i in range(4):
		block(0.04,2.42+i*0.20,-14.40,6.35,0.23,3.58-i*0.85,"597d74")
	for i in range(3):
		var x = -2.26+i*1.1
		block(x,0.33,-10.37,1.03,0.64,0.87,"dcad53")
		block(x,0.33,-10.37,0.10,0.66,0.89,"a07841")
	# Leave an opening at the south rail for the lane.
	for x in [4.1,6.7,9.3,11.9,14.5,17.1,19.7]:
		for z in [-16.25,-8.55]: block(x,0.68,z,0.17,1.36,0.17,"bfa47e")
	for y in [0.58,1.08]:
		block(11.90,y,-16.25,15.62,0.14,0.11,"dfc89f")
		block(8.00,y,-8.55,7.80,0.14,0.11,"dfc89f")
		block(17.10,y,-8.55,5.20,0.14,0.11,"dfc89f")
		for x in [4.1,19.7]: block(x,y,-12.40,0.11,0.14,7.70,"dfc89f")
	for x in [4.1,19.7]:
		for z in [-13.68,-11.12]: block(x,0.68,z,0.17,1.36,0.17,"bfa47e")
	block(17.4,0.30,-15.5,2.40,0.58,0.72,"927255")
	block(17.4,0.60,-15.5,2.18,0.045,0.53,"77b6bb")
	horse(Vector3(7.55,0,-13.65),"a36242","57433a")
	horse(Vector3(12.24,0,-10.64),"d4ae7b","ebe1bf")
	horse(Vector3(16.50,0,-13.10),"74534b","443b39")

func horse(home: Vector3, coat: String, mane: String):
	var actor = Node3D.new()
	add_child(actor)
	part(actor,Vector3(0,1.18,0),Vector3(1.50,0.69,0.60),coat)
	var tail = part(actor,Vector3(-0.80,1.04,0),Vector3(0.23,0.85,0.26),mane)
	tail.rotation.z = -0.19
	var legs = []
	for x in [-0.52,0.50]:
		for z in [-0.21,0.21]:
			var leg = Node3D.new()
			actor.add_child(leg)
			leg.position = Vector3(x,0.94,z)
			part(leg,Vector3(0,-0.33,0),Vector3(0.20,0.70,0.19),coat)
			part(leg,Vector3(0,-0.76,0),Vector3(0.17,0.26,0.17),"dbcba8")
			part(leg,Vector3(0.02,-0.88,0),Vector3(0.22,0.13,0.20),"514940")
			legs.append(leg)
	var neck = Node3D.new()
	actor.add_child(neck)
	neck.position = Vector3(0.55,1.35,0)
	part(neck,Vector3(0.20,0.31,0),Vector3(0.37,0.86,0.38),coat).rotation.z = -0.38
	part(neck,Vector3(0.01,0.42,0),Vector3(0.16,0.77,0.38),mane).rotation.z = -0.38
	part(neck,Vector3(0.45,0.71,0),Vector3(0.54,0.42,0.40),coat)
	part(neck,Vector3(0.75,0.60,0),Vector3(0.27,0.26,0.34),coat)
	part(neck,Vector3(0.73,0.75,0),Vector3(0.32,0.07,0.12),"eee0c0")
	for side in [-1,1]:
		part(neck,Vector3(0.30,0.99,side*0.13),Vector3(0.12,0.23,0.12),coat)
		part(neck,Vector3(0.51,0.76,side*0.205),Vector3(0.085,0.085,0.03),"312f30")
	horses.append({"actor":actor,"home":home,"legs":legs,"neck":neck,"tail":tail})

func pasture():
	for x in range(-21,-5,2):
		for z in [13.27,17.90]: block(x,0.52,z,0.15,1.04,0.16,"c0a077")
	block(-14,0.66,17.90,14.2,0.12,0.10,"cfb88a")
	block(-17.95,0.66,13.27,6.15,0.12,0.10,"cfb88a")
	block(-10,0.66,13.27,6.10,0.12,0.10,"cfb88a")
	for x in [-21,-7]:
		block(x,0.66,15.57,0.12,0.12,4.65,"cfb88a")
		block(x,0.53,15.6,0.16,1.06,0.16,"c0a077")
	for i in range(5):
		var actor = Node3D.new()
		add_child(actor)
		var body = Vector3(1.05,0.72,0.77)
		part(actor,Vector3(0,0.75,0),body,"f2e8ce")
		part(actor,Vector3(-0.10,1.12,0),Vector3(0.77,0.14,0.60),"f6efd9")
		for x in [-0.33,0.33]:
			for z in [-0.23,0.23]: part(actor,Vector3(x,0.22,z),Vector3(0.16,0.44,0.15),"5a5249")
		var neck = Node3D.new()
		actor.add_child(neck)
		neck.position = Vector3(0.48,0.81,0)
		part(neck,Vector3(0.18,0,0),Vector3(0.45,0.42,0.44),"70615a")
		part(neck,Vector3(0.12,0.22,0),Vector3(0.45,0.18,0.49),"e4dcc7")
		for side in [-1,1]:
			part(neck,Vector3(0.08,0.06,side*0.29),Vector3(0.17,0.14,0.19),"786c61")
			part(neck,Vector3(0.30,0.05,side*0.22),Vector3(0.065,0.07,0.04),"302f35")
		sheep.append({"actor":actor,"neck":neck,"home":Vector3(-19.65+i*2.72,0,14.68+(i%2)*1.6)})

func market():
	for i in range(3):
		var x = -3.8+i*3.16
		for dx in [-1.12,1.12]:
			for z in [14.0,15.72]: block(x+dx,1.04,z,0.15,2.08,0.15,"89633d")
		block(x,0.45,14.9,2.40,0.9,1.38,"ad8152")
		for stripe in range(6):
			var dye = ["bd6655","578d83","c49e4e"][i] if stripe%2==0 else "f1dfae"
			block(x-1.16+stripe*0.46,2.16,14.85,0.46,0.18,2.25,dye)
			block(x-1.16+stripe*0.46,2.02,15.94,0.46,0.27,0.13,dye)
		for bin in range(3):
			block(x-0.76+bin*0.76,1.02,15.24,0.66,0.21,0.52,["be6950","83a54d","d4a748"][bin])

func apiary():
	for i in range(3):
		var x = 8.2+i*3.75
		block(x,0.22,15.3,1.26,0.44,1.16,"8a7258")
		for tier in range(3):
			block(x,0.59+tier*0.32,15.3,1.52,0.29,1.27,"dba957" if tier!=1 else "e8bb68")
		block(x,1.48,15.3,1.72,0.18,1.47,"758f89")
		block(x,0.51,15.97,0.70,0.095,0.10,"705738")
		block(x,0.43,16.08,1.10,0.11,0.43,"b78d58")
		var bee = Node3D.new()
		add_child(bee)
		part(bee,Vector3.ZERO,Vector3(0.22,0.15,0.14),"e8b341")
		part(bee,Vector3(0.035,0,0),Vector3(0.06,0.16,0.15),"554737")
		part(bee,Vector3(0,0.09,0),Vector3(0.10,0.045,0.30),"dbe9da")
		bees.append(bee)
	for i in range(34):
		var x = 5.9+fmod(i*2.37,13.65)
		var z = 16.74+0.81*sin(i*2.11)
		block(x,0.19,z,0.08,0.38,0.08,"65884d")
		block(x,0.41,z,0.25,0.15,0.22,["c78baf","e2b951","e9debb"][i%3])

func watermill():
	block(11.48,1.62,10.59,3.66,3.24,2.43,"e0c89f")
	for x in [9.72,11.48,13.24]: block(x,1.6,11.82,0.15,3.20,0.12,"835f49")
	block(11.48,2.0,11.85,3.70,0.17,0.14,"835f49")
	block(11.52,0.86,11.87,0.86,1.72,0.12,"876344")
	for i in range(5): block(11.48,3.24+i*0.19,10.59,4.03,0.21,3.12-i*0.50,"697e83")
	block(12.74,4.06,10.40,0.53,1.53,0.54,"957c69")
	wheel.position = Vector3(13.64,1.18,9.35)
	add_child(wheel)
	for i in range(12):
		var spoke = Node3D.new()
		wheel.add_child(spoke)
		spoke.rotation.x = TAU*i/12
		part(spoke,Vector3(0,0.59,0),Vector3(0.20,1.18,0.10),"866442")
		part(spoke,Vector3(0,1.21,0),Vector3(0.74,0.18,0.57),"b88656")
	part(wheel,Vector3.ZERO,Vector3(0.90,0.28,0.28),"725740")

func _process(delta):
	elapsed += delta
	wheel.rotation.x = fmod(elapsed*0.57,TAU)
	for i in horses.size():
		var h = horses[i]
		var t = elapsed*0.34+i*2.15
		var stride = clampf(sin(t)*1.45,-1,1)
		var walking = absf(stride)<0.995
		var gait = sin(t*14)
		h.actor.position = h.home+Vector3(stride*1.16,absf(gait)*0.04 if walking else 0,stride*0.27)
		h.actor.rotation.y = lerp_angle(h.actor.rotation.y,-0.23 if cos(t)>0 else PI-0.23,1-exp(-delta*3))
		h.neck.rotation.z = lerpf(h.neck.rotation.z,0.04*gait if walking else -1.25+0.14*sin(2*elapsed+i),1-exp(-delta*4))
		h.tail.rotation.x = 0.24*sin(elapsed*2.2+i)
		for leg in range(4):
			h.legs[leg].rotation.z = (0.28 if leg in [0,3] else -0.28)*gait if walking else 0.0
	for i in bees.size():
		var t = elapsed*1.4+i
		bees[i].position = Vector3(8.2+i*3.75+0.85*sin(t),0.89+0.30*cos(2*t),16.15+0.74*cos(t))
	for i in sheep.size():
		var animal = sheep[i]
		var phase = elapsed*0.40+i*1.72
		var stride = clampf(sin(phase)*1.5,-1,1)
		var walking = absf(stride)<0.99
		animal.actor.position = animal.home+Vector3(stride*0.63,absf(sin(phase*18))*0.045 if walking else 0,0)
		animal.actor.rotation.y = lerp_angle(animal.actor.rotation.y,0.32 if cos(phase)>0 else PI+0.28,1-exp(-delta*3))
		animal.neck.rotation.z = -0.09 if walking else -0.63+0.16*sin(elapsed*2.3+i)
