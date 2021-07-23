## materialize
@inline mtb_materialize(x, ::Integer) = x
@inline mtb_materialize(bc::Broadcasted, TN::Integer) =
    mtb_copy(instantiate(bc), TN)

@inline mtb_materialize!(dest, x, TN::Integer) =
    mtb_materialize!(dest, instantiate(Broadcasted(identity, (x,), axes(dest))), TN)

@inline mtb_materialize!(dest, bc::Broadcasted{Style}, TN::Integer) where {Style} =
    mtb_materialize!(combine_styles(dest, bc), dest, bc, TN)

@inline mtb_materialize!(::BroadcastStyle, dest, bc::Broadcasted{Style}, TN::Integer) where {Style} =
    mtb_copyto!(dest, instantiate(Broadcasted{Style}(bc.f, bc.args, axes(dest))), TN)

## copyto
@inline mtb_copy(bc::Broadcasted{Style{Tuple}}, ::Integer) = copy(bc)
@inline mtb_copy(bc::FilledBC, ::Integer) = copy(bc)
@inline mtb_copy(bc::Broadcasted{<:Union{Nothing,Unknown}}, ::Integer) = copy(bc)
@inline function mtb_copy(bc::Broadcasted{Style}, TN::Integer) where {Style}
    ElType = combine_eltypes(bc.f, bc.args)
    if !Base.isconcretetype(ElType)
        @warn "$(ElType) is not concrete, call Base.copy instead"
        copy(bc)
    end
    mtb_copyto!(similar(bc, ElType), bc, TN)
end

## copyto!
@inline mtb_copyto!(dest::AbstractArray, bc::Broadcasted, TN::Integer) =
    mtb_copyto!(dest, convert(Broadcasted{Nothing}, bc), TN)

@inline mtb_copyto!(dest::AbstractArray, bc::FilledBC, ::Integer) = copyto!(dest, bc)

@inline function mtb_copyto!(dest::AbstractArray, bc::Broadcasted{Nothing}, TN::Integer)
    length(dest) == 1 && return copyto!(dest, bc)
    axes(dest) == axes(bc) || throwdm(axes(dest), axes(bc))
    if bc.f === identity && bc.args isa Tuple{AbstractArray}
        A = only(bc.args)
        axes(dest) == axes(A) && return copyto!(dest, A)
    end
    bc′ = preprocess(dest, bc)
    Inds = eachindex(bc′)
    info = mtb_config(TN, Inds)
    mtb_call(info...) do ran
        iter = @inbounds view(Inds, ran)
        @inbounds @simd for I in iter
            dest[I] = bc′[I]
        end
        nothing
    end
    dest
end

@inline function mtb_copyto!(dest::BitArray, bc::Broadcasted{Nothing}, TN::Integer)
    axes(dest) == axes(bc) || throwdm(axes(dest), axes(bc))
    ischunkedbroadcast(dest, bc) && return chunkedcopyto!(dest, bc)
    length(dest) < 256 &&
    invoke(copyto!, Tuple{AbstractArray,Broadcasted{Nothing}}, dest, bc)
    destc = dest.chunks
    bc′ = preprocess(dest, bc)
    Inds = eachindex(bc′)
    info = mtb_config(TN, Inds, bitcache_size)
    mtb_call(info...) do ran
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

using Polyester
## mtb_call
@static if threads_provider == "Polyester"
    function mtb_call(@nospecialize(kernal::Function), fis::StepRange{Int, Int}, li::Int)
        @batch for tid in Base.OneTo(length(fis)-1)
            @inbounds kernal(fis[tid]:min(li, fis[tid+1]-1))
        end
        nothing
    end
else
    function mtb_call(@nospecialize(kernal::Function), fis::AbstractRange{Int}, li::Int)
        len = length(fis)
        @inbounds if len > 4
            len′ = len >> 1 + 1
            task = Threads.@spawn mtb_call(kernal, fis[1:len′], li)
            mtb_call(kernal, fis[len′:len], li)
            wait(task)
        elseif len == 4
            task₁ = Threads.@spawn kernal(fis[1]:fis[2]-1)
            task₂ = Threads.@spawn kernal(fis[2]:fis[3]-1)
            kernal(fis[3]:min(fis[4]-1,li))
            wait(task₁)
            wait(task₂)
        else
            task = Threads.@spawn kernal(fis[1]:fis[2]-1)
            kernal(fis[2]:min(fis[3]-1,li))
            wait(task)
        end
        nothing
    end
end

##Multi-threading config
@inline function mtb_config(threads::Integer, ax::AbstractArray, batch::Integer = 1)
    Iˢ, Iᵉ = firstindex(ax), lastindex(ax)
    len = cld(length(ax), threads * batch) * batch
    Iˢ:len:Iᵉ+len, Iᵉ
end
