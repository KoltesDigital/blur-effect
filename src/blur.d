/**
 * This is a small project testing
 * - Derelict3 (https://github.com/aldacron/Derelict3)
 * - OpenGL 3+ API (http://www.opengl.org/registry/)
 * - Multipass post-processing effect via shaders and render-to-texture
 * - D builder for SCons
 * - SCons targets
 *
 * Author: Bloutiouf
 * Copyright: Public Domain.
 */
module blur;

import std.string;
import std.conv;
import std.stdio;
import std.file;
import std.math;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import derelict.devil.il;
import derelict.devil.ilu;
import derelict.devil.ilut;

/// Asset path.
immutable string data = "data/";

/// Screen resolution.
immutable int width = 512;
immutable int height = 512; /// ditto
immutable float[2] resolution = [width, height]; /// ditto

/// Shader attributes.
immutable int positionAttribute = 0;
immutable int uvAttribute = 1;

/// Objects for the quad.
uint quadVA, quadVB, quadUVB, quadIB;

/// Shaders.
uint blurVS, hBlurFS, vBlurFS, mixVS, mixFS;

/// Shader programs.
uint hBlurProgram, vBlurProgram, mixProgram;

/// Shader uniforms.
int hBlurTextureUniform, hBlurResolutionUniform,
	vBlurTextureUniform, vBlurResolutionUniform,
	mixInitialTextureUniform, mixBlurredTextureUniform,
	mixResolutionUniform, mixMouseUniform, mixSigmaUniform;

/// Textures.
uint initialTexture, hBlurTexture, vBlurTexture;

/// Framebuffers.
uint hBlurFB, vBlurFB;

/// Factors for gaussian blur.
immutable float sigmaBase = 1.5f;
float sigmaExponent = 10; /// ditto
float sigma; /// ditto

/// Creates the quad used to display a texture on screen... actually a triangle.
void createQuad() {
	// Triangle configuration
	float[6] vertices = [
		-1, -1,
		3, -1,
		-1, 3
	];

	float[6] uvs = [
		0, 0,
		2, 0,
		0, 2
	];

	ushort[3] indices = [0, 1, 2];

	// Vertex Array, retains states to easily use them
	glGenVertexArrays(1, &quadVA);
	assert(!glGetError());
	glBindVertexArray(quadVA);
	assert(!glGetError());

	// Vertex Buffer, holds the vertices' coordinates
	glGenBuffers(1, &quadVB);
	assert(!glGetError());
	glBindBuffer(GL_ARRAY_BUFFER, quadVB);
	assert(!glGetError());
	glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof, vertices.ptr, GL_STATIC_DRAW);
	assert(!glGetError());
	glVertexAttribPointer(positionAttribute, 2, GL_FLOAT, GL_FALSE, 0, null);
	assert(!glGetError());
	glEnableVertexAttribArray(positionAttribute);
	assert(!glGetError());

	// UV Buffer, holds the UV coordinates (related to the vertices)
	glGenBuffers(1, &quadUVB);
	assert(!glGetError());
	glBindBuffer(GL_ARRAY_BUFFER, quadUVB);
	assert(!glGetError());
	glBufferData(GL_ARRAY_BUFFER, uvs.length * float.sizeof, uvs.ptr, GL_STATIC_DRAW);
	assert(!glGetError());
	glVertexAttribPointer(uvAttribute, 2, GL_FLOAT, GL_FALSE, 0, null);
	assert(!glGetError());
	glEnableVertexAttribArray(uvAttribute);
	assert(!glGetError());

	// Index Buffer, holds vertices' indexes in drawing order
	glGenBuffers(1, &quadIB);
	assert(!glGetError());
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadIB);
	assert(!glGetError());
	glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * ushort.sizeof, indices.ptr, GL_STATIC_DRAW);
	assert(!glGetError());
}

/// Deletes the quad.
void deleteQuad() {
	glBindVertexArray(0);
	assert(!glGetError());

	glDeleteBuffers(1, &quadIB);
	assert(!glGetError());
	glDeleteBuffers(1, &quadUVB);
	assert(!glGetError());
	glDeleteBuffers(1, &quadVB);
	assert(!glGetError());
	glDeleteVertexArrays(1, &quadVA);
	assert(!glGetError());
}

/**
 * Creates a shader.
 * Params:
 *  type = shader type (GL_VERTEX_SHADER, GL_FRAGMENT_SHADER...)
 *  filename = asset name in data directory
 * Returns: OpenGL handle
 */
uint loadShader(uint type, string filename) {
	uint shader = glCreateShader(type);
	assert(!glGetError());

	char[] source = readText!(char[])(data ~ filename);
	char* sourcePtr = source.ptr;
	glShaderSource(shader, 1, &sourcePtr, null);
	assert(!glGetError());

	glCompileShader(shader);
	assert(!glGetError());

	char[256] infoBuffer;
	int infoLength;

	glGetShaderInfoLog(shader, infoBuffer.length, &infoLength, infoBuffer.ptr);
	assert(!infoLength, to!string(infoBuffer.ptr));

	return shader;
}

/**
 * Creates a shader program.
 * Params:
 *  vertexShader = handle to vertex shader
 *  fragmentShader = handle to fragment shader
 * Returns: OpenGL handle
 */
uint createShaderProgram(uint vertexShader, uint fragmentShader) {
	uint program = glCreateProgram();
	assert(!glGetError());

	glAttachShader(program, vertexShader);
	assert(!glGetError());

	glAttachShader(program, fragmentShader);
	assert(!glGetError());

	glLinkProgram(program);
	assert(!glGetError());

	char[256] infoBuffer;
	int infoLength;

	glGetProgramInfoLog(program, infoBuffer.length, &infoLength, infoBuffer.ptr);
	assert(!infoLength, to!string(infoBuffer.ptr));

	int isLinked;
	glGetProgramiv(program, GL_LINK_STATUS, &isLinked);
	assert(isLinked);

	return program;
}

/// Creates shaders.
void createShaders() {
	// Load the shaders
	blurVS = loadShader(GL_VERTEX_SHADER, "blur.vsh");
	hBlurFS = loadShader(GL_FRAGMENT_SHADER, "hBlur.fsh");
	vBlurFS = loadShader(GL_FRAGMENT_SHADER, "vBlur.fsh");
	mixVS = loadShader(GL_VERTEX_SHADER, "mix.vsh");
	mixFS = loadShader(GL_FRAGMENT_SHADER, "mix.fsh");

	// and create programs with them. BTW, set constants now

	// First pass
	hBlurProgram = createShaderProgram(blurVS, hBlurFS);
	hBlurTextureUniform = glGetUniformLocation(hBlurProgram, "texture");
	assert(hBlurTextureUniform >= 0);
	hBlurResolutionUniform = glGetUniformLocation(hBlurProgram, "resolution");
	assert(hBlurResolutionUniform >= 0);

	glUseProgram(hBlurProgram);
	assert(!glGetError());
	glUniform1i(hBlurTextureUniform, 0);
	assert(!glGetError());
	glUniform2fv(hBlurResolutionUniform, 1, resolution.ptr);
	assert(!glGetError());

	// Second pass
	vBlurProgram = createShaderProgram(blurVS, vBlurFS);
	vBlurTextureUniform = glGetUniformLocation(vBlurProgram, "texture");
	assert(vBlurTextureUniform >= 0);
	vBlurResolutionUniform = glGetUniformLocation(vBlurProgram, "resolution");
	assert(vBlurResolutionUniform >= 0);

	glUseProgram(vBlurProgram);
	assert(!glGetError());
	glUniform1i(vBlurTextureUniform, 0);
	assert(!glGetError());
	glUniform2fv(vBlurResolutionUniform, 1, resolution.ptr);
	assert(!glGetError());

	// Third pass
	mixProgram = createShaderProgram(mixVS, mixFS);
	mixInitialTextureUniform = glGetUniformLocation(mixProgram, "initialTexture");
	assert(mixInitialTextureUniform >= 0);
	mixBlurredTextureUniform = glGetUniformLocation(mixProgram, "blurredTexture");
	assert(mixBlurredTextureUniform >= 0);
	mixResolutionUniform = glGetUniformLocation(mixProgram, "resolution");
	assert(mixResolutionUniform >= 0);
	mixMouseUniform = glGetUniformLocation(mixProgram, "mouse");
	assert(mixMouseUniform >= 0);
	mixSigmaUniform = glGetUniformLocation(mixProgram, "sigma");
	assert(mixSigmaUniform >= 0);

	glUseProgram(mixProgram);
	assert(!glGetError());
	glUniform1i(mixInitialTextureUniform, 0);
	assert(!glGetError());
	glUniform1i(mixBlurredTextureUniform, 1);
	assert(!glGetError());
	glUniform2fv(mixResolutionUniform, 1, resolution.ptr);
	assert(!glGetError());
}

/// Deletes shaders.
void deleteShaders() {
	glDeleteProgram(mixProgram);
	assert(!glGetError());
	glDeleteProgram(vBlurProgram);
	assert(!glGetError());
	glDeleteProgram(hBlurProgram);
	assert(!glGetError());

	glDeleteShader(mixFS);
	assert(!glGetError());
	glDeleteShader(mixVS);
	assert(!glGetError());
	glDeleteShader(vBlurFS);
	assert(!glGetError());
	glDeleteShader(hBlurFS);
	assert(!glGetError());
	glDeleteShader(blurVS);
	assert(!glGetError());
}

/// Creates textures.
void createTextures() {
	// Initial texture comes from a file
	initialTexture = ilutGLLoadImage(cast(char*)toStringz(data ~ "texture.jpg"));
	assert(initialTexture >= 0);
	glGetError(); // ilutGLLoadImage behaves badly

	// Empty texture to render the first pass into
	glGenTextures(1, &hBlurTexture);
	assert(!glGetError());

	glBindTexture(GL_TEXTURE_2D, hBlurTexture);
	assert(!glGetError());

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	assert(!glGetError());

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, null);
	assert(!glGetError());

	// Empty texture to render the second pass into
	glGenTextures(1, &vBlurTexture);
	assert(!glGetError());

	glBindTexture(GL_TEXTURE_2D, vBlurTexture);
	assert(!glGetError());

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	assert(!glGetError());
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	assert(!glGetError());

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, null);
	assert(!glGetError());
}

/// Deletes textures.
void deleteTextures() {
	glDeleteTextures(1, &vBlurTexture);
	assert(!glGetError());
	glDeleteTextures(1, &hBlurTexture);
	assert(!glGetError());
	glDeleteTextures(1, &initialTexture);
	assert(!glGetError());
}

/// Creates framebuffers to render-to-texture.
void createFramebuffers() {
	// The shaders just output a color
	immutable GLenum buffers[1] = [GL_COLOR_ATTACHMENT0];

	// Framebuffer for the first pass
	glGenFramebuffers(1, &hBlurFB);
	assert(!glGetError());
    glBindFramebuffer(GL_FRAMEBUFFER, hBlurFB);
	assert(!glGetError());
    glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, hBlurTexture, 0);
	assert(!glGetError());
	glDrawBuffers(buffers.length, buffers.ptr);
	assert(!glGetError());

	assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);

	// Framebuffer for the second pass
	glGenFramebuffers(1, &vBlurFB);
	assert(!glGetError());
    glBindFramebuffer(GL_FRAMEBUFFER, vBlurFB);
	assert(!glGetError());
    glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, vBlurTexture, 0);
	assert(!glGetError());
	glDrawBuffers(buffers.length, buffers.ptr);
	assert(!glGetError());

	assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
}

/// Deletes framebuffers.
void deleteFramebuffers() {
	glDeleteFramebuffers(1, &vBlurFB);
	assert(!glGetError());
	glDeleteFramebuffers(1, &hBlurFB);
	assert(!glGetError());
}

/// Updates blur radius.
void updateSigma() {
	sigma = pow(sigmaBase, sigmaExponent);
}

/**
 * Changes blur radius.
 * To set as callback on scroll event.
 */
extern (C) void scrollCallback(GLFWwindow window, int x, int y) {
	sigmaExponent += y;
	updateSigma();
}

/// Program entry!
void main() {
	// Youou, we're going to have fun!
	DerelictGLFW3.load();
	DerelictIL.load();
	DerelictILU.load();
	DerelictILUT.load();
	DerelictGL3.load();

	assert(glfwInit());

	glfwOpenWindowHint(GLFW_WINDOW_RESIZABLE, false);
	glfwOpenWindowHint(GLFW_FSAA_SAMPLES, 4);
	glfwOpenWindowHint(GLFW_OPENGL_VERSION_MAJOR, 3);
	glfwOpenWindowHint(GLFW_OPENGL_VERSION_MINOR, 3);
	glfwOpenWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

	auto window = glfwOpenWindow(width, height, GLFW_WINDOWED, "Blur", null);
	assert(window);

	updateSigma();
	glfwSetScrollCallback(&scrollCallback);

	// Load OpenGL in earnest
	assert(DerelictGL3.reload() == 33);

	//writeln(to!string(glGetString(GL_SHADING_LANGUAGE_VERSION)));

	ilInit();
	iluInit();
	ilutRenderer(ILUT_OPENGL);

	ilutEnable(ILUT_OPENGL_CONV);

	glGetError(); // reset

	createTextures();
	createFramebuffers();
	createShaders();
	createQuad();

	// Some flashy color, in order to easily detect bugs
	glClearColor(1, 1, 0, 1);
	assert(!glGetError());

	while (true) {
		// I don't know whether it's the proper usage. API is changing
		glfwPollEvents();

		if (glfwGetKey(window, GLFW_KEY_ESC ) == GLFW_PRESS || !glfwIsWindow(window)) {
			break;
		}

		int mouseX, mouseY;
		glfwGetMousePos(window, &mouseX, &mouseY);

		// First pass: horizontal blur
		glBindFramebuffer(GL_FRAMEBUFFER, hBlurFB);
		assert(!glGetError());

		glClear(GL_COLOR_BUFFER_BIT);
		assert(!glGetError());

		glUseProgram(hBlurProgram);
		assert(!glGetError());

		glActiveTexture(GL_TEXTURE0);
		assert(!glGetError());
		glBindTexture(GL_TEXTURE_2D, initialTexture);
		assert(!glGetError());

		glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT, null);
		assert(!glGetError());

		// Second pass: vertical blur
		glBindFramebuffer(GL_FRAMEBUFFER, vBlurFB);
		assert(!glGetError());

		glClear(GL_COLOR_BUFFER_BIT);
		assert(!glGetError());

		glUseProgram(vBlurProgram);
		assert(!glGetError());

		glActiveTexture(GL_TEXTURE0);
		assert(!glGetError());
		glBindTexture(GL_TEXTURE_2D, hBlurTexture);
		assert(!glGetError());

		glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT, null);
		assert(!glGetError());

		// Third pass: mix of initial and blurred textures
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		assert(!glGetError());

		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		assert(!glGetError());

		glUseProgram(mixProgram);
		assert(!glGetError());

		glActiveTexture(GL_TEXTURE0);
		assert(!glGetError());
		glBindTexture(GL_TEXTURE_2D, initialTexture);
		assert(!glGetError());

		glActiveTexture(GL_TEXTURE1);
		assert(!glGetError());
		glBindTexture(GL_TEXTURE_2D, vBlurTexture);
		assert(!glGetError());

		glUniform2f(mixMouseUniform, mouseX, height - mouseY);
		assert(!glGetError());

		glUniform1f(mixSigmaUniform, sigma);
		assert(!glGetError());

		glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT, null);
		assert(!glGetError());

		glfwSwapBuffers();
	}

	// So long, and thanks for all the fish
	deleteQuad();
	deleteShaders();
	//deleteFramebuffers(); // buggy with Nvidia drivers? or simply wrong?
	deleteTextures();

	glfwTerminate();

	DerelictGL3.unload();
	DerelictILUT.unload();
	DerelictILU.unload();
	DerelictIL.unload();
	DerelictGLFW3.unload();
}
