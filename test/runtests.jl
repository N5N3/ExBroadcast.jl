using ExBroadcast
using Test
using OffsetArrays, StructArrays, StaticArrays

# macro testb(ex)
#     esc(ExBroadcast.lowerhack(@__MODULE__, ex, missing))
# end
@testset "@tab" begin
    a = randn(20)
    b, c = sin.(a), cos.(a)
    @test (@tab sincos.(a)) == (b, c)
    b′ = @view b[1:19]
    @test_throws ArgumentError @tab b′, c .= sincos.(a)
    b″ = OffsetArray(b, -1)
    @test_throws ArgumentError @tab b″, c .= sincos.(a)
    f(a) = @tab @tab @tab @tab @tab @tab sincos.(a)
    f(b, c, a) = @tab @tab @tab @tab @tab @tab b, c .= sincos.(a)
    @test @inferred(f(a)) == (b, c)
    @inferred(f(b, c, a))
    @test b == sin.(a)
    @test c == cos.(a)
    @test (@tab @mtb 2 @tab sincos.(@view(a[1:20]))) == (b, c)
    @tab @mtb 2 @tab b, c .= sincos.(@view(a[1:20]))
    @test b == sin.(a)
    @test c == cos.(a)
    @test (@tab broadcast(sincos, a)) == (b, c)
    @test (b, c) == (@tab broadcast(a) do x
                            sincos(x)
                          end)
    f2(x; y) = sincos(x + y)
    let y = 0
        @test (@tab f2.(a; y = 0)) == (@tab f2.(a; y))  == (@tab sincos.(a))
    end
end

@testset "@tab for StaticArray" begin
    a = randn(SVector{3})
    @tab b, c = sincos.(a)
    @test b === sin.(a)
    @test c === cos.(a)
end

@testset "@lzb" begin
    a = randn(SVector{3})
    @test (@lzb a .+ a) === (@lzb broadcast(+, a, a)) === (@lzb @. a + a)
    @test Base.materialize(@lzb a .+ a) === (a .+ a)
end

@testset "@stb" begin
    a = randn(3)
    @stb (;re, im) = cis.(a)
    @test im == sin.(a)
    @test re == cos.(a)
end
@testset "@mtb for OffsetVector" begin
    a = randn(1000)
    aᵒ = OffsetArray(a, -1)
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
    @test @mtb 6 (a .> 0) == b
end

@testset "kwargs" begin
    f(x; a, b) = x + a + b
    x = randn(100)
    a = 1
    @test f.(x; a, b = 1) == @mtb f.(x; a, b = 1)
end

# @testset "CUDA supports" begin
#     a = CUDA.randn(1000)
#     b, c = @tab sincos.(a)
#     @test b ≈ sin.(a)
#     @test c ≈ cos.(a)
#     @tab b, c .= sincos.(a)
#     @test b ≈ sin.(a)
#     @test c ≈ cos.(a)
# end

