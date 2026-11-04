# gpu-local: a GPU on the machine that runs the sandbox

Passes the host's GPU into the agent container. Nothing changes in the gateway: the
GPU is a device, not a network service.

| GPU | Image | Quadlet | Compose |
|---|---|---|---|
| AMD (ROCm) | `full-rocm` (or any flavor + `layers/rocm`) | `setup.sh --gpu amd` | `compose.gpu-amd.yaml` |
| NVIDIA (CUDA) | any flavor | `setup.sh --gpu nvidia` | `compose.gpu-nvidia.yaml` |

**AMD.** `/dev/kfd` and `/dev/dri` are passed in, plus the host user's `video` and
`render` groups (`GroupAdd=keep-groups` on Podman, `group_add` with the host's GIDs on
Docker). The entrypoint keeps those groups when `KEEP_GROUPS=1`. SELinux hosts need
`sudo setsebool -P container_use_devices on` once. RDNA4 cards (gfx1201) need
ROCm >= 6.4.1.

**NVIDIA.** Uses CDI (`nvidia.com/gpu=all`). Install `nvidia-container-toolkit` on the
host and generate the CDI spec once:
`sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`. CUDA comes from the
language packages (CUDA.jl artifacts, PyTorch wheels); their download hosts may need to
go into `extra.list`.

Check inside the sandbox: `rocminfo` (AMD) or `nvidia-smi` (NVIDIA, provided by CDI).
