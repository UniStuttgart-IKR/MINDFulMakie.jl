include("initialize.jl")
include("testsuite/ibngraphplot.jl")
include("testsuite/ibnplot.jl")
include("testsuite/intentplot.jl")
# include("testsuite/ibnplot_obs.jl")
# include("testsuite/intentplot_obs.jl")

@testset "MINDFulMakie.jl" begin
    include("testsuite/reftests.jl")
end
