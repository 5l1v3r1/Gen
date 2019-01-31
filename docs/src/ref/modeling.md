# Built-in Modeling Language

Gen provides a built-in embedded modeling language for defining generative functions.
The language uses a syntax that extends Julia's syntax for defining regular Julia functions.

Generative functions in the modeling language are identified using the `@gen` keyword in front of a Julia function definition.
Here is an example `@gen` function that samples two random choices:
```julia
@gen function foo(prob::Float64)
    z1 = @addr(bernoulli(prob), :a)
    z2 = @addr(bernoulli(prob), :b)
    return z1 || z2
end
```
After running this code, `foo` is a Julia value of type [`DynamicDSLFunction`](@ref):
```@docs
DynamicDSLFunction
```

We can call the resulting generative function like we would a regular Julia function:
```julia
retval::Bool = foo(0.5)
```
We can also trace its execution:
```julia
(trace, _) = initialize(foo, (0.5,))
```
See [Generative Functions](@ref) for the full set of operations supported by a generative function.
Note that the built-in modeling language described in this section is only one of many ways of defining a generative function -- generative functions can also be constructed using other embedded languages, or by directly implementing the methods of the generative function interface.
However, the built-in modeling language is intended to being flexible enough cover a wide range of use cases.
In the remainder of this section, we refer to generative functions defined using the built-in modeling language as `@gen` functions.

## Annotations

Annotations are a syntactic construct in the built-in modeling language that allows users to provide additional information about how `@gen` functions should be interpreted.
Annotations are optional, and not necessary to understand the basics of Gen.
There are two types of annotations -- *argument annotations* and *function annotations*.

**Argument annotations.** In addition to type declarations on arguments like regular Julia functions, `@gen` functions also support additional annotations on arguments.
Each argument can have the following different syntactic forms:

- `y`: No type declaration; no annotations.

- `y::Float64`: Type declaration; but no annotations.

- `(grad)(y)`: No type declaration provided;, annotated with `grad`.

- `(grad)(y::Float64)`: Type declaration provided; and annotated with `grad`.

Currently, the possible argument annotations are:

- `grad` (see [Differentiable programming](@ref)).

**Function annotations.** The `@gen` function itself can also be optionally associated with zero or more annotations, which are separate from the per-argument annotations.
Function-level annotations use the following different syntactic forms:

- `@gen function foo(<args>) <body> end`: No function annotations.

- `@gen (grad) function foo(<args>) <body> end`: The function has the `grad` annotation.

- `@gen (grad,static) function foo(<args>) <body> end`: The function has both the `grad` and `static` annotations.

Currently the possible function annotations are:

- `grad` (see [Differentiable programming](@ref)).

- `static` (see [Static DSL](@ref)).

## Making random choices

Random choices are made by calling a probability distribution on some arguments:
```julia
val::Bool = bernoulli(0.5)
```
See [Probability Distributions](@ref) for the set of built-in probability distributions, and for information on implementing new probability distributions.

In the body of a `@gen` function, wrapping a call to a random choice with an `@addr` expression associates the random choice with an *address*, and evaluates to the value of the random choice.
The syntax is:
```julia
@addr(<distribution>(<args>), <addr>)
```
Addresses can be any Julia value.
Here, we give the Julia symbol address `:z` to a Bernoulli random choice.
```julia
val::Bool = @addr(bernoulli(0.5), :z)
```
Not all random choices need to be given addresses.
An address is required if the random choice will be observed, or will be referenced by a custom inference algorithm (e.g. if it will be proposed to by a custom proposal distribution).

It is recommended to ensure that the support of a random choice at a given address (the set of values with nonzero probability or probability density) is constant across all possible executions of the `@gen` function.
This discipline will simplify reasoning about the probabilistic behavior of the function, and will help avoid difficult-to-debug NaNs or Infs from appearing.
If the support of a random choice needs to change, consider using a different address for each distinct support.


## Calling generative functions

`@gen` functions can invoke other generative functions in three ways:

**Untraced call**:
If `foo` is a generative function, we can invoke `foo` from within the body of a `@gen` function using regular call syntax.
The random choices made within the call are not given addresses in our trace, and are therefore *non-addressable* random choices (see [Generative Function Interface](@ref) for details on non-addressable random choices).
```julia
val = foo(0.5)
```

**Traced call with a nested address namespace**:
We can include the addressable random choices made by `foo` in the caller's trace, under a namespace, using `@addr`:
```julia
val = @addr(foo(0.5), :x)
```
Now, all random choices made by `foo` are included in our trace, under the namespace `:x`.
For example, if `foo` makes random choices at addresses `:a` and `:b`, these choices will have addresses `:x => :a` and `:x => :b` in the caller's trace.

**Traced call with shared address namespace**:
We can include the addressable random choices made by `foo` in the caller's trace using `@splice`:
```julia
val = @splice(foo(0.5))
```
Now, all random choices made by `foo` are included in our trace.
The caller must guarantee that there are no address collisions.
NOTE: This type of call can only be used when calling other `@gen` functions. Other types of generative functions cannot be called in this way.


## Composite addresses

In Julia, `Pair` values can be constructed using the `=>` operator.
For example, `:a => :b` is equivalent to `Pair(:a, :b)` and `:a => :b => :c` is equivalent to `Pair(:a, Pair(:b, :c))`.
A `Pair` value (e.g. `:a => :b => :c`) can be passed as the address field in an `@addr` expression, provided that there is not also a random choice or generative function called with `@addr` at any prefix of the address.

Consider the following examples.

This example is **invalid** because `:a => :b` is a prefix of `:a => :b => :c`:
```julia
@addr(normal(0, 1), :a => :b => :c)
@addr(normal(0, 1), :a => :b)
```

This example is **invalid** because `:a` is a prefix of `:a => :b => :c`:
```julia
@addr(normal(0, 1), :a => :b => :c)
@addr(normal(0, 1), :a)
```

This example is **invalid** because `:a => :b` is a prefix of `:a => :b => :c`:
```julia
@addr(normal(0, 1), :a => :b => :c)
@addr(foo(0.5), :a => :b)
```

This example is **invalid** because `:a` is a prefix of `:a => :b`:
```julia
@addr(normal(0, 1), :a)
@addr(foo(0.5), :a => :b)
```

This example is **valid** because `:a => :b` and `:a => :c` are not prefixes of one another:
```julia
@addr(normal(0, 1), :a => :b)
@addr(normal(0, 1), :a => :c)
```

This example is **valid** because `:a => :b` and `:a => :c` are not prefixes of one another:
```julia
@addr(normal(0, 1), :a => :b)
@addr(foo(0.5), :a => :c)
```

## Return value

Like regular Julia functions, `@gen` functions return either the expression used in a `return` keyword, or by evaluating the last expression in the function body.
Note that the return value of a `@gen` function is different from a trace of `@gen` function, which contains the return value associated with an execution as well as the assignment to each random choice made during the execution.
See [Generative Function Interface](@ref) for more information about traces.


## Trainable parameters

A `@gen` function may begin with an optional block of *trainable parameter declarations*.
The block consists of a sequence of statements, beginning with `@param`, that declare the name and Julia type for each trainable parameter.
The function below has a single trainable parameter `theta` with type `Float64`:
```julia
@gen function foo(prob::Float64)
    @param theta::Float64
    z1 = @addr(bernoulli(prob), :a)
    z2 = @addr(bernoulli(theta), :b)
    return z1 || z2
end
```
Trainable parameters obey the same scoping rules as Julia local variables defined at the beginning of the function body.
The value of a trainable parameter is undefined until it is initialized using [`init_param!`](@ref).
In addition to the current value, each trainable parameter has a current **gradient accumulator** value.
The gradent accumulator value has the same shape (e.g. array dimension) as the parameter value.
It is initialized to all zeros, and is incremented by [`backprop_params`](@ref).

The following methods are exported for the trainable parameters of `@gen` functions:
```@docs
init_param!
get_param
get_param_grad
set_param!
zero_param_grad!
```

Trainable parameters are designed to be trained using gradient-based methods.
This is discussed in the next section.

## Differentiable programming

Given a trace of a `@gen` function, Gen supports automatic differentiation of the log probability (density) of all of the random choices made in the trace with respect to the following types of inputs:

- all or a subset of the arguments to the function.

- the values of all or a subset of random choices.

- all or a subset of trainable parameters of the `@gen` function.

We first discuss the semantics of these gradient computations, and then discuss what how to write and use Julia code in the body of a `@gen` function so that it can be automatically differentiated by the gradient computation.

### Supported gradient computations

**Gradients with respect to arguments.**
A `@gen` function may have a fixed set of its arguments annotated with `grad`, which indicates that gradients with respect to that argument should be supported.
For example, in the function below, we indicate that we want to support differentiation with respect to the `y` argument, but that we do not want to support differentiation with respect to the `x` argument.
```julia
@gen function foo(x, (grad)(y))
    if x > 5
        @addr(normal(y, 1), :z)
    else
        @addr(normal(y, 10), :z)
    end
end
```
For the function `foo` above, when `x > 5`, the gradient with respect to `y` is the gradient of the log probability density of a normal distribution with standard deviation 1, with respect to its mean, evaluated at mean `y`.
When `x <= 5`, we instead differentiate the log density of a normal distribution with standard deviation 10, relative to its mean.

**Gradients with respect to values of random choices.**
The author of a `@gen` function also identifies a set of addresses of random choices with respect to which they wish to support gradients of the log probability (density).
Gradients of the log probability (density) with respect to the values of random choices are used in gradient-based numerical optimization of random choices, as well as certain MCMC updates that require gradient information.

**Gradients with respect to trainable parameters.**
The gradient of the log probability (density) with respect to the trainable parameters can also be computed using automatic differentiation.
Currently, the log probability (density) must be a differentiable function of all trainable parameters.

**Gradients of a function of the return value.**
Differentiable programming in Gen composes across function calls.
If the return value of the `@gen` function is conditionally dependent on source elements including (i) any arguments annotated with `grad` or (ii) any random choices for which gradients are supported, or (ii) any trainable parameters, then the gradient computation requires a gradient of the an external function with respect to the return value in order to the compute the correct gradients.
Thus, the function being differentiated always includes a term representing the log probability (density) of all random choices made by the function, but can be extended with a term that depends on the return value of the function.
The author of a `@gen` function can indicate that the return value depends on the source elements (causing the gradient with respect to the return value is required for all gradient computations) by adding the `grad` annotation to the `@gen` function itself.
For example, in the function below, the return value is conditionally dependent (and actually identical to) on the random value at address `:z`:
```julia
@gen function foo(x, (grad)(y))
    if x > 5
        return @addr(normal(y, 1), :z)
    else
        return @addr(normal(y, 10), :z)
    end
end
```
If the author of `foo` wished to support the computation of gradients with respect to the value of `:z`, they would need to add the `grad` annotation to `foo` using the following syntax:
```julia
@gen (grad) function foo(x, (grad)(y))
    if x > 5
        return @addr(normal(y, 1), :z)
    else
        return @addr(normal(y, 10), :z)
    end
end
```

### Writing differentiable code

In order to compute the gradients described above, the code in the body of the `@gen` function needs to be differentiable.
Code in the body of a `@gen` function consists of:

- Julia code

- Making random choices

- Calling generative functions

We now discuss how to ensure that code of each of these forms is differentiable.
Note that the procedures for differentiation of code described below are only performed during certain operations on `@gen` functions ([`backprop_trace`](@ref) and [`backprop_params`](@ref)).

**Julia code.**
Julia code used within a body of a `@gen` function is made differentiable using the [ReverseDiff](https://github.com/JuliaDiff/ReverseDiff.jl) package, which implements  reverse-mode automatic differentiation.
Specifically, values whose gradient is required (either values of arguments, random choices, or trainable parameters) are 'tracked' by boxing them into special values and storing the tracked value on a 'tape'.
For example a `Float64` value is boxed into a `ReverseDiff.TrackedReal` value.
Methods (including e.g. arithmetic operators) are defined that operate on these tracked values and produce other tracked values as a result.
As the computation proceeds all the values are placed onto the tape, with back-references to the parent operation and operands.
Arithmetic operators, array and linear algebra functions, and common special numerical functions, as well as broadcasting, are automatically supported.
See [ReverseDiff](https://github.com/JuliaDiff/ReverseDiff.jl) for more details.

**Making random choices.**
When making a random choice, each argument is either a tracked value or not.
If the argument is a tracked value, then the probability distribution must support differentiation of the log probability (density) with respect to that argument.
Otherwise, an error is thrown.
The [`has_argument_grads`](@ref) function indicates which arguments support differentiation for a given distribution (see [Probability Distributions](@ref)).
If the gradient is required for the *value* of a random choice, the distribution must support differentiation of the log probability (density) with respect to the value.
This is indicated by the [`has_output_grad`](@ref) function.

**Calling generative functions.**
Like distributions, generative functions indicate which of their arguments support differentiation, using the `has_argument_grads` function.
It is an error if a tracked value is passed as an argument of a generative function, when differentiation is not supported by the generative function for that argument.
If a generative function `gen_fn` has `accepts_output_grad(gen_fn) = true`, then the return value of the generative function call will be tracked and will propagate further through the caller `@gen` function's computation.

## Differencing code

`@gen` functions may include blocks of *differencing code* annotated with the `@diff` keyword.
Code that is annotated with `@diff` is only executed during one of the [Trace update methods](@ref).
During a trace update operation, `@diff` code is simply inserted inline into the body of the generative function.
Therefore, `@diff` code can read from the state of the non-diff code.
However, the flow of information is one-directional: diff` code is not permitted to affect the state of the regular code.

`@diff` code is used to compute the retdiff value for the update (see [Retdiff](@ref)) and the argdiff values for calls to generative function calls (see [Argdiff](@ref)).
To compute these values, the `@diff` code has access to special keywords:

`@argdiff`, which returns the argdiff that was passed to the update method for the generative function.

`@choicediff`, which returns a value of one of the following types that indicates whether the random choice changed or not:
```@docs
NewChoiceDiff
NoChoiceDiff
PrevChoiceDiff
```

`@calldiff`, which returns a value of one of the following types that provides information about the change in return value from the function:
```@docs
NewCallDiff
NoCallDiff
UnknownCallDiff
CustomCallDiff
```

To set a retdiff value, the `@diff` code uses the `@retdiff` keyword.

**Example.**
In the function below, if the argument is false and the argument did not change, then there is no change to the return value.
If the argument did not change, and :a and :b did not change, then there is no change to the return value.
Otherwise, return an [`DefaultRetDiff`](@ref) value.
```julia
@gen function foo(val::Bool)
    val = val && @addr(bernoulli(0.3), :a)
    val = val && @addr(bernoulli(0.4), :b)
    @diff begin
        argdiff = @argdiff()
        if argdiff == noargdiff
            if !val || (isnodiff(@choicediff(:a)) && isnodiff(@choicediff(:b)))
                @retdiff(noretdiff)
            else
                @retdiff(defaultretdiff)
            end
        else
            @retdiff(defaultretdiff)
        end
    end
    return val
end
```

## Static DSL

The *Static DSL* supports a subset of the built-in modeling language.
A static DSL function is identified by adding the `static` annotation to the function.
For example:
```julia
@gen (static) function foo(prob::Float64)
    z1 = @addr(bernoulli(prob), :a)
    z2 = @addr(bernoulli(prob), :b)
    z3 = z1 || z2
    return z3
end
```

After running this code, `foo` is a Julia value whose type is a subtype of `StaticIRGenerativeFunction`, which is a subtype of `GenerativeFunction`.

The static DSL permits a subset of the syntax of the built-in modeling language.
In particular, each statement must be one of the following forms:

- `<symbol> = <julia-expr>`

- `<symbol> = @addr(<dist|gen-fn>(..),<symbol> [ => ..])`

- `@addr(<dist|gen-fn>(..),<symbol> [ => ..])`

- `return <symbol>`

Currently, trainable parameters are not supported in static DSL functions.

Note that the `@addr` keyword may only appear in at the top-level of the right-hand-side expresssion.
Also, addresses used with the `@addr` keyword must be a literal Julia symbol (e.g. `:a`). If multi-part addresses are used, the first component in the multi-part address must be a literal Julia symbol (e.g. `:a => i` is valid).

Also, symbols used on the left-hand-side of assignment statements must be unique (this is called 'static single assignment' (SSA) form) (this is called 'static single-assignment' (SSA) form).

**Loading generated functions.**
Before a static DSL function can be invoked at runtime, `Gen.load_generated_functions()` method must be called.
Typically, this call immediately preceeds the execution of the inference algorithm.

**Performance tips.**
For better performance, annotate the left-hand side of random choices with the type.
This permits a more optimized trace data structure to be generated for the generative function.
For example:
```julia
@gen (static) function foo(prob::Float64)
    z1::Bool = @addr(bernoulli(prob), :a)
    z2::Bool = @addr(bernoulli(prob), :b)
    z3 = z1 || z2
    return z3
end
```
