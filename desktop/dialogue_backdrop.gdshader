shader_type canvas_item;
render_mode unshaded;

uniform sampler2D farm_frame : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec3 farm = textureLod(farm_frame, SCREEN_UV, 2.35).rgb;
	COLOR = vec4(mix(farm, vec3(0.055, 0.115, 0.13), 0.62), 1.0);
}
