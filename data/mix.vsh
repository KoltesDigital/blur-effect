#version 330

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;

out vec2 texCoord;
out vec2 fragCoord;

uniform vec2 resolution;

void main(void) {
	gl_Position = vec4(position, 0, 1);
	texCoord = uv;
	fragCoord = uv * resolution;
}