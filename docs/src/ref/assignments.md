# Assignments

Maps from the addresses of random choices to their values are stored in associative tree-structured data structures that have the following abstract type:
```@docs
Assignment
```

Assignments are constructed by users to express observations and/or constraints on the traces of generative functions.
Assignments are also returned by certain Gen inference methods, and are used internally by various Gen inference methods.

Assignments provide the following methods:
```@docs
has_value
get_value
get_subassmt
get_values_shallow
get_subassmts_shallow
to_array
from_array
address_set
```
Note that none of these methods mutate the assignment.

Assignments also provide `Base.isempty`, which tests of there are no random
choices in the assignment, and `Base.merge`, which takes two assignments, and
returns a new assignment containing all random choices in either assignment.
It is an error if the assignments both have values at the same address, or if
one assignment has a value at an address that is the prefix of the address of a
value in the other assignment.


## Dynamic Assignment

One concrete assignment type is `DynamicAssignment`, which is mutable.
Users construct `DynamicAssignments` and populate them for use as observations or constraints, e.g.:
```julia
assmt = DynamicAssignment()
assmt[:x] = true
assmt["foo"] = 1.25
assmt[:y => 1 => :z] = -6.3
```

There is also a constructor for `DynamicAssignment` that takes initial (address, value) pairs:
```julia
assmt = DynamicAssignment((:x, true), ("foo", 1.25), (:y => 1 => :z, -6.3))
```

```@docs
DynamicAssignment
set_value!
set_subassmt!
```
