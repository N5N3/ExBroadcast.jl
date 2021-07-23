export Lazy, eachdim′, eachcol′, eachrow′, eachslice′
# getsame
@inline getsame(f::F, x) where {F} = f(x)
@inline getsame(f::F, x, y, zs...) where {F} = begin
    fx = getsame(f, y, zs...)
    f(x) == fx || throw(ArgumentError("inputs with different $f"))
    fx
end

# force inlined map that return nothing
@inline fmap(f::F, t₁::Tuple{}) where {F} = nothing
@inline fmap(f::F, t₁::Tuple) where {F} = begin
    f(t₁[1])
    fmap(f, Base.tail(t₁))
end

@inline fmap(f::F, t₁::Tuple{}, t₂::Tuple{}) where {F} = nothing
@inline fmap(f::F, t₁::Tuple, t₂::Tuple) where {F} = begin
    f(t₁[1], t₂[1])
    fmap(f, Base.tail(t₁), Base.tail(t₂))
end

### import many funtions
import Base.Broadcast: throwdm, AbstractArrayStyle, Unknown, combine_eltypes,
    preprocess, Broadcasted, DefaultArrayStyle, ischunkedbroadcast, chunkedcopyto!, bitcache_size,
    dumpbitcache, bitcache_chunks, materialize!, BroadcastStyle, combine_styles, instantiate,
    broadcastable, broadcast_unalias, Style, _broadcast_getindex, broadcasted
import Base: size, axes, setindex!, unalias, mightalias, unaliascopy, IndexStyle, parent,
    unsafe_setindex!, copyto!, IndexStyle, tail
const FilledBC = Broadcasted{<:AbstractArrayStyle{0}}
"""
    TupleDummy(arrays::Tuple)
Dummy structure for broadcast with multiple outputs.
A simplified SoA implementation.
**This is not part of the interface. Not exported.**
"""
struct TupleDummy{T,N,L,As,AXs} <: AbstractArray{T,N}
    arrays::As
    ax::AXs
    TupleDummy{T,N,L}(arrays::As, ax::AXs) where {T,N,L,As,AXs} =
        new{T,N,L,As,AXs}(arrays, ax)
end

function TupleDummy(arrays::Tuple{AbstractArray,AbstractArray,Vararg{AbstractArray}}) ## at least 2 outputs
    ax = getsame(axes, arrays...)
    Style = IndexStyle(arrays...) |> typeof
    ElType = Tuple{eltype.(arrays)...}
    TupleDummy{ElType,length(ax),Style}(arrays, ax)
end
parent(td::TupleDummy) = td.arrays
size(td::TupleDummy, args...) = size(td.arrays[1], args...)
axes(td::TupleDummy) = td.ax
IndexStyle(T::Type{<:TupleDummy}) = T.parameters[3]()
@inline setindex!(td::TupleDummy{T,N,IndexLinear}, value::Tuple, ix::Int) where {T,N} =
    fmap((a, v) -> unsafe_setindex!(a, v, ix) , td.arrays, value)
@inline setindex!(td::TupleDummy{T,N,IndexCartesian}, value::Tuple, ixs::Vararg{Int,N}) where {T,N} =
    fmap((a, v) -> unsafe_setindex!(a, v, ixs...) , td.arrays, value)

@inline unalias(dest::TupleDummy, A::AbstractRange) = A
@inline unalias(dest::TupleDummy, A::AbstractArray) =
    mapreduce(x -> mightalias(x, A), |, dest.arrays) ? unaliascopy(A) : A
@inline broadcast_unalias(dest::TupleDummy, src::AbstractArray) =
    mapreduce(x -> x === src, |, dest.arrays) ? src : unalias(dest, src)

## toa_similar
_similar(bc, T) = similar(bc, T)
_similar(bc::Broadcasted{<:DefaultArrayStyle}, ::Type{Bool}) =
    similar(Array{Bool}, axes(bc))
function toa_similar(bc::Broadcasted)
    ElType = combine_eltypes(bc.f, bc.args)
    ElType <: Tuple{Any,Vararg{Any}} && Base.isconcretetype(ElType) ||
        throw(ArgumentError("$ElType is not a legal return type for @tab!"))
    dest = map(T -> _similar(bc, T), tuple(ElType.parameters...))
    TupleDummy{ElType,ndims(bc),IndexLinear}(dest, axes(bc))
end

module LazyCollect
import Base: @propagate_inbounds, getindex
import Base.Broadcast: BroadcastStyle, broadcastable, extrude, newindex, broadcasted,
    instantiate, Broadcasted, DefaultArrayStyle
import Base.Iterators: ProductIterator

export Lazy

@inline ndims(x) = x isa Tuple ? 1 : Base.ndims(x)
@inline size(x) = x isa Tuple ? (length(x),) : Base.size(x)
# Like reshape, but allow tuple inputs.
struct FakeDim{N,S,T,D} <: AbstractArray{T,N}
    data::D
    FakeDim{N,S}(data::T) where {N,S,T} = new{N,S,eltype(data),T}(data)
end
@inline FakeDim{AD}(data::AbstractArray{<:Any,0}) where {AD} = data
@inline FakeDim{AD}(data::Ref{<:Any}) where {AD} = data
@inline FakeDim{AD}(data::Tuple{Any}) where {AD} = data
@inline FakeDim{AD}(data::Number) where {AD} = data
@inline FakeDim{AD}(id::FakeDim{N,S}) where {N,S,AD} = FakeDim{AD + N,AD + S}(id.data)
@inline FakeDim{AD}(bc::Broadcasted{S}) where {AD,S} = Broadcasted{S}(bc.f, FakeDim{AD}.(bc.args)...) |> instantiate
@inline FakeDim{AD}(data) where {AD} = let data = lazy(data)
    iszero(AD) ? data : FakeDim{AD + ndims(data),AD + 1}(data)
end
@inline FakeDim{AD}(x, y, args...) where {AD} =
    (FakeDim{AD}(x), FakeDim{AD + ndims(x)}(y, args...)...)
@inline FakeDim{AD}(x, y) where {AD} =
    (FakeDim{AD}(x), FakeDim{AD + ndims(x)}(y))

Base.axes(id::FakeDim{N,S}) where {N,S} =
    (ntuple(_ -> Base.OneTo(1), Val(S - 1))..., axes(id.data)...)
Base.size(id::FakeDim{N,S}) where {N,S} = (ntuple(_ -> 1, Val(S - 1))..., size(id.data)...)
@inline extrude(x::FakeDim) = x
@inline newindex(::FakeDim{N,S}, I::CartesianIndex) where {N,S} = I.I[S:N]
@propagate_inbounds getindex(id::FakeDim, I::NTuple{N,Int}) where {N} = id.data[I...]
@inline BroadcastStyle(::Type{ID}) where {ID<:FakeDim} =
    ID.parameters[4] <: Tuple ? DefaultArrayStyle{ID.parameters[1]}() :
                                BroadcastStyle(ID.parameters[4])

# Lazy is used to wrap Generator/Productor to avoid collect before broadcast.
struct Lazy{P}
    ori::P
end
Lazy(l::Lazy) = l
Base.size(l::Lazy) = size(l.ori)
@inline Base.collect(l::Lazy) = collect(l.ori)
@inline Base.iterate(l::Lazy, args...) = iterate(l.ori, args...)

broadcastable(l::Lazy) = lazy(l.ori)
@inline lazy(x) = broadcastable(x)
@inline lazy(g::Base.Generator) = broadcasted(g.f, lazy(g.iter))
@inline lazy(i::Iterators.ProductIterator) =
    broadcasted(tuple, FakeDim{0}(i.iterators...)...) |> instantiate
end
using .LazyCollect
## better each
@inline unsafe_view(A, I...) = Base.unsafe_view(A, to_indices(A, I)...)
eachcol′(A::AbstractVecOrMat) = Lazy(unsafe_view(A, :, i) for i in axes(A, 2))
eachrow′(A::AbstractVecOrMat) = Lazy(unsafe_view(A, i, :) for i in axes(A, 1))
function eachdim′(A::AbstractArray; dim::Val{D}) where {D}
    D <= ndims(A) || throw(DimensionMismatch("A doesn't have $dim dimensions"))
    axes_all = ntuple(d -> d == D ? Ref(:) : axes(A, d), ndims(A))
    Lazy(unsafe_view(A, i...) for i in Iterators.product(axes_all...))
end
function eachslice′(A::AbstractArray; dim::Val{D}) where {D}
    D <= ndims(A) || throw(DimensionMismatch("A doesn't have $dim dimensions"))
    inds_before = ntuple(d -> (:), D - 1)
    inds_after = ntuple(d -> (:), ndims(A) - D)
    Lazy(unsafe_view(A, inds_before..., i, inds_after...) for i in axes(A, D))
end

## faster Base.copyto_unaliased!
function copyto_unaliased!(::IndexLinear, dest::AbstractArray, ::IndexLinear, src::AbstractArray)
    isempty(src) && return dest
    length(dest) < length(src) && throw(BoundsError(dest, LinearIndices(src)))
    Δi = firstindex(dest) - firstindex(src)
    for i in eachindex(IndexLinear(), src)
        @inbounds dest[i + Δi] = src[i]
    end
    return dest
end

splitloop(iter::CartesianIndices) = begin
    indices = iter.indices
    outer = CartesianIndices(tail(indices))
    inner = first(indices)
    outer, inner
end

function copyto_unaliased!(::IndexLinear, dest::AbstractArray, ::IndexCartesian, src::AbstractArray)
    isempty(src) && return dest
    length(dest) < length(src) && throw(BoundsError(dest, LinearIndices(src)))
    iter, j = CartesianIndices(src), firstindex(dest) - 1
    inner_len = size(iter, 1)
    if inner_len >= 16
        # manually expand the inner loop similar to @simd
        outer, inner = splitloop(iter)
        off = firstindex(inner)
        @inbounds for II in outer
            n = 0
            while n < inner_len
                dest[j += 1] = src[inner[n + off], II]
                n += 1
            end
        end
    else
        for I in iter
            @inbounds dest[j += 1] = src[I]
        end
    end
    return dest
end

function copyto_unaliased!(::IndexCartesian, dest::AbstractArray, ::IndexLinear, src::AbstractArray)
    isempty(src) && return dest
    length(dest) < length(src) && throw(BoundsError(dest, LinearIndices(src)))
    iter, i = CartesianIndices(dest), firstindex(src) - 1
    inner_len = size(iter, 1)
    if inner_len >= 16
        # manually expand the inner loop similar to @simd
        final = lastindex(src)
        outer, inner = splitloop(iter)
        off = firstindex(inner)
        @inbounds for II in outer
            n = 0
            if i + inner_len >= final
                while i < final
                    dest[inner[n + off], II] = src[i += 1]
                    n += 1
                end
                break
            end
            while n < inner_len
                dest[inner[n + off], II] = src[i += 1]
                n += 1
            end
        end
    elseif length(dest) == length(src)
        for I in iter
            @inbounds dest[I] = src[i += 1]
        end
    else
        # use zip based interator
        for (I, J) in zip(eachindex(src), iter)
            @inbounds dest[J] = src[I]
        end
    end
    return dest
end

function copyto_unaliased!(::IndexCartesian, dest::AbstractArray, ::IndexCartesian, src::AbstractArray)
    isempty(src) && return dest
    length(dest) < length(src) && throw(BoundsError(dest, LinearIndices(src)))
    iterdest, itersrc = CartesianIndices(dest), CartesianIndices(src)
    if iterdest == itersrc
        iter = itersrc
        inner_len = size(iter, 1)
        if inner_len >= 16
            # manually expand the inner loop similar to @simd
            outer, inner = splitloop(iter)
            off = firstindex(inner)
            @inbounds for II in outer
                n = 0
                while n < inner_len
                    n′ = inner[n + off]
                    dest[n′, II] = src[n′, II]
                    n += 1
                end
            end
        else
            for I in iter
                @inbounds dest[I] = src[I]
            end
        end
    else
        for (J, I) in zip(iterdest, itersrc)
            @inbounds dest[J] = src[I]
        end
    end
    return dest
end
