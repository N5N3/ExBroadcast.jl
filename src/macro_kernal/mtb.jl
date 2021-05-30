## overload Base
function Base.copy(bc::Broadcasted{<:MultiThreadStyle})
    (;style, nthread) = bc.style
    bc = adopt_style(bc, style)
    if ndims(bc) == 0 || nthread <= 1
        return copy(bc)
    end
    ElType = eltype(bc)
    if isconcretetype(ElType)
        dest = mtb_copyto!(similar(bc, ElType), bc, nthread)
        return dest isa TupleDummy ? parent(dest) : dest
    end
    @warn "$(ElType) is not concrete, call `Base.copy` instead"
    copy(bc)
end

function Base.copyto!(dest::AbstractArray, bc::Broadcasted{<:MultiThreadStyle})
    (;style, nthread) = bc.style
    bc = adopt_style(bc, style)
    nthread <= 1 && return copyto!(dest, bc)
    mtb_copyto!(dest, adopt_style(bc, style), nthread)
end

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
        noextrude, extrudeskipdim1, extrudeconstdim1, checkax1, isivdepsafe, flatten,
        simdable, preprocess, broadcast_unalias
else
    # We just skip all possible optimization On Offical Julia
    simdable(_) = false
    countunknown(_) = 0
    islinear(_) = false
    isivdepsafe(_, _) = false
    broadcast_unalias(dest::AbstractArray) = Base.Fix1(Base.Broadcast.broadcast_unalias, dest)
    @inline preprocess(f::Function, x) = f(x)
    @inline preprocess(f::Function, x, y) = f(x)
    @static if fieldcount(Broadcasted) == 4
        @inline preprocess(f::Function, bc::Broadcasted) =
            Broadcasted(bc.style, bc.f, preprocess_args(f, bc.args), bc.axes)
    else
        @inline preprocess(f::Function, bc::Broadcasted{Style}) where {Style} =
            Broadcasted{Style}(bc.f, preprocess_args(f, bc.args), bc.axes)
    end

    @inline preprocess_args(f, args::Tuple) = (preprocess(f, args[1]), preprocess(f, args[2]), preprocess_args(f, tail2(args))...)
    @inline preprocess_args(f, args::Tuple{Any}) = (preprocess(f, args[1]),)
    preprocess_args(f, ::Tuple{}) = ()
    using Base.Broadcast: extrude
end

function mtb_copyto!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer)
    axes(dest) == axes(bc) || throwdm(axes(dest), axes(bc))
    if bc.f === identity && bc.args isa Tuple{AbstractArray}
        A = only(bc.args)
        axes(dest) == axes(A) && return copyto!(dest, A)
    end
    length(dest) == 1 && (dest[] = bc[];)
    length(dest) <= 1 && return dest
    bc′ = preprocess(broadcast_unalias(dest), bc)
    return mtb_copyto_unaliased!(dest, bc′, TN)
end

function mtb_copyto_unaliased!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer)
    if !simdable(bc)
        return copyto_kernal!(dest, preprocess(extrude, bc), TN, Val(false))
    # The following optimization is only for SelfBase.
    elseif countunknown(bc) <= 3
        if islinear(dest) && linearable(bc) && checklinear(eachindex(dest), bc)
            return copyto_kernal!(dest, preprocess(noextrude, bc, eachindex(dest)), TN)
        else
            return copyto_kernal!(dest, preprocess(extrude, bc), TN)
        end
    else
        bc′ = flatten(bc)
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

@noinline copyto_kernal!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer) = 
    @inline copyto_kernal!(dest, bc, TN, Val(true))

function copyto_kernal!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer, ::Val{IV}) where {IV}
    Inds = vec(eachindex(bc))
    mtb_call(mtb_config(min(TN), Inds)) do ran
        iter = @inbounds view(Inds, ran)
        @inbounds if IV && isivdepsafe(dest, bc)
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
    length(dest) == 1 && (dest[] = bc[];)
    length(dest) <= 1 && return dest
    bc′ = preprocess(broadcast_unalias(dest), bc)
    return mtb_copyto_unaliased!(dest, bc′, TN)
end

using Base.MultiplicativeInverses: SignedMultiplicativeInverse
prepare_1diter(I::AbstractUnitRange) = I
make_1diter(I::AbstractUnitRange, ran::UnitRange) =
    Iterators.map(CartesianIndices(())) do J
        (@inbounds I[ran], J)
    end

function prepare_1diter(I::CartesianIndices)
    ax = I.indices
    ax1, outer = ax[1], vec(CartesianIndices(tail(ax)))
    mi1 = SignedMultiplicativeInverse{Int}(length(ax1))
    (;ax1, outer, mi1)
end
function make_1diter((;ax1, outer, mi1), ran::UnitRange)
    div, rem = divrem(first(ran) - 1, mi1)
    vl, fl = div + 1, rem + first(ax1)
    div, rem = divrem(last(ran) - 1, mi1)
    vr, fr = div + 1, rem + first(ax1)
    vouter = (vl:vr) .+ (firstindex(outer) - 1)
    out = @inbounds view(outer, vouter)
    return Iterators.map(enumerate(out)) do (i, I)
        @inline
        l = i == 1 ? fl : first(ax1)
        r = i == length(out) ? fr : last(ax1)
        Base.IdentityUnitRange(l:r), I
    end
end

function copyto_kernal!(dest::BitArray, bc::Broadcasted{Nothing}, TN::Integer, @nospecialize(::Val))
    info = prepare_1diter(eachindex(bc))
    destc = dest.chunks
    mtb_call(mtb_config(TN, eachindex(dest), 64)) do ran
        indc = (first(ran) - 1) >>> 6
        iter = make_1diter(info, ran)
        bitst, remain = 0, UInt64(0)
        @inbounds for (ax1, I) in iter
            i = first(ax1) - 1
            if ndims(bc) == 1 || bitst >= 64 - length(ax1)
                if ndims(bc) > 1 && bitst != 0
                    z = remain
                    @simd for j = bitst:63
                        z |= UInt64(convert(Bool, bc[i+=1, I])) << (j & 63)
                    end
                    destc[indc+=1] = z
                end
                while i <= last(ax1) - 64
                    z = UInt64(0)
                    @simd for j = 0:63
                        z |= UInt64(convert(Bool, bc[i+=1, I])) << (j & 63)
                    end
                    destc[indc+=1] = z
                end
                bitst, remain = 0, UInt64(0)
            end
            @simd for i = i+1:last(ax1)
                remain |= UInt64(convert(Bool, bc[i, I])) << (bitst & 63)
                bitst += 1
            end
        end
        @inbounds if bitst != 0
            destc[indc+=1] = remain
        end
    end
    return dest
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
