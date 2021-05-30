## overload Base
function Base.copy(bc::Broadcasted{<:MultiThreadStyle{N}}) where {N}
    bc = adopt_style(bc, bc.style.style)
    if ndims(bc) == 0 || N <= 1
        return copy(bc)
    end
    ElType = eltype(bc)
    if isconcretetype(ElType)
        dest = mtb_copyto!(similar(bc, ElType), bc, N)
        return dest isa TupleDummy ? parent(dest) : dest
    end
    @warn "$(ElType) is not concrete, call `Base.copy` instead"
    copy(bc)
end

Base.copyto!(dest::AbstractArray, bc::Broadcasted{<:MultiThreadStyle{N}}) where {N} =
    mtb_copyto!(dest, adopt_style(bc, bc.style.style), N)

function mtb_copyto!(dest::AbstractArray, bc::Broadcasted, TN::Integer)
    ndims(bc) == 0 && return copyto!(dest, bc)
    return mtb_copyto!(dest, convert(Broadcasted{Nothing}, bc), TN)
end

function mtb_copyto!(dest::AbstractArray, bc::Broadcasted{<:AbstractArrayStyle{0}}, TN::Integer)
    if bc.f === identity && bc.args isa Tuple{Any} && Broadcast.isflat(bc)
        return fill!(dest, bc.args[1][])
    else
        return mtb_copyto!(dest, convert(Broadcasted{Nothing}, bc), TN)
    end
end

if isdefined(Broadcast, :isivdepsafe)
    using Base.Broadcast: extrude, countunknown, islinear, linearable, checklinear,
        noextrude, extrudeskipdim1, extrudeconstdim1, checkax1, isivdepsafe, flatten
    const preprocess = Base.Broadcast.preprocess
else
    # We just skip all possible optimization On Offical Julia
    countunknown(_) = 0
    islinear(_) = false
    isivdepsafe(_, _) = false
    using Broadcast: prepare_args
    @inline preprocess(f::Function, x) = f(x)
    @inline preprocess(f::Function, bc::Broadcasted{Style}) where {Style} =
        Broadcasted{Style}(bc.f, preprocess_args(f, bc.args), bc.axes)
    @inline preprocess(dest::Union{AbstractArray,Nothing}, x) = Broadcast.preprocess(dest, x)
end

function mtb_copyto!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer)
    axes(dest) == axes(bc) || throwdm(axes(dest), axes(bc))
    if bc.f === identity && bc.args isa Tuple{AbstractArray}
        A = only(bc.args)
        axes(dest) == axes(A) && return copyto!(dest, A)
    end
    length(dest) == 1 && (dest[] = bc[]; return dest)
    if countunknown(bc) <= 3
        bc′ = preprocess(broadcast_unalias(dest), bc)
        if islinear(dest) && linearable(bc′) && checklinear(eachindex(dest), bc′)
            return copyto_kernal!(dest, preprocess(noextrude, bc′, eachindex(dest)), TN)
        else
            return copyto_kernal!(dest, preprocess(extrude, bc′), TN)
        end
    else
        bc′ = preprocess(broadcast_unalias(dest), flatten(bc))
        if islinear(dest) && linearable(bc′) && checklinear(eachindex(dest), bc′)
            # Linear indexable
            return copyto_kernal!(dest, preprocess(noextrude, bc′, eachindex(dest)), TN)
        elseif checkax1(axes1(dest), bc′)
            # If all unknown arguments have the same 1st axes, we'd better keep type-stability
            return copyto_kernal!(dest, preprocess(extrudeskipdim1, bc′), TN)
        else
            # Otherwise use dynamic dispatch to speed up
            return copyto_kernal!(dest, preprocess(extrudeconstdim1, bc′), TN)
        end
    end
end

@noinline function copyto_kernal!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer)
    Inds = vec(eachindex(bc))
    mtb_call(mtb_config(TN, Inds)) do ran
        iter = @inbounds view(Inds, ran)
        @inbounds if isivdepsafe(dest, bc)
            @simd ivdep for I in iter
                dest[I] = bc[I]
            end
        else
            @simd for I in iter
                dest[I] = bc[I]
            end
        end
        nothing
    end
    return dest
end

function mtb_copyto!(dest::BitArray, bc::Broadcasted{Nothing}, TN::Integer)
    axes(dest) == axes(bc) || throwdm(axes(dest), axes(bc))
    ischunkedbroadcast(dest, bc) && return chunkedcopyto!(dest, bc)
    length(dest) < 256 && return copyto!(dest, bc)
    destc = dest.chunks
    bc′ = preprocess(dest, bc)
    Inds = vec(eachindex(bc′))
    mtb_call(mtb_config(TN, Inds, bitcache_size)) do ran
        tmp = Vector{Bool}(undef, bitcache_size)
        iter = @inbounds view(Inds, ran)
        cind = 1 + (first(ran) - firstindex(Inds)) >> 6
        @inbounds for P in Iterators.partition(iter, bitcache_size)
            ind = 0
            @simd for I in P
                tmp[ind += 1] = bc′[I]
            end
            while ind < bitcache_size
                tmp[ind += 1] = false
            end
            dumpbitcache(destc, cind, tmp)
            cind += bitcache_chunks
        end
        nothing
    end
    dest
end

## mtb_call
@static if threads_provider == "Polyester"
    using Polyester: @batch
    @eval function mtb_call(@nospecialize(kernal::Function), (f, l, s, n)::NTuple{4,Int})
        @batch for tid in 1:n
            k = f + s * tid
            kernal(k - s:min(k - 1, l))
        end
        nothing
    end
else
    function mtb_call(@nospecialize(kernal::Function), (f, l, s, n)::Dims{4})
        if n > 3
            n′ = n >> 1 + (n & 1)
            task = Threads.@spawn mtb_call(kernal, (f, l, s, n′))
            mtb_call(kernal, (f + s * n′, l, s, n - n′))
            wait(task)
        elseif n == 3
            task₁ = Threads.@spawn kernal($f:$(f += s) - 1)
            task₂ = Threads.@spawn kernal($f:$(f += s) - 1)
            kernal(f:min(f + s - 1, l))
            wait(task₁)
            wait(task₂)
        else
            task = Threads.@spawn kernal($f:$(f += s) - 1)
            kernal(f:min(f + s - 1, l))
            wait(task)
        end
        nothing
    end
end

##Multi-threading config
@inline function mtb_config(threads::Integer, ax::AbstractVector, batch::Integer=1)
    len = cld(length(ax), threads * batch) * batch
    num = cld(length(ax), len)
    set = firstindex(ax), lastindex(ax), len, num
    return Dims{4}(set)
end
