extends Control
## Soft sky and low, stepped cloud banks behind the interactive 3D island.
func _draw():
	var corners = PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
	var top = Color("83cfd7")
	var bottom = Color("d4f0da")
	draw_polygon(corners,PackedColorArray([top,top,bottom,bottom]))
	for cloud in [[0.12,0.32,1.0],[0.73,0.13,0.72],[0.93,0.41,1.3],[0.16,0.74,0.65],[0.76,0.79,0.48],[-0.02,0.57,0.58]]:
		var p = size * Vector2(cloud[0],cloud[1])
		var s = cloud[2] * clampf(size.x/1380,0.75,1.45)
		for block in [Rect2(-42,0,96,10),Rect2(-30,-8,70,12),Rect2(-12,-16,30,16)]:
			draw_rect(Rect2(p + block.position*s,block.size*s),Color("dff4e8"))

