"""
Base function to plot an `AttributeGraph` made for `IBNFramework`
  - `showmap = false`
  - `shownodelocallabels = false`
"""
@recipe(IBNGraphPlot, ibnattributegraph) do scene
    Theme(
        showmap = false,
        shownodelocallabels = false,
        graphattr = (;)
    )
end

function Makie.plot!(ibngraphplot::IBNGraphPlot)

    map!(ibngraphplot.attributes, [:ibnattributegraph, :shownodelocallabels], :nodelabs) do ibnag, shownodelocallabels
        nodelabs = String[]
        for (i, nodeviews) in enumerate(MINDF.getnodeviews(ibnag))
            labelbuilder = IOBuffer()
            if shownodelocallabels
                print(labelbuilder, i)
            end
            push!(nodelabs, String(take!(labelbuilder)))
        end
        return nodelabs
    end
    #
    map!(ibngraphplot.attributes, [:ibnattributegraph], :coords) do ibnag
        return coordlayout(ibnag)
    end

    GraphMakie.graphplot!(ibngraphplot, ibngraphplot.ibnattributegraph; layout=ibngraphplot.coords, arrow_show=false, force_straight_edges=true, nlabels=ibngraphplot.nodelabs, ibngraphplot.graphattr[]...)

    return ibngraphplot
end
