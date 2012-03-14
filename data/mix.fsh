#version 330

in vec2 texCoord;
in vec2 fragCoord;

out vec4 fragColor;

uniform sampler2D initialTexture;
uniform sampler2D blurredTexture;
uniform vec2 resolution;
uniform vec2 mouse;
uniform float sigma;

void main() {
	float d2 = (fragCoord.x - mouse.x) * (fragCoord.x - mouse.x) + (fragCoord.y - mouse.y) * (fragCoord.y - mouse.y);
	float factor = exp(-d2 / (2 * sigma * sigma));
	fragColor = mix(texture2D(initialTexture, texCoord), texture2D(blurredTexture, texCoord), factor);
}