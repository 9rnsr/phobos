// Written in the D programming language.

/**
Auxiliary and algorithm templates for template metaprogramming on compile-time
entities.  Compile-time entities include types, compile-time values, symbols,
and sequences of those entities.

Macros:
  WIKI = Phobos/StdMeta
 TITLE = std.meta

Source:      $(PHOBOSSRC std/_meta.d)
Copyright:   Copyright Shin Fujishiro 2010.
License:     $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:     Shin Fujishiro, and Kenji Hara
 */
module std.meta;

//             Copyright Shin Fujishiro 2010.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// Introduce the symbols visible to user for unaryT etc.
import meta = std.meta;

// Introduce the symbols visible to use from string lambda templates.
import std.traits;
import std.typetuple;


//----------------------------------------------------------------------------//
// Fundamental Templates
//----------------------------------------------------------------------------//


/**
Makes an alias of $(D E).

Params:
 E = A compile-time entity: type, compile-time value, or any symbol.
 */
template Id(E)
{
    alias Id = E;
}

/// ditto
template Id(alias E)
{
    alias Id = E;
}

/**
 Literal values can't be aliased directly.  Use $(D meta.Id) as follows:
 */
unittest
{
    alias Front(seq...) = meta.Id!(seq[0]);
    alias front = Front!(10, 20, 30);
    static assert(front == 10);
}

unittest
{
    int sym;

    alias n = Id!100;
    alias T = Id!int;
    alias s = Id!sym;
    static assert(n == 100);
    static assert(is(T == int));
    static assert(__traits(isSame, s, sym));

    // Test for run-time equivalence with "alias sym s;"
    assert(&s == &sym);
}



/**
Makes a sequence of compile-time entities.  The sequence is just an alias of
the template variadic arguments: $(D seq).
 */
template Seq(seq...)
{
    alias Seq = seq;
}

/**
 */
unittest
{
    alias Types = meta.Seq!(int, double, string);

    static assert(is(Types[0] == int));
    static assert(is(Types[1] == double));
    static assert(is(Types[2] == string));
}

/**
The sequence may contain compile-time expressions.  The following example
makes a sequence of constant integers $(D numbers) and embeds it into an
array literal.
 */
unittest
{
    alias numbers = meta.Seq!(10, 20, 30);
    int[] arr = [ 0, numbers, 100 ];
    assert(arr == [ 0, 10, 20, 30, 100 ]);
}



/**
Makes a sequence of compile-time entities. The sequence can contain only types.
If the constraint is violated, an error occurs at compile-time.

Params:
 Types = Zero or more types making up the sequence.

Returns:
 Sequence of the given types.

See_Also:
 $(D meta.isType)
 */
template TypeSeq(Types...)
{
    static if (meta.all!(isType, Types))
        alias TypeSeq = Types;
    else
        static assert(0, Types.stringof ~ " is not type sequence");
}

/**
 Comparing type sequences with the $(D is) expression.
 */
unittest
{
    alias A = TypeSeq!(int, double, string);
    static assert( is(A == TypeSeq!(int, double, string)));
    static assert(!is(A == TypeSeq!(string, int, double)));
    static assert(!is(A == TypeSeq!()));
}

/**
Declaring a sequence of variables.  Note that it's different from a so-called
tuple and can't be nested.
 */
unittest
{
    TypeSeq!(int, double, TypeSeq!(bool, string)) vars;
    vars[0] = 10;
    vars[1] = 5.0;
    vars[2] = false;
    vars[3] = "Abcdef";
}


/**
Makes a sequence of compile-time entities. The sequence can contain only
compile-time values. If the constraint is violated, an error occurs at
compile-time.

Params:
 Values = Zero or more compile-time values making up the sequence.

Returns:
 Sequence of the given values.

See_Also:
 $(D meta.isValue)
 */
template ValueSeq(Values...)
{
    static if (meta.all!(isValue, Values))
        alias ValueSeq = Values;
    else
        static assert(0, Values.stringof ~ " is not value sequence");
}

/**
 Comparing type sequences with the $(D isSame) template.
 */
unittest
{
    alias A = ValueSeq!("sin", 3.14, [1,1,2,3]);
    static assert( isSame!(pack!A, pack!(ValueSeq!("sin", 3.14, [1,1,2,3]))));
    static assert(!isSame!(pack!A, pack!(ValueSeq!([1,1,2,3], "sin", 3.14))));
    static assert(!isSame!(pack!A, pack!(ValueSeq!())));
}


/**
$(D meta.pack) makes an atomic entity from a sequence, which is useful for
passing multiple sequences to a template.

Params:
 seq = Zero or more compile-time entities to _pack.
 */
template pack(seq...)
{
    /**
     * Returns the packed sequence: $(D seq).
     */
    alias expand = seq;


    /**
     * Returns the number of entities: $(D seq.length).
     */
    enum size_t length = seq.length;


    /**
     * Extracts the $(D i)-th element of the packed sequence.
     */
    template at(size_t i) if (i < length)
    {
        alias at = Id!(seq[i]);
    }


    /* undocumented (internal use) */
    struct Tag;
}

/**
 The following code passes three separate sequences to $(D meta.transverse)
 using $(D meta.pack):
 */
unittest
{
    // Query the 0-th element of each sequence.
    alias first = meta.transverse!(0, meta.pack!(int, 32),
                                      meta.pack!(double, 5.0),
                                      meta.pack!(string, "hello."));
    static assert(is(first == TypeSeq!(int, double, string)));
}

unittest
{
    alias empty = pack!();
    static assert(empty.length == 0);

    int sym;
    alias mixed = pack!(20, int, sym);
    static assert(mixed.length == 3);
    static assert(mixed.expand[0] == 20);
    static assert(is(mixed.expand[1] == int));
    static assert(__traits(isSame, mixed.expand[2], sym));

    alias nested = pack!( pack!(1,2), pack!(int,bool), pack!void );
    static assert(nested.length == 3);
}



/**
Returns $(D true) if and only if $(D E) is a packed sequence.

Params:
 seq = Zero or more compile-time entities.
 */
template isPack(seq...)
{
    static if (seq.length == 1)
        enum isPack = is(Id!(seq[0]).Tag == pack!(seq[0].expand).Tag);
    else
        enum isPack = false;
}

/**
 */
unittest
{
    static assert( isPack!(pack!(1,2, int)));
    static assert(!isPack!(1,2, int));
    static assert(!isPack!(1));
    static assert(!isPack!(int));
}



/**
Makes the mangled name of a compile-time entity.

Params:
 entity = Compile-time entity to get the mangled name of.

Returns:
 Compile-time string encoding the given entity in the name mangling rule of
 the language ABI.

 If $(D entity) is a sequence of several compile-time entities, the returned
 string is the concatenation of the mangled names of those entities.  The empty
 string is returned if $(D entity) is the empty sequence.
 */
template mangle(entity...)
{
    string _stripTag(string tag)
    {
        enum
        {
            prefix = "PS3std4meta",
            midfix = "__T4pack",
            suffix = "Z3Tag",
        }
        size_t i = prefix.length;

        while ('0' <= tag[i] && tag[i] <= '9')
        {
            ++i;
        }
        return tag[i + midfix.length .. $ - suffix.length];
    }

    enum mangle = _stripTag((pack!entity.Tag*).mangleof);
}

/**
 */
unittest
{
    import std.math : cos;

    static assert(meta.mangle!cos == "S133std4math3cos");
    static assert(meta.mangle!(real, int) == "TeTi");
}

unittest
{
    static assert(mangle!() == "");

    static assert(mangle!int == "Ti");
    static assert(mangle!512 == "Vi512");
    static assert(mangle!"abc" == "VAyaa3_616263");
    static assert(mangle!mangle == "S163std4meta6mangle");

    static assert(mangle!(int, 512, mangle) == "TiVi512S163std4meta6mangle");
}



/**
Determines if $(D A) and $(D B) are the same entities.  $(D A) and $(D B) are
considered the same if templates instantiated, respectively, with $(D A) and
$(D B) coincide with each other.

Returns:
 $(D true) if and only if $(D A) and $(D B) are the same entity.
 */
template isSame(A, B)
{
    enum isSame = is(A == B);
}

/// ditto
template isSame(A, alias B) if (!isType!B)
{
    enum isSame = false;
}

/// ditto
template isSame(alias A, B) if (!isType!A)
{
    enum isSame = false;
}

/// ditto
template isSame(alias A, alias B) if (!isType!A && !isType!B)
{
    enum isSame = is(pack!A.Tag == pack!B.Tag);
}

/**
 Comparing various entities.
 */
unittest
{
    struct MyType {}
    static assert( meta.isSame!(int, int));
    static assert(!meta.isSame!(MyType, double));

    enum str = "abc";
    static assert( meta.isSame!(str, "abc"));
    static assert(!meta.isSame!(10, 10u));      // int and uint

    void fun() {}
    static assert( meta.isSame!(fun, fun));
    static assert(!meta.isSame!(fun, std));     // function and package
}

unittest    // type vs type
{
    enum   E { a }
    struct S {}

    static assert( isSame!(int, int));
    static assert( isSame!(E, E));
    static assert( isSame!(S, S));

    static assert(!isSame!(const  int, int));
    static assert(!isSame!(shared int, int));

    static assert(!isSame!(int, E));
    static assert(!isSame!(E, S));
    static assert(!isSame!(S, int));
}

unittest    // value vs value
{
    struct S {}

    static assert( isSame!(100, 100));
    static assert( isSame!('A', 'A'));
    static assert( isSame!(S(), S()));
    static assert( isSame!("abc", "abc"));

    static assert(!isSame!(100, 'A'));
    static assert(!isSame!("abc", S()));
    static assert(!isSame!(100, 100u));
}

unittest    // symbol vs symbol
{
    void fun() {}
    void pun() {}

    static assert( isSame!(fun, fun));
    static assert( isSame!(pun, pun));
    static assert(!isSame!(fun, pun));

    static assert( isSame!(isSame, isSame));
    static assert( isSame!(   std,    std));

    static assert(!isSame!(fun, isSame));
    static assert(!isSame!(pun,    std));
}

unittest    // mismatch
{
    static assert(!isSame!(   int, isSame));
    static assert(!isSame!(isSame,    int));
    static assert(!isSame!(    40,    int));
    static assert(!isSame!(   int,     40));
    static assert(!isSame!(isSame,     40));
    static assert(!isSame!(    40, isSame));
}

unittest    // CTFE-able property is symbol
{
    struct S
    {
        static @property int property() { return 10; }
    }
    static assert( meta.isSame!(10, 10));
    static assert(!meta.isSame!(S.property, 10));
    static assert( meta.isSame!(S.property, S.property));
}



/**
These overloads serve partial application of $(D meta.isSame).
 */
template isSame(A)
{
    alias isSame(      B) = .isSame!(A, B);
    alias isSame(alias B) = .isSame!(A, B);
}

/// ditto
template isSame(alias A)
{
    alias isSame(      B) = .isSame!(A, B);
    alias isSame(alias B) = .isSame!(A, B);
}

/**
 */
unittest
{
    // Bind double as the first argument.
    alias isDouble = meta.isSame!double;

    static assert( isDouble!double);    // meta.isSame!(double, double)
    static assert(!isDouble!int   );    // meta.isSame!(double, int)
}

unittest
{
    alias Tx = isSame!int;
    static assert( Tx!int);
    static assert(!Tx!200);
    static assert(!Tx!std);

    alias Vx = isSame!200;
    static assert(!Vx!int);
    static assert( Vx!200);
    static assert(!Vx!std);

    alias Sx = isSame!std;
    static assert(!Sx!int);
    static assert(!Sx!200);
    static assert( Sx!std);
}



/**
Returns $(D true) if and only if $(D E) is a type.
 */
template isType(E)
{
    enum isType = true;
}

/// ditto
template isType(alias E)
{
    enum isType = is(E);
}

/**
 */
unittest
{
    alias Mixed = meta.Seq!(int,    "x",
                            double, "y",
                            string, "z");

    alias Types = meta.filter!(meta.isType, Mixed);
    static assert(is(Types == TypeSeq!(int, double, string)));
}

unittest
{
    // Basic & qualified types.
    static assert(isType!(int));
    static assert(isType!(const int));
    static assert(isType!(shared int));
    static assert(isType!(immutable int));

    // User-defined types.
    enum   Enum   { a }
    struct Struct {}
    class  Class  {}
    static assert(isType!Enum);
    static assert(isType!Struct);
    static assert(isType!Class);
}



/**
Returns $(D true) if and only if $(D E) has a compile-time value.  Literals,
constants and CTFE-able property functions would pass the test.
 */
template isValue(E)
{
    enum isValue = false;
}

/// ditto
template isValue(alias E)
{
    static if (is(typeof(E) T) && !is(T == void))
    {
        // NOTE: Some errors are gagged only inside static-if.
        static if (__traits(compiles, Id!([ E ])))
            enum isValue = true;
        else
            enum isValue = false;
    }
    else
    {
        enum isValue = false;
    }
}

/**
 */
unittest
{
    template increment(alias value) if (meta.isValue!value)
    {
        enum increment = value + 1;
    }
    static assert( __traits(compiles, increment!10));
    static assert(!__traits(compiles, increment!increment));    // Error: negates the constraint
}

unittest
{
    static struct S
    {
        int member;

      @property:
        static int fun() { return 10; }
               int gun() { return 10; }
        static int hun();
    }

    // Literal values
    static assert( isValue!100);
    static assert( isValue!"abc");
    static assert( isValue!([ 1,2,3,4 ]));
    static assert( isValue!(S(32)));

    // Constants
    static immutable staticConst = "immutable";
    enum manifestConst = 123;
    static assert( isValue!staticConst);
    static assert( isValue!manifestConst);

    // CTFE
    static assert( isValue!(S.fun));
    static assert(!isValue!(S.gun));
    static assert(!isValue!(S.hun));

    // Non-values
    static assert(!isValue!int);
    static assert(!isValue!S);
    static assert(!isValue!isValue);

    int runtimeVar;
    static assert(!isValue!(runtimeVar));
}



/**
Returns $(D true) if and only if $(D E) has a compile-time value implicitly
convertible to type $(D T).
 */
template isValue(T, E)
{
    enum isValue = false;
}

/// ditto
template isValue(T, alias E)
{
    enum isValue = is(typeof(E) : T) && isValue!E;
}

/**
 */
unittest
{
    template increment(alias value) if (meta.isValue!(long, value))
    {
        enum increment = value + 1;
    }
    static assert( __traits(compiles, increment!10));
    static assert(!__traits(compiles, increment!"me")); // Error: nonconvertible to long
}

unittest
{
    static immutable string immstr = "abc";
    string varstr;
    static assert( isValue!(string, ""));
    static assert( isValue!(string, immstr));
    static assert(!isValue!(string, varstr));
    static assert(!isValue!(string, 65536));
    static assert(!isValue!(string, string));
}



/* undocumented for now */
template metaComp(entities...) if (entities.length == 2)
{
    enum metaComp = (pack!(entities[0]).Tag*).mangleof <
                    (pack!(entities[1]).Tag*).mangleof;
}


unittest
{
    static assert(metaComp!(10, 20));
    static assert(metaComp!(10, -5)); // Yes
    static assert(metaComp!(int, 5));
}



//----------------------------------------------------------------------------//
// Auxiliary Templates
//----------------------------------------------------------------------------//


private mixin template _installLambdaExpr(string expr)
{
    template _expectEmptySeq() {}

    // The result can be an atomic entity or a sequence as expr returns.
    static if (__traits(compiles, _expectEmptySeq!(mixin("("~ expr ~")[0 .. 0]"))))
    {
        mixin("alias _ = Seq!("~ expr ~");");
    }
    else
    {
        mixin("alias _ =  Id!("~ expr ~");");
    }
}



/**
Transforms a string representing a compile-time entity into a unary template
that returns the represented entity.

Params:
 expr = String representing a compile-time entity using a template parameter
        $(D a) or $(D A).

Returns:
 Unary template that evaluates $(D expr).
 */
template unaryT(string expr)
{
    template _impl(args...)
    {
        alias A = Id!(args[0]), a = A;
        mixin _installLambdaExpr!expr;
    }

    alias unaryT(alias a) = _impl!a._;
    alias unaryT(      A) = _impl!A._;
}

/// ditto
template unaryT(alias templat)
{
    alias unaryT = templat;
}

/**
 */
unittest
{
    alias Constify = meta.unaryT!q{ const A };
    static assert(is(Constify!int == const int));

    alias lengthof = meta.unaryT!q{ a.length };
    static assert(lengthof!([ 1,2,3,4,5 ]) == 5);
}


/**
 The generated template can return a sequence.
 */
unittest
{
    import std.meta;
    import std.typecons;

    // Extracts the Types property of a Tuple instance.
    alias expand = meta.unaryT!q{ A.Types };

    alias Types = expand!(Tuple!(int, double, string));
    static assert(is(Types[0] == int));
    static assert(is(Types[1] == double));
    static assert(is(Types[2] == string));
}

unittest
{
    alias increment = unaryT!q{ a + 1 };
    alias Pointify  = unaryT!q{ A* };
    static assert(increment!10 == 11);
    static assert(is(Pointify!int == int*));

    // nested
    alias quadruple = unaryT!q{ apply!(unaryT!q{ a*2 }, a) * 2 };
    static assert(quadruple!10 == 40);
}

unittest    // Test for sequence return
{
    struct Tup(T...)
    {
        alias Types = T;
    }
    alias Expand = unaryT!q{ A.Types };
    alias IDS = Expand!(Tup!(int, double, string));
    static assert(is(IDS == Seq!(int, double, string)));

    // 1-sequence
    alias oneseq = unaryT!q{ Seq!(a) };
    static assert(oneseq!int.length == 1);

    // arrays are not sequences
    alias slice = unaryT!q{ a[0 .. 2] };
    static assert(slice!([1,2,3]) == [1,2]);
}



/**
Transforms a string representing a compile-time entity into a binary template
that returns the represented entity.

Params:
 expr = String representing a compile-time entity using two template
        parameters: $(D a, A) as the first one and $(D b, B) the second.

Returns:
 Binary template that evaluates $(D expr).
 */
template binaryT(string expr)
{
    template _impl(args...)
    {
        alias A = Id!(args[0]), a = A;
        alias B = Id!(args[1]), b = B;
        mixin _installLambdaExpr!expr;
    }

    template binaryT(AB...) if (AB.length == 2)
    {
        alias binaryT = _impl!AB._;
    }
}

/// ditto
template binaryT(alias templat)
{
    alias binaryT = templat;
}

/**
 This example uses the first parameter $(D a) as a value and the second one
 $(D B) as a type, and returns a value.
 */
unittest
{
    alias accumSize = meta.binaryT!q{ a + B.sizeof };

    enum n1 = accumSize!( 0,    int);
    enum n2 = accumSize!(n1, double);
    enum n3 = accumSize!(n2,  short);
    static assert(n3 == 4 + 8 + 2);
}

unittest
{
    alias Assoc  = binaryT!q{ B[A] };
    alias ArrayA = binaryT!q{ A[b] };
    alias ArrayB = binaryT!q{ B[a] };
    alias div    = binaryT!q{ a / b };
    static assert(is(Assoc!(string, int) == int[string]));
    static assert(is(ArrayA!(int, 10) == int[10]));
    static assert(is(ArrayB!(10, int) == int[10]));
    static assert(div!(28, -7) == -4);

    // nested
    alias Ave = binaryT!q{ apply!(binaryT!q{ a / b }, a+b, 2) };
    static assert(Ave!(10, 20) == 15);
}

unittest    // Test for sequence return
{
    alias ab3 = binaryT!q{ Seq!(a, b, 3) };
    static assert([ ab3!(10, 20) ] == [ 10, 20, 3 ]);
}

unittest    // bug 4431
{
    alias Assoc = binaryT!q{ B[A] };
    struct S {}
    static assert(is(Assoc!(int, S) == S[int]));
    static assert(is(Assoc!(S, int) == int[S]));
    static assert(is(Assoc!(S, S) == S[S]));
}



/**
Transforms a string representing an expression into a variadic template.
The expression can read variadic arguments via $(D args).

The expression can also use named parameters as $(D meta.unaryT), but
the number of implicitly-named parameters is limited up to eight:
$(D a, b, c, d, e, f, g) and $(D h) (plus capitalized ones) depending
on the number of arguments.

Params:
 expr = String representing a compile-time entity using variadic template
        parameters.  Thestring may use named parameters $(D a) to $(D h),
        $(D A) to $(D H) and variadic $(D args).

Returns:
 Variadic template that evaluates $(D fun).
 */
template variadicT(string expr)
{
    mixin template _parameters(size_t n, size_t i = 0)
    {
        static if (i < n && i < 8)
        {
            mixin("alias "~ "abcdefgh"[i] ~" = Id!(args[i]);");
            mixin("alias "~ "ABCDEFGH"[i] ~" = Id!(args[i]);");
            mixin _parameters!(n, i + 1);
        }
    }

    template _impl(args...)
    {
        mixin _parameters!(args.length);
        mixin _installLambdaExpr!expr;
    }

    alias variadicT(args...) = _impl!args._;
}

/// ditto
template variadicT(alias templat)
{
    alias variadicT = templat;
}

/**
 */
unittest
{
    alias rotate1 = meta.variadicT!q{ meta.Seq!(args[1 .. $], A) };

    static assert([ rotate1!(1, 2, 3, 4) ] == [ 2, 3, 4, 1 ]);
}

unittest
{
    alias addMul = variadicT!q{ a + b*c };
    static assert(addMul!(2,  3,  5) == 2 +  3* 5);
    static assert(addMul!(7, 11, 13) == 7 + 11*13);

    alias shuffle = variadicT!q{ [ g, e, c, a, b, d, f, h ] };
    static assert(shuffle!(1,2,3,4,5,6,7,8) == [ 7,5,3,1,2,4,6,8 ]);

    // Using uppercase parameters
    alias MakeConstAA = variadicT!q{ const(B)[A] };
    static assert(is(MakeConstAA!(int, double) == const(double)[int]));
    static assert(is(MakeConstAA!(int, string) == const(string)[int]));

    alias Shuffle = variadicT!q{ pack!(G, E, C, A, B, D, F, H) };
    static assert(isSame!(Shuffle!(int, double, string, bool,
                                   dchar, void*, short, byte),
                             pack!(short, dchar, string, int,
                                   double, bool, void*, byte)));

    // Mixing multicase parameters
    alias Make2D = variadicT!q{ A[b][c] };
    static assert(is(Make2D!(   int, 10, 20) ==    int[10][20]));
    static assert(is(Make2D!(double, 30, 10) == double[30][10]));

    // args
    alias lengthof = variadicT!q{ args.length };
    static assert(lengthof!(1,2,3,4,5,6,7,8,9) == 9);

    // nested
    alias argcv = variadicT!q{ apply!(variadicT!q{ pack!args }, args.length, args) };
    static assert(isSame!(argcv!(1, 2), pack!(2u, 1,2)));
}

unittest    // Test for sequence return
{
    alias halve = variadicT!q{ args[0 .. $/2] };
    static assert([ halve!(1,2,3,4) ] == [ 1,2 ]);
}



/**
Binds $(D args) to the leftmost parameters of a template $(D templat).

Params:
 templat = Template or string that can be tranformed to a variadic template
           using $(D meta.variadicT).
    args = Zero or more template instantiation arguments to _bind.

Returns:
 Template that instantiates $(D templat) with the bound arguments and
 additional ones as $(D templat!(args, ...)).
 */
template bind(alias templat, args...)
{
    alias bind(rest...) = apply!(variadicT!templat, args, rest);
}

/**
 */
unittest
{
    enum compareSize(T, U) = T.sizeof < U.sizeof;

    // Get the types satisfying "int.sizeof < U.sizeof".
    alias Result = meta.filter!(meta.bind!(compareSize, int),
                                byte, double, short, int, long);
    static assert(is(Result == TypeSeq!(double, long) ));
}

unittest
{
    alias Assoc      = bind!(q{ A[B] });
    alias ShortAssoc = bind!(q{ A[B] }, short);
    alias IntDouble  = bind!(q{ A[B] }, int, double);
    static assert(is(Assoc!(uint, void*) == uint[void*]));
    static assert(is(ShortAssoc!string == short[string]));
    static assert(is(IntDouble!() == int[double]));
}



/**
Same as $(D meta.bind) except that $(D meta.rbind) binds arguments to
rightmost parameters.

Params:
 templat = Template or string that can be tranformed to a variadic template
           using $(D meta.variadicT).
    args = Zero or more template instantiation arguments to bind.

Returns:
 Template that instantiates $(D templat) with the bound arguments and
 additional ones as $(D templat!(..., args)).
 */
template rbind(alias templat, args...)
{
    alias rbind(rest...) = apply!(variadicT!templat, rest, args);
}

/**
 */
unittest
{
    enum compareSize(T, U) = T.sizeof < U.sizeof;

    // Get the types satisfying "T.sizeof < int.sizeof"
    alias Result = meta.filter!(meta.rbind!(compareSize, int),
                                byte, double, short, int, long);
    static assert(is(Result == TypeSeq!(byte, short) ));
}

unittest
{
    alias Assoc      = rbind!(q{ A[B] });
    alias AssocShort = rbind!(q{ A[B] }, short);
    alias IntDouble  = rbind!(q{ A[B] }, int, double);
    static assert(is(Assoc!(uint, void*) == uint[void*]));
    static assert(is(AssocShort!string == string[short]));
    static assert(is(IntDouble!() == int[double]));
}



/**
Binds $(D args) to all the parameters of $(D templat).  Generated template
will instantiate $(D templat) with just the bound arguments.

Params:
 templat = Template or string to instantiate.
    args = Complete arguments for $(D templat).

Returns:
 Variadic template that constantly returns $(D templat!args) regardless of
 its arguments.
 */
template delay(alias templat, args...)
{
    alias delay(_...) = apply!(variadicT!templat, args);
}

/**
 */
unittest
{
    alias Int = meta.delay!(meta.Id, int);
    static assert(is(Int!() == int));
    static assert(is(Int!(void) == int));
    static assert(is(Int!(1,2,3) == int));
}

/**
 Using a delayed template for a fallback case of $(D meta.guard):
 */
unittest
{
    struct Error;

    alias Array = meta.guard!(q{ A[] }, meta.delay!(meta.Id, Error));
    static assert(is(Array!int == int[]));
    static assert(is(Array!100 == Error));
}

unittest
{
    alias empty = delay!(Seq);
    static assert(empty!().length == 0);
    static assert(empty!(int).length == 0);
    static assert(empty!(int, double).length == 0);

    alias sum30 = delay!(q{ a + b }, 10, 20);
    static assert(sum30!() == 30);
    static assert(sum30!(40) == 30);
}



/**
Generates a template that constantly evaluates to $(D E).

Params:
 E = Compile-time entity to hold.

Returns:
 Variadic template that ignores its arguments and just returns $(D E).
 */
template constant(E)
{
    alias constant(_...) = E;
}

/// ditto
template constant(alias E)
{
    alias constant(_...) = E;
}

/// ditto
template constant()
{
    alias constant(_...) = Seq!();
}

/**
 */
unittest
{
    alias Int = meta.constant!int;
    static assert(is(Int!() == int));
    static assert(is(Int!(double, string) == int));
}

unittest
{
    alias String = constant!string;
    static assert(is(String!() == string));
    static assert(is(String!(1,2,3) == string));
    static assert(is(String!(double, bool) == string));

    alias number = constant!512;
    static assert(number!() == 512);
    static assert(number!(1,2,3) == 512);
    static assert(number!(double, bool) == 512);

    alias empty = constant!();
    static assert(empty!().length == 0);
    static assert(empty!(1,2,3).length == 0);
    static assert(empty!(double, bool).length == 0);
}



/**
Creates a predicate template that inverts the result of the given one.

Params:
 pred = Predicate template to invert.  The result must be a compile-time value
        that is implicitly convertible to bool in conditional expressions.

Returns:
 Template that evaluates $(D pred) and returns an inverted result.
 */
template not(alias pred)
{
    enum not(args...) = !apply!(variadicT!pred, args);
}

/**
 Passing an inverted predicate to the $(D meta.countIf).
 */
unittest
{
    enum isStruct(T) = is(T == struct) || is(T == union);

    struct S {}
    union  U {}
    class  C {}

    // Count non-struct types in the sequence.
    enum n = meta.countIf!(meta.not!isStruct,
                           int, double, S, U, C);
    static assert(n == 3);
}

unittest
{
    alias notInt = not!(isSame!int);
    static assert( notInt!double);
    static assert( notInt!"none");
    static assert(!notInt!int   );

    // double invert
    alias isInt = not!notInt;
    static assert(!isInt!double);
    static assert(!isInt!"none");
    static assert( isInt!int   );
}

unittest
{
    alias notFive = not!"a == 5";
    static assert( notFive!4);
    static assert( notFive!6);
    static assert(!notFive!5);

    alias isFive = not!notFive;
    static assert(!isFive!4);
    static assert(!isFive!6);
    static assert( isFive!5);
}



/**
Composes predicate templates with the logical $(D &&) operator.

The predicates will be evaluated in the same order as passed to this
template.  The evaluations are lazy; if one of the predicates is not
satisfied, $(D meta.and) immediately returns $(D false) without evaluating
remaining predicates.

Params:
 preds = Zero or more predicate templates to compose.  This argument can be
         empty; in that case, the resulting template constantly evaluates to
         $(D true).

Returns:
 Composition predicate template that tests if its arguments satisfy all the
 predicates $(D preds).
 */
template and(preds...)
{
    alias and = reduce!(.and, preds);
}

/**
 */
unittest
{
    alias isSignedInt = meta.and!(meta.isType, q{ is(A : long) }, q{ A.min < 0 });
    static assert( isSignedInt!short);
    static assert( isSignedInt!int);
    static assert(!isSignedInt!uint);
    static assert(!isSignedInt!string);     // stops at the second predicate
    static assert(!isSignedInt!"wrong");    // stops at the first predicate
}

template and(alias pred1 = constant!true,
             alias pred2 = constant!true)
{
    template and(args...)
    {
        static if (apply!(pred1, args) && apply!(pred2, args))
            enum and = true;
        else
            enum and = false;
    }
}

unittest
{
    enum isConst(T) = is(T == const);

    // Compose nothing
    alias yes = and!();
    static assert(yes!());
    static assert(yes!(1, 2, 3));

    // No actual composition
    alias isConst2 = and!isConst;
    static assert( isConst2!(const int));
    static assert(!isConst2!(      int));

    alias isNeg = and!q{ a < 0 };
    static assert( isNeg!(-1));
    static assert(!isNeg!( 0));

    // Compose template and string
    alias isTinyConst = and!(isConst, q{ A.sizeof < 4 });
    static assert( isTinyConst!(const short));
    static assert(!isTinyConst!(      short));
    static assert(!isTinyConst!(const   int));
    static assert(!isTinyConst!(        int));
}



/**
Composes predicate templates with the logical $(D ||) operator.

The predicates will be evaluated in the same order as passed to this
template.  The evaluations are lazy; if one of the predicates is
satisfied, $(D meta.or) immediately returns $(D true) without evaluating
remaining predicates.

Params:
 preds = Zero _or more predicate templates to compose.  This argument can be
         empty; in that case, the resulting template constantly evaluates to
         $(D false).

Returns:
 Composition predicate template that tests if its arguments satisfy at least
 one of the predicates $(D preds).
 */
template or(preds...)
{
    alias or = reduce!(.or, preds);
}

/**
 */
unittest
{
    // Note that bool doesn't have the .min property.
    alias R = meta.filter!(meta.or!(q{ A.sizeof < 4 }, q{ A.min < 0 }),
                           bool, ushort, int, uint);
    static assert(is(R == TypeSeq!(bool, ushort, int)));
}

template or(alias pred1 = constant!false,
            alias pred2 = constant!false)
{
    template or(args...)
    {
        static if (apply!(pred1, args) || apply!(pred2, args))
            enum or = true;
        else
            enum or = false;
    }
}

unittest
{
    enum isConst(T) = is(T == const);

    // Compose nothing
    alias no = or!();
    static assert(!no!());

    // No actual composition
    alias isConst2 = or!isConst;
    static assert( isConst2!(const int));
    static assert(!isConst2!(      int));

    alias isNeg = or!q{ a < 0 };
    static assert( isNeg!(-1));
    static assert(!isNeg!( 0));

    // Compose template and string
    alias isTinyOrConst = or!(isConst, q{ A.sizeof < 4 });
    static assert( isTinyOrConst!(const short));
    static assert( isTinyOrConst!(      short));
    static assert( isTinyOrConst!(const   int));
    static assert(!isTinyOrConst!(        int));
}



/**
$(D meta.compose!(t1, t2, ..., tn)) returns a variadic template that in
turn instantiates the passed in templates in a chaining way:
----------
template composition(args...)
{
    alias composition = t1!(t2!( ... tn!(args) ... ));
}
----------

Params:
 templates = One or more templates making up the chain.  Each template
             can be a template or a string; strings are transformed to
             varadic templates using $(D meta.variadicT).

Returns:
 New template that instantiates the chain of $(D templates).
 */
template compose(templates...)
{
    alias compose = reduce!(.compose, templates);
}

/**
 */
unittest
{
    alias ConstArray = meta.compose!(q{ A[] },
                                     q{ const A });
    static assert(is(ConstArray!int == const(int)[]));
}

template compose(alias template1 = Seq,
                 alias template2 = Seq)
{
    alias compose(args...) = apply!(template1, apply!(template2, args));
}

unittest
{
    alias Const(T) = const(T);
    alias Array(T) = T[];

    // No actual composition
    alias Const1 = compose!Const;
    alias mul1   = compose!q{ a * 7 };
    static assert(is(Const1!int == const int));
    static assert(mul1!11 == 77);

    // Two templates
    alias ArrayConst = compose!(Array, Const);
    static assert(is(ArrayConst!int == const(int)[]));

    alias SeqDiv = compose!(Seq, q{ a / b });
    static assert(SeqDiv!(77, 11).length == 1);
    static assert(SeqDiv!(77, 11)[0] == 7);

    alias arrayRev = compose!(q{ [ args ] }, reverse);
    static assert(arrayRev!(1,2,3) == [ 3,2,1 ]);

    // More compositions
    alias mul11add7neg = compose!(q{ a * 11 }, q{ a + 7 }, q{ -a });
    static assert(mul11add7neg!(-6) == (6 + 7) * 11);
}



/**
Generates a template that tries instantiating specified templates in turn
and returns the result of the first compilable template.

For example, $(D meta.guard!(t1, t2)) generates a template that behaves
as follows:
----------
template trial(args...)
{
    static if (__traits(compiles, t1!(args)))
    {
        alias trial = t1!(args);
    }
    else
    {
        alias trial = t2!(args);
    }
}
----------

Params:
 templates = Templates to try instantiation.  Each template can be a real
             template or a string that can be transformed to a template
             using $(D meta.variadicT).

Returns:
 Variadic template that instantiates the first compilable template among
 $(D templates).  The last template is not guarded; if all the templates
 failed, the generated template will fail due to the last one.
 */
template guard(templates...) if (templates.length > 0)
{
    alias guard = reduce!(.guard, templates);
}

/**
 */
unittest
{
    alias hasNegativeMin = meta.guard!(q{ A.min < 0 }, q{ false });
    static assert( hasNegativeMin!int);
    static assert(!hasNegativeMin!double);
    static assert(!hasNegativeMin!void);    // void.min is not defined!
}

template guard(alias template1, alias template2)
{
    template guard(args...)
    {
        static if (__traits(compiles, apply!(template1, args)))
        {
            alias guard = apply!(template1, args);
        }
        else
        {
            alias guard = apply!(template2, args);
        }
    }
}

template guard(alias templat)
{
    alias guard(args...) = apply!(templat, args);
}

unittest
{
    alias Const(T) = const(T);

    // No actual guard
    alias JustConst = guard!Const;
    static assert(is(JustConst!int == const int));
    static assert(!__traits(compiles, JustConst!10));

    alias increment = guard!q{ a + 1 };
    static assert(increment!13 == 14);
    static assert(!__traits(compiles, increment!double));

    // Double trial
    alias MaybeConst = guard!(Const, Id);
    static assert(is(MaybeConst!int == const int));
    static assert(MaybeConst!"string" == "string");

    alias valueof = guard!(q{ +a }, q{ A.init });
    static assert(valueof!1.0 == 1.0);
    static assert(valueof!int == 0);

    // Triple trial
    alias makeArray = guard!(q{ [a] }, q{ [A.min]  }, q{ [A.init] });
    static assert(makeArray!1.0 == [ 1.0 ]);
    static assert(makeArray!int == [ int.min ]);
    static assert(makeArray!string == [ "" ]);
}



/**
Generates a template that conditionally instantiates either $(D then) or
$(D otherwise) depending on the result of $(D pred).

Params:
      pred = Predicate template.
      then = Template to instantiate when $(D pred) is satisfied.
 otherwise = Template to instantiate when $(D pred) is not satisfied.

Returns:
 Variadic template that instantiates $(D then) with its arguments if the
 arguments satisfy $(D pred), or instantiates $(D otherwise) with the same
 arguments if not.
 */
template conditional(alias pred, alias then, alias otherwise = meta.Id)
{
    alias _pred      = variadicT!pred;
    alias _then      = variadicT!then;
    alias _otherwise = variadicT!otherwise;

    template conditional(args...)
    {
        static if (_pred!args)
        {
            alias conditional = _then!args;
        }
        else
        {
            alias conditional = _otherwise!args;
        }
    }
}

/**
 */
unittest
{
    import std.meta, std.traits, std.typecons;

    alias NoTopConst = meta.conditional!(q{ is(A == class) }, Rebindable, Unqual);

    static assert(is( NoTopConst!(const Object) == Rebindable!(const Object) ));
    static assert(is( NoTopConst!(const int[]) == const(int)[] ));
    static assert(is( NoTopConst!(const int) == int ));
}

unittest
{
    alias Const = conditional!(q{  true }, q{ const A }, q{ immutable A });
    alias Imm   = conditional!(q{ false }, q{ const A }, q{ immutable A });
    static assert(is(Const!double ==     const double));
    static assert(is(  Imm!double == immutable double));

    alias LooseTypeof = conditional!(isType, q{ A }, q{ typeof(a) });
    static assert(is(LooseTypeof!int == int));
    static assert(is(LooseTypeof!"abc" == string));

    // Using default 'otherwise'
    alias ImmArray = conditional!(q{ is(A == immutable) }, q{ A[] });
    static assert(is(ImmArray!int == int));
    static assert(is(ImmArray!string == string));
    static assert(is(ImmArray!(immutable int) == immutable(int)[]));
}



/* undocumented (for internal use) */
template compiles(templates...)
{
    enum compiles(args...) = __traits(compiles, map!(applier!args, templates));
}



/**
Instantiates $(D templat) with the specified arguments.

Params:
 templat = Template to instantiate.  The argument can be a pure template or
           a string that can be transformed into a pure template using
           $(D meta.variadicT).
    args = The instantiation arguments to pass to $(D templat).

Returns:
 The result: $(D templat!args).

Example:
 Due to a syntactical limitation of the language, templates generated by
 higher-order templates (such as $(D meta.guard)) can't be instantiated
 directly.  Use $(D meta.apply) to instantiate such kind of temporary templates.
----------
template Example(Arg)
{
    static if (meta.apply!(meta.guard!(q{ A.min < 0 },
                                       q{     false }), Arg))
    {
        // ...
    }
}
----------
 */
template apply(alias templat, args...)
{
    alias _templat = variadicT!templat;

    alias apply = _templat!args;
}



/* undocumented (for internal use) */
template applier(args...)
{
    alias applier(alias templat) = apply!(templat, args);
}


unittest
{
    alias empty = applier!();
    static assert(isSame!( pack!(empty!Seq ), pack!( Seq!()) ));
    static assert(isSame!( pack!(empty!pack), pack!(pack!()) ));

    alias int100 = applier!(int, 100);
    static assert(isSame!( int100!q{ A[b] }, int[100] ));
}



//----------------------------------------------------------------------------//
// Sequence Construction
//----------------------------------------------------------------------------//


/* undocumented (internal use) */
template recurrence(size_t n, alias fun, Seed...)
{
    static if (n < 2)
    {
        alias recurrence = Seed[0 .. n * $];
    }
    else
    {
        alias recurrence = Seq!(Seed, recurrence!(n - 1, fun, apply!(fun, Seed)));
    }
}


unittest
{
    static assert([ recurrence!(0, q{ a*5 }, 1) ] == [ ]);
    static assert([ recurrence!(1, q{ a*5 }, 1) ] == [ 1 ]);
    static assert([ recurrence!(2, q{ a*5 }, 1) ] == [ 1,5 ]);
    static assert([ recurrence!(5, q{ a*5 }, 1) ] == [ 1,5,25,125,625 ]);

    alias VI = recurrence!(3, q{ Seq!(args, void) }, int);
    static assert(is(VI == TypeSeq!(int, int, void, int, void, void)));
}



/**
Yields a sequence of numbers starting from $(D beg) to $(D end) with the
specified $(D step).

Params:
  beg = Compile-time numeral value ($(D 0) if not specified).  The generated
        sequence starts with $(D beg) if not empty.

  end = Compile-time numeral value.  The resulting sequence stops before
        $(D end) and never contain this value.

 step = Compile-time numeral value ($(D 1) if not specified).  The generated
        sequence increases or decreases by $(D step).  This value may not
        be zero or NaN.

Returns:
 Sequence of compile-time numbers starting from $(D beg) to $(D end),
 increasing/decreasing by $(D step).  The generated sequence is empty if
 $(D beg) is ahead of $(D end) in terms of the $(D step)'s direction.
 */
template iota(alias beg, alias end, alias step) if (step != 0)
{
    static if ((end - beg) / step >= 0)
    {
        static assert(isValue!(long, beg) && isValue!(long, step));

        static if (step > 0)
            enum count = cast(size_t) ((end - beg + step - 1) / step);
        else
            enum count = cast(size_t) ((end - beg + step + 1) / step);

        alias T = typeof(true ? beg : step);

        template increment(alias cur) { enum T increment = cur + step; }

        alias iota = recurrence!(count, increment, beg);
    }
    else
    {
        alias iota = Seq!();
    }
}

/// ditto
template iota(alias beg, alias end)
{
    alias iota = iota!(beg, end, cast(typeof(beg)) 1);
}

/// ditto
template iota(alias end)
{
    alias iota = iota!(cast(typeof(end)) 0, end);
}

/**
 Filling array elements using $(D meta.iota):
 */
unittest
{
    static Base64Chars = cast(immutable char[64])
        [
            meta.iota!('A', 'Z'+1),
            meta.iota!('a', 'z'+1),
            meta.iota!('0', '9'+1), '+', '/'
        ];
    static assert(Base64Chars[16] == 'Q');
    static assert(Base64Chars[32] == 'g');
    static assert(Base64Chars[62] == '+');
}

unittest
{
    static assert([ iota!0 ] == []);
    static assert([ iota!1 ] == [ 0 ]);
    static assert([ iota!2 ] == [ 0,1 ]);
    static assert([ iota!3 ] == [ 0,1,2 ]);
    static assert([ iota!(-1) ] == []);
    static assert([ iota!(-2) ] == []);

    static assert([ iota!(-5,  5) ] == [ -5,-4,-3,-2,-1,0,1,2,3,4 ]);
    static assert([ iota!( 5, -5) ] == []);
    static assert([ iota!(-5, -5) ] == []);

    static assert([ iota!( 3,  20, +4) ] == [  3, 7, 11, 15, 19 ]);
    static assert([ iota!(-3, -20, -4) ] == [ -3,-7,-11,-15,-19 ]);
    static assert([ iota!(1, 5, +9) ] == [ 1 ]);
    static assert([ iota!(5, 1, -9) ] == [ 5 ]);
    static assert([ iota!(3, 5, -1) ] == []);
    static assert([ iota!(5, 3, +1) ] == []);
    static assert([ iota!(3, 3, -1) ] == []);
}



/**
Creates a sequence in which $(D seq) repeats $(D n) times.

Params:
   n = The number of repetition.  May be zero.
 seq = Sequence to _repeat.

Returns:
 Sequence composed of $(D n) $(D seq)s.  The empty sequence is returned
 if $(D n) is zero or $(D seq) is empty.
 */
template repeat(size_t n, seq...)
{
    static if (n < 2 || seq.length == 0)
    {
        alias repeat = seq[0 .. n*$];
    }
    else
    {
        alias repeat = Seq!(repeat!(   n    / 2, seq),
                            repeat!((n + 1) / 2, seq));
    }
}

/**
 */
unittest
{
    static immutable array =
        [
            meta.repeat!(3, 1,2,3),
            meta.repeat!(3, 4,5,6),
        ];
    static assert(array == [ 1,2,3, 1,2,3, 1,2,3,
                             4,5,6, 4,5,6, 4,5,6 ]);
}

unittest
{
    // degeneracy
    static assert(is(repeat!(0) == Seq!()));
    static assert(is(repeat!(1) == Seq!()));
    static assert(is(repeat!(9) == Seq!()));
    static assert(is(repeat!(0, int        ) == Seq!()));
    static assert(is(repeat!(0, int, double) == Seq!()));

    // basic
    static assert(is(repeat!( 1, int, double) == Seq!(int, double)));
    static assert(is(repeat!( 2, int, double) == Seq!(int, double,
                                                      int, double)));
    static assert(is(repeat!( 3, int, double) == Seq!(int, double,
                                                      int, double,
                                                      int, double)));
    static assert(is(repeat!( 9, int) == Seq!(int, int, int, int,
                                              int, int, int, int, int)));
    static assert(is(repeat!(10, int) == Seq!(int, int, int, int, int,
                                              int, int, int, int, int)));

    // expressions
    static assert([0, repeat!(0, 8,7), 0] == [0,                  0]);
    static assert([0, repeat!(1, 8,7), 0] == [0, 8,7,             0]);
    static assert([0, repeat!(3, 8,7), 0] == [0, 8,7,8,7,8,7,     0]);
    static assert([0, repeat!(4, 8,7), 0] == [0, 8,7,8,7,8,7,8,7, 0]);
}



/* undocumented (used by stride) */
template frontof(seq...)
{
    alias frontof = Id!(seq[0]);
}



//----------------------------------------------------------------------------//
// Topological Transformation
//----------------------------------------------------------------------------//


/**
Reverses the sequence $(D seq).

Params:
 seq = Sequence to _reverse.

Returns:
 $(D seq) in the _reverse order.
 */
template reverse(seq...)
{
    static if (seq.length < 2)
    {
        alias reverse = seq;
    }
    else
    {
        alias reverse = Seq!(reverse!(seq[$/2 ..  $ ]),
                             reverse!(seq[ 0  .. $/2]));
    }
}

/**
 */
unittest
{
    alias Rev = meta.reverse!(int, double, string);
    static assert(is(Rev == TypeSeq!(string, double, int)));
}

unittest
{
    static assert(is(reverse!() == Seq!()));

    // basic
    static assert(is(reverse!(int) == Seq!(int)));
    static assert(is(reverse!(int, double) == Seq!(double, int)));
    static assert(is(reverse!(int, double, string) ==
                         Seq!(string, double, int)));
    static assert(is(reverse!(int, double, string, bool) ==
                         Seq!(bool, string, double, int)));

    // expressions
    static assert([0, reverse!(),        0] == [0,          0]);
    static assert([0, reverse!(1),       0] == [0, 1,       0]);
    static assert([0, reverse!(1,2),     0] == [0, 2,1,     0]);
    static assert([0, reverse!(1,2,3),   0] == [0, 3,2,1,   0]);
    static assert([0, reverse!(1,2,3,4), 0] == [0, 4,3,2,1, 0]);
}



/**
Rotates $(D seq) by $(D n).  If $(D n) is positive and less than $(D seq),
the result is $(D (seq[n .. $], seq[0 .. n])).

Params:
   n = The amount of rotation.  The sign determines the direction:
       positive for left rotation and negative for right rotation.
       This argument can be zero or larger than $(D seq.length).
 seq = Sequence to _rotate.

Returns:
 Sequence $(D seq) rotated by $(D n).
 */
template rotate(sizediff_t n, seq...)
{
    static if (seq.length < 2)
    {
        alias rotate = seq;
    }
    else
    {
        static if (n < 0)
        {
            alias rotate = rotate!(seq.length + n, seq);
        }
        else
        {
            alias rotate = Seq!(seq[n % $ .. $], seq[0 .. n % $]);
        }
    }
}

/**
 */
unittest
{
    alias rotL = meta.rotate!(+1, int, double, string);
    alias rotR = meta.rotate!(-1, int, double, string);

    static assert(is(rotL == TypeSeq!(double, string, int)));
    static assert(is(rotR == TypeSeq!(string, int, double)));
}

unittest
{
    alias empty0  = rotate!(0);
    alias single0 = rotate!(0, int);
    alias triple0 = rotate!(0, int, double, string);
    static assert(is( empty0 == Seq!()));
    static assert(is(single0 == Seq!(int)));
    static assert(is(triple0 == Seq!(int, double, string)));

    alias empty2  = rotate!(+2);
    alias single2 = rotate!(+2, int);
    alias triple2 = rotate!(+2, int, double, string);
    static assert(is( empty2 == Seq!()));
    static assert(is(single2 == Seq!(int)));
    static assert(is(triple2 == Seq!(string, int, double)));

    alias empty2rev  = rotate!(-2);
    alias single2rev = rotate!(-2, int);
    alias triple2rev = rotate!(-2, int, double, string);
    static assert(is( empty2rev == Seq!()));
    static assert(is(single2rev == Seq!(int)));
    static assert(is(triple2rev == Seq!(double, string, int)));
}



/**
Gets the elements of sequence with _stride $(D n).

Params:
   n = Stride width.  $(D n) must not be zero.
 seq = Sequence to _stride.

Returns:
 Sequence of $(D 0,n,2n,...)-th elements of the given sequence:
 $(D (seq[0], seq[n], seq[2*n], ...)).  The empty sequence is returned if the
 given sequence $(D seq) is empty.
 */
template stride(size_t n, seq...) if (n > 0)
{
    alias stride = segmentWith!(frontof, n, seq);
}

/**
 */
unittest
{
    alias seq = meta.Seq!(int, "index", 10,
                          double, "number", 5.0);
    alias Types = meta.stride!(3, seq        );
    alias names = meta.stride!(3, seq[1 .. $]);

    static assert(meta.isSame!(meta.pack!Types, meta.pack!(int, double)));
    static assert(meta.isSame!(meta.pack!names, meta.pack!("index", "number")));
}

unittest
{
    static assert(is(stride!(1) == Seq!()));
    static assert(is(stride!(2) == Seq!()));
    static assert(is(stride!(5) == Seq!()));

    alias AsIs = stride!(1, int, double, string);
    static assert(is(AsIs == TypeSeq!(int, double, string)));

    static assert([ stride!(2, 1,2,3,4,5) ] == [ 1,3,5 ]);
    static assert([ stride!(3, 1,2,3,4,5) ] == [ 1,4 ]);
    static assert([ stride!(5, 1,2,3,4,5) ] == [ 1 ]);
}



/**
Splits sequence $(D seq) into segments of the same length $(D n).

Params:
   n = The size of each _segment.  $(D n) must not be zero.
 seq = Sequence to split.  The sequence can have arbitrary length.

Returns:
 Sequence of packed segments of length $(D n).  Each _segment is packed using
 $(D meta.pack); use the $(D expand) property to yield the contents.

 The last _segment can be shorter than $(D n) if $(D seq.length) is not an
 exact multiple of $(D n).  The empty sequence is returned if $(D seq) is
 empty.
 */
template segment(size_t n, seq...) if (n > 0)
{
    alias segment = segmentWith!(pack, n, seq);
}

/**
 $(D meta.segment) would be useful to scan simple patterns out of
 template parameters or other sequences.
 */
unittest
{
    alias seq = meta.Seq!(int, "index", 10,
                          double, "number", 5.0);

    alias patterns = meta.segment!(3, seq);
    static assert(meta.isSame!(patterns[0], meta.pack!(int, "index", 10)));
    static assert(meta.isSame!(patterns[1], meta.pack!(double, "number", 5.0)));
}

unittest
{
    alias empty1 = segment!(1);
    alias empty9 = segment!(9);
    static assert(empty1.length == 0);
    static assert(empty9.length == 0);

    alias seg1 = segment!(1, 1,2,3,4);
    alias seg2 = segment!(2, 1,2,3,4);
    alias seg3 = segment!(3, 1,2,3,4);
    static assert(isSame!( pack!seg1, pack!(pack!(1), pack!(2), pack!(3), pack!(4)) ));
    static assert(isSame!( pack!seg2, pack!(pack!(1,2), pack!(3,4)) ));
    static assert(isSame!( pack!seg3, pack!(pack!(1,2,3), pack!4) ));
}



/* undocumented (for internal use) */
template segmentWith(string fun, size_t n, seq...)
{
    alias segmentWith = segmentWith!(variadicT!fun, n, seq);
}

template segmentWith(alias fun, size_t n, seq...) if (n > 0)
{
    template segment()
    {
        alias segment = Seq!();
    }
    template segment(seq...)
    {
        static if (seq.length <= n)
        {
            alias segment = Seq!(fun!seq);
        }
        else
        {
            alias segment = Seq!(fun!(seq[0 .. n]), segment!(seq[n .. $]));
        }
    }

    alias segmentWith = segment!seq;
}


unittest
{
    alias empty1 = segmentWith!(pack, 1);
    alias empty5 = segmentWith!(pack, 5);
    static assert(empty1.length == 0);
    static assert(empty5.length == 0);

    alias doubled = segmentWith!(q{ a*2 }, 1,
                                 1,2,3,4,5,6);
    static assert([ doubled ] == [ 2,4,6,8,10,12 ]);

    alias rev2 = segmentWith!(reverse, 2,
                              1,2,3,4,5,6,7,8,9);
    static assert([ rev2 ] == [ 2,1,4,3,6,5,8,7,9 ]);
}

unittest
{
    alias result = meta.segmentWith!(q{ B[A] }, 2,
                                     string, int, string, double);
    static assert(is(result[0] ==    int[string]));
    static assert(is(result[1] == double[string]));
}



/* undocumented (for internal use) */
template transverse(size_t i, seqs...) if (isTransversable!(i, seqs))
{
    alias transverse = map!(unpackAt!i, seqs);
}

private
{
    template unpackAt(size_t i)
    {
        alias unpackAt(alias pak) = Id!(pak.expand[i]);
    }

    template isTransversable(size_t i, seqs...)
    {
        enum isTransversable = all!(compiles!(unpackAt!i), seqs);
    }
}


unittest
{
    alias empty0 = transverse!0;
    alias empty9 = transverse!9;
    static assert(empty0.length == 0);
    static assert(empty9.length == 0);

    alias single0 = transverse!(0, pack!(int, double, string));
    alias single2 = transverse!(2, pack!(int, double, string));
    static assert(is(single0 == Seq!int));
    static assert(is(single2 == Seq!string));

    alias jagged = transverse!(1, pack!(1,2), pack!(3,4,5), pack!(6,7));
    static assert([ jagged ] == [ 2,4,7 ]);

    static assert(!__traits(compiles, transverse!(0, 1,2,3) ));
    static assert(!__traits(compiles, transverse!(0, pack!1, pack!()) ));
}

unittest
{
    alias second = meta.transverse!(1, meta.pack!(int, 255),
                                       meta.pack!(double, 7.5),
                                       meta.pack!(string, "yo"));
    static assert(meta.isSame!(meta.pack!second, meta.pack!(255, 7.5, "yo")));
}



/**
Generates a sequence iterating given sequences in lockstep.  The iteration
stops at the end of the shortest sequence.

Params:
 seqs = Sequence of packed sequences.  Each packed sequence must have a
        property $(D expand) that yields a sequence.

Returns:
 Sequence of the transversals of $(D seqs).  The $(D i)-th transversal is a
 packed sequence containing the $(D i)-th elements of given sequences.  The
 empty sequence is returned if $(D seqs) is empty or any of the sequences
 is empty.
 */
template zip(seqs...) if (isZippable!seqs)
{
    alias zip = zipWith!(pack, seqs);
}

/**
 */
unittest
{
    alias zipped = meta.zip!(meta.pack!(int, 255),
                             meta.pack!(double, 7.5),
                             meta.pack!(string, "yo"));
    static assert(meta.isSame!(zipped[0], meta.pack!(int, double, string)));
    static assert(meta.isSame!(zipped[1], meta.pack!(255, 7.5, "yo")));
}

private
{
    template isZippable(seqs...)
    {
        static if (_minLength!seqs == 0)
            enum isZippable = true;
        else
            enum isZippable = isTransversable!(_minLength!seqs - 1, seqs);
    }

    template _minLength(seqs...)
    {
        static if (seqs.length == 0)
            enum _minLength = 0;
        else
        {
            alias shortest = most!(q{ a.length < b.length }, seqs);

            enum _minLength = shortest.length;
        }
    }
}


unittest
{
    alias empty = zip!();
    static assert(empty.length == 0);

    alias zip3 = zip!(pack!(int, double, bool), pack!(4, 8, 1));
    static assert(zip3.length == 3);
    static assert(isSame!(zip3[0], pack!(   int, 4)));
    static assert(isSame!(zip3[1], pack!(double, 8)));
    static assert(isSame!(zip3[2], pack!(  bool, 1)));

    alias jagged = zip!(pack!(int, double, string),
                        pack!("i", "x"),
                        pack!(5, 1.5, "moinmoin"));
    static assert(jagged.length == 2);
    static assert(isSame!(jagged[0], pack!(   int, "i",   5)));
    static assert(isSame!(jagged[1], pack!(double, "x", 1.5)));

    alias degen = zip!(pack!int, pack!(), pack!(double, string));
    static assert(degen.length == 0);
}



/**
Generalization of $(D meta.zip) passing each transversal to $(D fun), instead
of packing with $(D meta.pack).

Params:
  fun = Template of arity $(D seqs.length) that transforms each transversal.
 seqs = Sequence of packed sequences.

Returns:
 Sequence of the results of $(D fun) applied to each transversal of $(D seqs).
 */
template zipWith(alias fun, seqs...) if (isZippable!seqs)
{
    alias _fun = variadicT!fun;

    alias transverser(size_t i) = _fun!(transverse!(i, seqs));

    alias zipWith = map!(transverser, iota!(_minLength!seqs));
}

/**
 */
unittest
{
    alias types = meta.pack!("int", "double", "string");
    alias names = meta.pack!(  "i",      "x",      "s");
    alias zipped = meta.zipWith!(q{ a~" "~b }, types, names);

    static assert(zipped[0] == "int i");
    static assert(zipped[1] == "double x");
    static assert(zipped[2] == "string s");
}

unittest
{
    static struct MyPack(int n, T);

    alias revzip = zipWith!(compose!(MyPack, reverse),
                            pack!(int, double, string),
                            pack!(  1,      2,      3));
    static assert(is(revzip[0] == MyPack!(1,    int)));
    static assert(is(revzip[1] == MyPack!(2, double)));
    static assert(is(revzip[2] == MyPack!(3, string)));

    alias assoc = zipWith!(q{ A[B] },
                           pack!(  int, double, string),
                           pack!(dchar, string,    int));
    static assert(is(assoc[0] ==    int[ dchar]));
    static assert(is(assoc[1] == double[string]));
    static assert(is(assoc[2] == string[   int]));
}



//----------------------------------------------------------------------------//
// Elements Transformation
//----------------------------------------------------------------------------//


/**
Transforms a sequence $(D seq) into $(D (fun!(seq[0]), fun!(seq[1]), ...)).

Params:
 fun = Unary template used to transform each element of $(D seq) into another
       compile-time entity.  The result can be a sequence.
 seq = Sequence of compile-time entities to transform.

Returns:
 Sequence of the results of $(D fun) applied to each element of $(D seq) in
 turn.
 */
template map(alias fun, seq...)
{
    alias _fun = unaryT!fun;

    static if (seq.length == 0)
    {
        alias map = Seq!();
    }
    else static if (seq.length == 1)
    {
        alias map = Seq!(_fun!(seq[0]));
    }
    else
    {
        alias map = Seq!(map!(_fun, seq[ 0  .. $/2]),
                         map!(_fun, seq[$/2 ..  $ ]));
    }
}

/**
 Map types into pointers.
 */
unittest
{
    alias PP = meta.map!(q{ A* }, int, double, void*);
    static assert(is(PP[0] ==    int*));
    static assert(is(PP[1] == double*));
    static assert(is(PP[2] ==  void**));
}

unittest
{
    static assert(map!(Id).length == 0);
    static assert(map!(q{ a }).length == 0);

    alias single = map!(Id, int);
    static assert(is(single == Seq!int));

    alias const1 = map!(q{ const A }, int);
    static assert(is(const1 == Seq!(const int)));

    alias double5 = map!(q{ 2*a }, 1,2,3,4,5);
    static assert([ double5 ] == [ 2,4,6,8,10 ]);
}



/* Recursive map, used by uniqBy */
template mapRec(string fun, seq...)
{
    alias mapRec = mapRec!(variadicT!fun, seq);
}

template mapRec(alias fun, seq...)
{
    alias _impl()       = Seq!();
    alias _impl(seq...) = fun!(seq[0], _impl!(seq[1 .. $]));

    alias mapRec = _impl!seq;
}



/**
Creates a sequence only containing elements of $(D seq) satisfying $(D pred).

Params:
 pred = Unary predicate template that decides whether or not to include an
        element in the resulting sequence.
  seq = Sequence to _filter.

Returns:
 Sequence only containing elements of $(D seq) for each of which $(D pred)
 evaluates to $(D true).
 */
template filter(alias pred, seq...)
{
    alias filter = map!(conditional!(pred, Id, constant!()), seq);
}

/**
 */
unittest
{
    alias SmallTypes = meta.filter!(q{ A.sizeof < 4 }, byte, short, int, long);
    static assert(is(SmallTypes == TypeSeq!(byte, short)));
}

unittest
{
    alias empty = filter!(isType);
    static assert(empty.length == 0);

    alias none = filter!(isType, 1,2,3);
    alias all = filter!(isValue, 1,2,3);
    static assert([ none ] == []);
    static assert([ all ] == [ 1,2,3 ]);

    alias someT = filter!(isType, int, "x", double, "y");
    static assert(is(someT == Seq!(int, double)));

    alias someV = filter!(q{ a < 0 }, 4, -3, 2, -1, 0);
    static assert([ someV ] == [ -3, -1 ]);
}



/**
Removes all occurrences of $(D E) in $(D seq) if any.  Each occurrence is
tested in terms of $(D meta.isSame).

Params:
   E = Compile-time entity to _remove.
 seq = Target sequence.

Returns:
 Sequence $(D seq) in which any occurrence of $(D E) is erased.
 */
template remove(E, seq...)
{
    alias remove = filter!(not!(isSame!E), seq);
}

/// ditto
template remove(alias E, seq...)
{
    alias remove = filter!(not!(isSame!E), seq);
}

/**
 */
unittest
{
    alias Res = meta.remove!(void, int, void, double, void, string);
    static assert(is(Res == TypeSeq!(int, double, string)));
}

unittest
{
    alias empty1 = remove!(void);
    alias empty2 = remove!(1024);
    static assert(empty1.length == 0);
    static assert(empty2.length == 0);

    static assert([ remove!(void, 1,2,3,2,1) ] == [ 1,2,3,2,1 ]);
    static assert([ remove!(   2, 1,2,3,2,1) ] == [ 1,  3,  1 ]);

    alias NoVoid = remove!(void, int,void,string,void,double);
    alias No2    = remove!(   2, int,void,string,void,double);
    static assert(is(NoVoid == Seq!(int,     string,     double)));
    static assert(is(No2    == Seq!(int,void,string,void,double)));
}



/**
Replaces all occurrences of $(D From) in $(D seq) with $(D To).

Params:
 From = Element to remove.
   To = Element to insert in place of $(D From).
  seq = Sequence to perform replacements.

Returns:
 Sequence $(D seq) in which every occurrence of $(D From) (if any) is
 replaced by $(D To).
 */
template replace(From, To, seq...)
{
    alias replace = map!(conditional!(isSame!From, constant!To), seq);
}

/// ditto
template replace(alias From, alias To, seq...)
{
    alias replace = map!(conditional!(isSame!From, constant!To), seq);
}

/**
 */
unittest
{
    struct This;

    struct Example(Params...)
    {
        // Resolve 'This'
        alias Types = meta.replace!(This, Example!Params, Params);
    }
    alias Ex = Example!(int, double, This);
    static assert(is(Ex.Types[2] == Ex));
}

/**
 You may want to use $(D meta.map) with $(D meta.conditional) to perform more
 complex replacements.  The following example replaces every const types in a
 type sequence with a $(D void).
 */
unittest
{
    alias Res = meta.map!(meta.conditional!(q{ is(A == const) }, meta.constant!void),
                          int, const double, string, const bool);
    static assert(is(Res == TypeSeq!(int, void, string, void)));
}

unittest
{
    alias empty = replace!(void, int);
    static assert(empty.length == 0);

    alias NoMatch = replace!(void, int, Seq!(int, string, double));
    static assert(is(NoMatch == TypeSeq!(int, string, double)));

    // Test for the specializations
    alias TT = replace!(void, int, Seq!(void, double, void, string));
    static assert(is(TT == TypeSeq!(int, double, int, string)));

    alias vv = replace!(null, "", Seq!(null, "abc", null, "def"));
    static assert([ vv ] == [ "", "abc", "", "def" ]);

    // Test for ambiguity problem with user-defined types due to @@@BUG4431@@@
    struct S;
    alias amb1 = replace!(  S, int, S, S, S);
    alias amb2 = replace!(int,   S, S, S, S);
    alias amb3 = replace!(  S,   S, S, S, S);
}



/**
Sorts a sequence according to comparison predicate $(D comp).

Params:
 comp = Binary comparison predicate that compares elements of $(D seq).
        It typically works as the $(D <) operator to arrange the result in
        ascending order.
  seq = Sequence to _sort.

Returns:
 Sequence $(D seq) sorted according to the predicate $(D comp).  The relative
 order of equivalent elements will be preserved (i.e. stable).
 */
template sort(alias comp, seq...)
{
    template _impl(alias comp)
    {
        template sort(seq...)
        {
            static if (seq.length < 2)
            {
                alias sort = seq;
            }
            else
            {
                alias sort = Merge!(sort!(seq[ 0  .. $/2]))
                             .With!(sort!(seq[$/2 ..  $ ]));
            }
        }

        template Merge()
        {
            template With(B...)
            {
                alias With = B;
            }
        }

        template Merge(A...)
        {
            template With()
            {
                alias With = A;
            }

            template With(B...)
            {
                // Comparison must be in this order for stability.
                static if (comp!(B[0], A[0]))
                {
                    alias With = Seq!(B[0], Merge!(A        ).With!(B[1 .. $]));
                }
                else
                {
                    alias With = Seq!(A[0], Merge!(A[1 .. $]).With!(B        ));
                }
            }
        }
    }

    alias sort = _impl!(binaryT!comp).sort!seq;
}

/**
 */
unittest
{
    // Sort types in terms of the sizes.
    alias Types = TypeSeq!(double, int, bool, uint, short);

    alias Inc = meta.sort!(q{ A.sizeof < B.sizeof }, Types);
    alias Dec = meta.sort!(q{ A.sizeof > B.sizeof }, Types);

    static assert(is( Inc == TypeSeq!(bool, short, int, uint, double) ));
    static assert(is( Dec == TypeSeq!(double, int, uint, short, bool) ));
}

unittest
{
    enum sizeLess(A, B) = (A.sizeof < B.sizeof);

    // Trivial cases
    alias Empty  = sort!(sizeLess);
    alias Single = sort!(sizeLess, int);
    static assert(is(Empty == Seq!()));
    static assert(is(Single == Seq!(int)));

    //
    alias Double = sort!(sizeLess, int, short);
    static assert(is(Double == Seq!(short, int)));

    alias Sorted1 = sort!(sizeLess, long, int, short, byte);
    alias Sorted2 = sort!(sizeLess, short, int, byte, long);
    static assert(is(Sorted1 == Seq!(byte, short, int, long)));
    static assert(is(Sorted2 == Seq!(byte, short, int, long)));

    static assert([ sort!(q{ a < b }, 3,5,1,4,2) ] == [ 1,2,3,4,5 ]);
    static assert([ sort!(q{ a > b }, 3,5,1,4,2) ] == [ 5,4,3,2,1 ]);

    // Test for stability
    alias Equiv = sort!(sizeLess, uint, short, ushort, int);
    static assert(is(Equiv == Seq!(short, ushort, uint, int)));
}



/**
Removes any consecutive group of duplicate elements in $(D seq) except the
first one of each group.  Duplicates are detected with $(D meta.isSame).

Params:
 seq = Target sequence.

Returns:
 $(D seq) without any consecutive duplicate elements.
 */
template uniq(seq...)
{
    alias uniq = uniqBy!(isSame, seq);
}

/**
 */
unittest
{
    alias result = meta.uniq!(1, 2, 3, 3, 4, 4, 4, 2, 2);
    static assert([ result ] == [ 1, 2, 3, 4, 2 ]);
}

unittest
{
    alias empty = uniq!();
    static assert(empty.length == 0);

    alias Single = uniq!(int);
    static assert(is(Single == Seq!(int)));

    alias Nodup = uniq!(int, double, string);
    static assert(is(Nodup == Seq!(int, double, string)));

    alias Dup = uniq!(int, int, double, string, string, string);
    static assert(is(Dup == Seq!(int, double, string)));

    alias noConsec = uniq!("abc", "123", "abc", "123");
    static assert([ noConsec ] == [ "abc", "123", "abc", "123" ]);
}



/**
Generalization of $(D meta.uniq) detecting duplicates with $(D eq), instead
of $(D meta.isSame).

Params:
  eq = Binary predicate template that determines if passed-in arguments are
       the same (or duplicated).
 seq = Target sequence.

Returns:
 Sequence $(D seq) in which any consecutive group of duplicate elements are
 squeezed into the fist one of each group.
 */
template uniqBy(alias eq, seq...)
{
    template _impl(alias eq)
    {
        template uniqCons(car, cdr...)
        {
            static if (cdr.length && eq!(car, cdr[0]))
            {
                alias uniqCons = Seq!(car, cdr[1 .. $]);
            }
            else
            {
                alias uniqCons = Seq!(car, cdr);
            }
        }

        template uniqCons(alias car, cdr...)
        {
            static if (cdr.length && eq!(car, cdr[0]))
            {
                alias uniqCons = Seq!(car, cdr[1 .. $]);
            }
            else
            {
                alias uniqCons = Seq!(car, cdr);
            }
        }
    }

    alias uniqBy = mapRec!(_impl!(binaryT!eq).uniqCons, seq);
}

/**
 */
unittest
{
    alias Res = meta.uniqBy!(q{ A.sizeof == B.sizeof },
                             int, uint, short, ushort, uint);
    static assert(is(Res == TypeSeq!(int, short, uint)));
}

unittest
{
    alias empty = uniqBy!(q{ a == b });
    static assert(empty.length == 0);

    alias nodup = uniqBy!(q{ a == b }, 1,2,3,4,5);
    static assert([ nodup ] == [ 1,2,3,4,5 ]);

    alias noinc = uniqBy!(q{ a < b }, 1,2,3,0,8,7,6,5);
    static assert([ noinc ] == [ 1,0,7,6,5 ]);
}



/**
Completely removes all duplicate elements in $(D seq) except the first one.
Duplicates are detected with $(D meta.isSame).

Params:
 seq = Target sequence.

Returns:
 Sequence $(D seq) without any duplicate elements.
 */
template removeDuplicates(seq...)
{
    alias removeDuplicates = removeDuplicatesBy!(isSame, seq);
}

/**
 */
unittest
{
    alias Res = meta.removeDuplicates!(int, bool, bool, int, string);
    static assert(is(Res == TypeSeq!(int, bool, string)));
}

unittest
{
    alias empty = removeDuplicates!();
    static assert(empty.length == 0);

    alias Single = removeDuplicates!(int);
    static assert(is(Single == Seq!(int)));

    alias Dup = removeDuplicates!(int, double, string, int, double);
    static assert(is(Dup == Seq!(int, double, string)));

    alias values = removeDuplicates!("fun", "gun", "fun", "hun");
    static assert([ values ] == [ "fun", "gun", "hun" ]);
}



/**
Generalization of $(D meta.removeDuplicates) detecting duplicates with
$(D eq), instead of $(D meta.isSame).

Params:
  eq = Binary predicate template that determines if passed-in arguments are
       the same (or duplicated).
 seq = Target sequence.

Returns:
 Sequence $(D seq) in which any group of duplicate elements are eliminated
 except the fist one of each group.
 */
template removeDuplicatesBy(alias eq, seq...)
{
    static if (seq.length < 2)
    {
        alias removeDuplicatesBy = seq;
    }
    else
    {
        alias removeDuplicatesBy =
              Seq!(seq[0],
                   removeDuplicatesBy!(
                       eq, filter!(bind!(not!eq, seq[0]), seq[1 .. $])));
    }
}

/**
 */
unittest
{
    alias Res = meta.removeDuplicatesBy!(q{ A.sizeof == B.sizeof },
                                         int, uint, short, ushort, uint);
    static assert(is(Res == TypeSeq!(int, short)));
}

unittest
{
    alias empty = removeDuplicatesBy!(q{ a == b });
    static assert(empty.length == 0);

    alias nodup = removeDuplicatesBy!(q{ a == b }, 1,2,3,4,5);
    static assert([ nodup ] == [ 1,2,3,4,5 ]);

    alias decrease = removeDuplicatesBy!(q{ a < b }, 9,6,7,8,3,4,5,0);
    static assert([ decrease ] == [ 9,6,3,0 ]);
}



//----------------------------------------------------------------------------//
// Iteration & Query
//----------------------------------------------------------------------------//


/**
Reduces the sequence $(D seq) by successively applying a binary template
$(D fun) over elements, with an initial state $(D Seed):
----------
fun!( ... fun!(fun!(Seed, seq[0]), seq[1]) ..., seq[$ - 1])
----------

Params:
  fun = Binary template or string.
 Seed = The initial state.
  seq = Sequence of zero or more compile-time entities to _reduce.

Returns:
 The last result of $(D fun), or $(D Seed) if $(D seq) is empty.

See_Also:
 $(D meta.scan): reduce with history.
 */
template reduce(alias fun, Seed, seq...)
{
    alias reduce = _reduce!(binaryT!fun)._impl!(Seed, seq);
}

/// ditto
template reduce(alias fun, alias Seed, seq...)
{
    alias reduce = _reduce!(binaryT!fun)._impl!(Seed, seq);
}

/**
 Computing the net accumulation of the size of types.
 */
unittest
{
    alias Types = TypeSeq!(int, double, short, bool, dchar);

    // Note: 'a' gets the "current sum" and 'B' gets a type in the sequence.
    enum size = meta.reduce!(q{ a + B.sizeof }, 0, Types);
    static assert(size == 4 + 8 + 2 + 1 + 4);
}


private template _reduce(alias fun)
{
    template _impl(      Seed) { alias _impl = Seed; }
    template _impl(alias Seed) { alias _impl = Seed; }
    template _impl(      Seed, seq...) { mixin(_reduceBody); }
    template _impl(alias Seed, seq...) { mixin(_reduceBody); }

    enum _reduceBody =
    q{
        static if (seq.length == 1)
        {
            alias _impl = fun!(Seed, seq[0]);
        }
        else
        {
            // Halving seq reduces the recursion depth.
            alias _impl = _impl!(_impl!(Seed, seq[0 .. $/2]), seq[$/2 .. $]);
        }
    };
}


unittest
{
    static assert(is(reduce!(q{ A[B] }, int) == int));
    static assert(reduce!(q{ a ~ b }, "abc") == "abc");

    alias Assoc = reduce!(q{ A[B] }, int, double, string);
    static assert(is(Assoc == int[double][string]));

    enum concat = reduce!(q{ a ~ b }, "abc", "123", "xyz", "987");
    static assert(concat == "abc123xyz987");

    // Test for ambiguity on matching string/alias parameters
    struct S {}
    alias K1 = reduce!(        q{ A[B] }, S);
    alias K2 = reduce!(binaryT!q{ A[B] }, S);
    enum s1 = reduce!(        q{ a ~ b }, "");
    enum s2 = reduce!(binaryT!q{ a ~ b }, "");
}



/**
Returns a sequence generated by successively applying a binary template
$(D fun) over the elements of $(D seq), with an initial state $(D Seed):
----------
scan[0] = Seed;
scan[1] = fun!(scan[0], seq[0]);
scan[2] = fun!(scan[1], seq[1]);
        :
----------
Note that $(D scan[i]) is equal to $(D meta.reduce!(fun, Seed, seq[0 .. i])).

Params:
  fun = Binary template or string.
 Seed = The initial state.
  seq = Sequence of zero or more compile-time entities to _scan.

Returns:
 Sequence of the results of $(D fun) preceded by $(D Seed).
 */
template scan(alias fun, Seed, seq...)
{
    alias scan = _scan!(binaryT!fun).scan!(Seed, seq);
}

/// ditto
template scan(alias fun, alias Seed, seq...)
{
    alias scan = _scan!(binaryT!fun).scan!(Seed, seq);
}

/**
 Computing the sum of the size of types with history.

 Note that $(D sums[5]), or $(D sums[Types.length]), equals the result
 of the corresponding example of $(D meta.reduce).
 */
unittest
{
    alias Types = TypeSeq!(int, double, short, bool, dchar);

    alias sums = meta.scan!(q{ a + B.sizeof }, 0, Types);
    static assert([ sums ] == [ 0,
                                0+4,
                                0+4+8,
                                0+4+8+2,
                                0+4+8+2+1,
                                0+4+8+2+1+4 ]);
}

private template _scan(alias fun)
{
    template scan(      Seed, seq...) { mixin(_scanBody); }
    template scan(alias Seed, seq...) { mixin(_scanBody); }

    enum _scanBody =
    q{
        static if (seq.length == 0)
        {
            alias scan = Seq!(Seed);
        }
        else
        {
            alias scan = Seq!(Seed, scan!(fun!(Seed, seq[0]), seq[1 .. $]));
        }
    };
}


unittest
{
    alias Assocs = scan!(q{ A[B] }, int, double, string);
    static assert(Assocs.length == 3);
    static assert(is(Assocs[0] == int));
    static assert(is(Assocs[1] == int[double]));
    static assert(is(Assocs[2] == int[double][string]));

    alias concats = scan!(q{ a ~ b }, "abc", "123", "xyz", "987");
    static assert(concats.length == 4);
    static assert(concats[0] == "abc");
    static assert(concats[1] == "abc123");
    static assert(concats[2] == "abc123xyz");
    static assert(concats[3] == "abc123xyz987");

    // Test for non-ambiguity
    struct S {}
    alias K1 = scan!(        q{ A[B] }, S);
    alias K2 = scan!(binaryT!q{ A[B] }, S);
    enum s1 = scan!(        q{ a ~ b }, "");
    enum s2 = scan!(binaryT!q{ a ~ b }, "");
}



/**
Looks for the first "top" element of a sequence in terms of the specified
comparison template $(D comp).  This template is effectively the same
as $(D meta.sort!(comp, seq)[0]).

Params:
 comp = Binary template that compares items in the sequence.
  seq = One or more compile-time entities.
 */
template most(alias comp, seq...) if (seq.length > 0)
{
    template more(alias comp)
    {
        template more(pair...)
        {
            // Comparison must be in this order for stability.
            static if (comp!(pair[1], pair[0]))
            {
                alias more = Id!(pair[1]);
            }
            else
            {
                alias more = Id!(pair[0]);
            }
        }
    }

    alias most = reduce!(more!(binaryT!comp), seq);
}

/**
 To get the largest element in the sequence, specify a greater-than operator
 as the $(D comp) argument.
 */
unittest
{
    alias Types = TypeSeq!(int, bool, double, short);

    // Take the largest type in the sequence: double.
    alias Largest = meta.most!(q{ A.sizeof > B.sizeof }, Types);
    static assert(is(Largest == double));
}

unittest
{
    static assert(most!(q{ a < b }, 5) == 5);
    static assert(most!(q{ a < b }, 5, 5, 5) == 5);
    static assert(most!(q{ a < b }, 5, 1, -3, 2, 4) == -3);

    // stability
    alias Min = most!(q{ A.sizeof < B.sizeof }, short, byte, float, ubyte, uint);
    alias Max = most!(q{ A.sizeof > B.sizeof }, short, byte, float, ubyte, uint);
    static assert(is(Min ==  byte));
    static assert(is(Max == float));
}



/*
Groundwork for find-family algorithms.  index!() finds the index of the
first m-subsequence satisfying the predicate.  The predicate is evaluated
lazily so that unnecessary instantiations should not kick in.

Params:
 pred = m-ary predicate template.
    m = Size of chunk to find.
 */
template _findChunk(alias pred, size_t m)
{
    template index(seq...) if (seq.length < m)
    {
        enum index = seq.length;    // not found
    }

    // Simple search.
    template index(seq...) if (m <= seq.length && seq.length < 2*m)
    {
        static if (pred!(seq[0 .. m]))
        {
            enum size_t index = 0;
        }
        else
        {
            enum size_t index = index!(seq[1 .. $]) + 1;
        }
    }

    // Halve seq to reduce the recursion depth.  This specialization
    // is just for that purpose and index!() could work without this.
    template index(seq...) if (2*m <= seq.length)
    {
        static if (index!(seq[0 .. $/2 + m - 1]) < seq.length/2)
        {
            enum index = index!(seq[0 .. $/2 + m - 1]);
        }
        else
        {
            enum index = index!(seq[$/2 .. $]) + seq.length/2;
        }
    }
}



/**
Looks for the first occurrence of $(D E) in $(D seq).

Params:
   E = Compile-time entity to look for.
 seq = Target sequence.

Returns:
 Subsequence of $(D seq) after $(D E) (inclusive).  The empty sequence
 is returned if $(D E) is not found.
 */
template find(E, seq...)
{
    alias find = findIf!(isSame!E, seq);
}

/// ditto
template find(alias E, seq...)
{
    alias find = findIf!(isSame!E, seq);
}

/**
 */
unittest
{
    alias Types = TypeSeq!(int, short, double, bool, string);

    alias AfterBool = meta.find!(bool, Types);
    static assert(is(AfterBool == TypeSeq!(bool, string)));
}

unittest
{
    static assert(find!(void).length == 0);
    static assert(find!(   0).length == 0);

    static assert(find!(void, int, string).length == 0);
    static assert(find!(   0, int, string).length == 0);

    alias Void = find!(void, int, string, void, void, double);
    static assert(is(Void == Seq!(void, void, double)));

    alias opAss = find!("opAssign", "toString", "opAssign", "empty");
    static assert([ opAss ] == [ "opAssign", "empty" ]);
}

unittest
{
    alias Types = TypeSeq!(int, short, double, bool, string);

    alias Sub = meta.find!(meta.most!(q{ A.sizeof > B.sizeof }, Types),
                           Types);
    static assert(is(Sub == TypeSeq!(double, bool, string)));
}



/**
Looks for the first element of $(D seq) satisfying $(D pred).

Params:
 pred = Unary predicate template.
  seq = Target sequence.

Returns:
 Subsequence of $(D seq) after the found element, if any, inclusive.
 The empty sequence is returned if not found.
 */
template findIf(alias pred, seq...)
{
    alias findIf = seq[_findChunk!(unaryT!pred, 1).index!seq .. $];
}

/**
 */
unittest
{
    alias Res = meta.findIf!(q{ is(A == const) },
                             int, double, const string, bool);
    static assert(is(Res == TypeSeq!(const string, bool)));
}

unittest
{
    static assert(findIf!(q{ true }).length == 0);

    static assert([ findIf!(q{ a < 0 }, 5,4,3,2,1,0) ] == []);
    static assert([ findIf!(q{ a < 0 }, 2,1,0,-1,-2) ] == [ -1,-2 ]);
}



/**
Finds the _index of the first occurrence of $(D E) in a sequence.

Params:
   E = Compile-time entity to look for.
 seq = Target sequence.

Returns:
 Index of the first element, if any, that is same as $(D E).  $(D -1) is
 returned if not found.  The type of the result is $(D sizediff_t).
 */
template index(E, seq...)
{
    enum index = indexIf!(isSame!E, seq);
}

/// ditto
template index(alias E, seq...)
{
    enum index = indexIf!(isSame!E, seq);
}

/**
 */
unittest
{
    alias Types = TypeSeq!(int, double, bool, string);

    static assert(meta.index!(bool, Types) ==  2);
    static assert(meta.index!(void, Types) == -1);
}

unittest
{
    static assert(index!(int) == -1);
    static assert(index!( 16) == -1);

    static assert(index!(int, string, double, bool) == -1);
    static assert(index!( 16, string, double, bool) == -1);

    static assert(index!(string, string, double, int) == 0);
    static assert(index!(double, string, double, int) == 1);
    static assert(index!(   int, string, double, int) == 2);

    static assert(index!( 4, 4, 8, 16) == 0);
    static assert(index!( 8, 4, 8, 16) == 1);
    static assert(index!(16, 4, 8, 16) == 2);

    // Type check
    static assert(is(typeof(index!(int, int, double)) == sizediff_t));
    static assert(is(typeof(index!( 16, int, double)) == sizediff_t));
}



/**
Finds the index of the first element of a sequence satisfying a predicate.

Params:
 pred = Unary predicate template.
  seq = Target sequence.

Returns:
 Index of the first element, if any, satisfying the predicate $(D pred).
 $(D -1) is returned if not found.  The type of the result is $(D sizediff_t).
 */
template indexIf(alias pred, seq...)
{
    static if (_findChunk!(unaryT!pred, 1).index!seq == seq.length)
    {
        enum sizediff_t indexIf = -1;
    }
    else
    {
        enum sizediff_t indexIf = _findChunk!(unaryT!pred, 1).index!seq;
    }
}

/**
 */
unittest
{
    alias Types = TypeSeq!(int, double, short, string);

    static assert(meta.indexIf!(q{ A.sizeof < 4 }, Types) ==  2);
    static assert(meta.indexIf!(q{ A.sizeof < 2 }, Types) == -1);
}

unittest
{
    static assert(indexIf!(q{  true }) == -1);
    static assert(indexIf!(q{ false }, string, double, bool) == -1);

    static assert(indexIf!(q{ a % 2 == 0 }, 2, 6, 8) == 0);
    static assert(indexIf!(q{ a % 3 == 0 }, 2, 6, 8) == 1);
    static assert(indexIf!(q{ a % 4 == 0 }, 2, 6, 8) == 2);

    // Type check
    static assert(is(typeof(indexIf!(q{  true }, int, double)) == sizediff_t));
    static assert(is(typeof(indexIf!(q{ false }, int, double)) == sizediff_t));
}



/**
Counts the number of occurrences of $(D E) in $(D seq).

Params:
   E = Compile-time entity to look for.
 seq = Target sequence.

Returns:
 The number of elements in $(D seq) satisfying $(D isSame!E).
 */
template count(E, seq...)
{
    enum count = countIf!(isSame!E, seq);
}

/// ditto
template count(alias E, seq...)
{
    enum count = countIf!(isSame!E, seq);
}

/**
 */
unittest
{
    alias Types = TypeSeq!(int, double, string, void);
    static assert(meta.count!(void, Types) == 1);
}

unittest
{
    static assert(count!(int) == 0);
    static assert(count!( 16) == 0);

    static assert(count!(int, double, string, bool) == 0);
    static assert(count!( 16, double, string, bool) == 0);

    static assert(count!(int, int, void, void) == 1);
    static assert(count!(int, int,  int, void) == 2);
    static assert(count!(int, int,  int,  int) == 3);

    static assert(count!(16, 16,  8,  4) == 1);
    static assert(count!(16, 16, 16,  4) == 2);
    static assert(count!(16, 16, 16, 16) == 3);
}



/**
Counts the number of elements in $(D seq) satisfying the predicate $(D pred).

Params:
 pred = Unary predicate template.
  seq = Target sequence.

Returns:
 The number of elements in $(D seq) satisfying the predicate $(D pred).
 */
template countIf(alias pred, seq...)
{
    alias _pred = unaryT!pred;

    static if (seq.length < 2)
    {
        static if (seq.length == 0 || !_pred!(seq[0]))
        {
            enum size_t countIf = 0;
        }
        else
        {
            enum size_t countIf = 1;
        }
    }
    else
    {
        enum countIf = countIf!(_pred, seq[ 0  .. $/2]) +
                       countIf!(_pred, seq[$/2 ..  $ ]);
    }
}

/**
 */
unittest
{
    static assert(meta.countIf!(q{ a[0] == '_' },
                                "__ctor", "__dtor", "foo", "bar") == 2);
}

unittest
{
    static assert(countIf!(q{  true }) == 0);
    static assert(countIf!(q{ false }, int, double, string) == 0);

    static assert(countIf!(q{ a % 6 == 0 }, 1,2,3,4,5,6) == 1);
    static assert(countIf!(q{ a % 3 == 0 }, 1,2,3,4,5,6) == 2);
    static assert(countIf!(q{ a % 2 == 0 }, 1,2,3,4,5,6) == 3);
}



/**
Determines if, respectively, _all/_any/_none of the elements in a
sequence $(D seq) satisfies the predicate $(D pred).  Specifically:
----------
 all =  pred!(seq[0]) &&  pred!(seq[1]) && ... ;
 any =  pred!(seq[0]) ||  pred!(seq[1]) || ... ;
none = !pred!(seq[0]) && !pred!(seq[1]) && ... ;
----------

Params:
 pred = Unary predicate template.
  seq = Zero or more compile-time entities to examine.

Returns:
 $(D true) if _all/_any/_none of the elements of the sequence satisfies
 the predicate.  For the empty sequence, $(D meta.all) and $(D meta.none)
 returns $(D true); and $(D meta.any) returns $(D false).
 */
template all(alias pred, seq...)
{
    enum all = (_findChunk!(not!pred, 1).index!seq == seq.length);
}

/**
 */
unittest
{
    import std.meta, std.range;

    static assert( meta.all!(isInputRange, int[], typeof(retro([1.0, 2.0])), dstring));
    static assert(!meta.all!(isInputRange, int[], typeof(retro([1.0, 2.0])),   dchar));
}

unittest
{
    enum isZero(int n) = (n == 0);

    static assert( all!(isZero));
    static assert( all!(isZero, 0));
    static assert(!all!(isZero, 1));
    static assert(!all!(isZero, 1, 2));
    static assert(!all!(isZero, 0, 1, 2));
    static assert( all!(isZero, 0, 0, 0));

    // Laziness
    static assert(!all!(isZero, 1, int));
    static assert(!all!(isZero, 0, 1, int));
    static assert(!all!(isZero, 0, 0, 1, int));
    static assert(!all!(isZero, 0, 0, 0, 1, int));

    // String
    static assert( all!(q{ is(A == const) }));
    static assert( all!(q{ is(A == const) }, const int));
}


/** ditto */
template any(alias pred, seq...)
{
    enum any = (_findChunk!(unaryT!pred, 1).index!seq < seq.length);
}


unittest
{
    enum isZero(int n) = (n == 0);

    static assert(!any!(isZero));
    static assert( any!(isZero, 0));
    static assert(!any!(isZero, 1));
    static assert(!any!(isZero, 1, 2));
    static assert( any!(isZero, 0, 1, 2));
    static assert( any!(isZero, 0, 0, 0));

    // Laziness
    static assert( any!(isZero, 0, int));
    static assert( any!(isZero, 1, 0, int));
    static assert( any!(isZero, 1, 2, 0, int));
    static assert( any!(isZero, 1, 2, 3, 0, int));

    // String
    static assert(!any!(q{ is(A == const) }));
    static assert( any!(q{ is(A == const) }, const int));
}


/** ditto */
template none(alias pred, seq...)
{
    enum none = (_findChunk!(unaryT!pred, 1).index!seq == seq.length);
}


unittest
{
    enum isZero(int n) = (n == 0);

    static assert( none!(isZero));
    static assert(!none!(isZero, 0));
    static assert( none!(isZero, 1));
    static assert( none!(isZero, 1, 2));
    static assert(!none!(isZero, 0, 1, 2));
    static assert(!none!(isZero, 0, 0, 0));

    // Laziness
    static assert(!none!(isZero, 0, int));
    static assert(!none!(isZero, 1, 0, int));
    static assert(!none!(isZero, 1, 2, 0, int));
    static assert(!none!(isZero, 1, 2, 3, 0, int));

    // String
    static assert( none!(q{ is(A == const) }));
    static assert(!none!(q{ is(A == const) }, const int));
}



/**
Determines if _only one of the elements of $(D seq) satisfies the predicate
$(D pred).  The predicate is tested for all the elements.

Params:
 pred = Unary predicate template.
  seq = Zero or more compile-time entities to examine.

Returns:
 $(D true) if $(D seq) is not empty and _only one of the elements satisfies
 the predicate.  Otherwise, $(D false) is returned.
 */
template only(alias pred, seq...)
{
    enum only = (countIf!(pred, seq) == 1);
}

/**
 */
unittest
{
    class B {}
    class C {}
    interface I {}
    interface J {}

    static assert(!meta.only!(q{ is(A == class) }, I, J));
    static assert( meta.only!(q{ is(A == class) }, B, I, J));
    static assert(!meta.only!(q{ is(A == class) }, B, C, I, J));
}

unittest
{
    enum isZero(int n) = (n == 0);

    static assert(!only!(isZero));
    static assert( only!(isZero, 0));
    static assert(!only!(isZero, 1));
    static assert(!only!(isZero, 1, 2));
    static assert( only!(isZero, 0, 1, 2));
    static assert(!only!(isZero, 0, 0, 0));

    // String
    static assert(!only!(q{ is(A == const) }));
    static assert( only!(q{ is(A == const) }, const int));
}



//----------------------------------------------------------------------------//
// Set Operations
//----------------------------------------------------------------------------//


/**
Normalizes the order of elements in a given sequence.  The normalization
would be useful for comparing sequences with respect only to their contents,
independent of the order of elements.

Params:
 seq = Any sequence to canonicalize the order.

Returns:
 Sequence $(D seq) rearranged in a uniform order.  Duplicate elements will
 be grouped into a continuous repetition of that entity.
 */
template setify(seq...)
{
    alias setify = sort!(metaComp, seq);
}

/**
 */
unittest
{
    alias A = meta.setify!(int, double, bool, int);
    alias B = meta.setify!(int, bool, double, bool);

    static assert(is(A == TypeSeq!(bool, double, int, int)));
    static assert(is(B == TypeSeq!(bool, bool, double, int)));

    // Use meta.uniq to ignore the duplicates.
    static assert(is(meta.uniq!A == meta.uniq!B));
}



/**
Determines if all the specified items present in a sequence.

Params:
   set = The sequence, packed with $(D meta.pack), to test.
 items = Zero or more compile-time entities to test the presence of.

         The number of duplicates, if any, is significant.  If there are
         $(D m) repetitions of an entity in $(D items), the template checks
         if $(D sub) _contains $(D m) or more duplicates of that entity; and
         returns $(D false) if not.

Returns:
 $(D true) if the sequence $(D set.expand) _contains all the _items in
 $(D items) including duplicates, or $(D false) if not.  $(D true) is
 returned if $(D items) is empty.
 */
template contains(alias set, items...)
{
    enum contains = (intersection!(set, pack!items).length == items.length);
}

/**
 */
unittest
{
    alias A = TypeSeq!(string, int, int, double);
    static assert( meta.contains!(meta.pack!A, string));
    static assert( meta.contains!(meta.pack!A, int, double, int));
    static assert(!meta.contains!(meta.pack!A, double, double));
    static assert(!meta.contains!(meta.pack!A, void));
}

unittest
{
    static assert( contains!(pack!()));
    static assert(!contains!(pack!(), int));
    static assert(!contains!(pack!(), int, "index"));

    alias nums = pack!(1, 1, 1, 2, 2, 3);
    static assert( contains!(nums));
    static assert( contains!(nums, nums.expand));

    static assert( contains!(nums, 3));
    static assert( contains!(nums, 1, 2, 3));
    static assert( contains!(nums, 3, 1, 2));
    static assert( contains!(nums, 1, 1, 2, 2));
    static assert( contains!(nums, 3, 1, 1, 1));

    static assert(!contains!(nums, 0));
    static assert(!contains!(nums, 0, 1, 2, 3));
    static assert(!contains!(nums, 1, 1, 1, 1));
    static assert(!contains!(nums, 3, 3));
}



/**
Determines if a sequence is composed of specified _items.

Params:
   set = The sequence, packed with $(D meta.pack), to test.
 items = Zero or more compile-time entities to test the presence of.

         The number of duplicates, if any, is significant.  If there are
         $(D m) repetitions of an entity in $(D items), the template checks
         if $(D set) _contains exactly $(D m) duplicates of that entity; and
         returns $(D false) if not.

Returns:
 $(D true) if the sequence $(D set.expand) is composed of exactly the same
 _items in $(D items) including duplicates, or $(D false) if not.
 */
template isComposedOf(alias set, items...)
{
    enum isComposedOf = is(pack!(setify!(set.expand)).Tag ==
                           pack!(setify!items).Tag);
}

/**
 */
unittest
{
    alias A = TypeSeq!(string, int, int, double);

    static assert( meta.isComposedOf!(meta.pack!A, double, int, string, int));
    static assert( meta.isComposedOf!(meta.pack!A, int, double, int, string));
    static assert(!meta.isComposedOf!(meta.pack!A, int, double, string));
    static assert(!meta.isComposedOf!(meta.pack!A, void));
}



/**
Takes the _intersection of zero or more sequences.

Params:
 seqs = Sequence of sequences to take _intersection of.  Each sequence must
        be packed into $(D meta.pack) or a compatible entity.

Returns:
 Sequence composed only of common elements of all the given sequences.  The
 empty sequence is returned if no sequence is passed or at least one sequence
 is empty.

 If the sequences contain $(D m1,m2,...) duplicates of the same entity
 respectively, the resulting _intersection will contain $(D min(m1,m2,...)),
 or the least, duplicates of that entity.

 The order of elements in the returned sequence is normalized to the order
 defined by $(D meta.setify).
 */
template intersection(seqs...)
{
    alias _impl(seqs...)          = reduce!(compose!(pack, .intersection), seqs).expand;
    alias _impl(alias A, alias B) = intersectionBy!(metaComp, A, B);
    alias _impl(alias A)          = setify!(A.expand);
    alias _impl()                 = Seq!();

    alias intersection = _impl!seqs;
}

/**
 */
unittest
{
    alias Inter = meta.intersection!(meta.pack!(int, int, double, bool, bool),
                                     meta.pack!(int, double, bool, double, bool),
                                     meta.pack!(bool, string, int, bool));
    static assert(is(Inter == TypeSeq!(bool, bool, int)));
}

unittest
{
    // Test for values
    alias a = Seq!(1,2,2,4,5,7,9);
    alias b = Seq!(0,1,2,4,4,7,8);
    alias c = Seq!(0,1,4,4,5,7,8);

    alias aa = intersection!(pack!a, pack!a);
    alias ab = intersection!(pack!a, pack!b);
    alias bc = intersection!(pack!b, pack!c);
    static assert(isComposedOf!(pack!aa, a));
    static assert(isComposedOf!(pack!ab, 1,2,4,7));
    static assert(isComposedOf!(pack!bc, 0,1,4,4,7,8));

    // Test for types
    alias T = Seq!(int, int, double, string);
    alias U = Seq!(double, string, double, int);
    alias V = Seq!(double, void, int, double);

    alias TT = intersection!(pack!T, pack!T);
    alias TU = intersection!(pack!T, pack!U);
    alias UV = intersection!(pack!U, pack!V);
    static assert(isComposedOf!(pack!TT, T));
    static assert(isComposedOf!(pack!TU, double, int, string));
    static assert(isComposedOf!(pack!UV, double, double, int));

    // Degeneration
    alias e = Seq!();
    static assert(intersection!(pack!e, pack!e).length == 0);
    static assert(intersection!(pack!e, pack!T).length == 0);
    static assert(intersection!(pack!T, pack!a).length == 0);
}

unittest
{
    static assert(intersection!().length == 0);

    alias Empty  = intersection!(pack!());
    alias Single = intersection!(pack!(int, double, string));
    static assert(is(Empty == TypeSeq!()));
    static assert(is(Single == setify!(int, double, string)));
}


/* internal use */
template intersectionBy(alias comp, alias A, alias B)
{
    template Intersect(A...)
    {
        template With(B...)
        {
            static if (comp!(A[0], B[0]))
            {
                alias With = Seq!(Intersect!(A[1 .. $])
                                      .With!(B        ));
            }
            else static if (comp!(B[0], A[0]))
            {
                alias With = Seq!(Intersect!(A        )
                                      .With!(B[1 .. $]));
            }
            else
            {
                alias With = Seq!(A[0], Intersect!(A[1 .. $])
                                            .With!(B[1 .. $]));
            }
        }

        template With() { alias With = Seq!(); }
    }

    template Intersect()
    {
        template With(B...) { alias With = Seq!(); }
    }

    alias intersectionBy = Intersect!(sort!(comp, A.expand))
                               .With!(sort!(comp, B.expand));
}



//----------------------------------------------------------------------------//
// Utility
//----------------------------------------------------------------------------//


/**
The $(D switch) statement-like utility template.

Params:
 cases = Sequence of zero or more $(D (_cond, then)) patterns optionally
         followed by a $(D default) argument.  $(D _cond) is a compile-time
         boolean value; $(D then) and $(D default) are any compile-time entities.

Returns:
 The $(D then) argument associated with the first $(D _cond) that is $(D true).
 The $(D default) argument is returned if all the $(D _cond)s are $(D false).

 Instantiation fails if no $(D _cond) is $(D true) and the $(D default) argument
 is not specified.  It also fails if there is a $(D _cond) that is not strictly
 typed as $(D bool).
 */
template cond(cases...) if (cases.length > 0)
{
    template _matchCase(bool cond, then...)
    {
        static if (cond)
        {
            alias _matchCase = then;
        }
        else
        {
            alias _matchCase = Seq!();
        }
    }

    template _matchCase(      fallback) { alias _matchCase = fallback; }
    template _matchCase(alias fallback) { alias _matchCase = fallback; }

    template _matchCase(spec...) if (spec.length > 1)
    {
        static assert(0, "Malformed cond-then: "~ spec.stringof);
    }

    static if (segmentWith!(_matchCase, 2, cases).length)
    {
        alias cond = frontof!(segmentWith!(_matchCase, 2, cases));
    }
    else static assert(0, "No match");
}

/**
 */
unittest
{
    enum n = 100000;

    alias T = meta.cond!(n <=  ubyte.max,  ubyte,
                         n <= ushort.max, ushort,
                         n <=   uint.max,   uint,   // matches
                                           ulong);
    static assert(is(T == uint));
}

unittest
{
    static assert(is(cond!(true, int) == int));
    static assert(is(cond!(true, int, void) == int));
    static assert(is(cond!(false, int, void) == void));

    static assert(is(cond!(true, int, true, double) == int));
    static assert(is(cond!(false, int, true, double, void) == double));
    static assert(is(cond!(false, int, false, double, void) == void));

    struct S;
    static assert(!__traits(compiles, cond!(S, int)));
    static assert(!__traits(compiles, cond!(-1, int)));
    static assert(!__traits(compiles, cond!(true, int, 123, int)));
    static assert(!__traits(compiles, cond!(false, int, false, int)));
}

