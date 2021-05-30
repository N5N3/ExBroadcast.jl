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

TupleDummy(x::TupleDummy) = x
TupleDummy(x) = thrown(ArgumentError("Invalid dest type for @tab"))
function TupleDummy(arrays::Tuple{AbstractArray,Vararg{AbstractArray}}) ## at least 1 outputs
    ax = getsame(axes, arrays...)
    Style = typeof(IndexStyle(arrays...))
    ElType = Tuple{eltype.(arrays)...}
    TupleDummy{ElType,length(ax),Style}(arrays, ax)
end
Broadcast.BroadcastStyle(::Type{TupleDummy{T,N,L,As,AXs}}) where {T,N,L,As,AXs} =
    foldl(Broadcast.result_style, map(BroadcastStyle, fieldtypes(As)))

parent(td::TupleDummy) = td.arrays
size(td::TupleDummy, args...) = size(td.arrays[1], args...)
axes(td::TupleDummy) = td.ax
IndexStyle(T::Type{<:TupleDummy}) = T.parameters[3]()
@inline function setindex!(td::TupleDummy{T,N,IndexLinear}, value, ix::Int) where {T,N}
    value isa NTuple{length(td.arrays),Any} ||
        throw(ArgumentError("Invalid return type for @tab"))
    map(td.arrays, value) do a, v
        unsafe_setindex!(a, v, ix)
    end
    return td
end
@inline function setindex!(td::TupleDummy{T,N,IndexCartesian}, value, ixs::Vararg{Int,N}) where {T,N}
    value isa NTuple{length(td.arrays),Any} ||
        throw(ArgumentError("Invalid return type for @tab"))
    map(td.arrays, value) do a, v
        unsafe_setindex!(a, v, ixs...)
    end
    return td
end
unalias(    ::TupleDummy, A::AbstractRange) = A
unalias(dest::TupleDummy, A::AbstractArray) =
    mapreduce(x -> mightalias(x, A), |, dest.arrays) ? unaliascopy(A) : A
if isdefined(Base.Broadcast, :Scalar)
    Base.unalias(::TupleDummy, x::Broadcast.Scalar) = x
end
Broadcast.broadcast_unalias(dest::TupleDummy, src::AbstractArray) =
    mapreduce(x -> x === src, |, dest.arrays) ? src : unalias(dest, src)

## toa_similar
_similar(bc, T) = similar(bc, T)
_similar(bc::Broadcasted{<:DefaultArrayStyle}, ::Type{Bool}) =
    similar(Array{Bool}, axes(bc))

function Base.similar(bc::Broadcasted{<:TupleArrayStyle}, ::Type{T}) where {T}
    T <: Tuple{Any,Vararg{Any}} || throw(ArgumentError(lazy"$T is not a legal return type for @tab!"))
    bc′ = adopt_style(bc, bc.style.style)
    dest = map(Base.Fix1(_similar, bc′), fieldtypes(T))
    TupleDummy{T,ndims(bc),IndexLinear}(dest, axes(bc))
end

## overload Base.copy
function Base.copy(bc::Broadcasted{<:TupleArrayStyle})
    ndims(bc) == 0 && return copy(adopt_style(bc, bc.style.style))
    ElType = eltype(bc)
    isconcretetype(ElType) && return parent(copyto!(similar(bc, ElType), bc))
    dest = @invoke copy(bc::Broadcasted)
    return parent(dest)
end

function Base.copy(bc::Broadcasted{TupleArrayStyle{Style{Tuple}}})
    res = copy(adopt_style(bc, bc.style.style))
    ntuple(Val(length(res[1]))) do i
        ntuple(d -> res[d][i], Val(length(res)))
    end
end

function Base.copyto!(dest::AbstractArray, bc::Broadcasted{<:TupleArrayStyle})
    dest isa TupleDummy || error("Internal error!")
    return copyto!(dest, adopt_style(bc, bc.style.style))
end

Base.materialize!(dest::TupleDummy, bc::Broadcasted) = (@invoke Base.materialize!(dest::Any, bc); parent(dest))

Broadcast.combine_styles(dest::TupleDummy) = Broadcast.combine_styles(dest.arrays...)
