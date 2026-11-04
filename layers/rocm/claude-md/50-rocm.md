## AMD GPU (ROCm)

The ROCm runtime is installed (`/opt/rocm`). If the user enabled local GPU access,
`rocminfo` lists the GPU and AMDGPU.jl / PyTorch-ROCm can use it. If `rocminfo` shows no
GPU agent, GPU access is not enabled for this container: say so instead of trying to
fix it.
