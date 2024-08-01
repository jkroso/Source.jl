@use "./compact.jl" src
@use "./humane.jl" serialize
@use "./expr.jl" expr

hydrate(str; mod=Main) = begin
  m = Module()
  eval(m, :(using Kip))
  eval(m, :(const ctx = $mod))
  eval(m, Meta.parseall(str))
end
