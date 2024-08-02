@testitem "Plotting GL" tags[:plotting_gl] begin
using GLMakie
GLMakie.activate!()

end

@testitem "Plotting GL - register coordinates" tags[:plotting_gl] begin
    include("test_plotting_1_regcoords.jl")
end
end

@testitem "Plotting GL - arguments and observables and tags" tags[:plotting_gl] begin
    include("test_plotting_2_tags_observables.jl")
end
end