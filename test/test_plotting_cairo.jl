@testitem "Plotting Cairo" tags[:plotting_cairo] begin
using CairoMakie
CairoMakie.activate!()

end

@testitem "Plotting Cairo - register coordinates" tags[:plotting_cairo] begin
    include("test_plotting_1_regcoords.jl")
end
end

@testitem "Plotting Cairo - arguments and observables and tags" tags[:plotting_cairo] begin
    include("test_plotting_2_tags_observables.jl")
end
end