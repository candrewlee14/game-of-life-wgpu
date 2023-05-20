<!-- Yo -->
<script lang="ts">
    import { onMount } from "svelte";
    import cellWgsl from "../shaders/cell.wgsl?raw";
    // import cellWgsl from './../shaders/cell.wgsl?raw';

    let canvas: HTMLCanvasElement;
    let width: number = 0;
    let height: number = 0;

    const gridCellsY = 30;
    let gridCellsX: number = gridCellsY;
    $: gridCellsX = Math.floor((width / height) * gridCellsY);

    const vertices = new Float32Array([
        -0.8, -0.8, 0.8, -0.8, -0.8, 0.8, 0.8, 0.8,
    ]);

    const indices = new Uint16Array([0, 1, 2, 2, 1, 3]);

    onMount(async () => {
        if (!navigator.gpu) {
            throw new Error("WebGPU not supported");
        }
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) {
            throw new Error("No adapter found");
        }
        const device = await adapter.requestDevice();
        if (!device) {
            throw new Error("No device found");
        }
        const context = canvas.getContext("webgpu");
        if (!context) {
            throw new Error("No context found");
        }
        const canvasFormat = navigator.gpu.getPreferredCanvasFormat(adapter);
        context.configure({
            device,
            format: canvasFormat,
        });

        const encoder = device.createCommandEncoder();
        const pass = encoder.beginRenderPass({
            colorAttachments: [
                {
                    view: context.getCurrentTexture().createView(),
                    loadOp: "clear",
                    clearValue: { r: 0, g: 0, b: 0.4, a: 1 },
                    storeOp: "store",
                },
            ],
        });

        const vertexBuffer = device.createBuffer({
            label: "Vertex Buffer",
            size: vertices.byteLength,
            usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
        });
        device.queue.writeBuffer(vertexBuffer, 0, vertices);

        const indexBuffer = device.createBuffer({
            label: "Index Buffer",
            size: indices.byteLength,
            usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST,
        });
        device.queue.writeBuffer(indexBuffer, 0, indices);

        const uniformArray = new Float32Array([gridCellsY, gridCellsY]);
        const uniformBuffer = device.createBuffer({
            label: "Grid uniform",
            size: uniformArray.byteLength,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        device.queue.writeBuffer(uniformBuffer, 0, uniformArray);

        const vertexBufferLayout = {
            arrayStride: 2 * 4,
            attributes: [
                {
                    shaderLocation: 0,
                    offset: 0,
                    format: "float32x2",
                },
            ],
        };

        const cellShaderModule = device.createShaderModule({
            label: "Cell Shader Module",
            code: cellWgsl,
        });

        const cellPipeline = device.createRenderPipeline({
            label: "Cell pipeline",
            layout: "auto",
            vertex: {
                module: cellShaderModule,
                entryPoint: "vertexMain",
                buffers: [vertexBufferLayout],
            },
            fragment: {
                module: cellShaderModule,
                entryPoint: "fragmentMain",
                targets: [
                    {
                        format: canvasFormat,
                    },
                ],
            },
        });

        const bindGroup = device.createBindGroup({
        label: "Cell renderer bind group",
        layout: cellPipeline.getBindGroupLayout(0),
        entries: [{
            binding: 0,
            resource: { buffer: uniformBuffer }
        }],
        });

        pass.setPipeline(cellPipeline);
        pass.setVertexBuffer(0, vertexBuffer);
        pass.setIndexBuffer(indexBuffer, "uint16");
        pass.setBindGroup(0, bindGroup);
        pass.drawIndexed(indices.length, gridCellsY * gridCellsY, 0, 0, 0);

        pass.end();
        device.queue.submit([encoder.finish()]);
    });
</script>

<svelte:window bind:innerWidth={width} bind:innerHeight={height} />

<canvas bind:this={canvas} {width} {height} />

<style>
    :root html,
    body {
        width: 100%;
        height: 100%;
        margin: 0;
        padding: 0;
    }
    canvas {
        width: 100%;
        height: 100%;
        display: block;
        margin: 0;
    }
</style>
