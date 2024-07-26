@use "github.com/jkroso/DynamicVar.jl" @dynamic!
@use "./expr" expr generate_import evalstring
@use MacroTools: postwalk, @capture

mapjoin(fn, io, itr, (pre, sep, post)=('(', ',', ')')) = begin
  first = true
  write(io, pre)
  for value in itr
    first ? (first = false) : write(io, sep)
    fn(io, value)
  end
  write(io, post)
end

@dynamic! globals = Set{GlobalRef}()

src(x) = @dynamic! let globals = Set{GlobalRef}()
  str = sprint(src, x)
  buf = IOBuffer()
  gs = filter(globals[]) do g
    g.mod in (Main, Core) && return false
    !isdefined(Main, g.name)
  end
  s = join([(generate_import(g) for g in gs)..., str], '\n')
  replace(s, r"#=[^=]+=# " => "")
end

src(io::IO, x) = begin
  e = expr(x)
  e == x ? print(io, x) : src(io, e)
end

ref(s::Symbol) = s
ref(g::GlobalRef) = begin
  push!(globals[], g)
  g.name
end
ref(D::DataType) = ref(GlobalRef(getmod(D), getname(D)))
getmod(D::DataType) = D.name.module
getmod(D::UnionAll) = getmod(D.body)
getname(D::DataType) = D.name.name
getname(D::UnionAll) = getmod(D.body)

src(io::IO, T::DataType) = begin
  write(io, ref(T))
  length(T.parameters) == 0 && return
  mapjoin(src, io, T.parameters, ('{', ',', '}'))
end

src(io::IO, x::Pair) = begin
  src(io, x[1])
  write(io, "=>")
  src(io, x[2])
end

src(io::IO, x::AbstractChar) = write(io, "'$x'")
src(io::IO, x::AbstractString) = write(io, '"', Base.escape_string(x), '"')
src(io::IO, x::Symbol) = write(io, String(x))

src(io::IO, x::Rational) = begin
  src(io, x.num)
  write(io, "//")
  src(io, x.den)
end

src(io::IO, x::Vector) = mapjoin(src, io, x, ('[', ',', ']'))

src(io::IO, x::AbstractDict) = begin
  src(io, typeof(x))
  mapjoin(src, io, x)
end

src(io::IO, x::AbstractSet) = begin
  src(io, typeof(x))
  mapjoin(src, io, values(x), ("([", ',', "])"))
end

src(io::IO, x::Tuple) = mapjoin(src, io, x, ('(', ',', length(x) == 1 ? ",)" : ')'))

src(io::IO, x::NamedTuple) = mapjoin(tuple_pair, io, pairs(x), ('(', ',', length(x) == 1 ? ",)" : ')'))

tuple_pair(io, (key, value)) = begin
  write(io, key, '=')
  src(io, value)
end

src(io::IO, x::Enum) = begin
  src(io, typeof(x))
  write(io, '(', string(Int(x)), ')')
end

src(io::IO, ::Nothing) = write(io, "nothing")
src(io::IO, ::Missing) = write(io, "missing")
src(io::IO, g::GlobalRef) = write(io, ref(g))
src(io::IO, x::Expr) = src(io, x, Val(x.head))

src(io, x, ::Val{:call}) = begin
  @capture x name_(args__)
  if name isa Symbol && Base.isoperator(name)
    if length(args) == 1
      prefix(io, args[1], name)
    elseif name == :* && args[1] isa Real && args[2] isa Symbol
      src(io, args[1])
      src(io, args[2])
    else
      mapjoin(src, io, args, ("", ref(name), ""))
    end
  else
    src(io, name)
    mapjoin(src, io, args)
  end
end

src(io::IO, x::QuoteNode) = show(io, x.value)

src(io, x, ::Val{:quote}) = begin
  code = x.args[1]
  if Meta.isexpr(code, :block)
    mapjoin(src, io, rmlines(code).args, ("quote\n", '\n', "end\n"))
  else
    mapjoin(src, io, code, (":(", ';', ')'))
  end
end

src(io, dolla, ::Val{:$}) = dollar(dolla.args[1])

dollar(io, x) = begin
  write(io, '$')
  if value isa Number
    src(io, x)
  else
    write(io, '(')
    src(io, x)
    write(io, ')')
  end
end

src(io, string, ::Val{:string}) = mapjoin(string_interp, io, string.args, ('"', "", '"'))
string_interp(io, x::String) = write(io, x)
string_interp(x) = dollar(x)

src(io, s::AbstractString) = begin
  write(io, '"')
  Base.escape_string(io, s)
  write(io, '"')
end

src(io, block, ::Val{:block}) = begin
  statements = rmlines(block).args
  length(statements) == 1 && return src(io, statements[1])
  mapjoin(src, io, statements, ("begin\n", '\n', "end\n"))
end

src(io, x, ::Union{Val{:(=)}, Val{:kw}}) = src_pair(io, x.args, '=')
src(io, x, ::Val{:const}) = prefix(io, x.args[1], "const ")

src(io, x, ::Val{:(::)}) = begin
  if length(x.args) == 1
    prefix(io, x.args[1], "::")
  else
    src_pair(io, x.args, "::")
  end
end

src(io, x, ::Val{:curly}) = begin
  @capture x name_{params__}
  src(io, name)
  mapjoin(src, io, params, ('{', ',', '}'))
end

prefix(io, x, pre) = begin
  write(io, pre)
  src(io, x)
end

src_pair(io, (a,b), sep='=') = begin
  src(io, a)
  write(io, sep)
  src(io, b)
end

src(io, fn, ::Val{:->}) = src_pair(io, rmlines.(fn.args), "->")
src(io, fn, ::Val{:function}) = mapjoin(src, io, fn.args, ("function ", '\n', "end\n"))

src(io, c, ::Val{:comprehension}) = comprehension(c.args[1], '[', ']')
src(io, g, ::Val{:generator}) = comprehension(g, '(', ')')

comprehension(g, open, close) = begin
  body, assignments = g.args[1], g.args[2:end]
  write(io, open)
  src(io, body)
  write(io, " for ")
  if length(assignments) == 1
    src_pair(io, assignments[1].args, " in ")
  else
    mapjoin(src, io, assignments, ("", ',', ""))
  end
  write(io, close)
end

src(io, t, ::Val{:tuple}) = invoke(src, Tuple{IO,Tuple}, io, tuple(t.args...))
src(io, v, ::Val{:vect}) = mapjoin(src, io, v.args, ('[', ',', ']'))
src(io, v, ::Val{:hcat}) = mapjoin(src, io, v.args, ('[', ' ', ']'))
src(io, v, ::Val{:vcat}) = mapjoin(row, io, v.args, ('[', ';', ']'))
row(io, r) = mapjoin(src, io, r.args, ("", ' ', ""))

src(io, r, ::Val{:ref}) = begin
  @capture r ref_[args__]
  src(io, ref)
  mapjoin(src, io, args, ('[', ',', ']'))
end

src(io, cond, ::Val{:if}) = conditional(cond, "if")

conditional(io, cond, kw) = begin
  pred, branch = cond.args
  if Meta.isexpr(branch, :block)
    write(io, kw, ' ')
    src(io, pred)
    mapjoin(src, io, rmlines(branch).args, ('\n', '\n', '\n'))
    if length(cond.args) == 3
      altbranch(io, cond.args[3])
    else
      write(io, "end")
    end
  else
    src(io, pred)
    write(io, '?')
    src(io, branch)
    write(io, " : ")
    src(io, cond.args[3])
  end
end

altbranch(io, e) = Meta.isexpr(e, :elseif) ? conditional(io, e, "elseif") : elsebranch(io, e)

elsebranch(io, e) = begin
  write(io, "else")
  mapjoin(src, io, rmlines(e).args, ('\n', '\n', '\n'))
  write(io, "end")
end

src(io, x, ::Val{:&&}) = src_pair(io, x.args, "&&")
src(io, x, ::Val{:||}) = src_pair(io, x.args, "||")

src(io, dot, ::Val{:.}) = begin
  left, right = dot.args
  src(io, left)
  write(io, '.')
  if right isa QuoteNode && right.value isa Symbol
    write(io, right.value)
  elseif Meta.isexpr(right, :tuple, 1)
    write(io, '(')
    src(io, right.args[1])
    write(io, ')')
  else
    src(io, right)
  end
end

src(io, splat, ::Val{:...}) = (src(io, splat.args[1]); write(io, "..."))

src(io, struc, ::Val{:struct}) = begin
  mutable, name, body = struc.args
  write(io, mutable ? "mutable struct " : "struct ")
  src(io, name)
  lines = rmlines(body).args
  isempty(lines) ? mapjoin(src, io, lines, ('\n', '\n', '\n')) : write(io, ' ')
  write(io, "end")
end

src(io, struc, ::Val{:abstract}) = begin
  write(io, "abstract type ")
  src(io, struc.args[1])
  write(io, "end")
end

src(io, meta, ::Val{:meta}) = write(io, repr(meta))

src(io, m, ::Val{:macro}) = begin
  call, block = m.args
  write(io, "macro ")
  src(io, call)
  mapjoin(src, io, rmlines(block).args, ('\n', '\n', '\n'))
  write(io, "end")
end

src(io, params, ::Val{:parameters}) = mapjoin(src, io, params.args, (';', ',', ""))
src(io, e, ::Val{:<:}) = src_pair(io, e.args, " <: ")
src(io, e, ::Val{:where}) = begin
  if length(e.args) == 1
    src(io, e.args[1])
  elseif length(e.args) == 2
    src_pair(io, e.args, " where ")
  else
    src(io, e.args[1])
    write(io, " where ")
    mapjoin(src, io, e.args[2:end], ('{', ',', '}'))
  end
end
src(io, e, ::Val{:break}) = write(io, "break")
src(io, e, ::Val{:continue}) = write(io, "continue")
src(io, e, ::Val{:while}) = begin
  cond, body = e.args
  write(io, "while ")
  src(io, cond)
  mapjoin(src, io, rmlines(body).args, ('\n', '\n', "\nend"))
end

src(io, e, ::Val{:for}) = begin
  assignments, body = e.args
  write(io, "for ")
  if Meta.isexpr(assignments, :block)
    mapjoin(src, io, rmlines(assignments).args, ("", ',', ""))
  else
    src_pair(io, assignments.args, " in ")
  end
  mapjoin(src, io, rmlines(body).args, ('\n', '\n', "\nend"))
end

src(io, e, ::Val{:macrocall}) = begin
  name, args = e.args[1], e.args[2:end]
  m = match(r"(\w+)_str\"?$", string(name))
  if !isnothing(m)
    write(io, m[1])
    name isa GlobalRef && push!(globals[], name)
    src(io, args[1])
  elseif name == GlobalRef(Core, Symbol("@doc"))
    mapjoin(src, io, args, ("", '\n', ""))
  elseif length(args) == 1 && Meta.isexpr(args[1], :hcat)
    src(io, name)
    src(io, args[1])
  else
    src(io, name)
    mapjoin(src, io, args)
  end
end

src(io, e, ::Val{:toplevel}) = mapjoin(src, io, e.args, ("", '\n', ""))
