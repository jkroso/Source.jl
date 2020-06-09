@use "github.com" [
  "rbt-lang/PrettyPrinting.jl" pprint tile literal list_layout indent pair_layout Layout
  "MikeInnes/MacroTools.jl" rmlines @capture
  "jkroso/Prospects.jl" interleave
  "jkroso/DynamicVar.jl" @dynamic!]

const m = Ref{Module}(Main)

resize(w, io) = IOContext(io, :displaysize => (24, w))
serialize(io, x; mod=@__MODULE__) = @dynamic! let m=mod; pprint(io, x) end
serialize(x; width=100, kwargs...) = begin
  io = IOBuffer()
  serialize(resize(width, io), x; kwargs...)
  String(take!(io))
end

name(T::UnionAll, m) = name(T.body, m)
name(T::DataType, m) = begin
  n = T.name.name
  string(isdefined(m, n) ? n : T)
end

tile(x::Set) = list_layout(tile.(x), prefix="Set", par=("([", "])"))

tile(x::T) where T = begin
  keys = fieldnames(T)
  isempty(keys) && return literal(repr(x))
  vals = (getfield(x, k) for k in keys)
  list_layout(tile.(vals), prefix=name(T, m[]))
end

tile(m::Module) = literal(string(m))

indent_all(exprs) = Layout[indent(2)expr(x) for x in exprs]
list_layout(v::Vector{Any}; kwargs...) = list_layout(convert(Vector{Layout}, v); kwargs...)

tile(x::Expr) = expr(x)
expr(x) = literal(repr(x))
expr(r::GlobalRef) = literal(string(r))
expr(s::Symbol) = literal(string(s))
expr(x::Expr) = expr(x, Val(x.head))
expr(x, ::Val{:call}) = begin
  @capture x name_(args__)
  if name isa Symbol && Base.isoperator(name)
    if length(args) == 1
      expr(name)list_layout(expr.(args), par=("",""))
    elseif name == :* && args[1] isa Real && args[2] isa Symbol
      expr(args[1])expr(args[2])
    else
      list_layout(expr.(interleave(args, name)), sep=" ", par=("",""))
    end
  else
    expr(name)list_layout(expr.(args))
  end
end

expr(x::QuoteNode) = literal(":")expr(x.value)
expr(x, ::Val{:quote}) = begin
  code = x.args[1]
  if Meta.isexpr(code, :block)
    /(literal("quote"), indent_all(rmlines(code).args)..., literal("end"))
  else
    literal(":(")expr(code)literal(")")
  end
end
expr(dolla, ::Val{:$}) = begin
  value = dolla.args[1]
  if value isa Union{Symbol,Number}
    literal("\$")expr(value)
  else
    literal("\$(")expr(value)literal(")")
  end
end

expr(string, ::Val{:string}) = *(literal("\""), render_interp.(string.args)..., literal("\""))
render_interp(x::String) = literal(x)
render_interp(x) =
  if x isa Symbol
    literal("\$")literal(string(x))
  else
    literal("\$(")expr(x)literal(")")
  end

expr(s::AbstractString) =
  if occursin(r"\n", s)
    /(literal("\"\"\""), literal.(split(s, '\n'))..., literal("\"\"\""))
  else
    literal(repr(s))
  end

expr(block, ::Val{:block}) = begin
  statements = rmlines(block).args
  length(statements) == 1 && return expr(statements[1])
  /(literal("begin"), indent_all(statements)..., literal("end"))
end

expr(x, ::Val{:(=)}) = pair_layout(expr.(x.args)..., sep=" = ")
expr(x, ::Val{:kw}) = pair_layout(expr.(x.args)..., sep="=")
expr(x, ::Val{:const}) = literal("const ")expr(x.args[1])

expr(x, ::Val{:(::)}) =
  if length(x.args) == 1
    literal("::")expr(x.args[1])
  else
    pair_layout(expr.(x.args)..., sep="::")
  end

expr(x, ::Val{:curly}) = begin
  @capture x name_{params__}
  expr(name)list_layout(compact.(params), par=("{","}"), sep=",")
end
compact(x) = expr(x)
compact(x::Expr) = compact(x, Val(x.head))
compact(x, ::Val{:<:}) = pair_layout(expr.(x.args)..., sep="<:")
compact(x, ::Val{:(=)}) = pair_layout(expr.(x.args)..., sep="=")

expr(fn, ::Val{:->}) = pair_layout(expr.(rmlines.(fn.args))..., sep="->")
expr(fn, ::Val{:function}) = begin
  call, body = fn.args
  /(literal("function ")expr(call), indent_all(rmlines(body).args)..., literal("end"))
end

expr(c, ::Val{:comprehension}) = comprehension(c.args[1], "[", "]")
expr(g, ::Val{:generator}) = comprehension(g, "(", ")")

comprehension(g, open, close) = begin
  body, assignments = g.args[1], g.args[2:end]
  assignments = if length(assignments) == 1
    pair_layout(expr.(assignments[1].args)..., sep=" in ")
  else
    list_layout(expr.(assignments), sep=", ", par=("",""))
  end
  *(literal(open), expr(body), literal(" for "), assignments, literal(close))
end

expr(t, ::Val{:tuple}) = length(t.args) == 1 ? literal("(")compact(t.args[1])literal(",)") : list_layout(compact.(t.args))
expr(v, ::Val{:vect}) = list_layout(expr.(v.args), par=("[", "]"))
expr(v, ::Val{:hcat}) = list_layout(expr.(v.args), sep=" ", par=("[", "]"))
expr(v, ::Val{:vcat}) = begin
  rows = v.args
  lines = collect([row(e, i==length(rows)) for (i, e) in enumerate(rows)])
  length(lines) == 1 && return literal("[")lines[1]literal(";]")
  h = *(literal("["), interleave(lines, literal("; "))..., literal("]"))
  v = /(literal("[")lines[1],
        map(x->indent(1)x, lines[2:end-1])...,
        indent(1)lines[end]literal("]"))
  h|v
end
row(e, islast) = *(interleave(expr.(e.args), literal(" "))...)

expr(r, ::Val{:ref}) = begin
  @capture r ref_[args__]
  expr(ref)list_layout(compact.(args), par=("[", "]"))
end

expr(cond, ::Val{:if}) = conditional(cond, literal("if"))

conditional(cond, kw) = begin
  pred, branch = cond.args
  if Meta.isexpr(branch, :block)
    v = /(kw*literal(" ")expr(pred), indent_all(rmlines(branch).args)...)
    length(cond.args) == 3 ? v/altbranch(cond.args[3]) : v/literal("end")
  else
    expr(pred)literal(" ? ")expr(branch)literal(" : ")expr(cond.args[3])
  end
end
elsebranch(e) = /(literal("else"), indent_all(rmlines(e).args)..., literal("end"))
altbranch(e) = Meta.isexpr(e, :elseif) ? conditional(e, literal("elseif")) : elsebranch(e)

expr(x, ::Val{:&&}) = list_layout(expr.(x.args), sep=" && ", par=("",""))
expr(x,  ::Val{:||}) = list_layout(expr.(x.args), sep=" || ", par=("",""))

expr(dot, ::Val{:.}) = begin
  left, right = dot.args
  r = if right isa QuoteNode && right.value isa Symbol
    expr(right.value)
  elseif Meta.isexpr(right, :tuple, 1)
    literal("(")expr(right.args[1])literal(")")
  else
    expr(right)
  end
  expr(left)literal(".")r
end

expr(struc, ::Val{:struct}) = begin
  mutable, name, body = struc.args
  kw = mutable ? literal("mutable struct ") : literal("struct ")
  lines = rmlines(body).args
  isempty(lines) && return kw*expr(name)literal(" end")
  /(kw*expr(name), indent_all(lines)..., literal("end"))
end

expr(struc, ::Val{:abstract}) = literal("abstract type ")expr(struc.args[1])literal(" end")

expr(meta, ::Val{:meta}) = literal(repr(meta))
expr(m, ::Val{:macro}) = begin
  call, block = m.args
  lines = rmlines(block).args
  /(literal("macro ")expr(call), indent_all(lines)..., literal("end"))
end

expr(params, ::Val{:parameters}) = literal(";")list_layout(expr.(params.args), par=("",""))
expr(e, ::Val{:<:}) = pair_layout(expr.(e.args)..., sep=" <: ")
expr(e, ::Val{:where}) = pair_layout(expr.(e.args)..., sep=" where ")
expr(e, ::Val{:break}) = literal("break")
expr(e, ::Val{:continue}) = literal("continue")
expr(e, ::Val{:while}) = begin
  cond, body = e.args
  /(literal("while ")expr(cond), indent_all(rmlines(body).args)..., literal("end"))
end

expr(e, ::Val{:for}) = begin
  assignments, body = e.args
  assignment = if Meta.isexpr(assignments, :block)
    list_layout(expr.(rmlines(assignments).args), par=("",""))
  else
    pair_layout(expr.(assignments.args)..., sep=" in ")
  end
  /(literal("for ")assignment, indent_all(rmlines(body).args)..., literal("end"))
end

expr(e, ::Val{:macrocall}) = begin
  name, args = e.args[1], e.args[3:end]
  m = match(r"(\w+)_str$", string(name))
  if !isnothing(m)
    literal(m.captures[1])expr(args[1])
  elseif name == GlobalRef(Core, Symbol("@doc"))
    /(expr.(args)...)
  elseif length(args) == 1 && Meta.isexpr(args[1], :hcat)
    literal(name)expr(args[1])
  else
    expr(name)literal(" ")list_layout(expr.(args), sep=" ", par=("",""))
  end
end
