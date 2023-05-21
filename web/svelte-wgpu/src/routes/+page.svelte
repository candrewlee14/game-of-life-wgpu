<!-- Yo -->
<script lang="ts">
    import { onMount } from "svelte";
    import cellWgsl from "../shaders/cell.wgsl?raw";
    import computeWgsl from "../shaders/compute.wgsl?raw";

    interface State {
        device: GPUDevice;
        context: GPUCanvasContext;
        pipeline: GPURenderPipeline;
        pipelineLayout: GPUPipelineLayout;
        simulationPipeline: GPUComputePipeline;
        bindGroupLayout: GPUBindGroupLayout;
        vertexBuffer: GPUBuffer;
        indexBuffer: GPUBuffer;
        uniformBuffer: GPUBuffer;
        uniformArray: Uint32Array;
        cellStateBuffers: GPUBuffer[];
        cellStateArray: Uint32Array;
        bindGroups: GPUBindGroup[];
        cellShaderModule: GPUShaderModule;
        computeShaderModule: GPUShaderModule;
        vertexBufferLayout: GPUVertexBufferLayout;
    };

    let canvas: HTMLCanvasElement;
    let width: number = 0;
    let height: number = 0;

    const GRID_CELLS_Y = 180;
    let gridCellsX: number = GRID_CELLS_Y;
    $: gridCellsX = Math.floor((width / height) * GRID_CELLS_Y);

    const UPDATE_INTERVAL = 20; // Update every 200ms (5 times/sec)
    const WORKGROUP_SIZE = 8;
    let step = 0; // Track how many simulation steps have been run

    const vertices = new Float32Array([
        -0.8, -0.8, 0.8, -0.8, -0.8, 0.8, 0.8, 0.8,
    ]);

    const indices = new Uint16Array([0, 1, 2, 2, 1, 3]);

    let state: State | undefined = undefined;

    const setupState = async () : Promise<State> => {
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
        const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
        context.configure({
            device,
            format: canvasFormat,
        });
        const textureView = context.getCurrentTexture().createView();

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

        const uniformArray = new Uint32Array([GRID_CELLS_Y, GRID_CELLS_Y]);
        const uniformBuffer = device.createBuffer({
            label: "Grid uniform",
            size: uniformArray.byteLength,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        device.queue.writeBuffer(uniformBuffer, 0, uniformArray);

        const cellStateArray = new Uint32Array(gridCellsX * GRID_CELLS_Y);

        const cellStateBuffers = [
            device.createBuffer({
                label: "Cell state A",
                size: cellStateArray.byteLength,
                usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
            }),
            device.createBuffer({
                label: "Cell state B",
                size: cellStateArray.byteLength,
                usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
            }),
        ];
        for (let i = 0; i < cellStateArray.length; ++i) {
            cellStateArray[i] = Math.random() > 0.6 ? 1 : 0;
        }
        device.queue.writeBuffer(cellStateBuffers[0], 0, cellStateArray);
        // for (let i = 0; i < cellStateArrays[1].length; i += 5) {
        //     cellStateArrays[1][i] = 1;
        // }
        // device.queue.writeBuffer(cellStateBuffers[1], 0, cellStateArrays[1]);

        const vertexBufferLayout: GPUVertexBufferLayout = {
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

        const bindGroupLayout = device.createBindGroupLayout({
            label: "Cell renderer bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT | GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "uniform",
                    },
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "read-only-storage",
                    },
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: {
                        type: "storage",
                    },
                },
            ],
        });

        const pipelineLayout = device.createPipelineLayout({
            label: "Cell renderer pipeline layout",
            bindGroupLayouts: [bindGroupLayout],
        });

        const cellPipeline = device.createRenderPipeline({
            label: "Cell pipeline",
            layout: pipelineLayout, 
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

        const bindGroups = [
            device.createBindGroup({
                label: "Cell renderer bind group A",
                layout: bindGroupLayout,
                entries: [
                    {
                        binding: 0,
                        resource: { buffer: uniformBuffer },
                    },
                    {
                        binding: 1,
                        resource: { buffer: cellStateBuffers[0] },
                    },
                    {
                        binding: 2,
                        resource: { buffer: cellStateBuffers[1] },
                    },
                ],
            }),
            device.createBindGroup({
                label: "Cell renderer bind group B",
                layout: cellPipeline.getBindGroupLayout(0),
                entries: [
                    {
                        binding: 0,
                        resource: { buffer: uniformBuffer },
                    },
                    {
                        binding: 1,
                        resource: { buffer: cellStateBuffers[1] },
                    },
                    {
                        binding: 2,
                        resource: { buffer: cellStateBuffers[0] },
                    },
                ],
            }),
        ];

        const computeShaderModule = device.createShaderModule({
            label: "Compute shader module",
            code: computeWgsl,
        });

        const simulationPipeline = device.createComputePipeline({
            label: "Simulation pipeline",
            layout: pipelineLayout,
            compute: {
                module: computeShaderModule,
                entryPoint: "computeMain",
            },
        });

        return {
            device,
            context,
            pipeline: cellPipeline,
            pipelineLayout,
            simulationPipeline,
            bindGroupLayout,
            bindGroups,
            uniformArray,
            uniformBuffer,
            cellStateBuffers,
            cellStateArray,
            vertexBuffer,
            indexBuffer,
            cellShaderModule,
            computeShaderModule,
            vertexBufferLayout,
        };
    };

    const updateGrid = (state: State) => {
        const encoder = state.device.createCommandEncoder();
        
        const computePass = encoder.beginComputePass();
        computePass.setPipeline(state.simulationPipeline);
        computePass.setBindGroup(0, state.bindGroups[step % 2]);

        const workgroupCountX = Math.ceil(gridCellsX / WORKGROUP_SIZE);
        const workgroupCountY = Math.ceil(GRID_CELLS_Y / WORKGROUP_SIZE);
        computePass.dispatchWorkgroups(workgroupCountX, workgroupCountY);

        computePass.end();
        step+=1;

        const pass = encoder.beginRenderPass({
            colorAttachments: [
                {
                    view: state.context.getCurrentTexture().createView(),
                    loadOp: "clear",
                    clearValue: { r: 0, g: 0, b: 0.4, a: 1 },
                    storeOp: "store",
                },
            ],
        });

        pass.setPipeline(state.pipeline);
        pass.setVertexBuffer(0, state.vertexBuffer);
        pass.setIndexBuffer(state.indexBuffer, "uint16");
        pass.setBindGroup(0, state.bindGroups[step % 2]);
        pass.drawIndexed(indices.length, GRID_CELLS_Y * GRID_CELLS_Y);

        pass.end();
        state.device.queue.submit([encoder.finish()]);
    };

    onMount(async () => {
        state = await setupState();
        setInterval(() => updateGrid(state!), UPDATE_INTERVAL);
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
