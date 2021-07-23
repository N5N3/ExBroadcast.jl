using ExBroadcast
using Test
using OffsetArrays, CUDA, StructArrays, Interpolations, Adapt
@testset "@tab.jl" begin
    a = randn(1000)
    b, c = @tab sincos.(a)
    @test b == sin.(a)
    @test c == cos.(a)
    b′ = @view b[1:999]
    @test_throws ArgumentError b′, c .= sincos.(a)
    b″ = OffsetArray(b,-1)
    @test_throws ArgumentError b″, c .= sincos.(a)
end

@testset "@mtb for OffsetVector" begin
    a = randn(1000)
    aᵒ = OffsetArray(a,-1)
    @mtb b = parent(aᵒ .+ 1)
    @test (a .+ 1) == b
end

@testset "@mtb for small array" begin
    a = [1]
    @mtb 2 a .+= 1
    @test a[1] == 2
end

@testset "@mtb for BitArray" begin
    a = randn(4096 * 6 - 2048)
    b = a .> 0
    @test @mtb (a .> 0) == b
end

@testset "CUDA supports" begin
    a = CUDA.randn(1000)
    b, c = @tab sincos.(a)
    @test b ≈ sin.(a)
    @test c ≈ cos.(a)
    d = StructArray{ComplexF32}((b, c))
    @test abs.(d) isa CuVector
    e = OffsetArray(d, -1) .+ 1
    @test e isa StructArray
    @test eachindex(e) == 0:999
end

@testset "Lazy test" begin
    a = ((i,k...) for i in 1:10, k in Iterators.product(1:10,1:2))
    @test identity.(a) == identity.(Lazy(a))
    a = (randn() for i in 1:100)
    b = Lazy(a) .+ [1 2] .- [1 2]
    @test b[:,1] != b[:,2]
    a = (randn() for i in 1:100, j in tuple())
    @test identity.(a) == identity.(Lazy(a))
end

@testset "CUDA Interp test" begin
    a = randn(Float32,101,101)
    itp = CubicSplineInterpolation((-50f0:50f0,-50f0:50f0), a)
    cuitp = adapt(CuArray, itp)
    res = cuitp.(-10:10,-10:10)
    @test res isa CuArray
    @test collect(res) ≈ itp.(-10:10,-10:10)

    itp = itp.itp
    a,b,c = preweight(itp,-1:0.01f0:1,-1:0.01f0:1)
    @test a.(b,c) == itp.(-1:0.01f0:1,-1:0.01f0:1)
end

