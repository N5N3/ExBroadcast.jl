# check the backend
import ArrayInterface: GPU, device, parent_type
devices(::Type{<:NamedTuple{<:Any,T}}) where {T} = devices(T)
devices(::Type{T}) where {T<:Tuple} = getsame(device, T.parameters...)
backends(::Type{<:NamedTuple{<:Any,T}}) where {T} = backends(T)
backends(::Type{T}) where {T<:Tuple} = getsame(backend, T.parameters...)
device(::Type{T}) where {T<:TupleDummy} = devices(T.parameters[4])
backend(::Type{T}) where {T<:TupleDummy} = backends(T.parameters[4])

# general gpu_copyto!(modified from GPUArrays.jl's implement to support OffsetArrays.jl)

# ## use style to dispatch
# function dispatch_style(Style, need_more = false)
#     @eval @inline mtb_materialize(bc::Broadcasted{<:$Style}, ::Integer) =
#         copy(instantiate(bc))
#     @eval @inline mtab_materialize(bc::Broadcasted{<:$Style}, ::Integer) =
#         tab_copy(instantiate(bc))
#     @eval @inline mtb_materialize!(::$Style, dest, bc::Broadcasted{Style}, ::Integer) where {Style} =
#         copyto!(dest, instantiate(Broadcasted{Style}(bc.f, bc.args, axes(dest))))
#     @eval @inline tab_copy(bc::Broadcasted{<:$Style}) = 
#         copyto!(toa_similar(bc), bc) |> parent
# end
# dispatch_style(:AbstractGPUArrayStyle)
# @inline tab_copy(bc::Broadcasted{<:AbstractGPUArrayStyle{0}}) = copy(bc)

## AbstractWrapper
# function map_show_copy(WrapperType::Symbol)

#     @eval @inline copyto!(dest::$WrapperType, bc::Broadcasted{Nothing}) = begin
#         device(dest) isa GPU && return gpu_copyto!(dest, bc)
#         invoke(copyto!, Tuple{AbstractArray,Broadcasted{Nothing}}, dest, bc)
#     end
    
#     @eval BroadcastStyle(::Type{Base.RefValue{AT}}) where {AT<:$WrapperType} =
#         BroadcastStyle(AT) |> forcedim0
# end

# forcedim0(x) = x
# forcedim0(::Style) where {Style<:AbstractArrayStyle} = Val(0) |> Style

# @require OffsetArrays = "6fe1bfb0-de20-5000-8ca7-80f57d26f881" begin
#     import .OffsetArrays: OffsetArray
#     ## general
#     ## device has been defined in ArrayInterface
#     backend(::Type{T}) where {T<:OffsetArray} = parent_type(T) |> backend
#     ## adapt_structure has been defined in OffsetArrays.jl
#     map_show_copy(:OffsetArray)
#     ## unique
#     Base.collect(A::OffsetArray) = collect(parent(A))
#     BroadcastStyle(::Type{OA}) where {OA<:OffsetArray} = parent_type(OA) |> BroadcastStyle
# end

# @require StructArrays = "09ab397b-f2b6-538f-b94a-2f83cf4a842a" begin
    # import .StructArrays: StructArray, StructArrayStyle, components
    ## general
    # device(::Type{T}) where {T<:StructArray} = T.parameters[3] |> devices
    # backend(::Type{T}) where {T<:StructArray} = T.parameters[3] |> backends
    ## adapt_structure has been defined in StructArrays.jl
    # map_show_copy(:StructArray)
    # unique
    # dispatch_style(:(StructArrayStyle{<:AbstractGPUArrayStyle}))
    # forcedim0(::StructArrayStyle{Style}) where {Style} = StructArrayStyle{typeof(forcedim0(Style()))}()

    # function Base.similar(bc::Broadcasted{StructArrayStyle{S}}, ::Type{ElType}) where {S,ElType}
    #     bc′ = convert(Broadcasted{S}, bc)
    #     if isstructtype(ElType)
    #         return StructArrays.buildfromschema(T -> similar(bc′, T), ElType)
    #     else
    #         return similar(bc′, ElType)
    #     end
    # end
# end
