struct VertexInput {
  @location(0) pos: vec2<f32>,
  @builtin(instance_index) instance: u32,
}

struct VertexOutput {
  @builtin(position) pos: vec4<f32>,
  @location(0) cell: vec2<f32>,
}

@group(0) @binding(0) var<uniform> grid: vec2<u32>;

@vertex
fn vertexMain(input: VertexInput) -> VertexOutput {
  let i = f32(input.instance);
  let grid_f = vec2<f32>(grid);
  let cell = vec2<f32>(i % grid_f.x, floor(i / grid_f.x));
  let cell_offset = cell / grid_f * 2;
  let grid_pos = (input.pos + 1) / grid_f - 1 + cell_offset;

  var output: VertexOutput;
  output.pos = vec4(grid_pos, 0, 1);
  output.cell = cell;
  return output;
}

@fragment
fn fragmentMain(input: VertexOutput) -> @location(0) vec4<f32> {
  let grid_f = vec2<f32>(grid);
  let col = input.cell / grid_f;
  return vec4(col, 1 - col.x, 1); // (R, G, B, A)
}
