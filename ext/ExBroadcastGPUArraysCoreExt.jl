module ExBroadcastGPUArraysCoreExt
using ExBroadcast, GPUArraysCore
using ExBroadcast: MultiThreadStyle, getsame, TupleDummy
## GPU support
import KernelAbstractions as KA
ExBroadcast.add_style(::Type{MultiThreadStyle}, s::AbstractGPUArrayStyle, _) = s
KA.get_backend(x::TupleDummy) = getsame(KA.get_backend, x.arrays...)
end