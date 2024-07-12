mapjoin(fn, io, itr) = begin
  first = true
  for value in itr
    first ? (first = false) : write(io, ',')
    fn(io, value)
  end
end

src(io::IO, T::DataType) = begin
  write(io, String(T.name.name))
  length(T.parameters) == 0 && return
  write(io, '{')
  mapjoin(src, io, T.parameters)
  write(io, '}')
end

src(io::IO, x::T) where T = begin
  fields = fieldnames(T)
  isempty(fields) && return write(io, repr(x))
  src(io, T)
  write(io, '(')
  mapjoin(src, io, (getfield(x, f) for f in fields))
  write(io, ')')
end

src(io::IO, x::Pair) = begin
  src(io, x[1])
  write(io, "=>")
  src(io, x[2])
end

src(io::IO, x::Rational) = begin
  src(io, x.num)
  write(io, "//")
  src(io, x.den)
end

src(io::IO, x::Vector) = begin
  src(io, eltype(x))
  write(io, '[')
  mapjoin(src, io, x)
  write(io, ']')
end

src(io::IO, x::AbstractDict) = begin
  src(io, typeof(x))
  write(io, '(')
  mapjoin(src, io, x)
  write(io, ')')
end

src(io::IO, x::AbstractSet) = begin
  src(io, typeof(x))
  write(io, "([")
  mapjoin(src, io, values(x))
  write(io, "])")
end

src(io::IO, x::Tuple) = begin
  write(io, '(')
  mapjoin(src, io, x)
  write(io, length(x) == 1 ? ",)" : ')')
end

src(io::IO, x::NamedTuple) = begin
  write(io, '(')
  mapjoin(io, pairs(x)) do io, (k, v)
    write(io, k, '=')
    src(io, v)
  end
  write(io, length(x) == 1 ? ",)" : ')')
end

src(io::IO, x::Enum) = begin
  src(io, typeof(x))
  write(io, '(', string(Int(x)), ')')
end

src(io::IO, x::Expr) = print(io, x)
