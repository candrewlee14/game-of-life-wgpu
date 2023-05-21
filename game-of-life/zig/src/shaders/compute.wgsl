@group(0) @binding(0) var<uniform> grid: vec2<u32>;

@group(0) @binding(1) var<storage> cell_state_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> cell_state_out: array<u32>;

fn cellIndex(cell: vec2<u32>) -> u32 {
  let cell_x = cell.x % grid.x;
  let cell_y = cell.y % grid.y;
  return (cell_y * grid.x + cell_x);
}

fn cellActive(x: u32, y: u32) -> u32 {
  return cell_state_in[cellIndex(vec2(x, y))];
}

@compute @workgroup_size(8,8)
fn computeMain(
  @builtin(global_invocation_id) cell: vec3<u32>,
){
//   Determine how many active neighbors this cell has.
  let active_neighbors = cellActive(cell.x+1, cell.y+1) +
                        cellActive(cell.x+1, cell.y) +
                        cellActive(cell.x+1, cell.y-1) +
                        cellActive(cell.x, cell.y-1) +
                        cellActive(cell.x-1, cell.y-1) +
                        cellActive(cell.x-1, cell.y) +
                        cellActive(cell.x-1, cell.y+1) +
                        cellActive(cell.x, cell.y+1);

  let i = cellIndex(cell.xy);

  switch active_neighbors {
    case 2: {
      cell_state_out[i] = cell_state_in[i];
    }
    case 3: {
      cell_state_out[i] = 1;
    }
    default: {
      cell_state_out[i] = 0;
    }
  }
}
