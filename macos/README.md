> Build script (MacOS specific) helpers and tool config files for buuilding `sculite/sqlite` with CUDA, LSP support and formatters

**For CUDA includes**

> [!NOTE]
> The example below uses the nvidia/cuda with the tag `12.1.0-devel-ubuntu22.04`. The other available tags are would be to use `13.1.0-devel-ubuntu24.04` or `13.1.0-devel-ubuntu22.04`. The `12.1.0` was primarily chosen for it to be compatible with the T4 GPU runtime available on [colab.research.google.com](https://colab.research.google.com/). If these tags are changed, then make sure that you change the tag used in the [build.sh]

```
docker run --name cuda-temp -d nvidia/cuda:12.1.0-devel-ubuntu22.04 sleep infinity
mkdir -p cuda_include
docker cp cuda-temp:/usr/local/cuda/include/. ./cuda_include/
docker rm -f cuda-temp
```

**Building the project**

```sh
tree -L1
```

```
.
├── build # the emitted build directory (used by the build container)
├── build.sh # the build script
├── cuda_include # instructions in the previous section 
├── source.sh # source file with LDFLAGS and CPPFLAGS
└── sqlite # the sculite/sqlite repository
```

```sh
# building the source
./build.sh
```
