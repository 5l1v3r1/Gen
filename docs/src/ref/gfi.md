# Generative Function Interface

A *trace* is a record of an execution of a generative function.
There is no abstract type representing all traces.
Generative functions implement the *generative function interface*, which is a set of methods that involve the execution traces and probabilistic behavior of generative functions.
In the mathematical description of the interface methods, we denote arguments to a function by ``x``, complete assignments of values to addresses of random choices (containing all the random choices made during some execution) by ``t`` and partial assignments by either ``u`` or ``v``.
We denote a trace of a generative function by the tuple ``(x, t)``.
We say that two assignments ``u`` and ``t`` *agree* when they assign addresses that appear in both assignments to the same values (they can different or even disjoint sets of addresses and still agree).
A generative function is associated with a family of probability distributions ``P(t; x)`` on assignments ``t``, parameterized by arguments ``x``, and a second family of distributions ``Q(t; u, x)`` on assignments ``t`` parameterized by partial assignment ``u`` and arguments ``x``.
``Q`` is called the *internal proposal family* of the generative function, and satisfies that if ``u`` and ``t`` agree then ``P(t; x) > 0`` if and only if ``Q(t; x, u) > 0``, and that ``Q(t; x, u) > 0`` implies that ``u`` and ``t`` agree.
See the [Gen technical report](http://hdl.handle.net/1721.1/119255) for additional details.

### Non-addressabe random choices

Generative functions may also use *non-addressable random choices*, denoted ``r``.
Unlike regular (addressable) random choices, non-addressable random choices do not have addresses, and the value of non-addressable random choices is not exposed through the generative function interface.
However, the state of non-addressable random choices is maintained in the trace.
A trace that contains non-addressable random choices is denoted ``(x, t, r)``.
Non-addressable random choices manifest to the user of the interface as stochasticity in weights returned by generative function interface methods.
The behavior of non-addressable random choices is defined by an additional pair of families of distributions associated with the generative function, denoted ``Q(r; x, t)`` and ``P(r; x, t)``, which are defined for ``P(t; x) > 0``, and which satisfy ``Q(r; x, t) > 0`` if and only if ``P(r; x, t) > 0``.
For each generative function below, we describe its semantics first in the basic setting where there is no non-addressable random choices, and then in the more general setting that may include non-addressable random choices.

### Differentiable programming

Generative functions may support computation of gradients with respect to (i) all or a subset of its arguments, (ii) its **trainable parameters**, and (iii) the value of certain random choices.
The set of elements (either arguments, trainable parameters, or random choices) for which gradients are available is called the *gradient source set*.
A generative function statically reports whether or not it is able to compute gradients with respect to each of its arguments, through the function `has_argument_grads`.
Let ``x_G`` denote the set of arguments for which the generative function does support gradient computation.
Similarly, a generative function supports gradients with respect the value of random choices made at all or a subset of addresses.
If the return value of the function is conditionally independent of each element in the gradient source set given the other elements in the gradient source set and values of all other random choices, for all possible traces of the function, then the generative function requires a *return value gradient* to compute gradients with respect to elements of the gradient source set.
This static property of the generative function is reported by `accepts_output_grad`.

### Trainable parameters



### Interface methods

```@docs
has_argument_grads
accepts_output_grad
initialize
project
propose
assess
force_update
fix_update
free_update
extend
backprop_params
backprop_trace
get_assmt
get_args
get_retval
get_score
get_gen_fn
get_params
```
