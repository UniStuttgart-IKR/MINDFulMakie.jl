"""
Plot the intent dag with the following options
  - `showstate = false`
  - `showintent = false`,
  - `intentid = nothing`
Plot the intent DAG based on the given intent
  - `subidag = [:descendants, :exclusivedescendants, :all, :connected, :multidomain]
`:descendants` plots only child intents and their childs and so on, 
`:exclusivedescendants` plots only child intents that do not have multiple parents, 
`:all` plots all nodes in the intent dag (`intentid` is not really needed),
`:connected` plots all nodes that are connected
    - `multidomain` = false
"""
@recipe(IntentPlot, ibnf) do scene
    Theme(
        showstate = false,
        showintent = false,
        intentid = nothing,
        subidag = :descendants,
        multidomain = false,
        graphattr = (;)
    )
end

#TODO plot only descendants of the idagnode
function Makie.plot!(intplot::IntentPlot)

    map!(intplot.attributes, [:ibnf, :intentid, :subidag, :multidomain], [:idagsdict, :mdidag, :mdidagmap] ) do ibnf, intentid, subidag, multidomain
        idagsdict = multidomain ? getmultidomainIntentDAGs(ibnf) : Dict(getibnfid(ibnf) => getidag(ibnf))
        remoteintents, remoteintents_precon, directionforward = getmultidomainremoteintents(idagsdict, getibnfid(ibnf), intentid, subidag)
        mdidag, mdidagmap = buildmdidagandmap(idagsdict, getibnfid(ibnf), intentid, remoteintents, remoteintents_precon, directionforward, subidag)
        return idagsdict, mdidag, mdidagmap
    end

    map!(intplot.attributes, [:mdidag, :mdidagmap], :edgecolors) do mdidag, mdidagmap
        [let
            mdidagmap[src(e)][1] == mdidagmap[dst(e)][1] ? :black : :red
         end 
         for e in edges(mdidag)]
    end

    map!(intplot.attributes, [:ibnf, :showintent, :showstate, :idagsdict, :mdidagmap], :labsob ) do ibnf, showintent, showstate, idagsdict, mdidagmap
        labs = String[]

        for (ibnfid, intentid) in mdidagmap
            idagnode = getidagnodefrommultidomain(idagsdict, ibnfid, intentid)
            labelbuilder = IOBuffer()

            uuid = @sprintf("%x, %x", getfield(ibnfid, :value), getfield(MINDF.getidagnodeid(idagnode), :value))
            println(labelbuilder, uuid)

            if showintent
                println(labelbuilder, MINDF.getintent(idagnode))
            end
            if showstate
                state = string(MINDF.getidagnodestate(idagnode))            
                println(labelbuilder, state)
            end

            push!(labs, String(take!(labelbuilder)))
        end
        labs
    end

    if Graphs.nv(intplot.mdidag[]) > 2
        try 
            GraphMakie.graphplot!(intplot, intplot.mdidag; layout=daglayout, nlabels=intplot.labsob, edge_color=intplot.edgecolors, intplot.graphattr[]...)
        catch e
            # if e isa Makie.ComputePipeline.ResolveException{MathOptInterface.ResultIndexBoundsError{MathOptInterface.ObjectiveValue}}
                # without special layout
                GraphMakie.graphplot!(intplot, intplot.mdidag; nlabels=intplot.labsob, intplot.graphattr[]...)#, edge_color=intplot.edgecolors)
            # else 
                # GraphMakie.graphplot!(intplot, SimpleGraph())#, edge_color=intplot.edgecolors)
                # rethrow(e)
            # end
        end
    else
        GraphMakie.graphplot!(intplot, intplot.mdidag; nlabels=intplot.labsob, intplot.graphattr[]...)#, edge_color=intplot.edgecolors)
    end

    return intplot
end


function daglayout(dag::AbstractGraph; angle=-π/2)
    if nv(dag) == 0 || ne(dag) == 1
        # return (args...) -> Spring()(dag)
        return Spring()(dag)
    else
        xs, ys, paths = solve_positions(Zarate(), dag)
        rotatecoords!(xs, ys, paths, -π/2)
        # return (args...) -> Point2.(zip(xs,ys))
        return Point2.(zip(xs,ys))
    end
end

"""
    rotatecoords!(xs::AbstractVector, ys::AbstractVector, paths::AbstractDict, θ)

Rotate coordinates `xs`, `ys` and paths `paths` by `angle`
"""
function rotatecoords!(xs::AbstractVector, ys::AbstractVector, paths::AbstractDict, θ)
    # rotation matrix
    r = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    points = vcat.(xs, ys)
    newpoints = [r * pointvec for pointvec in points]
    xs .= getindex.(newpoints, 1)
    ys .= getindex.(newpoints, 2)
    for (k,v) in paths
        newpath = [r * pointvec for pointvec in vcat.(v...)]
        paths[k] = (getindex.(newpath, 1), getindex.(newpath, 2))
    end
end

"""
Starting from (ibnfid, intentid) construct the multi domain intent DAG
Return the mdidag and the mapping as `(ibnfid, intentid)`
"""
function buildmdidagandmap(idagsdict::Dict{UUID, IntentDAG}, ibnfid::UUID, intentid::Union{UUID,Nothing}, remoteintents::Vector{Tuple{UUID, UUID}}, remoteintents_precon::Vector{Tuple{UUID, UUID}}, directionforward::Vector{Bool}, subidag::Symbol)
    mdidag = SimpleDiGraph{Int}()
    mdidagmap = Vector{Tuple{UUID, UUID}}()

    addgraphtograph!(mdidag, mdidagmap, idagsdict, ibnfid, intentid, subidag)

    for ((previbnfid, previntentid), (ibnfid2, intentid), dirfor) in zip(remoteintents_precon, remoteintents, directionforward)
        if ibnfid2 !== ibnfid
            haskey(idagsdict, ibnfid2) || break
            addgraphtograph!(mdidag, mdidagmap, idagsdict, ibnfid2, intentid, subidag)
        else
            haskey(idagsdict, previbnfid) || break
            addgraphtograph!(mdidag, mdidagmap, idagsdict, previbnfid, intentid, subidag)
        end
        src_ibnfid_intentid = (previbnfid, previntentid)
        dst_ibnfid_intentid = (ibnfid2, intentid)
        srcidx = something(findfirst(==(src_ibnfid_intentid), mdidagmap))
        dstidx = something(findfirst(==(dst_ibnfid_intentid), mdidagmap))
        if dirfor
            add_edge!(mdidag, srcidx, dstidx)
        else
            add_edge!(mdidag, dstidx, srcidx)
        end
    end
    return mdidag, mdidagmap
end

function addgraphtograph!(mdidag::SimpleDiGraph, mdidagmap::Vector{Tuple{UUID, UUID}}, idagsdict::Dict{UUID,IntentDAG}, ibnfid::UUID, intentid::Union{UUID,Nothing}, subidag::Symbol)
    haskey(idagsdict, ibnfid) || return
    idag = idagsdict[ibnfid]
    involvedgraphnodes = getinvolvednodespersymbol(idag, intentid, subidag)
    subgraph, subgraphvmap = Graphs.induced_subgraph(AG.getgraph(idag), involvedgraphnodes)
    idagnodes = getidagnodes(idag)

    for remv in subgraphvmap
        tuptoadd = (ibnfid, getidagnodeid(idagnodes[remv]))
        if tuptoadd ∉ mdidagmap
            add_vertex!(mdidag)
            push!(mdidagmap, tuptoadd)
        end
    end
    for reme in edges(subgraph)
        src_ibnfid_intentid = (ibnfid, getidagnodeid(idagnodes[ subgraphvmap[src(reme)] ]))
        dst_ibnfid_intentid = (ibnfid, getidagnodeid(idagnodes[ subgraphvmap[dst(reme)] ]))
        srcidx = something(findfirst(==(src_ibnfid_intentid), mdidagmap))
        dstidx = something(findfirst(==(dst_ibnfid_intentid), mdidagmap))
        add_edge!(mdidag, srcidx, dstidx)
    end
end

function getidagnodesfrommultidomain(mdidagmap::Vector{Tuple{UUID, UUID}}, idagsdict::Dict{UUID, IntentDAG})
    [getidagnodefrommultidomain(idagsdict, ibnfid, intentid) for (ibnfid, intentid) in mdidagmap]
end

function getidagnodefrommultidomain(idagsdict::Dict{UUID, IntentDAG}, ibnfid::UUID, intentid::UUID)
    return getidagnode(idagsdict[ibnfid], intentid)
end

function getidagnodefrommultidomain(idagsdict::Dict{UUID, IntentDAG}, mdidagmap::Vector{Tuple{UUID, UUID}}, v::Int)
    ibnfid, intentid = mdidagmap[v]
    return getidagnodefrommultidomain(idagsdict, ibnfid, intentid)
end
