# TODO put these in a namespace somehow and remove bb_
const bb_score = gensym("score")
const bb_weight = gensym("weight")
const bb_new_trace = gensym("trace")

struct BBUpdateState
    marked::Set{ValueNode}
    stmts::Vector{Expr}
    schema::Union{StaticAddressSchema,EmptyAddressSchema}
    addr_visited::Set{Symbol}
    discard_leaf_nodes::Dict{Symbol, Symbol}
    discard_internal_nodes::Dict{Symbol, Symbol}
end

function BBUpdateState(stmts::Vector{Expr}, schema::Union{StaticAddressSchema,EmptyAddressSchema}, args_change)
    addr_visited = Set{Symbol}()
    marked = Set{ValueNode}()
    mark_arguments!(marked, ir, args_change)
    mark_input_change_nodes!(marked, ir)
    discard_leaf_node = Dict{Symbol,Symbol}()
    discard_internal_node = Dict{Symbol,Symbol}()
    BBUpdateState(marked, stmts, schema, addr_visited, discard_leaf_node, discard_internal_node)
end

struct BBFixUpdateState 
    marked::Set{ValueNode}
    stmts::Vector{Expr}
    schema::Union{StaticAddressSchema,EmptyAddressSchema}
    addr_visited::Set{Symbol}
    discard_leaf_nodes::Dict{Symbol, Symbol}
    discard_internal_nodes::Dict{Symbol, Symbol}
end

function BBFixUpdateState(stmts::Vector{Expr}, schema::Union{StaticAddressSchema,EmptyAddressSchema}, args_change)
    addr_visited = Set{Symbol}()
    marked = Set{ValueNode}()
    mark_arguments!(marked, ir, args_change)
    mark_input_change_nodes!(marked, ir)
    discard_leaf_node = Dict{Symbol,Symbol}()
    discard_internal_node = Dict{Symbol,Symbol}()
    BBFixUpdateState(marked, stmts, schema, addr_visited, discard_leaf_node, discard_internal_node)
end

struct BBExtendState
    marked::Set{ValueNode}
    stmts::Vector{Expr}
    schema::Union{StaticAddressSchema,EmptyAddressSchema}
    addr_visited::Set{Symbol}
end

function BBExtendState(stmts::Vector{Expr}, schema::Union{StaticAddressSchema,EmptyAddressSchema})
    addr_visited = Set{Symbol}()
    marked = Set{ValueNode}()
    mark_arguments!(marked, ir, args_change)
    mark_input_change_nodes!(marked, ir)
    BBExtendState(marked, stmts, schema, addr_visited)
end

function mark_input_change_nodes!(marked::Set{ValueNode}, ir::BasicBlockIR)
    for node in ir.generator_input_change_nodes
        # for now, mark every input change node to a generator
        # TODO we should only mark the node if the corresponding generator is
        # either constrained or marked, however, this requires two passes.
        # postponed for simplicity.
        push!(marked, node)
    end
end

function mark_arguments!(marked::Set{ValueNode}, ir::BasicBlockIR, args_change::Type{Nothing})
    for arg_node in ir.arg_nodes
        push!(marked, arg_node)
    end
end

function mark_arguments!(marked::Set{ValueNode}, ir::BasicBlockIR, args_change::Type{NoChange}) end

function mark_arguments!(marked::Set{ValueNode}, ir::BasicBlockIR, args_change::Type{T}) where {T <: MaskedArgChange}
    mask = args_change.parameters[1].parameters
    for (arg_node, maybe_changed_val) in zip(ir.arg_nodes, mask)
        if maybe_changed_val.parameters[1]
            push!(marked, arg_node)
        end
    end
end

function process!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState,BBExtendState}, node::JuliaNode)
    
    # if any input nodes are marked, mark the output node
    if any([input in state.marked for input in node.input_nodes])
        push!(state.marked, node.output)
    end

    # set the value in the new trace based on other values in the new trace
    (typ, trace_field) = get_value_info(node)
    if node.output in state.marked
        push!(state.stmts, quote
            $bb_new_trace.$trace_field = $(expr_read_from_trace(node, bb_new_trace))
        end)
    end
end

function process!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState,BBExtendState}, node::ArgsChangeNode)
    # always mark
    push!(state.marked, node.output)

    # set the value in the new trace (in the future, for performance
    # optimization, we can avoid tracing this value). we trace it for
    # simplicity and uniformity of implementation.
    (typ, trace_field) = get_value_info(node)
    push!(state.stmts, quote
        $bb_new_trace.$trace_field = args_change
    end)
end

const addr_change_prefix = gensym("addrchange")

function addr_change_variable(addr::Symbol)
    Symbol("$(addr_change_prefix)_$(addr)")
end

function process!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState,BBExtendState}, node::AddrChangeNode)
    # always mark
    push!(state.marked, node.output)

    (typ, trace_field) = get_value_info(node)
    addr = node.address
    @assert addr in state.addr_visited
    if haskey(ir.addr_dist_nodes, addr)
        dist_node = ir.addr_dist_nodes[addr]
        # TODO: this implies we cannot access @change for addresses that don't have outputs?
        constrained = dist_node.output in state.marked
        # return whether the value changed and the previous value
        push!(state.stmts, quote
            $bb_new_trace.$trace_field = ($(QuoteNode(constrained)), trace.$addr)
        end)
    else
        if !haskey(ir.addr_gen_nodes, addr)
            # it is neither the address of a distribution or a generator
            error("Unknown address: $addr")
        end
        push!(state.stmts, quote
            $bb_new_trace.$trace_field = $(addr_change_variable(addr))
        end)
    end
end

function process_no_discard!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState,BBExtendState}, node::AddrDistNode)
    addr = node.address
    push!(state.addr_visited, addr)
    typ = get_return_type(node.dist)
    dist = QuoteNode(node.dist)
    args = get_args(bb_new_trace, node)
    prev_args = get_args(:trace, node)
    decrement = gensym("decrement")
    increment = gensym("increment")
    input_nodes_marked = any([input in state.marked for input in node.input_nodes])
    if isa(state.schema, StaticAddressSchema) && addr in leaf_node_keys(state.schema)
        # constrained to a new value (mark the output)
        if has_output(node)
            push!(state.marked, node.output)
        end
        prev_value = gensym("prev_value")
        push!(state.stmts, quote
            $bb_new_trace.$addr = static_get_leaf_node(constraints, Val($(QuoteNode(addr)))) 
            $prev_value::$typ = trace.$addr
            $increment = logpdf($dist, $bb_new_trace.$addr, $(args...))
            $decrement = logpdf($dist, $prev_value, $(prev_args...))
            $bb_score += $increment - $decrement
            $bb_weight += $increment - $decrement
        end)
        state.discard_leaf_nodes[addr] = prev_value
        if has_output(node)
            (_, trace_field) = get_value_info(node)
            # TODO redundant with addr field, for use by other later statements:
            push!(state.stmts, quote
                $bb_new_trace.$trace_field = $bb_new_trace.$addr
            end)
        end
    elseif input_nodes_marked
         push!(state.stmts, quote
            $increment = logpdf($dist, trace.$addr, $(args...))
            $decrement = logpdf($dist, trace.$addr, $(prev_args...))
            $bb_score += $increment - $decrement
            $bb_weight += $increment - $decrement
        end)
    end
end

function process!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState}, node::AddrDistNode)
    process_no_discard!(ir, state, node)
    if isa(state.schema, StaticAddressSchema) && addr in leaf_node_keys(state.schema)
        state.discard_leaf_nodes[addr] = prev_value
    end
end

function process!(ir::BasicBlockIR, state::BBExtendState, node::AddrDistNode)
    process_no_discard!(ir, state, node)
end

function get_constraints(schema::Union{StaticAddressSchema,EmptyAddressSchema}, addr::Symbol)
    if isa(schema, StaticAddressSchema) && addr in internal_node_keys(schema)
        constraints = :(static_get_internal_node(constraints, Val($(QuoteNode(addr)))))
        constrained = true
    else
        constrained = false
        constraints = :(EmptyChoiceTrie())
    end
    (constrained, constraints)
end

function generate_generator_output_statement!(stmts::Vector{Expr}, node::AddrGeneratorNode)
    if has_output(node)
        (_, trace_field) = get_value_info(node)
        push!(stmts, quote
            $bb_new_trace.$trace_field = $call_record.retval
        end)
    end
end

function generate_generator_call_statement!(state::BBUpdateState, addr:Symbol, node::AddrGeneratorNode)
    push!(state.stmts, quote
        ($bb_new_trace.$addr, _, $discard, $(addr_change_variable(addr))) = update(
            $(QuoteNode(node.gen)), $(Expr(:tuple, args...)),
            $change_value_ref, trace.$addr, $constraints)
        $call_record = get_call_record($bb_new_trace.$addr)
        $decrement = get_call_record(trace.$addr).score
        $increment = $call_record.score
        $bb_score += $increment - $decrement
        $bb_weight += $increment - $decrement
    end)
end

function generate_generator_call_statement!(state::BBFixUpdateStatement, addr:Symbol, node::AddrGeneratorNode, constraints)
    args = get_args(bb_new_trace, node)
    prev_args = get_args(:trace, node)
    change_value_ref = :($bb_new_trace.$(value_field(node.change_node)))
    push!(state.stmts, quote
        ($bb_new_trace.$addr, _, $discard, $(addr_change_variable(addr))) = update(
            $(QuoteNode(node.gen)), $(Expr(:tuple, args...)),
            $change_value_ref, trace.$addr, $constraints)
    end)
end

function generate_generator_score_and_weight_statements!(stmts::Vector{Expr}, addr::Symbol)
    decrement = gensym("decrement")
    increment = gensym("increment")
    call_record = gensym("call_record")
    push!(stmts, quote
        $call_record = get_call_record($bb_new_trace.$addr)
        $decrement = get_call_record(trace.$addr).score
        $increment = $call_record.score
        $bb_score += $increment - $decrement
        $bb_weight += $increment - $decrement
    end)
end

function process_generator_update_marked!(state::Union{BBUpdateState,BBFixUpdateState}, node::AddrGeneratorNode)
    # return value could change (even if just the input nodes are marked,
    # we don't currently statically identify a generator that can absorb
    # arbitrary changes to its arguments)
    if has_output(node)
        push!(state.marked, node.output)
    end
end

function process!(ir::BasicBlockIR, state::Union{BBUpdateState,BBFixUpdateState}, node::AddrGeneratorNode, method::Symbol)
    addr = node.address
    push!(state.addr_visited, addr)
    discard = gensym("discard")
    input_nodes_marked = any([input in state.marked for input in node.input_nodes])
    (constrained, constraints) = get_constraints(state.schema, addr)
    if constrained || input_nodes_marked
        process_generator_update_marked!(state, node)
        generate_generator_call_statement!(state, addr, node, constraints)
        generate_generator_score_and_weight_statements!(stmts, addr)
        state.discard_internal_nodes[addr] = discard
        generate_generator_output_statement!(state.stmts, node)
    else
        push!(state.stmts, quote
            $(addr_change_variable(addr)) = NoChange()
        end)
    end
end

function process!(ir::BasicBlockIR, state::BBExtendState, node::AddrGeneratorNode, method::Symbol)
    addr = node.address
    push!(state.addr_visited, addr)
    input_nodes_marked = any([input in state.marked for input in node.input_nodes])
    (constrained, constraints) = get_constraints(state.schema, addr)
    if constrained || input_nodes_marked
        process_generator_update_marked!(state, node)
        generate_generator_call_statement!(state, addr, node, constraints)
        generate_generator_score_and_weight_statements!(stmts, addr)
        generate_generator_output_statement!(state.stmts, node)
    else
        push!(state.stmts, quote
            $(addr_change_variable(addr)) = NoChange()
        end)
    end
end

####

function generate_init_statements!(stmts::Vector{Expr})
    push!(stmts, quote
        $bb_new_trace = copy(trace)
        $bb_score = trace.$call_record_field.score
        $bb_weight = 0.
    end)
end

function generate_arg_statements!(stmts::Vector{Expr}, ir::BasicBlockIR)

    # unpack arguments into variables
    arg_names = Symbol[arg_node.name for arg_node in ir.arg_nodes]
    push!(stmts, Expr(:(=), Expr(:tuple, arg_names...), :new_args))

    # record arguments in trace
    for arg_node in ir.arg_nodes
        push!(stmts, quote $bb_new_trace.$(value_field(arg_node)) = $(arg_node.name) end)
    end
end

function generate_expr_node_statements!(stmts::Vector{Expr}, ir::BasicBlockIR, schema, mode)
    state = BBUpdateState(mode, stmts, schema)
    # visit statements in topological order, generating code
    for node in ir.expr_nodes_sorted
        process!(ir, state, node)
    end
end

function generate_is_empty!(stmts::Vector{Expr}, ir::BasicBlockIR)
    # NOTE: this is still O(N) where N is the number of generator calls,
    # including non-visited calls
    if !isempty(ir.addr_dist_nodes)
        push!(stmts, quote
            $bb_new_trace.$is_empty_field = false
        end)
    else
        for (addr, node::AddrGeneratorNode) in ir.addr_gen_nodes
            push!(stmts, quote
                $bb_new_trace.$is_empty_field = $bb_new_trace.$is_empty_field && !has_choices($bb_new_trace.$addr)
            end)
        end
    end
end

function generate_discard!(stmts::Vector{Expr}, state::BBUpdateState)
    if length(state.discard_leaf_nodes) > 0
        (leaf_keys, leaf_nodes) = collect(zip(state.discard_leaf_nodes...))
    else
        (leaf_keys, leaf_nodes) = ((), ())
    end
    if length(state.discard_internal_nodes) > 0
        (internal_keys, internal_nodes) = collect(zip(state.discard_internal_nodes...))
    else
        (internal_keys, internal_nodes) = ((), ())
    end
    leaf_keys = map((k) -> QuoteNode(k), leaf_keys)
    internal_keys = map((k) -> QuoteNode(k), internal_keys)
    push!(stmts, quote
        discard = StaticChoiceTrie(
            NamedTuple{($(leaf_keys...),)}(($(leaf_nodes...),)),
            NamedTuple{($(internal_keys...),)}(($(internal_nodes...),)))
    end)
end

function check_no_extra_constraints(schema::StaticAddressSchema, ir::BasicBlockIR)
    addresses = union(keys(ir.addr_dist_nodes), keys(ir.addr_gen_nodes))
    for addr in union(leaf_node_keys(schema), internal_node_keys(schema))
        if !(addr in addresses)
            error("Update did not consume all constraints")
        end
    end
end

function check_no_extra_constraints(schema::EmptyAddressSchema, ir::BasicBlockIR)
end


function generate_call_record!(stmts::Vector{Expr}, ir::BasicBlockIR)

    # return value
    if ir.output_node === nothing
        retval = :nothing
    else
        if ir.output_node in marked
            retval = quote $bb_new_trace.$(value_field(ir.output_node)) end
        else
            retval = quote trace.$call_record_field.retval end
        end
    end

    # construct new call record
    # TODO move the change to a returnvalue of update, not part of the call record
    # if we do that, then we will need separate fields in which to store the
    # retchange values (one for each geneator)
    push!(stmts, quote
        $bb_new_trace.$call_record_field = CallRecord($bb_score, $retval, new_args)
    end)
end

function generate_update_return_statement!(stmts::Vector{Expr}, ir::BasicBlockIR)
    if ir.retchange_node === nothing
        retchange = :(nothing)
    else
        retchange = Expr(:(.), bb_new_trace, QuoteNode(value_field(ir.retchange_node)))
    end
    push!(stmts, quote return ($bb_new_trace, $bb_weight, discard, $retchange) end)
end

function generate_extend_return_statement!(stmts::Vector{Expr}, ir::BasicBlockIR)
    if ir.retchange_node === nothing
        retchange = :(nothing)
    else
        retchange = Expr(:(.), bb_new_trace, QuoteNode(value_field(ir.retchange_node)))
    end
    push!(stmts, quote return ($bb_new_trace, $bb_weight, $retchange) end)
end

function codegen_update(gen::Type{T}, new_args, args_change, trace, constraints) where {T <: BasicGenFunction}
    schema = get_address_schema(constraints)
    ir = get_ir(gen)
    stmts = Expr[]
    generate_init_stmts!(stmts)
    generate_arg_statements!(stmts, ir)
    generate_expr_node_statements!(stmts, ir, schema, bb_update_mode)
    generate_is_empty!(stmts, ir)
    generate_discard!(stmts, state)
    generate_call_record!(stmts, ir)
    generate_update_return_statement!(stmts, ir)
    return Expr(:block, stmts...)
end

function codegen_fix_update(gen::Type{T}, new_args, args_change, trace, constraints) where {T <: BasicGenFunction}
    schema = get_address_schema(constraints)
    ir = get_ir(gen)
    stmts = Expr[]
    generate_init_stmts!(stmts)
    generate_arg_statements!(stmts, ir)
    generate_expr_node_statements!(stmts, ir, schema, bb_fix_update_mode)
    generate_is_empty!(stmts, ir)
    generate_discard!(stmts, state)
    generate_call_record!(stmts, ir)
    generate_update_return_statement!(stmts, ir)
    return Expr(:block, stmts...)
end

function codegen_extend(gen::Type{T}, new_args, args_change, trace, constraints) where {T <: BasicGenFunction}
    schema = get_address_schema(constraints)
    ir = get_ir(gen)
    stmts = Expr[]
    generate_init_stmts!(stmts)
    generate_arg_statements!(stmts, ir)
    generate_expr_node_statements!(stmts, ir, schema, bb_fix_update_mode)
    generate_is_empty!(stmts, ir)
    generate_call_record!(stmts, ir)
    generate_extend_return_statement!(stmts, ir)
    return Expr(:block, stmts...)
end


push!(Gen.generated_functions, quote
@generated function Gen.update(gen::Gen.BasicGenFunction{T,U}, new_args, args_change, trace::U, constraints) where {T,U}
    schema = get_address_schema(constraints)
    if !(isa(schema, StaticAddressSchema) || isa(schema, EmptyAddressSchema))
        # try to convert it to a static choice trie
        return quote update(gen, new_args, args_change, trace, StaticChoiceTrie(constraints)) end
    end
    Gen.codegen_update(Gen.bb_update_mode, gen, new_args, args_change, trace, constraints)
end
end)

push!(Gen.generated_functions, quote
@generated function Gen.fix_update(gen::Gen.BasicGenFunction{T,U}, new_args, args_change, trace::U, constraints) where {T,U}
    schema = get_address_schema(constraints)
    if !(isa(schema, StaticAddressSchema) || isa(schema, EmptyAddressSchema))
        # try to convert it to a static choice trie
        return quote fix_update(gen, new_args, args_change, trace, StaticChoiceTrie(constraints)) end
    end
    Gen.codegen_fix_update(gen, new_args, args_change, trace, constraints)
end
end)

push!(Gen.generated_functions, quote
@generated function Gen.extend(gen::Gen.BasicGenFunction{T,U}, new_args, args_change, trace::U, constraints) where {T,U}
    schema = get_address_schema(constraints)
    if !(isa(schema, StaticAddressSchema) || isa(schema, EmptyAddressSchema))
        # try to convert it to a static choice trie
        return quote extend(gen, new_args, args_change, trace, StaticChoiceTrie(constraints)) end
    end
    Gen.codegen_extend(gen, new_args, args_change, trace, constraints)
end
end)
