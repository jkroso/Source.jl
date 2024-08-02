@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@use "." source src expr hydrate @src @hydrate
@use Dates

str(x, width=100) = source(x; width=width, mod=@__MODULE__)

struct A
  a
  b
end

@test str(A(1,2)) == "A(1, 2)"
@test str(Dict(1=>2,3=>4), 13) == """
                                  Dict(3 => 4,
                                       1 => 2)\
                                  """

@test str([1,2,3]) == "[1, 2, 3]"
@test str([1,2,3], 9) == "[1,\n 2,\n 3]"
@test str((1,2,3)) == "(1, 2, 3)"
@test str((1,)) == "(1,)"
@test str(Set([1,2])) == "Set([2, 1])"
@test str(:([1 2])) == "[1 2]"
@test str(:([1 2;])) == "[1 2;]"
@test str(:([1 2; 3 4])) == "[1 2; 3 4]"
@test str(:((a,b))) == "(a, b)"
@test str(:((a=1,))) == "(a=1,)"
@test str(:(+(1,2))) == "1 + 2"
@test str(:(1*m)) == "1m"
@test str(:(!3)) == "!3"
@test str(:(1+:1)) == "1 + 1"
@test str(:(1 + :(1+2))) == "1 + :(1 + 2)"
@test str(quote :(1+2; 3) end) == """
                                  quote
                                    1 + 2
                                    3
                                  end"""
@test str(quote :($(2+a)) end) == ":(\$(2 + a))"
@test str(:("s$(1)")) == "\"s\$(1)\""
@test str(:(-"s\nb")) == """
                         -\"\"\"
                          s
                          b
                          \"\"\""""
@test str(:(a=1)) == "a = 1"
@test str(:(const a=1)) == "const a = 1"
@test str(:(a{T,b<:B})) == "a{T,b<:B}"
@test str(:(a::T))  == "a::T"
@test str(quote
  function a(b) a end
  (x)->1
end) == """
        begin
          function a(b)
            a
          end
          x->1
        end"""
@test str(:([x for x in a])) == "[x for x in a]"
@test str(:((begin x*y; y*x end for x=a, y=b))) == """
                                                   (begin
                                                      x * y
                                                      y * x
                                                    end for x = a, y = b)"""
@test str(:(a[1,2])) == "a[1, 2]"
@test str(:(1||2)) ==  "1 || 2"
@test str(:(1&&2)) == "1 && 2"
@test str(quote
  if a == true
    a
  elseif a == false
    b
  else
    c
  end
  if a
    a
  end
  a ? a : b
end) == """begin
          if a == true
            a
          elseif a == false
            b
          else
            c
          end
          if a
            a
          end
          a ? a : b
        end"""
@test str(:(a.b; a.(b))) == """begin
                              a.b
                              a.(b)
                            end"""
@test str(:(a(;b=2,c=3)=a+b)) == "a(;b=2, c=3) = a + b"
@test str(quote
  struct A
    a
    b::Int
  end
  struct B end
  mutable struct C
    a
  end
end) == """begin
          struct A
            a
            b::Int
          end
          struct B end
          mutable struct C
            a
          end
        end"""
@test str(:(a<:b)) == "a <: b"
@test str(:(a where b)) == "a where b"
@test str(:(a(::B{c,d}) where {c,d} = 1)) == "a(::B{c,d}) where {c,d} = 1"
@test str(:(B{c,d} where {c,d})) == "B{c,d} where {c,d}"
@test str(:(B{c,d} where {c,d<:Int})) == "B{c,d} where {c,d<:Int}"
@test str(Expr(:where, :a)) == "a"
@test str(:(while a
  if a
    break
  else
    continue
  end
end)) == """while a
           if a
             break
           else
             continue
           end
         end"""
@test str(quote
  for a in b
    a
  end
  for (a,b) in b
    a+b
  end
  for a=b,c=d
    a+c
  end
end) == """begin
          for a in b
            a
          end
          for (a, b) in b
            a + b
          end
          for a = b, c = d
            a + c
          end
        end"""
@test str(:(a"b")) == "a\"b\""
@test str(:(@a b c)) == "@a b c"
@test str(:(@a[b c])) == "@a[b c]"
@test str(quote
  "a"
  fn()=1
end) == """
        "a"
        fn() = 1"""

@test str(:(abstract type A end)) == "abstract type A end"
@test str(:(abstract type A <: B end)) == "abstract type A <: B end"

@test str(:(macro a()
  Base.@__doc__ abstract type A end
end)) == """macro a()
           Base.@__doc__ abstract type A end
         end"""

@test str(:(a(b::Int) = b)) == "a(b::Int) = b"
@test str(:(a(::Type{Int}) = 1)) == "a(::Type{Int}) = 1"
@test str(:([b...])) == "[b...]"
@test str(:(a(b...))) == "a(b...)"

@test str(Expr(:toplevel, quote a end)) == "a"

@test str(Base.ImmutableDict(:a=>1,:b=>2)) == "Base.ImmutableDict(:b => 2, :a => 1)"

mutable struct B
  parent::Union{Nothing,B}
  child::Union{Nothing,B}
end
const circular_ref = B(nothing, B(nothing, nothing))
circular_ref.child.parent = circular_ref
@test str(circular_ref) == "B(nothing, B(#= circular reference @-2 =#, nothing))"

@use "./compact.jl" src
@use "github.com/jkroso/Units.jl/Money" AUD Money
@enum Fruit apple

@test src(Base.ImmutableDict("a"=>1)) == """
                                         import Base:ImmutableDict
                                         ImmutableDict{String,Int64}(\"a\"=>1)\
                                         """
@test src([1,2,3]) == "[1,2,3]"
@test src(:(:a)) == ":a"
@test src(:a) == "a"
@test src('b') == "'b'"
@test src("ab") == "\"ab\""
@test src(1.1) == "1.1"
@test src(1//2) == "1//2"
@test src("abc") == "\"abc\""
@test src(Set([1,2,3])) == "Set{Int64}([2,3,1])"
@test src(A(1,2)) == """
                     @use("$(@__FILE__)",A)
                     A(1,2)\
                     """
@test src((1,2)) == "(1,2)"
@test src((1,)) == "(1,)"
@test src((a=1,b=2)) == "(a=1,b=2)"
@test src((a=1,)) == "(a=1,)"
@test src(:(1+1)) == "1+1"
@test src(apple) == """
                    @use("$(@__FILE__)",Fruit)
                    Fruit(0)\
                    """
@test src(Dates.Date(1776, 7, 4)) == "import Dates:Date\nDate(1776,7,4)"
@test src(Dates.DateTime(1776, 7, 4, 12, 0, 0)) == """
                                                   import Dates:DateTime
                                                   DateTime(1776,7,4,12,0,0)\
                                                   """
@test src(Dates.Time(1,2,3)) == "import Dates:Time\nTime(1,2,3)"
@test src(Base.UUID(UInt128(1))) == "import Base:UUID\nUUID(1)"
@test src(r"abc") == "r\"abc\""
@test src(1:2) == "1:2"
@test src(1:2:3) == "1:2:3"
@test src('a':'c') == "'a':1:'c'"
@test src(v"1.2.3") == "v\"1.2.3\""
@test src(:(@a[1 2 3])) == "@a[1 2 3]"
@test src(3.50AUD) == """
                      @use("github.com/jkroso/Units.jl/Money.jl",Money)
                      Money{:AUD}(3.5)\
                      """

module M
  struct C
    a
  end
end

@test hydrate(src(M.C(1), mod=M), mod=M) == M.C(1)
