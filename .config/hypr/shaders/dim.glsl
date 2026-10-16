#version 300 es
precision highp float;

in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    // Multiply by 0.5 to darken by 50% (lower value = darker)
    fragColor = vec4(pixColor.rgb * 0.5, pixColor.a);
}
