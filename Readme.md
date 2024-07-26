# Source.jl

Serializes objects back into the source code that generated them.

Provides a version that's human readable and an optimised version designed for storing data that you intend to rehydrate later.

```julia
@use "github.com/jkroso/Source.jl" src evalstring
@use Dates: Date

src(Date(2024, 7, 9)) == "import Dates.Date\nDate(2024,7,9)"
evalstring(src(Date(2024, 7, 9))) == Date(2024, 7, 9)
```

For types that use a fancy constructor syntax you can get it to serialize to that syntax by defining `expr(x)`. An example of doing this for URIs is given below:

```julia
@use "github.com/jkroso/URI.jl" URI @uri_str
@use "github.com/jkroso/Source.jl" expr

# without expr(::URI) defined the output is very verbose
src(uri"github.com") == """
                        @use "github.com/jkroso/URI.jl/FSPath.jl" RelativePath
                        @use "github.com/jkroso/URI.jl/main.jl" URI
                        @use "github.com/jkroso/Sequences.jl/main.jl" EmptySequence
                        @use "github.com/jkroso/Sequences.jl/main.jl" Sequence
                        URI{Symbol("")}("","","github.com",0,RelativePath(EmptySequence{String}(Sequence{String} where Path)),(),"")\
                        """

expr(x::URI) = Expr(:macrocall,
                    GlobalRef(URI.body.name.module, Symbol("@uri_str")),
                    string(x))

# with expr(::URI) defined the output is shorter and more readable
src(uri"github.com") == """
                        @use "github.com/jkroso/URI.jl" @uri_str
                        uri"github.com"\
                        """
evalstring(src(uri"github.com")) == uri"github.com"
```
