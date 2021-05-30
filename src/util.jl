# withstyle
adopt_style(bc::Broadcasted, style::Union{Nothing,BroadcastStyle}) = Broadcasted(style, bc.f, bc.args, bc.axes)


# getsame
@noinline _getsamethrow(@nospecialize(f)) = throw(ArgumentError("Inputs with different $f"))
@inline getsame(f::F, x) where {F} = f(x)
@inline function getsame(f::F, x, y, zs...) where {F}
    fx = getsame(f, y, zs...)
    f(x) == fx || _getsamethrow(f)
    fx
end

# eltype
eltype(x) = Base.eltype(x)
eltype(bc::Broadcasted) = Base.promote_typejoin_union(Broadcast._broadcast_getindex_eltype(bc))

# module LazyCollect
# import Base: @propagate_inbounds, getindex
# import Base.Broadcast: BroadcastStyle, broadcastable, extrude, newindex, broadcasted,
#     instantiate, Broadcasted, DefaultArrayStyle, combine_styles
# import Base.Iterators: ProductIterator

# export Lazy, fakedim

# ndims(x::Tuple) = 1
# size(x::Tuple) = (length(x),)
# ndims(x) = Base.ndims(x)
# size(x) = Base.size(x)
# # Like reshape, but allow tuple inputs.
# struct FakeDim{N,S,T,D} <: AbstractArray{T,N}
#     data::D
#     FakeDim{N,S}(data::T) where {N,S,T} = new{N,S,eltype(data),T}(data)
# end
# FakeDim{N,S}(data::FakeDim) where {N,S} = FakeDim{N,S}(data.data)
# Base.axes(id::FakeDim{N,S}) where {N,S} = (ntuple(Returns(Base.OneTo(1)), Val(S - 1))..., axes(id.data)...)
# Base.size(id::FakeDim{N,S}) where {N,S} = (ntuple(Returns(1), Val(S - 1))..., size(id.data)...)
# extrude(x::FakeDim) = x
# if isdefined(Broadcast, :knownsize1)
#     Broadcast.knownsize1(::FakeDim{N,S}) where {N,S} = S > 1
# end
# struct FakeIndex{N}
#     inds::NTuple{N,Int}
#     FakeIndex(inds::NTuple{N,Int}) where {N} = new{N}(inds)
# end
# @inline pick_inds(I::NTuple{N,Int}, ::Val{S}, ::Val{E}) where {N,S,E} = ntuple(i -> I[S+i-1], Val(E - S + 1))
# @inline newindex(::FakeDim{N,S}, I::CartesianIndex) where {N,S} = FakeIndex(pick_inds(I.I, Val(S), Val(N)))
# @propagate_inbounds getindex(id::FakeDim, I::FakeIndex{N}) where {N} = id.data[I.inds...]
# @propagate_inbounds getindex(id::FakeDim{N,S}, I::Vararg{Int,N}) where {N,S} = id.data[I[S:N]...]
# function BroadcastStyle(::Type{ID}) where {ID<:FakeDim}
#     PT = fieldtype(ID, 1)
#     PT <: Tuple && return DefaultArrayStyle{ndims(ID)}()
#     S = BroadcastStyle(PT)
#     S isa Broadcast.AbstractArrayStyle{Any} && return S
#     S isa Broadcast.AbstractArrayStyle && return typeof(S)(Val(ndims(ID)))
#     return S
# end

# @inline _fakedim(pre_ax::Tuple, data) = begin
#     data′ = broadcastable(data)
#     ax = axes(data)
#     m, n = length(pre_ax), length(ax)
#     data″ = m == 0 || n == 0 ? data′ : FakeDim{m + n,m + 1}(data′)
#     data″, (pre_ax..., ax...)
# end
# @inline _fakedim(pre_ax::Tuple, g::Base.Generator) = begin
#     iter, ax = _fakedim(pre_ax, g.iter)
#     Broadcasted(g.f, (iter,), ax), ax
# end
# @inline _fakedim(pre_ax::Tuple, i::Iterators.ProductIterator) = begin
#     iter, ax = fakedims(pre_ax, i.iterators...)
#     Broadcasted(tuple, iter, ax), ax
# end
# @inline fakedims(pre_ax::Tuple) = (), pre_ax
# @inline fakedims(pre_ax::Tuple, x, y...) = begin
#     x′, pre_ax′ = _fakedim(pre_ax, x)
#     y′, ax = fakedims(pre_ax′, y...)
#     (x′, y′...), ax
# end
# # Lazy is used to wrap Generator to avoid collect before broadcast.
# Lazy(x) = _fakedim((), x)[1]
# fakedim(x::AbstractArray, ::Val{N}) where {N} = N <= 0 ? x : FakeDim{N+ndims(x),N+1}(x)
# fakedim(x::Tuple, ::Val{N}) where {N} = N <= 0 ? x : FakeDim{N+1,N+1}(x)

# end
# using .LazyCollect
