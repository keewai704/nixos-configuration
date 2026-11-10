vec4 window(vec2 uv) {
  vec4 c = umbriel_sample(uv);
  float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 rgb = mix(c.rgb, vec3(luma), 0.2);
  float sheen = pow(1.0 - clamp(uv.x * 0.35 + uv.y, 0.0, 1.0), 3.0) * 0.07;
  return vec4(rgb + vec3(sheen) * c.a, c.a);
}
