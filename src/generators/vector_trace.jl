using FunctionalCollections: PersistentVector

#######################################
# trace for vector of generator calls #
#######################################

"""

U is the type of the subtrace, R is the return value type for the kernel
"""
struct VectorTrace{T,U}
    subtraces::PersistentVector{U}
    call::CallRecord{PersistentVector{T}}
    is_empty::Bool
end

function VectorTrace{T,U}() where {T,U}
    VectorTrace{T,U}(PersistentVector{U}(), PersistentVector{T}(), true)
end

function get_subtrace(trace::VectorTrace{T,U}, i::Int) where {T,U}
    get(trace.subtraces, i)
end

# TODO need to manage is_empty

# trace API

get_call_record(trace::VectorTrace) = trace.call
has_choices(trace::VectorTrace) = !trace.is_empty
get_choices(trace::VectorTrace) = VectorTraceChoiceTrie(trace)

struct VectorTraceChoiceTrie <: ChoiceTrie
    trace::VectorTrace
end

Base.isempty(choices::VectorTraceChoiceTrie) = choices.trace.is_empty
get_address_schema(::Type{VectorTraceChoiceTrie}) = VectorAddressSchema()
has_internal_node(choices::VectorTraceChoiceTrie, addr) = false

function has_internal_node(choices::VectorTraceChoiceTrie, addr::Int)
    n = length(choices.trace.subtraces)
    addr >= 1 && addr <= n
end

function has_internal_node(choices::VectorTraceChoiceTrie, addr::Pair)
    (first, rest) = addr
    subchoices = get_choices(choices.trace.subtraces[first])
    has_internal_node(subchoices, rest)
end

function get_internal_node(choices::VectorTraceChoiceTrie, addr::Int)
    get_choices(choices.trace.subtraces[addr])
end

function get_internal_node(choices::VectorTraceChoiceTrie, addr::Pair)
    (first, rest) = addr
    subchoices = get_choices(choices.trace.subtraces[first])
    get_internal_node(subchoices, rest)
end

has_leaf_node(choices::VectorTraceChoiceTrie, addr) = false

function has_leaf_node(choices::VectorTraceChoiceTrie, addr::Pair)
    (first, rest) = addr
    subchoices = get_choices(choices.trace.subtraces[first])
    has_leaf_node(subchoices, rest)
end

function get_leaf_node(choices::VectorTraceChoiceTrie, addr::Pair)
    (first, rest) = addr
    subchoices = get_choices(choices.trace.subtraces[first])
    get_leaf_node(subchoices, rest)
end

function get_internal_nodes(choices::VectorTraceChoiceTrie)
    [(i, get_choices(choices.trace.subtraces[i])) for i=1:length(choices.trace.subtraces)]
end

get_leaf_nodes(choices::VectorTraceChoiceTrie) = []


##########################################
# trace for vector of distribution calls #
##########################################

struct VectorDistTrace{T}
    values::PersistentVector{T}
    call::CallRecord{PersistentVector{T}}
end

function VectorDistTrace{T}() where {T}
    VectorDistTrace{T}(PersistentVector{T}())
end

# trace API

get_call_record(trace::VectorDistTrace) = trace.call
has_choices(trace::VectorDistTrace) = length(trace.values) > 0
get_choices(trace::VectorDistTrace) = VectorDistTraceChoiceTrie(trace)

struct VectorDistTraceChoiceTrie <: ChoiceTrie
    trace::VectorDistTrace
end

Base.isempty(choices::VectorDistTraceChoiceTrie) = !has_choices(choices.trace)
get_address_schema(::Type{VectorDistTraceChoiceTrie}) = VectorAddressSchema()
has_internal_node(choices::VectorDistTraceChoiceTrie, addr) = false
has_leaf_node(choices::VectorDistTraceChoiceTrie, addr) = false

function get_leaf_node(choices::VectorDistTraceChoiceTrie, addr::Int)
    choices.trace.values[addr]
end

get_internal_nodes(choices::VectorDistTraceChoiceTrie) = ()
get_leaf_nodes(choices::VectorDistTraceChoiceTrie) = choices.values
