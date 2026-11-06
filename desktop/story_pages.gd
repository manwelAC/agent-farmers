extends RefCounted

# Keep passages in document order. Headings start chapters; long paragraphs
# break at sentence or word boundaries without generating new claims.
static func passages(text: String) -> Array:
	var result = []
	var heading = ""
	var prose = ""
	var fenced = false
	for line in text.replace("\r\n","\n").split("\n"):
		var clean = line.strip_edges()
		if clean.begins_with("```"): fenced = not fenced
		if not fenced and clean.begins_with("#") and clean.lstrip("#").begins_with(" "):
			if not prose.strip_edges().is_empty():
				result.append({"heading":heading,"body":prose.strip_edges()})
				prose=""
			heading=clean.lstrip("#").strip_edges()
			continue
		if prose.length()>150 and (clean.is_empty() or prose.length()+line.length()>440):
			result.append({"heading":heading,"body":prose.strip_edges()})
			prose=""
		prose+=line+"\n"
		while prose.length()>540:
			var split_at = prose.rfind(". ",460)
			if split_at<100: split_at=prose.rfind(" ",460)
			if split_at<1: split_at=459
			result.append({"heading":heading,"body":prose.left(split_at+1).strip_edges()})
			prose=prose.substr(split_at+1)
	if not prose.strip_edges().is_empty() or result.is_empty():
		result.append({"heading":heading,"body":prose.strip_edges()})
	return result
# Adapt report scaffolding into spoken prose. Keep names, quantities, caveats
# and quotations from the file; Rowan attributes the material to the crew.
static func dialogue(passage: Dictionary, index: int, previous_heading: String) -> String:
	var heading = str(passage.heading).strip_edges()
	var lines = PackedStringArray()
	var link = RegEx.create_from_string(r"\[([^\]]+)\]\([^)]+\)")
	var prefix = RegEx.create_from_string(r"^(?:[-*]|\d+[.)])\s+")
	for raw in str(passage.body).split("\n"):
		var line = raw.strip_edges()
		if line.is_empty() or line.begins_with("```"): continue
		line = link.sub(line,"$1",true).replace("**","").replace("`","")
		line = prefix.sub(line,"")
		if line.begins_with("\\[") and line.ends_with("\\]"):
			line = line.substr(2,line.length()-4).replace("\\times"," times ").replace("\\%","%")
		for pair in [["Limitations:","Here’s where I’d be careful:"],["Source:","I’ll point you to the source:"],["Sources:","Let me show you where this came from:"],["Findings:","Here’s what the crew found:"],["Conclusion:","Here’s what I’d take away:"],["Objective:","Let me start with the goal:"]]:
			if line.begins_with(pair[0]):
				line = pair[1]+line.substr(pair[0].length())
				break
		lines.append(line)
	var lead = ""
	if index==0:
		lead = "Let me tell you about “"+heading+"”." if not heading.is_empty() else "Come closer. Let me tell you what the crew brought back."
	elif heading!=previous_heading and not heading.is_empty():
		lead = "Now, let me take you to “"+heading+"”."
	elif not lines.is_empty() and not lines[0].begins_with("I’ll") and not lines[0].begins_with("Here’s"):
		lead = ["There’s another detail I want to share.","Let me pick up the thread here.","Here’s what comes next."][index%3]
	if not lead.is_empty(): lines.insert(0,lead)
	return "\n\n".join(lines)
