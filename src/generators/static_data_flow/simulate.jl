struct StaticDataFlowSimulateState
    trace::Symbol
    score::Symbol
    stmts::Vector{Expr}
end

function process!(ir::DataFlowIR, state::StaticDataFlowSimulateState, node::JuliaNode)
    trace = state.trace
    (typ, trace_field) = get_value_info(node)
    push!(state.stmts, quote
        $trace.$trace_field = $(expr_read_from_trace(node, trace))
    end)
end

function process!(ir::DataFlowIR, state::StaticDataFlowSimulateState,
                  node::Union{ArgsChangeNode,AddrChangeNode})
    trace = state.trace
    (typ, trace_field) = get_value_info(node)
    push!(state.stmts, quote
        $trace.$trace_field = nothing
    end)
end

function process!(ir::DataFlowIR, state::StaticDataFlowSimulateState, node::AddrDistNode)
    trace, score = state.trace, state.score
    addr = node.address
    dist = QuoteNode(node.dist)
    args = get_args(trace, node)
    value = value_trace_ref(trace, node.output)
    push!(state.stmts, quote
        $value = random($dist, $(args...))
        $score += logpdf($dist, $value, $(args...))
        $trace.$is_empty_field = false
    end)
end

function process!(ir::DataFlowIR, state::StaticDataFlowSimulateState, node::AddrGeneratorNode)
    trace, score = state.trace, state.score
    addr = node.address
    gen = QuoteNode(node.gen)
    args = get_args(trace, node)
    call_record = gensym("call_record")
    push!(state.stmts, quote
        $trace.$addr = simulate($gen, $(Expr(:tuple, args...)))
        $call_record = get_call_record($trace.$addr)
        $score += $call_record.score
        $trace.$is_empty_field = $trace.$is_empty_field && !has_choices($trace.$addr)
    end)
    (_, trace_field) = get_value_info(node)
    push!(state.stmts, quote
        $trace.$trace_field = $call_record.retval
    end)
end

function codegen_simulate(gen::Type{T}, args) where {T <: StaticDataFlowGenerator}
    trace_type = get_trace_type(gen)
    ir = get_ir(gen)
    stmts = Expr[]

    # initialize trace and score
    trace = gensym("trace")
    score = gensym("score")
    push!(stmts, quote
        $trace = $trace_type()
        $score = 0.
        $trace.$is_empty_field = true
    end)

    # unpack arguments
    arg_names = Symbol[arg_node.name for arg_node in ir.arg_nodes]
    push!(stmts, Expr(:(=), Expr(:tuple, arg_names...), :args))

    # record arguments in trace
    for arg_node in ir.arg_nodes
        push!(stmts, quote $trace.$(value_field(arg_node)) = $(arg_node.name) end)
    end

    # record parameters in trace
    for param in ir.params
        value_node = ir.value_nodes[param.name]
        push!(stmts, quote $trace.$(value_field(value_node)) = gen.params[$(QuoteNode(param.name))] end)
    end

    # process expression nodes in topological order
    state = StaticDataFlowSimulateState(trace, score, stmts)
    for node in ir.expr_nodes_sorted
        process!(ir, state, node)
    end
    
    if ir.output_node === nothing
        retval = :nothing
    else
        retval = quote $trace.$(value_field(something(ir.output_node))) end
    end

    push!(stmts, quote
        $trace.$call_record_field = CallRecord($score, $retval, args)
        return $trace
    end)
    Expr(:block, stmts...)
end


push!(Gen.generated_functions, quote
@generated function Gen.simulate(gen::Gen.StaticDataFlowGenerator, args)
    Gen.codegen_simulate(gen, args)
end
end)
