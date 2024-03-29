const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");

const content_dir = @import("build_options").content_dir;
const window_title = "Conway's Game of Life (Native WebGPU)";

const cell_wgsl = @embedFile("shaders/cell.wgsl");
const compute_wgsl = @embedFile("shaders/compute.wgsl");

const Vertex = struct {
    x: f32,
    y: f32,
};

const WORKGROUP_SIZE = 8; // must be same as in shader

const GRID_CELLS_Y: u32 = 260;

const DemoState = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    compute_pipeline: zgpu.ComputePipelineHandle,
    bind_groups: [2]zgpu.BindGroupHandle,

    vertex_buffer_handle: zgpu.BufferHandle,
    cell_storage_handles: [2]zgpu.BufferHandle,

    cell_state_arrays: [2]std.ArrayList(u32),
    // index_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !DemoState {
        const gctx = try zgpu.GraphicsContext.create(allocator, window, .{});

        // Create a bind group layout needed for our render pipeline.
        const bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true, .compute = true }, .uniform, false, @sizeOf(u32) * 2),
            zgpu.bufferEntry(1, .{ .vertex = true, .fragment = true, .compute = true }, .read_only_storage, true, 0),
            zgpu.bufferEntry(2, .{ .fragment = true, .compute = true }, .storage, false, 0),
        });
        defer gctx.releaseResource(bind_group_layout);

        const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
        defer gctx.releaseResource(pipeline_layout);

        const pipeline = pipline: {
            const cell_module = zgpu.createWgslShaderModule(gctx.device, cell_wgsl, "cell");
            defer cell_module.release();

            const color_targets = [_]wgpu.ColorTargetState{.{
                .format = zgpu.GraphicsContext.swapchain_format,
            }};

            const vertex_attributes = [_]wgpu.VertexAttribute{.{
                .format = .float32x2,
                .offset = 0,
                .shader_location = 0,
            }};

            const vertex_buf_layouts = [_]wgpu.VertexBufferLayout{.{
                .array_stride = 8,
                .attribute_count = vertex_attributes.len,
                .attributes = &vertex_attributes,
            }};

            // zig fmt: off
            const pipeline_descriptor = wgpu.RenderPipelineDescriptor{ 
                .label = "Cell pipeline", 
                .vertex = wgpu.VertexState{
                    .module = cell_module,
                    .entry_point = "vertexMain",
                    .buffer_count = vertex_buf_layouts.len,
                    .buffers = &vertex_buf_layouts,
                }, 
                .fragment = &wgpu.FragmentState{
                    .module = cell_module,
                    .entry_point = "fragmentMain",
                    .target_count = color_targets.len,
                    .targets = &color_targets,
                },
                .primitive = wgpu.PrimitiveState{
                    .front_face = .ccw,
                    .cull_mode = .none,
                    .topology = .triangle_list,
                },
                .depth_stencil = &wgpu.DepthStencilState{
                    .format = .depth32_float,
                    .depth_write_enabled = true,
                    .depth_compare = .less,
                },
            };
            // zig fmt: on

            break :pipline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
        };

        const compute_pipeline = compute_pipline: {
            const compute_module = zgpu.createWgslShaderModule(gctx.device, compute_wgsl, "compute");
            defer compute_module.release();

            const compute_pipeline_descriptor = wgpu.ComputePipelineDescriptor{
                .label = "Compute pipeline",
                .compute = .{
                    .module = compute_module,
                    .entry_point = "computeMain",
                },
            };

            break :compute_pipline gctx.createComputePipeline(pipeline_layout, compute_pipeline_descriptor);
        };

        const grid_cells_x = gctx.swapchain_descriptor.width * GRID_CELLS_Y / gctx.swapchain_descriptor.height;
        const uniform_array = [_]u32{ grid_cells_x, GRID_CELLS_Y };
        const mem = gctx.uniformsAllocate(u32, 2);
        @memcpy(mem.slice[0..2], uniform_array[0..]);

        // zig fmt: off
        const vertices = [_]f32{
        //    X,    Y,
            -0.8, -0.8, // Triangle 1 (Blue)
             0.8, -0.8,
             0.8,  0.8,

            -0.8, -0.8, // Triangle 2 (Red)
             0.8,  0.8,
            -0.8,  0.8, 
        };
        // zig fmt: on

        const vertex_buffer_handle = gctx.createBuffer(.{
            .label = "Cell vertices",
            .size = vertices.len * @sizeOf(f32),
            .usage = .{ .vertex = true, .copy_dst = true },
        });
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer_handle).?, 0, f32, vertices[0..]);

        const n = grid_cells_x * GRID_CELLS_Y;
        var cell_state_arrays = [_]std.ArrayList(u32){
            try std.ArrayList(u32).initCapacity(allocator, n),
            try std.ArrayList(u32).initCapacity(allocator, n),
        };
        cell_state_arrays[0].appendNTimesAssumeCapacity(0, n);
        cell_state_arrays[1].appendNTimesAssumeCapacity(0, n);
        // zig fmt: off
        const cell_storage_handles = [_]zgpu.BufferHandle{
            gctx.createBuffer(.{
                .label = "Cell State Storage A",
                .size = cell_state_arrays[0].items.len * @sizeOf(u32),
                .usage = .{ .storage = true, .copy_dst = true },
            }),
            gctx.createBuffer(.{
                .label = "Cell State Storage B",
                .size = cell_state_arrays[1].items.len * @sizeOf(u32),
                .usage = .{ .storage = true, .copy_dst = true },
            }),
        };
        // zig fmt: on
        {
            var rand_impl = std.rand.DefaultPrng.init(1);
            var i: usize = 0;
            while (i < cell_state_arrays[0].items.len) : (i += 3) {
                cell_state_arrays[0].items[i] = @intFromBool(@mod(rand_impl.random().int(i32), 2) == 0);
            }
            gctx.queue.writeBuffer(gctx.lookupResource(cell_storage_handles[0]).?, 0, u32, cell_state_arrays[0].items);
        }
        {
            // var i: usize = 0;
            // while (i < cell_state_arrays[1].items.len) : (i += 2) {
            //     cell_state_arrays[1].items[i] = 1;
            // }
            gctx.queue.writeBuffer(gctx.lookupResource(cell_storage_handles[1]).?, 0, u32, cell_state_arrays[1].items);
        }

        const depth = createDepthTexture(gctx);

        // Create a bind group layout needed for our compute & render pipelines.
        // zig fmt: off
        const bind_groups = [_]zgpu.BindGroupHandle{
            gctx.createBindGroup(bind_group_layout, 
                &[_]zgpu.BindGroupEntryInfo{ .{
                    .binding = 0,
                    .buffer_handle = gctx.uniforms.buffer,
                    .size = @sizeOf(u32) * 2,
                }, 
                .{
                    .binding = 1,
                    .buffer_handle = cell_storage_handles[0],
                    .size = @sizeOf(u32) * cell_state_arrays[0].items.len,
                },
                .{
                    .binding = 2,
                    .buffer_handle = cell_storage_handles[1],
                    .size = @sizeOf(u32) * cell_state_arrays[1].items.len,
                },
            }),
            gctx.createBindGroup(bind_group_layout, 
                &[_]zgpu.BindGroupEntryInfo{ .{
                    .binding = 0,
                    .buffer_handle = gctx.uniforms.buffer,
                    .size = @sizeOf(u32) * 2,
                }, 
                .{
                    .binding = 1,
                    .buffer_handle = cell_storage_handles[1],
                    .size = @sizeOf(u32) * cell_state_arrays[1].items.len,
                },
                .{
                    .binding = 2,
                    .buffer_handle = cell_storage_handles[0],
                    .size = @sizeOf(u32) * cell_state_arrays[0].items.len,
                },
            }),
        };
        // zig fmt: on

        return Self{
            .gctx = gctx,
            .vertex_buffer_handle = vertex_buffer_handle,
            .cell_storage_handles = cell_storage_handles,
            .cell_state_arrays = cell_state_arrays,
            .pipeline = pipeline,
            .compute_pipeline = compute_pipeline,
            .bind_groups = bind_groups,
            .depth_texture = depth.texture,
            .depth_texture_view = depth.view,
        };
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.cell_state_arrays[0].deinit();
        self.cell_state_arrays[1].deinit();
        self.gctx.destroy(allocator);
        self.* = undefined;
    }
    fn update(self: *Self) void {
        zgui.backend.newFrame(
            self.gctx.swapchain_descriptor.width,
            self.gctx.swapchain_descriptor.height,
        );
        zgui.showDemoWindow(null);
    }
    fn draw(demo: *Self) void {
        const gctx = demo.gctx;
        const t = gctx.stats.cpu_frame_number;
        const fb_width = gctx.swapchain_descriptor.width;
        _ = fb_width;
        const fb_height = gctx.swapchain_descriptor.height;
        _ = fb_height;

        const back_buffer_view = gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();
        const grid_cells_x = gctx.swapchain_descriptor.width * GRID_CELLS_Y / gctx.swapchain_descriptor.height;

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            compute_pass: {
                const pipeline = gctx.lookupResource(demo.compute_pipeline) orelse break :compute_pass;
                const bind_group = gctx.lookupResource(demo.bind_groups[t % 2]) orelse break :compute_pass;
                const pass = encoder.beginComputePass(null);
                defer {
                    pass.end();
                    pass.release();
                }
                pass.setPipeline(pipeline);
                pass.setBindGroup(0, bind_group, &.{0});

                const wg_count_x : u32 = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(grid_cells_x)) / @as(f32, @floatFromInt(WORKGROUP_SIZE))));
                const wg_count_y : u32 = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(GRID_CELLS_Y)) / @as(f32, @floatFromInt(WORKGROUP_SIZE))));
                pass.dispatchWorkgroups(wg_count_x, wg_count_y, 1);
            }

            pass: {
                const vb_info = gctx.lookupResourceInfo(demo.vertex_buffer_handle) orelse break :pass;
                // const ib_info = gctx.lookupResourceInfo(demo.index_buffer) orelse break :pass;
                const pipeline = gctx.lookupResource(demo.pipeline) orelse break :pass;
                const bind_group = gctx.lookupResource(demo.bind_groups[t % 2]) orelse break :pass;
                const depth_view = gctx.lookupResource(demo.depth_texture_view) orelse break :pass;

                const clear_value = wgpu.Color{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.4,
                    .a = 1.0,
                };
                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .clear,
                    .store_op = .store,
                    .clear_value = clear_value,
                }};
                const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                    .view = depth_view,
                    .depth_load_op = .clear,
                    .depth_store_op = .store,
                    .depth_clear_value = 1.0,
                };

                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                    .depth_stencil_attachment = &depth_attachment,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }
                const uniform_array = [_]u32{ grid_cells_x, GRID_CELLS_Y };
                const mem = gctx.uniformsAllocate(u32, 2);
                @memcpy(mem.slice[0..2], uniform_array[0..]);

                // pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);
                pass.setPipeline(pipeline);
                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);

                pass.setBindGroup(0, bind_group, &.{0});

                pass.draw(6, grid_cells_x * GRID_CELLS_Y, 0, 0);
            }
            {
                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .load,
                    .store_op = .store,
                }};
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }

                zgui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();
        gctx.submit(&.{commands});

        if (gctx.present() == .swap_chain_resized) {
            // Release old depth texture.
            gctx.releaseResource(demo.depth_texture_view);
            gctx.destroyResource(demo.depth_texture);

            // Create a new depth texture to match the new window size.
            const depth = createDepthTexture(gctx);
            demo.depth_texture = depth.texture;
            demo.depth_texture_view = depth.view;
        }
        // std.time.sleep(1e+8); // 100 millis
        const milli = 1e6;
        std.time.sleep(milli);
    }
};

fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
} {
    const texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = gctx.swapchain_descriptor.width,
            .height = gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.", .{});
        return;
    };
    defer zglfw.terminate();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.os.chdir(path) catch {};
    }

    const window = zglfw.Window.create(1920, 1080, window_title, null) catch {
        std.log.err("Failed to create demo window.", .{});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var demo = DemoState.init(allocator, window) catch {
        std.log.err("Failed to initialize the demo.", .{});
        return;
    };
    defer demo.deinit(allocator);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        demo.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        demo.update();
        demo.draw();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
