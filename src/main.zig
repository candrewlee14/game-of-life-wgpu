const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");

const content_dir = @import("build_options").content_dir;
const window_title = "Conway's Game of Life (Native WebGPU)";

const wgsl_vs = @embedFile("../shaders/vs.wgsl");
const wgsl_fs = @embedFile("../shaders/fs.wgsl");

const Vertex = struct {
    x: f32,
    y: f32,
};

const DemoState = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,

    // pipeline: zgpu.RenderPipelineHandle,
    // bind_group: zgpu.BindGroupHandle,

    // vertex_buffer: zgpu.BufferHandle,
    // index_buffer: zgpu.BufferHandle,

    // depth_texture: zgpu.TextureHandle,
    // depth_texture_view: zgpu.TextureViewHandle,

    fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !DemoState {
        const gctx = try zgpu.GraphicsContext.create(allocator, window);
        // Create a bind group layout needed for our render pipeline.
        return DemoState{
            .gctx = gctx,
            // .pipeline = pipeline,
            // .bind_group = bind_group,
        };
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
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
        const fb_width = gctx.swapchain_descriptor.width;
        _ = fb_width;
        const fb_height = gctx.swapchain_descriptor.height;
        _ = fb_height;

        const back_buffer_view = gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        const commands = commands: {
            const encoder = demo.gctx.device.createCommandEncoder(null);
            defer encoder.release();

            {
                // const vb_info = gctx.lookupResourceInfo(demo.vertex_buffer) orelse break :pass;
                // const ib_info = gctx.lookupResourceInfo(demo.index_buffer) orelse break :pass;
                // const pipeline = gctx.lookupResource(demo.pipeline) orelse break :pass;
                // const bind_group = gctx.lookupResource(demo.bind_group) orelse break :pass;
                // const depth_view = gctx.lookupResource(demo.depth_texture_view) orelse break :pass;

                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .clear,
                    .store_op = .store,
                }};
                // const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                //     .view = depth_view,
                //     .depth_load_op = .clear,
                //     .depth_store_op = .store,
                //     .depth_clear_value = 1.0,
                // };

                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }
                // pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                // pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);
                // pass.setPipeline(pipeline);
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

        // if (gctx.present() == .swap_chain_resized) {
        //     // Release old depth texture.
        //     gctx.releaseResource(demo.depth_texture_view);
        //     gctx.destroyResource(demo.depth_texture);
        //
        //     // Create a new depth texture to match the new window size.
        //     const depth = createDepthTexture(gctx);
        //     demo.depth_texture = depth.texture;
        //     demo.depth_texture_view = depth.view;
        // }
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

    const window = zglfw.Window.create(1600, 1000, window_title, null) catch {
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
        break :scale_factor math.max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        demo.gctx.device,
        @enumToInt(zgpu.GraphicsContext.swapchain_format),
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
