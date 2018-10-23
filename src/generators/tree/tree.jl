import DataStructures: PriorityQueue

##################
# tree generator #
##################

# production kernel
# - input type U
# - trace type S
# - return type Tuple{V,Vector{U}}
# - argdiff for U
#       if the argdiff is NoChange() and there are no assignment changes, then
#       we do not need to run.
# - return-value-diff (each of these values may be NoChange)
#       for V
#       for each U

# aggregation kernel
# - input type Tuple{V,Vector{W}}
# - trace type T
# - return type W
# - argdiff
#       for V
#       for each W
#       if the argdiff is NoChange() for each V and each W then we do not need to run.
# return-value-diff
#       for W
# obtain custom argdiff value, by combining argdiffs from
# (1) production kernel of the same address (for V)
# (2) children aggregation kernels (for each W)
# custom change object, which indicates how the W object changed.

##############
# tree trace #
##############

struct TreeTrace{S,T,U,V,W}
    production_traces::PersistentHashMap{Int,S}
    aggregation_traces::PersistentHashMap{Int,T}
    max_branch::Int
    score::Float64
    has_choices::Bool
end

has_choices(trace::TreeTrace) = trace.has_choices

function get_call_record(trace::TreeTrace{S,T,U,V,W}) where {S,T,U,V,W}
    args::Tuple{U} = (get_call_record(trace.production_traces[1]).args[1]::U,)
    retval::W = get_call_record(trace.aggregation_traces[1]).retval
    CallRecord(trace.score, retval, args)
end


###########################
# tree assignment wrapper #
###########################

struct TreeTraceAssignment <: Assignment
    trace::TreeTrace
end

get_assignment(trace::TreeTrace) = TreeTraceAssignment(trace)

function Base.isempty(assignment::TreeTraceAssignment)
    !assignment.trace.has_choices
end

get_address_schema(::Type{TreeTraceAssignment}) = DynamicAddressSchema()

function has_internal_node(assignment::TreeTraceAssignment,
                           addr::Tuple{Int,Val{:production}})
    haskey(assignment.trace.production_traces, addr[1])
end

function has_internal_node(assignment::TreeTraceAssignment,
                           addr::Tuple{Int,Val{:aggregation}})
    haskey(assignment.trace.aggregation_traces, addr[1])
end

function has_internal_node(assignment::TreeTraceAssignment, addr::Pair)
    _has_internal_node(assignment, addr)
end

function get_internal_node(assignment::TreeTraceAssignment,
                           addr::Tuple{Int,Val{:production}})
    get_assignment(assignment.trace.production_traces[addr[1]])
end

function get_internal_node(assignment::TreeTraceAssignment,
                           addr::Tuple{Int,Val{:aggregation}})
    get_assignment(assignment.trace.aggregation_traces[addr[1]])
end

function get_internal_node(assignment::TreeTraceAssignment, addr::Pair)
    _get_internal_node(assignment, addr)
end

function has_leaf_node(assignment::TreeTraceAssignment, addr::Pair)
    _has_leaf_node(assignment, addr)
end

function get_leaf_node(assignment::TreeTraceAssignment, addr::Pair)
    _get_leaf_node(assignment, addr)
end

get_leaf_nodes(assignment::TreeTraceAssignment) = ()

function get_internal_nodes(assignment::TreeTraceAssignment)
    production_iter = (((idx, Val(:production)), get_assignment(subtrace))
        for (idx, subtrace) in assignment.trace.production_traces)
    aggregation_iter = (((idx, Val(:aggregation)), get_assignment(subtrace))
        for (idx, subtrace) in assignment.trace.aggregation_traces)
    Iterators.flatten((production_iter, aggregation_iter))
end



##################
# tree generator #
##################

# TODO when lightweight Gen functions properly declare their argument and return types, use:
# production_kern::Generator{Tuple{V,Vector{U}},S}
# aggregation_kern::Generator{W,T}

struct Tree{S,T,U,V,W,X,Y} <: Generator{W,TreeTrace{S,T,U,V,W}}
    production_kern::Generator{X,S}
    aggregation_kern::Generator{Y,T}
    max_branch::Int
end

function Tree(production_kernel::Generator{X,S}, aggregation_kernel::Generator{Y,T},
              ::Type{U}, ::Type{V}, ::Type{W}, max_branch::Int) where {S,T,U,V,W,X,Y}
    Tree{S,T,U,V,W,X,Y}(production_kernel, aggregation_kernel, max_branch)
end

get_child(parent::Int, child_num::Int, max_branch::Int) = (parent * max_branch) - 1 + child_num
get_parent(child::Int, max_branch::Int) = div(child - 2, max_branch) + 1
get_child_num(child::Int, max_branch::Int) = (child - 2) % max_branch + 1

@assert get_child(1, 1, 2) == 2
@assert get_child(1, 2, 2) == 3
@assert get_child(2, 1, 2) == 4
@assert get_child(2, 2, 2) == 5
@assert get_child(3, 1, 2) == 6

@assert get_parent(2, 2) == 1
@assert get_parent(3, 2) == 1
@assert get_parent(4, 2) == 2
@assert get_parent(5, 2) == 2
@assert get_parent(6, 2) == 3

@assert get_child_num(2, 2) == 1
@assert get_child_num(3, 2) == 2
@assert get_child_num(4, 2) == 1
@assert get_child_num(5, 2) == 2
@assert get_child_num(6, 2) == 1

struct TreeProductionRetDiff{DV,DU}
    vdiff::DV
    udiffs::Dict{Int,DU}
end

struct TreeAggregationArgDiff{DV,DW}
    vdiff::DV
    wdiffs::Dict{Int,DW}
end

function generate(gen::Tree{S,T,U,V,W}, args::Tuple{U}, constraints) where {S,T,U,V,W}
    (root_production_input::U,) = args
    production_traces = PersistentHashMap{Int,S}()
    aggregation_traces = PersistentHashMap{Int,T}()
    weight = 0.
    score = 0.
    trace_has_choices = false
    
    # production phase
    prod_to_visit = Set{Int}([1])
    while !isempty(prod_to_visit)
        local subtrace::S
        local input::U
        cur = first(prod_to_visit)
        delete!(prod_to_visit, cur)
        if cur == 1
            input = root_production_input
        else
            parent = get_parent(cur, gen.max_branch)
            child_num = get_child_num(cur, gen.max_branch)
            # return type of parent is Tuple{V,Vector{U}}
            input = get_call_record(production_traces[parent]).retval[2][child_num]
        end
        if has_internal_node(constraints, (cur, Val(:production)))
            subconstraints = get_internal_node(constraints, (cur, Val(:production)))
        else
            subconstraints = EmptyAssignment()
        end
        (subtrace, subweight) = generate(gen.production_kern, (input,), subconstraints)
        score += get_call_record(subtrace).score
        production_traces = assoc(production_traces, cur, subtrace)
        weight += subweight
        children_inputs::Vector{U} = get_call_record(subtrace).retval[2]
        for child_num in 1:length(children_inputs)
            push!(prod_to_visit, get_child(cur, child_num, gen.max_branch))
        end
        trace_has_choices = trace_has_choices || has_choices(subtrace)
    end

    # aggregation phase
    agg_to_visit = sort(collect(keys(production_traces)), rev=true) # visit children first
    for cur in agg_to_visit
        local subtrace::T
        vinput::V = get_call_record(production_traces[cur]).retval[1]
        num_children = length(get_call_record(production_traces[cur]).retval[2])
        winputs::Vector{W} = [get_call_record(aggregation_traces[get_child(cur, i, gen.max_branch)]).retval for i=1:num_children]
        if has_internal_node(constraints, (cur, Val(:aggregation)))
            subconstraints = get_internal_node(constraints, (cur, Val(:aggregation)))
        else
            subconstraints = EmptyAssignment()
        end
        (subtrace, subweight) = generate(gen.aggregation_kern, (vinput, winputs), subconstraints)
        score += get_call_record(subtrace).score
        aggregation_traces = assoc(aggregation_traces, cur, subtrace)
        weight += subweight
        trace_has_choices = trace_has_choices || has_choices(subtrace)
    end

    trace = TreeTrace{S,T,U,V,W}(production_traces, aggregation_traces, gen.max_branch,
                      score, trace_has_choices)
    return (trace, weight)
end

# TODO we assume that argdiff is NoChange; others are not yet implemented
# it would have type Union{Nothing,NoChange,Some{DU}}
# if argdiff is not NoChange() then we always need to visit the root production node

function update(gen::Tree{S,T,U,V,W}, new_args::Tuple{U}, argdiff::NoChange,
                trace::TreeTrace{S,T,U,V,W}, constraints) where {S,T,U,V,W,DU}

    production_traces = trace.production_traces
    aggregation_traces = trace.aggregation_traces

    # unpack constraints
    production_nodes = Dict{Int, Any}()
    for (addr, node) in get_internal_nodes(constraints)
        idx::Int = addr[1]
        if addr[2] == Val(:production)
            production_nodes[idx] = node
        elseif addr[2] == Val(:aggregation)
            aggregation_nodes[idx] = node
        else
            error("Unknown address: $addr")
        end
    end
    if length(get_leaf_nodes(constraints)) > 0
        error("Unknown address: $(first(get_leaf_nodes(constraints))[1])")
    end

    # production phase
    to_visit = PriorityQueue{Int,Int}()
    for key in keys(production_nodes)
        enqueue!(to_visit, key, key)
    end
    while !isempty(to_visit)
        cur = dequeue!(to_visit)
        if haskey(production_traces, cur)
            # TODO recursive call update on it; depending on retdiff, maybe add some of its children to the queue
        else
            # TODO use assess to generate a new trace; add all its children to the queue
        end
    end

    # aggregation phase
    # TODO visit all nodes marked during production phae, and any with constraints, and any new ones

    return (new_trace, weight, discard, retdiff)
end

function 

export Tree
