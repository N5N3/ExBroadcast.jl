import .Interpolations: AbstractInterpolation, AbstractInterpolationWrapper, BSplineInterpolation,
                        LanczosInterpolation, ScaledInterpolation, GriddedInterpolation, MonotonicInterpolation,
                        Extrapolation, itptype, coefficients,  itpinfo, value_weights, WeightedAdjIndex,
                        allbetween, interp_getindex, WeightedIndex, weightedindex_parts, maybe_weightedindex,
                        BoundsCheckStyle, _checkbounds
import Base: @propagate_inbounds
export UnSafeInterp, preweight

# a wrapper to turn off the boundary check when we use broadcast
struct UnSafeInterp{T,N,ITPT,IT} <: AbstractInterpolationWrapper{T,N,ITPT,IT}
    itp::ITPT
    UnSafeInterp(itp::AbstractInterpolation{T,N,IT}) where {T,N,IT} = new{T,N,typeof(itp),IT}(itp)
end
Base.parent(usitp::UnSafeInterp) = usitp.itp
@inline (usitp::UnSafeInterp{T,N})(args::Vararg{Any,N}) where {T,N} = @inbounds usitp.itp(args...)

struct WeightedInterp{A}
    coefs::A
end
Base.parent(witp::WeightedInterp) = witp.coefs
@inline (witp::WeightedInterp{<:AbstractArray{T,N}})(args::Vararg{Any,N}) where {T,N} = @inbounds witp.coefs[args...]

# pre_weight
unsaled(r::AbstractUnitRange, x) = @lzb x .- first(r) .+ oneunit(eltype(r))
unsaled(r::AbstractRange, x) = @lzb (x .- first(r)) .* inv(step(r)) .+ oneunit(eltype(r))

@inline getcoefs(x::AbstractInterpolationWrapper) = parent(x) |> getcoefs
@inline getcoefs(x::AbstractInterpolation) = coefficients(x)
@inline getcoefs(x::WeightedInterp) = parent(x)

# preweight
@inline preweight(itp::Extrapolation{T,N}, args::Vararg{Any,N}) where {T,N} =
    throw(ArgumentError("Extrapolation is not supported"))
@inline preweight(sitp::ScaledInterpolation{T,N}, args::Vararg{Any,N}) where {T,N} = begin
    @boundscheck _checkbounds(BoundsCheckStyle(sitp), sitp, args) || 
        Base.throw_boundserror(sitp, args)
    @inbounds preweight(sitp.itp, unsaled.(sitp.ranges, args)...)
end
@inline preweight(itp::BSplineInterpolation{T,N}, args::Vararg{Any,N}) where {T,N} = begin
    @boundscheck _checkbounds(BoundsCheckStyle(itp), itp, args) || 
        Base.throw_boundserror(itp, args)
    function weight_ind(itpflag, knotvec, x)
        makewi(y, ::Any) = begin
            pos, (coefs,) = weightedindex_parts((value_weights,), itpflag, knotvec, y)
            maybe_weightedindex(pos, coefs)
        end
        makewi.(x, getcoefs(itp) |> Ref)
    end
    (WeightedInterp(itp.coefs), weight_ind.(itpinfo(itp)..., args)...)
end
