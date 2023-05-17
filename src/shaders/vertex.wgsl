@group(0) @binding(0) var<uniform> grid: vec2<u32>;

@vertex
fn vertexMain(
  @location(0) pos: vec2<f32>,
  @builtin(instance_index) instance: u32,
) -> @builtin(position) vec4<f32> {
  let i = f32(instance);
  let grid_f = vec2<f32>(grid);
  let cell = vec2<f32>(i % grid_f.x, floor(i / grid_f.x));
  let cell_offset = cell / grid_f * 2;
  let grid_pos = (pos + 1) / grid_f - 1 + cell_offset;
  return vec4(grid_pos, 0, 1); // (X, Y, Z, W)
}
