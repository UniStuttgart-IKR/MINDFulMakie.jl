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
        multidomain = false
    )
end

#TODO plot only descendants of the idagnode
function Makie.plot!(intplot::IntentPlot)
    md_obs = lift(intplot.ibnf, intplot.intentid, intplot.subidag, intplot.multidomain) do ibnf, intentid, subidag, multidomain
        idagsdict = multidomain ? getmultidomainIntentDAGs(ibnf) : Dict(getibnfid(ibnf) => getidag(ibnf))
        remoteintents, remoteintents_precon = getmultidomainremoteintents(idagsdict, getibnfid(ibnf), intentid, subidag)
        mdidag, mdidagmap = buildmdidagandmap(idagsdict, getibnfid(ibnf), intentid, remoteintents, remoteintents_precon, subidag)
        # @info "md_obs entered", mdidagmap
        return idagsdict, mdidag, mdidagmap
    end
    idagsdict_obs = @lift $(md_obs)[1]
    mdidag_obs = @lift $(md_obs)[2]
    mdidagmap_obs = @lift $(md_obs)[3]

    edgecolors = lift(md_obs) do allmd
        mdidag = allmd[2]
        mdidagmap = allmd[3]
        [let
            mdidagmap[src(e)][1] == mdidagmap[dst(e)][1] ? :black : :red
         end 
         for e in edges(mdidag)]
    end

    labsob = lift(intplot.ibnf, intplot.showintent, intplot.showstate, md_obs) do ibnf, showintent, showstate, allmd
        idagsdict = allmd[1]
        mdidagmap = allmd[3]
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

    try 
        GraphMakie.graphplot!(intplot, mdidag_obs; layout=daglayout, nlabels=labsob, edge_color=edgecolors)
    catch e
        if e isa MathOptInterface.ResultIndexBoundsError{MathOptInterface.ObjectiveValue}
            # without special layout
            GraphMakie.graphplot!(intplot, mdidag_obs; nlabels=labsob, edge_color=edgecolors)
        else 
            rethrow(e)
        end
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
function buildmdidagandmap(idagsdict::Dict{UUID, IntentDAG}, ibnfid::UUID, intentid::Union{UUID,Nothing}, remoteintents::Vector{Tuple{UUID, UUID}}, remoteintents_precon::Vector{Tuple{UUID, UUID}}, subidag::Symbol)
    mdidag = SimpleDiGraph{Int}()
    mdidagmap = Vector{Tuple{UUID, UUID}}()

    addgraphtograph!(mdidag, mdidagmap, idagsdict, ibnfid, intentid, subidag)

    for ((previbnfid, previntentid), (ibnfid, intentid)) in zip(remoteintents_precon, remoteintents)
        haskey(idagsdict, ibnfid) || break
        addgraphtograph!(mdidag, mdidagmap, idagsdict, ibnfid, intentid, subidag)
        src_ibnfid_intentid = (previbnfid, previntentid)
        dst_ibnfid_intentid = (ibnfid, intentid)
        srcidx = something(findfirst(==(src_ibnfid_intentid), mdidagmap))
        dstidx = something(findfirst(==(dst_ibnfid_intentid), mdidagmap))
        add_edge!(mdidag, srcidx, dstidx)
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
