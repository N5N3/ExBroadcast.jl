using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    a = randn(10)
    @compile_workload begin
        # all calls in this block will be precompiled, regardless of whether
        # they belong to your package or not (on Julia 1.8 and higher)
        @mtb 6 b = sin.(a)
        @mtb b = sin.(a)
        @tab c, d = sincos.(a)
    end
end