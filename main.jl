@use "./humane.jl" source
@use "./compact.jl" src
@use "./expr.jl" expr

hydrate(str; mod=Main) = begin
  m = Module()
  eval(m, :(using Kip))
  eval(m, :(const ctx = $mod))
  eval(m, Meta.parseall(str))
end

macro src(x)
  :(src($(esc(x)), mod=@__MODULE__))
end

macro hydrate(x)
  :(hydrate($(esc(x)), mod=@__MODULE__))
end
