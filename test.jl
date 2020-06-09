@use "github.com/jkroso/Rutherford.jl/test.jl" @test
@use "." serialize

str(x, width=100) = serialize(x, mod=@__MODULE__, width=width)

struct A
  a
  b
end

@test str(A(1,2)) == "A(1, 2)"
@test str(Dict(1=>2,3=>4), 13) == """
                                  Dict(3 => 4,
                                       1 => 2)"""
@test str([1,2,3]) == "[1, 2, 3]"
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
@test str(:(1+:1)) == "1 + :1"
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
