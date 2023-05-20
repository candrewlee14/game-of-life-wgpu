@group(0) @binding(0) var<uniform> grid: vec2f;

fn cellIndex(idx: u32) -> vec2f {
  let i = f32(idx);
  let x = i % grid.x;
  let y = floor(i / grid.x);
  return vec2f(x, y);
}

struct VertexInput {
  @location(0) pos: vec2f,
  @builtin(instance_index) instance: u32,
}

struct VertexOutput {
  @builtin(position) pos: vec4f,
  @location(0) cell: vec2f,
}

@vertex
fn vertexMain(
  input: VertexInput,
) -> VertexOutput {
  let cell = cellIndex(input.instance);
  let cellOffset = cell / grid * 2;
  let gridPos = (input.pos + 1) / grid - 1 + cellOffset;
  
  var output: VertexOutput;
  output.pos = vec4f(gridPos, 0, 1);
  output.cell = cell;
  return output;
}

@fragment
fn fragmentMain(
  input: VertexOutput,
) -> @location(0) vec4f {
  let val = input.cell / grid;
  return vec4f(val,1 - length(val.xy), 1);
}