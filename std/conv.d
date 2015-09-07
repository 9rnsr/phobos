// Written in the D programming language.

/**
A one-stop shop for converting values from one type to another.

Copyright: Copyright Digital Mars 2007-.

License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors:   $(WEB digitalmars.com, Walter Bright),
           $(WEB erdani.org, Andrei Alexandrescu),
           Shin Fujishiro,
           Adam D. Ruppe,
           Kenji Hara

Source:    $(PHOBOSSRC std/_conv.d)

Macros:
WIKI = Phobos/StdConv

*/
module std.conv;

public import std.ascii : LetterCase;

import std.range.primitives;
import std.traits;
import std.typetuple;

private string convFormat(Char, Args...)(in Char[] fmt, Args args)
{
    import std.format : format;
    return std.format.format(fmt, args);
}

/* ************* Exceptions *************** */

/**
 * Thrown on conversion errors.
 */
class ConvException : Exception
{
    @safe pure nothrow
    this(string s, string fn = __FILE__, size_t ln = __LINE__)
    {
        super(s, fn, ln);
    }
}

private string convError_unexpected(S)(S source)
{
    return source.empty ? "end of input" : text("'", source.front, "'");
}

private auto convError(S, T)(S source, string fn = __FILE__, size_t ln = __LINE__)
{
    return new ConvException(
        text("Unexpected ", convError_unexpected(source),
             " when converting from type "~S.stringof~" to type "~T.stringof),
        fn, ln);
}

private auto convError(S, T)(S source, int radix, string fn = __FILE__, size_t ln = __LINE__)
{
    return new ConvException(
        text("Unexpected ", convError_unexpected(source),
             " when converting from type "~S.stringof~" base ", radix,
             " to type "~T.stringof),
        fn, ln);
}

@safe pure/* nothrow*/  // lazy parameter bug
private auto parseError(lazy string msg, string fn = __FILE__, size_t ln = __LINE__)
{
    return new ConvException(text("Can't parse string: ", msg), fn, ln);
}

private void parseCheck(alias source)(dchar c, string fn = __FILE__, size_t ln = __LINE__)
{
    if (source.empty)
        throw parseError(text("unexpected end of input when expecting", "\"", c, "\""));
    if (source.front != c)
        throw parseError(text("\"", c, "\" is missing"), fn, ln);
    source.popFront();
}

private
{
    T toStr(T, S)(S src)
        if (isSomeString!T)
    {
        // workaround for Bugzilla 14198
//        static if (is(S == bool) && is(typeof({ T s = "string"; })))
//        {
//            return src ? "true" : "false";
//        }
//        else
        {
            import std.format;// : FormatSpec, formatValue;
//            import std.array : appender;

            //auto w = appender!T();
            FormatSpec!(ElementEncodingType!T) f;
            //formatValue(w, src, f);
            enforceValidFormatSpec!(S, char)(f);
            return "";//w.data;
        }
    }

    template isExactSomeString(T)
    {
        enum isExactSomeString = isSomeString!T && !is(T == enum);
    }

    template isEnumStrToStr(S, T)
    {
        enum isEnumStrToStr = isImplicitlyConvertible!(S, T) &&
                              is(S == enum) && isExactSomeString!T;
    }
    template isNullToStr(S, T)
    {
        enum isNullToStr = isImplicitlyConvertible!(S, T) &&
                           (is(Unqual!S == typeof(null))) && isExactSomeString!T;
    }

    template isRawStaticArray(T, A...)
    {
        enum isRawStaticArray =
            A.length == 0 &&
            isStaticArray!T &&
            !is(T == class) &&
            !is(T == interface) &&
            !is(T == struct) &&
            !is(T == union);
    }
}

/**
 * Thrown on conversion overflow errors.
 */
class ConvOverflowException : ConvException
{
    @safe pure nothrow
    this(string s, string fn = __FILE__, size_t ln = __LINE__)
    {
        super(s, fn, ln);
    }
}

template to(T)
{
    T to(A...)(A args)
        if (!isRawStaticArray!A)
    {
        return toImpl!T(args);
    }

    // Fix issue 6175
    T to(S)(ref S arg)
        if (isRawStaticArray!S)
    {
        return toImpl!T(arg);
    }
}

T toImpl(T, S)(S value)
    if (isImplicitlyConvertible!(S, T) &&
        !isEnumStrToStr!(S, T) && !isNullToStr!(S, T))
{

    return value;
}

T toImpl(T, S)(S value)
    if (!isImplicitlyConvertible!(S, T)
        &&
        isExactSomeString!T
       )
{
pragma(msg, "L", __LINE__);
        // other non-string values runs formatting
        //return toStr!T(value);

            import std.format;// : FormatSpec, formatValue;
//            import std.array : appender;

            //auto w = appender!T();
            FormatSpec!(char) f;
            //formatValue(w, src, f);
            enforceValidFormatSpec!(S, char)(f);
            return "";//w.data;
}

T toImpl(T, S)(S value)
    if (!isImplicitlyConvertible!(S, T) &&
        (isNumeric!T || isSomeChar!T || isBoolean!T) && !is(T == enum)
       )
{
    return T.init;
}

/***************************************************************
 * The $(D_PARAM parse) family of functions works quite like the
 * $(D_PARAM to) family, except that (1) it only works with character ranges
 * as input, (2) takes the input by reference and advances it to
 * the position following the conversion, and (3) does not throw if it
 * could not convert the entire input. It still throws if an overflow
 * occurred during conversion or if no character of the input
 * was meaningfully converted.
 */
Target parse(Target, Source)(ref Source s)
    if (isInputRange!Source &&
        isSomeChar!(ElementType!Source) &&
        is(Unqual!Target == bool))
{
    import std.ascii : toLower;
    if (!s.empty)
    {
        auto c1 = toLower(s.front);
        bool result = (c1 == 't');
        if (result || c1 == 'f')
        {
            s.popFront();
            foreach (c; result ? "rue" : "alse")
            {
                if (s.empty || toLower(s.front) != c)
                    goto Lerr;
                s.popFront();
            }
            return result;
        }
    }
Lerr:
    throw parseError("bool should be case-insensitive 'true' or 'false'");
}

///


Target parse(Target, Source)(ref Source s)
    if (isSomeChar!(ElementType!Source) &&
        isIntegral!Target && !is(Target == enum))
{
    assert(0);
}

Target parse(Target, Source)(ref Source s, uint radix)
    if (isSomeChar!(ElementType!Source) &&
        isIntegral!Target && !is(Target == enum))
{
    assert(0);
}

Target parse(Target, Source)(ref Source s)
    if (isExactSomeString!Source &&
        is(Target == enum))
{
    assert(0);
}

Target parse(Target, Source)(ref Source p)
    if (isInputRange!Source && isSomeChar!(ElementType!Source) && !is(Source == enum) &&
        isFloatingPoint!Target && !is(Target == enum))
{
    assert(0);
}

Target parse(Target, Source)(ref Source s)
    if (isExactSomeString!Source &&
        staticIndexOf!(Unqual!Target, dchar, Unqual!(ElementEncodingType!Source)) >= 0)
{
    assert(0);
}

Target parse(Target, Source)(ref Source s)
    if (!isSomeString!Source && isInputRange!Source && isSomeChar!(ElementType!Source) &&
        isSomeChar!Target && Target.sizeof >= ElementType!Source.sizeof && !is(Target == enum))
{
    assert(0);
}

Target parse(Target, Source)(ref Source s)
    if (isInputRange!Source &&
        isSomeChar!(ElementType!Source) &&
        is(Unqual!Target == typeof(null)))
{
    assert(0);
}


//Used internally by parse Array/AA, to remove ascii whites
package void skipWS(R)(ref R r)
{
}

/**
 * Parses an array from a string given the left bracket (default $(D
 * '[')), right bracket (default $(D ']')), and element separator (by
 * default $(D ',')).
 */
Target parse(Target, Source)(ref Source s, dchar lbracket = '[', dchar rbracket = ']', dchar comma = ',')
    if (isExactSomeString!Source &&
        isDynamicArray!Target && !is(Target == enum))
{
    assert(0);
}







/// ditto
Target parse(Target, Source)(ref Source s, dchar lbracket = '[', dchar rbracket = ']', dchar comma = ',')
    if (isExactSomeString!Source &&
        isStaticArray!Target && !is(Target == enum))
{
    assert(0);
}


/**
 * Parses an associative array from a string given the left bracket (default $(D
 * '[')), right bracket (default $(D ']')), key-value separator (default $(D
 * ':')), and element seprator (by default $(D ',')).
 */
Target parse(Target, Source)(ref Source s, dchar lbracket = '[', dchar rbracket = ']', dchar keyval = ':', dchar comma = ',')
    if (isExactSomeString!Source &&
        isAssociativeArray!Target && !is(Target == enum))
{
    assert(0);
}
/***************************************************************
 * Convenience functions for converting any number and types of
 * arguments into _text (the three character widths).
 */
string text(T...)(T args) { return textImpl!string(args); }
///ditto
wstring wtext(T...)(T args) { return textImpl!wstring(args); }
///ditto
dstring dtext(T...)(T args) { return textImpl!dstring(args); }

private S textImpl(S, U...)(U args)
{
    static if (U.length == 0)
    {
        return null;
    }
    else
    {
        auto result = to!S(args[0]);
        foreach (arg; args[1 .. $])
            result ~= to!S(arg);
        return result;
    }
}



/+
emplaceRef is a package function for phobos internal use. It works like
emplace, but takes its argument by ref (as opposed to "by pointer").

This makes it easier to use, easier to be safe, and faster in a non-inline
build.

Furthermore, emplaceRef optionally takes a type paremeter, which specifies
the type we want to build. This helps to build qualified objects on mutable
buffer, without breaking the type system with unsafe casts.
+/
package ref UT emplaceRef(UT, Args...)(ref UT chunk, auto ref Args args)
if (is(UT == Unqual!UT))
{
    return emplaceImpl!UT(chunk, args);
}
// ditto
package ref UT emplaceRef(T, UT, Args...)(ref UT chunk, auto ref Args args)
if (is(UT == Unqual!T) && !is(T == UT))
{
    return emplaceImpl!T(chunk, args);
}


private template emplaceImpl(T)
{
    alias UT = Unqual!T;

    ref UT emplaceImpl()(ref UT chunk)
    {
        static assert (is(typeof({static T i;})),
            convFormat("Cannot emplace a %1$s because %1$s.this() is annotated with @disable.", T.stringof));

        return emplaceInitializer(chunk);
    }

    static if (!is(T == struct))
    ref UT emplaceImpl(Arg)(ref UT chunk, auto ref Arg arg)
    {
        static assert(is(typeof({T t = arg;})),
            convFormat("%s cannot be emplaced from a %s.", T.stringof, Arg.stringof));

        static if (isStaticArray!T)
        {
            alias UArg = Unqual!Arg;
            alias E = ElementEncodingType!(typeof(T.init[]));
            alias UE = Unqual!E;
            enum n = T.length;

            static if (is(Arg : T))
            {
                //Matching static array
                static if (!hasElaborateAssign!UT && isAssignable!(UT, Arg))
                    chunk = arg;
                else static if (is(UArg == UT))
                {
                    import core.stdc.string : memcpy;
                    // This is known to be safe as the two values are the same
                    // type and the source (arg) should be initialized
                    () @trusted { memcpy(&chunk, &arg, T.sizeof); }();
                    static if (hasElaborateCopyConstructor!T)
                        _postblitRecurse(chunk);
                }
                else
                    .emplaceImpl!T(chunk, cast(T)arg);
            }
            else static if (is(Arg : E[]))
            {
                //Matching dynamic array
                static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg[])))
                    chunk[] = arg[];
                else static if (is(Unqual!(ElementEncodingType!Arg) == UE))
                {
                    import core.stdc.string : memcpy;
                    assert(n == chunk.length, "Array length missmatch in emplace");

                    // This is unsafe as long as the length match is a
                    // precondition and not an unconditional exception
                    memcpy(&chunk, arg.ptr, T.sizeof);

                    static if (hasElaborateCopyConstructor!T)
                        _postblitRecurse(chunk);
                }
                else
                    .emplaceImpl!T(chunk, cast(E[])arg);
            }
            else static if (is(Arg : E))
            {
                //Case matching single element to array.
                static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg)))
                    chunk[] = arg;
                else static if (is(UArg == Unqual!E))
                {
                    import core.stdc.string : memcpy;

                    foreach(i; 0 .. n)
                    {
                        // This is known to be safe as the two values are the same
                        // type and the source (arg) should be initialized
                        () @trusted { memcpy(&(chunk[i]), &arg, E.sizeof); }();
                    }

                    static if (hasElaborateCopyConstructor!T)
                        _postblitRecurse(chunk);
                }
                else
                    //Alias this. Coerce.
                    .emplaceImpl!T(chunk, cast(E)arg);
            }
            else static if (is(typeof(.emplaceImpl!E(chunk[0], arg))))
            {
                //Final case for everything else:
                //Types that don't match (int to uint[2])
                //Recursion for multidimensions
                static if (!hasElaborateAssign!UT && is(typeof(chunk[] = arg)))
                    chunk[] = arg;
                else
                    foreach(i; 0 .. n)
                        .emplaceImpl!E(chunk[i], arg);
            }
            else
                static assert(0, convFormat("Sorry, this implementation doesn't know how to emplace a %s with a %s", T.stringof, Arg.stringof));

            return chunk;
        }
        else
        {
            chunk = arg;
            return chunk;
        }
    }
    // ditto
    static if (is(T == struct))
    ref UT emplaceImpl(Args...)(ref UT chunk, auto ref Args args)
    {
        static if (Args.length == 1 && is(Args[0] : T) &&
            is (typeof({T t = args[0];})) //Check for legal postblit
            )
        {
            static if (is(Unqual!T == Unqual!(Args[0])))
            {
                //Types match exactly: we postblit
                static if (!hasElaborateAssign!UT && isAssignable!(UT, T))
                    chunk = args[0];
                else
                {
                    import core.stdc.string : memcpy;
                    // This is known to be safe as the two values are the same
                    // type and the source (args[0]) should be initialized
                    () @trusted { memcpy(&chunk, &args[0], T.sizeof); }();
                    static if (hasElaborateCopyConstructor!T)
                        _postblitRecurse(chunk);
                }
            }
            else
                //Alias this. Coerce to type T.
                .emplaceImpl!T(chunk, cast(T)args[0]);
        }
        else static if (is(typeof(chunk.__ctor(args))))
        {
            // T defines a genuine constructor accepting args
            // Go the classic route: write .init first, then call ctor
            emplaceInitializer(chunk);
            chunk.__ctor(args);
        }
        else static if (is(typeof(T.opCall(args))))
        {
            //Can be built calling opCall
            emplaceOpCaller(chunk, args); //emplaceOpCaller is deprecated
        }
        else static if (is(typeof(T(args))))
        {
            // Struct without constructor that has one matching field for
            // each argument. Individually emplace each field
            emplaceInitializer(chunk);
            foreach (i, ref field; chunk.tupleof[0 .. Args.length])
            {
                alias Field = typeof(field);
                alias UField = Unqual!Field;
                static if (is(Field == UField))
                    .emplaceImpl!Field(field, args[i]);
                else
                    .emplaceImpl!Field(*cast(Unqual!Field*)&field, args[i]);
            }
        }
        else
        {
            //We can't emplace. Try to diagnose a disabled postblit.
            static assert(!(Args.length == 1 && is(Args[0] : T)),
                convFormat("Cannot emplace a %1$s because %1$s.this(this) is annotated with @disable.", T.stringof));

            //We can't emplace.
            static assert(false,
                convFormat("%s cannot be emplaced from %s.", T.stringof, Args[].stringof));
        }

        return chunk;
    }
}
//emplace helper functions
private ref T emplaceInitializer(T)(ref T chunk) @trusted pure nothrow
{
    static if (!hasElaborateAssign!T && isAssignable!T)
        chunk = T.init;
    else
    {
        import core.stdc.string : memcpy;
        static immutable T init = T.init;
        memcpy(&chunk, &init, T.sizeof);
    }
    return chunk;
}
private deprecated("Using static opCall for emplace is deprecated. Plase use emplace(chunk, T(args)) instead.")
ref T emplaceOpCaller(T, Args...)(ref T chunk, auto ref Args args)
{
    static assert (is(typeof({T t = T.opCall(args);})),
        convFormat("%s.opCall does not return adequate data for construction.", T.stringof));
    return emplaceImpl!T(chunk, chunk.opCall(args));
}


// emplace
/**
Given a pointer $(D chunk) to uninitialized memory (but already typed
as $(D T)), constructs an object of non-$(D class) type $(D T) at that
address.

Returns: A pointer to the newly constructed object (which is the same
as $(D chunk)).
 */
T* emplace(T)(T* chunk) @safe pure nothrow
{
    emplaceImpl!T(*chunk);
    return chunk;
}

/**
Given a pointer $(D chunk) to uninitialized memory (but already typed
as a non-class type $(D T)), constructs an object of type $(D T) at
that address from arguments $(D args).

This function can be $(D @trusted) if the corresponding constructor of
$(D T) is $(D @safe).

Returns: A pointer to the newly constructed object (which is the same
as $(D chunk)).
 */
T* emplace(T, Args...)(T* chunk, auto ref Args args)
if (!is(T == struct) && Args.length == 1)
{
    emplaceImpl!T(*chunk, args);
    return chunk;
}
/// ditto
T* emplace(T, Args...)(T* chunk, auto ref Args args)
if (is(T == struct))
{
    emplaceImpl!T(*chunk, args);
    return chunk;
}









//Start testing emplace-args here




//Start testing emplace-struct here

// Test constructor branch



// Test matching fields branch



//opAssign

//postblit precedence

//nested structs and postblit

//disabled postblit

//Imutability


//Context pointer

//Alias this

//Nested classes

//safety & nothrow & CTFE



//disable opAssign

//opCall



//static arrays







// Test attribute propagation for UDTs

private void testEmplaceChunk(void[] chunk, size_t typeSize, size_t typeAlignment, string typeName) @nogc pure nothrow
{
    assert(chunk.length >= typeSize, "emplace: Chunk size too small.");
    assert((cast(size_t)chunk.ptr) % typeAlignment == 0, "emplace: Chunk is not aligned.");
}

/**
Given a raw memory area $(D chunk), constructs an object of $(D class)
type $(D T) at that address. The constructor is passed the arguments
$(D Args). The $(D chunk) must be as least as large as $(D T) needs
and should have an alignment multiple of $(D T)'s alignment. (The size
of a $(D class) instance is obtained by using $(D
__traits(classInstanceSize, T))).

This function can be $(D @trusted) if the corresponding constructor of
$(D T) is $(D @safe).

Returns: A pointer to the newly constructed object.
 */
T emplace(T, Args...)(void[] chunk, auto ref Args args)
    if (is(T == class))
{
    enum classSize = __traits(classInstanceSize, T);
    testEmplaceChunk(chunk, classSize, classInstanceAlignment!T, T.stringof);
    auto result = cast(T) chunk.ptr;

    // Initialize the object in its pre-ctor state
    chunk[0 .. classSize] = typeid(T).init[];

    // Call the ctor if any
    static if (is(typeof(result.__ctor(args))))
    {
        // T defines a genuine constructor accepting args
        // Go the classic route: write .init first, then call ctor
        result.__ctor(args);
    }
    else
    {
        static assert(args.length == 0 && !is(typeof(&T.__ctor)),
                "Don't know how to initialize an object of type "
                ~ T.stringof ~ " with arguments " ~ Args.stringof);
    }
    return result;
}

T* emplace(T, Args...)(void[] chunk, auto ref Args args)
    if (!is(T == class))
{
    testEmplaceChunk(chunk, T.sizeof, T.alignof, T.stringof);
    return emplace(cast(T*) chunk.ptr, args);
}
