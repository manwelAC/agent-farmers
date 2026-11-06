extends VBoxContainer
## Display worker prose as a report without rewriting the stored reply.
var sources: Array[String] = []
var titles: Array[String] = []
var link_pattern = RegEx.create_from_string(r"\[([^\]\n]+)\]\((https?://[^\s<>]+?)\)(?=[\s.,;:!?)]|$)|(https?://[^\s<>\x22]+)")
var sentence_end = RegEx.create_from_string(r"[.!?][’”\x22)]*\s+(?=[A-Z0-9(])")
var inline_style = RegEx.create_from_string(r"(\*\*([^*\n]+)\*\*|`([^`\n]+)`|〔(\d+)〕)")
var body_font = SystemFont.new()

func display(source: String):
	body_font.font_names = PackedStringArray(["Segoe UI","Arial"])
	body_font.font_weight = 400
	add_theme_constant_override("separation",12)
	var first = true
	var code_block = false
	for line in source.replace("\r\n","\n").split("\n"):
		if line.strip_edges().begins_with("```"):
			code_block = not code_block
			continue
		if code_block:
			var code = text_block(15)
			code.push_mono()
			code.add_text(line)
			continue
		var plain = line.strip_edges()
		if plain.begins_with("\\[") and plain.ends_with("\\]"):
			plain=plain.substr(2,plain.length()-4).replace("\\times","×").replace("\\%","%")
		var clean = citations(plain)
		if clean.is_empty(): continue
		var heading = clean.begins_with("#") and clean.lstrip("#").begins_with(" ")
		if heading: clean = clean.lstrip("#").strip_edges()
		if clean.begins_with("- ") or clean.begins_with("* "): clean = "•  "+clean.substr(2)
		var paragraphs = readable_paragraphs(clean,first)
		for paragraph in paragraphs:
			var label = text_block(22 if first or heading else 18)
			if first or heading: label.push_bold()
			write_inline(label,paragraph)
			first = false
	if sources.is_empty(): return
	add_child(HSeparator.new())
	var caption = text_block(15)
	caption.push_bold()
	caption.add_text("Sources")
	for i in sources.size():
		var link = text_block(16)
		link.push_color(Color("256c68"))
		link.push_meta(sources[i],RichTextLabel.META_UNDERLINE_ON_HOVER,sources[i])
		link.add_text("[%d]  %s  ↗"%[i+1,titles[i]])
		link.pop()
		link.pop()

func text_block(font_size: int) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.add_theme_font_override("normal_font",body_font)
	label.add_theme_font_size_override("normal_font_size",font_size)
	label.add_theme_font_size_override("bold_font_size",font_size)
	label.add_theme_color_override("default_color",Color("253f46"))
	label.add_theme_constant_override("line_separation",4)
	label.meta_clicked.connect(func(uri): OS.shell_open(str(uri)))
	add_child(label)
	return label

func citations(line: String) -> String:
	var result = ""
	var offset = 0
	for hit in link_pattern.search_all(line):
		var before = line.substr(offset,hit.get_start()-offset)
		var uri = hit.get_string(2)
		var title = hit.get_string(1)
		var tail = ""
		if uri.is_empty():
			uri = hit.get_string(3)
			while not uri.is_empty() and (uri.right(1) in [".",",",";",":","!","?"] or (uri.ends_with(")") and uri.count(")")>uri.count("("))):
				tail=uri.right(1)+tail
				uri=uri.left(-1)
		var host = uri.split("://",true,1)[1].get_slice("/",0).get_slice("?",0).get_slice("#",0)
		if host.is_empty() or host.contains("@"):
			result += before+hit.get_string()
		else:
			var idx = sources.find(uri)
			if idx<0:
				idx=sources.size()
				sources.append(uri)
				titles.append(title if not title.is_empty() else host.trim_prefix("www."))
			if before.ends_with("Source: "):
				before=before.left(-8)
				if before.ends_with(". ") and tail.begins_with("."): before=before.left(-2)+" "
			result += before+(title+" " if not title.is_empty() else "")+"〔%d〕"%(idx+1)+tail
		offset=hit.get_end()
	return result+line.substr(offset)

func readable_paragraphs(line: String, first: bool) -> Array[String]:
	var paragraphs: Array[String] = []
	var start = 0
	for boundary in sentence_end.search_all(line):
		var end = boundary.get_end()
		var piece = line.substr(start,end-start).strip_edges()
		# Keep inline citations next to the sentence they support.
		if line.substr(end).begins_with("〔"): continue
		if piece.length()<48 or piece.ends_with("e.g.") or piece.ends_with("i.e."): continue
		if (first and paragraphs.is_empty() and line.length()>160) or piece.ends_with("〕.") or piece.length()>=210:
			paragraphs.append(piece)
			start=end
	if start<line.length(): paragraphs.append(line.substr(start))
	return paragraphs

func write_inline(label: RichTextLabel, value: String):
	var offset = 0
	for token in inline_style.search_all(value):
		label.add_text(value.substr(offset,token.get_start()-offset))
		if token.get_string(2)!="":
			label.push_bold()
			label.add_text(token.get_string(2))
		elif token.get_string(3)!="":
			label.push_mono()
			label.add_text(token.get_string(3))
		else:
			var i = int(token.get_string(4))-1
			if i<0 or i>=sources.size():
				label.add_text(token.get_string())
				offset=token.get_end()
				continue
			label.push_meta(sources[i],RichTextLabel.META_UNDERLINE_ON_HOVER,sources[i])
			label.add_text("[%d]"%(i+1))
		label.pop()
		offset=token.get_end()
	label.add_text(value.substr(offset))
