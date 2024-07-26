@use "./compact.jl" src evalstring
@use "./humane.jl" serialize
@use "./expr.jl" expr

hydrate(str) = evalstring(str)
