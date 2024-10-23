# Method dispatch based on concepts
Concepts are compile-time predicates (functions that evaluate to true/false) given a concrete type as input. We use them to constrain template parameters in order to dispatch to the "right" template method. Our implementation is similar in scope to concepts in C++20.

# Types of concepts
We distinguise between the following types of concepts:
* collections: concepts that evaluate to true for a set of concrete types (used to create type hierarchies)
* constraints: concepts based on a set of constraints
* composition: combinations of other concepts (using "and", "or", "not")
* specials: ANY or NONE concept

Collections are a set of types, an explicit representation. Constraints on the other hand implicitly define a set. Compositions can be a combination of these two representations.

# Concepts and template method resolution
Its easy to evaluate concepts given a concrete type as input. What is more difficult is to compare concepts to determine which one is more specialized than the other. We assign scores to perform method selection as follows. 


Consider the following scenario: two template methods are candidate functions (which means all concepts pass on all concrete types that are passed) 

    f(C_1, C_2, ..., C_n)
    f(D_1, D_2, ..., D_n)

We need to check for k in {1, ...,n} if the concepts 

    C_k << D_k -> {score=1}             (C_k is more specialized than D_k)

or wheter

    C_k >> D_k -> {score=1}             (D_k is more specialized than C_k)

or they are equally specialized.

    C_k <=> D_k -> {score=0}

We dispatch as follows:

    * sum(C_k << D_k) > sum(C_k >> D_k) --> f(C_1, C_2, ..., C_n) 
    * sum(C_k << D_k) < sum(C_k >> D_k) --> f(D_1, D_2, ..., D_n)
    * sum(C_k << D_k) == sum(C_k >> D_k) --> ambiguity compile error


Key question: How do we define / measure specialization?

# How to measure specialization?
We assign a weight to the concept to measure its level of specialization

## Comparing collections
    * for comparing (compositions of) collections we just use ordinary set operations
    * collections of concrete types are always more specialized than (compositions of) constraints

## Comparing constraints

    * Concepts based on constraints can be assigned a weight, the number of constraints that are listed. For concept C we denote by #C this weight. 



## New "concept" domain specific language

template(T) where T implements Concept{}
    terra ...


    end
end

template(T) where T <: Concept
    terra ...


    end
end
