@group(0) @binding(0) var<uniform> grid: vec2<u32>;

@group(0) @binding(1) var<storage> cell_state_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> cell_state_out: array<u32>;

fn cellIndex(cell: vec2<u32>) -> u32 {
  return cell.y * grid.x + cell.x;
}

@compute @workgroup_size(8,8)
fn computeMain(
  @builtin(global_invocation_id) cell: vec3<u32>,
){
  let idx = cellIndex(cell.xy);
  if (cell_state_in[idx] == 1) {
    cell_state_out[idx] = 0;
  } else {
    cell_state_out[idx] = 1;
  }
  
}
