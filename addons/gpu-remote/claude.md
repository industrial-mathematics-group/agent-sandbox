## Remote GPU server (`gpu`)

GPU code can't run locally. `gpu` runs this project's Julia code on a remote GPU server
through a restricted gateway (no shell there):

```bash
gpu sync            # upload the project (tracked + new files, respects .gitignore)
gpu instantiate     # first time / after dependency changes (with network)
gpu test            # Pkg.test() on the least busy GPU, no network
gpu check           # sync + test, the usual loop
gpu run bench/gpu.jl 1024
gpu --gpu 2 test    # pick a GPU
gpu status | gpu kill
```

After changing dependencies, run `gpu instantiate` first. If a command fails with a
missing configuration or SSH error, report it instead of trying to fix it.
