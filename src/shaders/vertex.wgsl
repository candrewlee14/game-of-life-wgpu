@group(0) @binding(0) var<uniform> grid: vec2<f32>;

@vertex
fn vertexMain(@location(0) pos: vec2<f32>) -> 
@builtin(position) vec4<f32> {
  return vec4(pos, 0, 1); // (X, Y, Z, W)
}
