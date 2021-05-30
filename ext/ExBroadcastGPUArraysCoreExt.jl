module ExBroadcastGPUArraysCoreExt
import ExBroadcast: add_style, getsame, TupleDummy
## GPU support
import GPUArraysCore: backend, AbstractGPUArrayStyle
add_style(::Type{MultiThreadStyle{N}}, s::AbstractGPUArrayStyle) where {N} = s
# check the backend
backend(::Type{T}) where {T<:TupleDummy} = getsame(backend, fieldtypes(fieldtype(T, 1))...)
end