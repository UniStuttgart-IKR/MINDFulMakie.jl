function coordlayout(ibnag::IBNAttributeGraph)
    xs = [[getlongitude(nodeprop), getlatitude(nodeprop)] for nodeprop in MINDF.getnodeproperties.(AG.vertex_attr(ibnag))]
end

"""
$(TYPEDSIGNATURES) 

Get a Dict of IntentDAG with keys being the `IBNFramework` uuid
"""
function getmultidomainIntentDAGs(ibnf::MINDF.IBNFramework)
    idagsdict = Dict{UUID, IntentDAG}()
    ibnfuuidschecked = UUID[]
    _recursive_getmultidomainIntentDAGs!(idagsdict, ibnfuuidschecked, ibnf, ibnf)
    return idagsdict
end

function _recursive_getmultidomainIntentDAGs!(idagsdict::Dict{UUID, IntentDAG}, ibnfuuidchecked::Vector{UUID}, myibnf, remoteibnf)
    remoteibnfid = getibnfid(remoteibnf)
    remoteibnfid ∈ ibnfuuidchecked && return
    push!(ibnfuuidchecked, remoteibnfid)
    idagsdict[remoteibnfid] = requestidag_init(myibnf, remoteibnf)
    for interibnf in MINDF.getibnfhandlers(myibnf)
        _recursive_getmultidomainIntentDAGs!(idagsdict, ibnfuuidchecked, myibnf, interibnf)
    end
    return 
end

"""
$(TYPEDSIGNATURES) 
Return a `Vector{Tuple{UUID, UUID}}`, with the first being the ibnfid and the second the intent id.
Start from ibnfid, and intentid
"""
function getmultidomainremoteintents(idagsdict::Dict{UUID, IntentDAG}, ibnfid::UUID, intentid::Union{UUID,Nothing}, subidag::Symbol)
    calltups = Vector{Tuple{UUID, UUID}}()
    directionforward = Vector{Bool}()
    remoteintents = Vector{Tuple{UUID, UUID}}()
    # previous idagnode connection of the remote. To cross connect to intent DAGs.
    remoteintents_precon = Vector{Tuple{UUID, UUID}}()
    _recursive_getmultidomainremoteintents!(remoteintents, remoteintents_precon, idagsdict, ibnfid, intentid, subidag, calltups, directionforward)
    return remoteintents, remoteintents_precon, directionforward
end

function _recursive_getmultidomainremoteintents!(remoteintents::Vector{Tuple{UUID, UUID}}, remoteintents_precon::Vector{Tuple{UUID, UUID}}, idagsdict::Dict{UUID, IntentDAG}, ibnfid::UUID, intentid::Union{UUID,Nothing}, subidag::Symbol, calltups::Vector{Tuple{UUID, UUID}}, directionforward::Vector{Bool})
    haskey(idagsdict, ibnfid) || return
    idag = idagsdict[ibnfid]
    involvedgraphnodes = getinvolvednodespersymbol(idag, intentid, subidag)
    for idagnode in MINDF.getidagnodes(idag)[involvedgraphnodes]
        if getintent(idagnode) isa RemoteIntent
            calltup = nothing
            if MINDF.getisinitiator(getintent(idagnode))
                tup = (getibnfid(getintent(idagnode)), getidagnodeid(getintent(idagnode)))
                tupprev = (ibnfid, getidagnodeid(idagnode))
                calltup = tup
            else
                if subidag == :connected
                    tup = (getibnfid(getintent(idagnode)), getidagnodeid(getintent(idagnode)))
                    tupprev = (ibnfid, getidagnodeid(idagnode))
                    calltup = tupprev
                end
            end
            if !isnothing(calltup) && calltup ∉ calltups && tup ∉ remoteintents
                push!(remoteintents, tup)
                push!(remoteintents_precon, tupprev)
                push!(calltups, calltup)
                if calltup == tup
                    push!(directionforward, true)
                elseif calltup == tupprev
                    push!(directionforward, false)
                end
                _recursive_getmultidomainremoteintents!(remoteintents, remoteintents_precon, idagsdict, calltup... , subidag, calltups, directionforward)
            end
        end
    end
end

# moved to MINDFul.jl
"""
$(TYPEDSIGNATURES) 

Construct a `IBNAttributeGraph` representation for all mutli-domain network from the IBNFramework neighboring `interIBNF`
ATTENTION: the inner graph data are still representing information internally per domain.
"""
function createmultidomainIBNAttributeGraph(ibnf::MINDF.IBNFramework)
    ibnfuuids = UUID[]

    ag1 = MINDF.getibnag(ibnf)
    mdag = MINDF.emptyaggraphwithnewuuid(ag1, UUID(0))

    _recursive_createmultidomainIBNAttributeGraph!(mdag, ibnfuuids, ibnf, ibnf)

    return mdag
end

# moved to MINDFul.jl
function _recursive_createmultidomainIBNAttributeGraph!(mdag::MINDF.IBNAttributeGraph, ibnfuuids::Vector{UUID}, myibnf::IBNFramework, remoteibnf::AbstractIBNFHandler)
    ibnfid = MINDF.getibnfid(remoteibnf)
    ibnfid ∈ ibnfuuids && return
    remoteibnag = MINDF.requestibnattributegraph_init(myibnf, remoteibnf)

    for v in vertices(remoteibnag)
        nodeview = MINDF.getnodeview(remoteibnag, v)
        globalnode = MINDF.getglobalnode(MINDF.getproperties(nodeview))
        
        foundindex = MINDF.findindexglobalnode(mdag, globalnode)
        if isnothing(foundindex)
            add_vertex!(mdag)
            push!(AG.vertex_attr(mdag), nodeview)
        else
            if MINDF.isnodeviewinternal(nodeview)
                AG.vertex_attr(mdag)[foundindex] = nodeview
            end
        end
    end

    for e in edges(remoteibnag)
        offset_e = findoffsetedge(mdag, remoteibnag, e)
        add_edge!(mdag, offset_e)
        edgeview = MINDF.getedgeview(remoteibnag, e)
        AG.edge_attr(mdag)[offset_e] = edgeview
    end

    push!(ibnfuuids, ibnfid)

    for interibnf in MINDF.requestibnfhandlers_init(myibnf, remoteibnf)
        _recursive_createmultidomainIBNAttributeGraph!(mdag, ibnfuuids, myibnf, interibnf)
    end
end

"""
Get a Dict{UUID, IBNAttributeGraph} with the ibnfid as key and the attribute graph as value.
"""
function getattributegraphneighbors(ibnf::MINDF.IBNFramework)
    dictneiag = Dict{UUID, MINDF.IBNAttributeGraph}()
    _recursive_getattributegraphneighbors(dictneiag, ibnf, ibnf)

    return dictneiag
end

function _recursive_getattributegraphneighbors(dictneiag::Dict{UUID, MINDF.IBNAttributeGraph}, myibnf, remoteibnf)
    ibnfid = MINDF.getibnfid(remoteibnf)
    ibnfid ∈ keys(dictneiag) && return
    remoteibnag = MINDF.requestibnattributegraph_init(myibnf, remoteibnf)
    dictneiag[ibnfid] = remoteibnag
    if remoteibnf isa IBNFramework
        for interibnf in MINDF.getibnfhandlers(remoteibnf)
            _recursive_getattributegraphneighbors(dictneiag, myibnf, interibnf)
        end
    end
end

function getcorrespondingibnagedge(mdag::MINDF.IBNAttributeGraph, edge::Edge, dictneiag::Dict{UUID, <: MINDF.IBNAttributeGraph})
    srcglobalnode = MINDF.getglobalnode(MINDF.getproperties(MINDF.getnodeview(mdag, src(edge))))
    dstglobalnode = MINDF.getglobalnode(MINDF.getproperties(MINDF.getnodeview(mdag, dst(edge))))
    firstibnag = haskey(dictneiag, getibnfid(srcglobalnode)) ? dictneiag[getibnfid(srcglobalnode)] : dictneiag[getibnfid(dstglobalnode)]
    src_idx = MINDF.findindexglobalnode(firstibnag, srcglobalnode)
    dst_idx = MINDF.findindexglobalnode(firstibnag, dstglobalnode)
    return firstibnag, Edge(src_idx, dst_idx)
end

# moved to MINDFul.jl
function findoffsetedge(mdag::MINDF.IBNAttributeGraph, remoteibnag::MINDF.IBNAttributeGraph, e::Edge)
    globalnode_src = MINDF.getglobalnode(MINDF.getproperties(MINDF.getnodeview(remoteibnag, src(e))))
    globalnode_dst = MINDF.getglobalnode(MINDF.getproperties(MINDF.getnodeview(remoteibnag, dst(e))))
    # TODO find the globalnode index
    src_idx = MINDF.findindexglobalnode(mdag, globalnode_src)
    dst_idx = MINDF.findindexglobalnode(mdag, globalnode_dst)
    (isnothing(src_idx) || isnothing(src_idx)) && error("global node not found in multi-domain attribute graph")
    
    offset_e = Edge(src_idx, dst_idx)
    return offset_e
end


function pathtolines(path, positions)
    nonothingpath = filter(!isnothing, path)
    pos = positions[nonothingpath]
    return [GraphMakie.Line(p1, p2) for (p1,p2) in zip(pos[1:end-1], pos[2:end])]
end

function euklideandistance(p1, p2)
    return sqrt( sum((p2 .- p1).^2) )
end

function getinvolvednodespersymbol(idag::IntentDAG, intentid::Union{UUID,Nothing}, subidag::Symbol)
    if subidag == :connected
        return MINDF.getidagnodeidxsconnected(idag, intentid; includeroot=true)
    elseif subidag == :descendants
        return MINDF.getidagnodeidxsdescendants(idag, intentid; includeroot=true)
    elseif subidag == :exclusivedescendants
        return MINDF.getidagnodeidxsdescendants(idag, intentid; includeroot=true, exclusive=true)
    elseif subidag == :all
        return vertices(idag)
    end
end

