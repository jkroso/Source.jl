@use "github.com/jkroso/Prospects.jl" interleave
@use PrettyPrinting: literal, list_layout, indent, pair_layout, Layout, pprint
@use MacroTools: rmlines, @capture, postwalk
@use "./expr" expr

source(io, x; mod=@__MODULE__) = begin
  expression = postwalk(expr(x)) do e
    e isa GlobalRef || return e
    e.mod == mod && return e.name
    e
  end
  pprint(io, tile(expression))
end

source(x; width=100, kwargs...) = begin
  io = IOBuffer()
  source(IOContext(io, :displaysize => (24, width)), x; kwargs...)
  String(take!(io))
end

indent_all(exprs) = Layout[indent(2)tile(x) for x in exprs]
list_layout(v::Vector{Any}; kwargs...) = list_layout(convert(Vector{Layout}, v); kwargs...)

tile(x) = literal(repr(x))
tile(x::Nothing) = literal("nothing")
tile(x::Missing) = literal("Missing")
tile(r::GlobalRef) = literal(string(r))
tile(s::Symbol) = literal(string(s))
tile(x::Expr) = tile(x, Val(x.head))
tile(x, ::Val{:call}) = begin
  @capture x name_(args__)
  if name isa Symbol && Base.isoperator(name)
    if length(args) == 1
      tile(name)list_layout(tile.(args), par=("",""))
    elseif name == :* && args[1] isa Real && args[2] isa Symbol
      tile(args[1])tile(args[2])
    else
      list_layout(tile.(interleave(args, name)), sep=" ", par=("",""))
    end
  else
    tile(name)list_layout(tile.(args))
  end
end

tile(x::QuoteNode) = literal(repr(x.value))
tile(x, ::Val{:quote}) = begin
  code = x.args[1]
  if Meta.isexpr(code, :block)
    /(literal("quote"), indent_all(rmlines(code).args)..., literal("end"))
  else
    literal(":(")tile(code)literal(")")
  end
end
tile(dolla, ::Val{:$}) = begin
  value = dolla.args[1]
  if value isa Union{Symbol,Number}
    literal("\$")tile(value)
  else
    literal("\$(")tile(value)literal(")")
  end
end

tile(string, ::Val{:string}) = *(literal("\""), render_interp.(string.args)..., literal("\""))
render_interp(x::String) = literal(x)
render_interp(x) =
  if x isa Symbol
    literal("\$")literal(string(x))
  else
    literal("\$(")tile(x)literal(")")
  end

tile(s::AbstractString) =
  if occursin(r"\n", s)
    /(literal("\"\"\""), literal.(split(s, '\n'))..., literal("\"\"\""))
  else
    literal(repr(s))
  end

tile(block, ::Val{:block}) = begin
  statements = rmlines(block).args
  length(statements) == 1 && return tile(statements[1])
  /(literal("begin"), indent_all(statements)..., literal("end"))
end

tile(x, ::Val{:(=)}) = pair_layout(tile.(x.args)..., sep=" = ")
tile(x, ::Val{:kw}) = pair_layout(tile.(x.args)..., sep="=")
tile(x, ::Val{:const}) = literal("const ")tile(x.args[1])

tile(x, ::Val{:(::)}) =
  if length(x.args) == 1
    literal("::")tile(x.args[1])
  else
    pair_layout(tile.(x.args)..., sep="::")
  end

tile(x, ::Val{:curly}) = begin
  @capture x name_{params__}
  tile(name)list_layout(compact.(params), par=("{","}"), sep=",")
end
compact(x) = tile(x)
compact(x::Expr) = compact(x, Val(x.head))
compact(x, v) = tile(x, v)
compact(x, ::Val{:<:}) = pair_layout(tile.(x.args)..., sep="<:")
compact(x, ::Val{:(=)}) = pair_layout(tile.(x.args)..., sep="=")

tile(fn, ::Val{:->}) = pair_layout(tile.(rmlines.(fn.args))..., sep="->")
tile(fn, ::Val{:function}) = begin
  call, body = fn.args
  /(literal("function ")tile(call), indent_all(rmlines(body).args)..., literal("end"))
end

tile(c, ::Val{:comprehension}) = comprehension(c.args[1], "[", "]")
tile(g, ::Val{:generator}) = comprehension(g, "(", ")")

comprehension(g, open, close) = begin
  body, assignments = g.args[1], g.args[2:end]
  assignments = if length(assignments) == 1
    pair_layout(tile.(assignments[1].args)..., sep=" in ")
  else
    list_layout(tile.(assignments), sep=", ", par=("",""))
  end
  *(literal(open), tile(body), literal(" for "), assignments, literal(close))
end

tile(t, ::Val{:tuple}) = length(t.args) == 1 ? literal("(")compact(t.args[1])literal(",)") : list_layout(compact.(t.args))
tile(v, ::Val{:vect}) = list_layout(tile.(v.args), par=("[", "]"))
tile(v, ::Val{:hcat}) = list_layout(tile.(v.args), sep=" ", par=("[", "]"))
tile(v, ::Val{:vcat}) = begin
  rows = v.args
  lines = collect([row(e, i==length(rows)) for (i, e) in enumerate(rows)])
  length(lines) == 1 && return literal("[")lines[1]literal(";]")
  h = *(literal("["), interleave(lines, literal("; "))..., literal("]"))
  v = /(literal("[")lines[1],
        map(x->indent(1)x, lines[2:end-1])...,
        indent(1)lines[end]literal("]"))
  h|v
end
row(e, islast) = *(interleave(tile.(e.args), literal(" "))...)

tile(r, ::Val{:ref}) = begin
  @capture r ref_[args__]
  tile(ref)list_layout(compact.(args), par=("[", "]"))
end

tile(cond, ::Val{:if}) = conditional(cond, literal("if"))

conditional(cond, kw) = begin
  pred, branch = cond.args
  if Meta.isexpr(branch, :block)
    v = /(kw*literal(" ")tile(pred), indent_all(rmlines(branch).args)...)
    length(cond.args) == 3 ? v/altbranch(cond.args[3]) : v/literal("end")
  else
    tile(pred)literal(" ? ")tile(branch)literal(" : ")tile(cond.args[3])
  end
end
elsebranch(e) = /(literal("else"), indent_all(rmlines(e).args)..., literal("end"))
altbranch(e) = Meta.isexpr(e, :elseif) ? conditional(e, literal("elseif")) : elsebranch(e)

tile(x, ::Val{:&&}) = list_layout(tile.(x.args), sep=" && ", par=("",""))
tile(x,  ::Val{:||}) = list_layout(tile.(x.args), sep=" || ", par=("",""))

tile(dot, ::Val{:.}) = begin
  left, right = dot.args
  r = if right isa QuoteNode && right.value isa Symbol
    tile(right.value)
  elseif Meta.isexpr(right, :tuple, 1)
    literal("(")tile(right.args[1])literal(")")
  else
    tile(right)
  end
  tile(left)literal(".")r
end

tile(splat, ::Val{:...}) = tile(splat.args[1])literal("...")

tile(struc, ::Val{:struct}) = begin
  mutable, name, body = struc.args
  kw = mutable ? literal("mutable struct ") : literal("struct ")
  lines = rmlines(body).args
  isempty(lines) && return kw*tile(name)literal(" end")
  /(kw*tile(name), indent_all(lines)..., literal("end"))
end

tile(struc, ::Val{:abstract}) = literal("abstract type ")tile(struc.args[1])literal(" end")

tile(meta, ::Val{:meta}) = literal(repr(meta))
tile(m, ::Val{:macro}) = begin
  call, block = m.args
  lines = rmlines(block).args
  /(literal("macro ")tile(call), indent_all(lines)..., literal("end"))
end

tile(params, ::Val{:parameters}) = literal(";")list_layout(tile.(params.args), par=("",""))
tile(e, ::Val{:<:}) = pair_layout(tile.(e.args)..., sep=" <: ")
tile(e, ::Val{:where}) =
  if length(e.args) == 1
    tile(e.args[1])
  elseif length(e.args) == 2
    pair_layout(tile.(e.args)..., sep=" where ")
  else
    *(tile(e.args[1]),
      literal(" where "),
      list_layout(compact.(e.args[2:end]), par=("{","}"), sep=","))
  end
tile(e, ::Val{:break}) = literal("break")
tile(e, ::Val{:continue}) = literal("continue")
tile(e, ::Val{:while}) = begin
  cond, body = e.args
  /(literal("while ")tile(cond), indent_all(rmlines(body).args)..., literal("end"))
end

tile(e, ::Val{:for}) = begin
  assignments, body = e.args
  assignment = if Meta.isexpr(assignments, :block)
    list_layout(tile.(rmlines(assignments).args), par=("",""))
  else
    pair_layout(tile.(assignments.args)..., sep=" in ")
  end
  /(literal("for ")assignment, indent_all(rmlines(body).args)..., literal("end"))
end

tile(e, ::Val{:macrocall}) = begin
  name, args = e.args[1], e.args[3:end]
  m = match(r"(\w+)_str$", string(name))
  if !isnothing(m)
    literal(m.captures[1])tile(args[1])
  elseif name == GlobalRef(Core, Symbol("@doc"))
    /(tile.(args)...)
  elseif length(args) == 1 && Meta.isexpr(args[1], :hcat)
    literal(name)tile(args[1])
  else
    tile(name)literal(" ")list_layout(tile.(args), sep=" ", par=("",""))
  end
end

tile(e, ::Val{:toplevel}) = /(tile.(e.args)...)
