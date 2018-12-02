using FunctionalCollections: PersistentVector

struct Params
    prob_outlier::Float64
    slope::Float64
    intercept::Float64
    inlier_std::Float64
    outlier_std::Float64
end

@staticgen function datum(x, @grad(params::Params)) # TODO @grad on params?
    is_outlier::Bool = @addr(bernoulli(params.prob_outlier), :z)
    std::Float64 = is_outlier ? params.inlier_std : params.outlier_std
    y::Float64 = @addr(normal(x * params.slope + params.intercept, std), :y)
    return y
end

data_fn = Map(datum)

@staticgen function model(xs::Vector{Float64})
    n = length(xs)
    inlier_std::Float64 = @addr(gamma(1, 1), :inlier_std)
    outlier_std::Float64 = @addr(gamma(1, 1), :outlier_std)
    slope::Float64 = @addr(normal(0, 2), :slope)
    intercept::Float64 = @addr(normal(0, 2), :intercept)
    params = Params(0.5, inlier_std, outlier_std, slope, intercept)
    ys::PersistentVector{Float64} = @addr(data_fn(xs, fill(params, n)), :data)
    return ys
end

@testset "static DSL" begin

function get_node_by_name(ir, name::Symbol)
    nodes = filter((node) -> (node.name == name), ir.nodes)
    @assert length(nodes) == 1
    nodes[1]
end

#####################
# check IR of datum #
#####################

ir = Gen.get_ir(typeof(datum))

# argument nodes
@test length(ir.arg_nodes) == 2
x = ir.arg_nodes[1]
params = ir.arg_nodes[2]
@test x.name == :x
@test x.typ == Any
@test !x.compute_grad
@test params.name == :params
@test params.typ == Params
@test params.compute_grad

# choice nodes and call nodes
@test length(ir.choice_nodes) == 2
@test length(ir.call_nodes) == 0

# is_outlier
is_outlier = ir.choice_nodes[1]
@test is_outlier.name == :is_outlier
@test is_outlier.addr == :z
@test is_outlier.typ == Bool
@test is_outlier.dist == bernoulli
@test length(is_outlier.inputs) == 1

# std
std = get_node_by_name(ir, :std)
@test isa(std, Gen.JuliaNode)
@test std.name == :std
@test std.typ == Float64
@test length(std.inputs) == 2
in1 = std.inputs[1]
in2 = std.inputs[2]
@test (in1 === is_outlier && in2 === params) || (in2 === is_outlier && in1 === params)

# y
y = ir.choice_nodes[2]
@test y.name == :y
@test y.addr == :y
@test y.typ == Float64
@test y.dist == normal
@test length(y.inputs) == 2
@test y.inputs[2] === std

# y_mean
y_mean = y.inputs[1]
@test isa(y_mean, Gen.JuliaNode)
@test y_mean.typ == Any
@test length(y_mean.inputs) == 2
in1 = y_mean.inputs[1]
in2 = y_mean.inputs[2]
@test (in1 === x && in2 === params) || (in2 === x && in1 === params)

# prob outlier
prob_outlier = is_outlier.inputs[1]
@test isa(prob_outlier, Gen.JuliaNode)
@test length(prob_outlier.inputs) == 1
@test prob_outlier.inputs[1] === params
@test prob_outlier.typ == Any

@test ir.return_node === y

#####################
# check IR of model #
#####################

ir = Gen.get_ir(typeof(model))
@test length(ir.arg_nodes) == 1
xs = ir.arg_nodes[1]
@test xs.name == :xs
@test xs.typ == Vector{Float64}
@test !xs.compute_grad

# choice nodes and call nodes
@test length(ir.choice_nodes) == 4
@test length(ir.call_nodes) == 1

# inlier_std
inlier_std = ir.choice_nodes[1]
@test inlier_std.name == :inlier_std
@test inlier_std.addr == :inlier_std
@test inlier_std.typ == Float64
@test inlier_std.dist == gamma
@test length(inlier_std.inputs) == 2

# outlier_std 
outlier_std = ir.choice_nodes[2]
@test outlier_std.name == :outlier_std
@test outlier_std.addr == :outlier_std
@test outlier_std.typ == Float64
@test outlier_std.dist == gamma
@test length(outlier_std.inputs) == 2

# slope 
slope = ir.choice_nodes[3]
@test slope.name == :slope
@test slope.addr == :slope
@test slope.typ == Float64
@test slope.dist == normal
@test length(slope.inputs) == 2

# intercept 
intercept = ir.choice_nodes[4]
@test intercept.name == :intercept
@test intercept.addr == :intercept
@test intercept.typ == Float64
@test intercept.dist == normal
@test length(intercept.inputs) == 2

# data
ys = ir.call_nodes[1]
@test ys.name == :ys
@test ys.addr == :data
@test ys.typ == PersistentVector{Float64}
@test ys.generative_function == data_fn
@test length(ys.inputs) == 2
@test ys.inputs[1] == xs

# params
params = get_node_by_name(ir, :params)
@test isa(params, Gen.JuliaNode)
@test params.name == :params
@test params.typ == Any
@test length(params.inputs) == 4
@test slope in params.inputs
@test intercept in params.inputs
@test inlier_std in params.inputs
@test outlier_std in params.inputs

# n
n = get_node_by_name(ir, :n)
@test isa(n, Gen.JuliaNode)
@test n.name == :n
@test n.typ == Any
@test length(n.inputs) == 1
@test n.inputs[1] === xs

# params_vec
params_vec = ys.inputs[2]
@test isa(params_vec, Gen.JuliaNode)
@test params_vec.typ == Any
@test length(params_vec.inputs) == 2
in1 = params_vec.inputs[1]
in2 = params_vec.inputs[2]
@test (in1 === params && in2 === n) || (in2 === params && in1 === n)

@test ir.return_node === ys

end # @testset "static DSL"
