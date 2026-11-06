extends RefCounted

# Deliberately small sprites: each square stays crisp at desktop HUD scale.
const COLORS = {"d":"263e49","w":"fff2cf","g":"93cc51","l":"d0ec80","b":"c58b54","y":"ffd15e","o":"ed9a46","r":"ec7454","t":"6abec5","s":"9ca9d8"}
const SPRITES = {
	"Save":["............",".ddddddddd..",".dwwwddwsdd.",".dwwwddwsdd.",".dwwwwwwsdd.",".dsssssssdd.",".ddwwwwwddd.",".ddwssswddd.",".ddwwwwwddd.",".dddddddddd."],
	"Farm":["....rr......","...rrrr.....","..rrrrrr....",".rrrrrrrr...","..owwwwo....","..owddwo..g.","..owddwo.gg.","llllllllllll",".gggggggggg.","..bbbbbbbb.."],
	"Projects":["............","..yyyy......",".yyyyyyooo..",".ywwwwwwwo..",".ywwwwwwwo..",".yyyyyyyyyy.",".yooooooooy.",".yooooooooy.",".oooooooooo.","............"],
	"Workers":["....yyyy....","...yyyyyy...","..oooooooo..","....wwww....","....dwwd....","....wwww....","...tbtbtb...", "..wttttttw..","...tttttt...","...dd..dd..."],
	"Connections":[".......tt...","......t..t..",".....t..tt..","....t..tt...","...ttytt....","....tyyt....","...yy..y....","..yy..y.....","..y..y......","...yy......."],
	"Results":[".....yy.....",".....yy.....","...yyyyyy...","....yyyy....",".....yy.....","............","..tt....tt..","..tt....tt..","..tttttttt..","..dddddddd.."],
	"Memory":["............","..sssssss...","..swwwwwws..","..swwwwwws..","..swwddwws..","..swwwwwws..","..swwddwws..","..swwwwwws..","..ssssssss..","...ddddddd.."],
	"Overview":["....yyyy....","...yy..yy...",".......yy...","......yy....",".....yy.....",".....yy.....","............",".....yy.....",".....yy.....","............"]
}
static func texture(route: String, palette: Dictionary = {}) -> Texture2D:
	var rows = SPRITES[route]
	var bitmap = Image.create_empty(12,12,false,Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var pixel = rows[y][x]
			if COLORS.has(pixel): bitmap.set_pixel(x,y+1,Color(palette.get(pixel,COLORS[pixel])))
	bitmap.resize(36,36,Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(bitmap)
