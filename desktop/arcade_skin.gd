extends RefCounted
## Nine-slice pixel artwork. Only the flat middle stretches with a control.
static var textures = {}

static func box(face: String, rim: String, depth: String, highlight: String, large: bool=false) -> StyleBoxTexture:
	var key = [face,rim,depth,highlight,large]
	var side = 48 if large else 24
	var cut = 11 if large else 4
	var bevel = 7 if large else 3
	if not textures.has(key):
		var image = Image.create_empty(side,side,false,Image.FORMAT_RGBA8)
		for y in side:
			for x in side:
				var offset = maxi(0,cut-mini(y,side-1-y))
				if x<offset or x>=side-offset: continue
				var edge = mini(mini(x-offset,side-1-x-offset),mini(y,side-1-y))
				var color = Color(face).lerp(Color(highlight),0.13*(1.0-float(y)/(side-1)))
				if edge<2: color=Color(rim)
				elif y>=side-bevel-2 or x>=side-offset-3: color=Color(depth)
				elif edge<4: color=Color(highlight)
				elif large and edge<bevel: color=Color(depth).lightened(0.24)
				image.set_pixel(x,y,color)
		textures[key]=ImageTexture.create_from_image(image)
	var style = StyleBoxTexture.new()
	style.texture=textures[key]
	for margin in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(margin,cut+bevel+2)
		style.set_content_margin(margin,16 if large else 9 if margin in [SIDE_LEFT,SIDE_RIGHT] else 6)
	return style

static func button(control: Button, face: String, edge: String, ink: String="18253e"):
	for state in ["normal","hover","pressed","disabled"]:
		var fill = Color(face)
		if state=="hover": fill=fill.lightened(0.16)
		if state=="pressed": fill=fill.darkened(0.10)
		if state=="disabled": fill=Color("c8cbd4")
		control.add_theme_stylebox_override(state,box(fill.to_html(false),"192c4a",edge,fill.lightened(0.48).to_html(false)))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		control.add_theme_color_override(state,Color(ink))
	control.add_theme_font_size_override("font_size",17)
	control.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
