module std.algorithm.fill;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;

version(unittest)
{
}

/**
 * Fills $(D range) with a $(D filler).
 */
void fill(Range, Value)(Range range, Value filler)
if (isInputRange!Range && is(typeof(range.front = filler)))
{
    alias E = ElementType!Range;

    static if (is(typeof(range[] = filler)))
    {
        range[] = filler;
    }
    else static if (is(typeof(range[] = E(filler))))
    {
        range[] = E(filler);
    }
    else
    {
        for ( ; !range.empty; range.popFront())
        {
            range.front = filler;
        }
    }
}
/**
 */
unittest
{
    int[] a = [ 1, 2, 3, 4 ];
    fill(a, 5);
    assert(a == [ 5, 5, 5, 5 ]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 3 ];
    fill(a, 6);
    assert(a == [ 6, 6, 6 ]);

    void fun0()
    {
        foreach (i; 0 .. 1000)
        {
            foreach (ref e; a) e = 6;
        }
    }
    void fun1() { foreach (i; 0 .. 1000) fill(a, 6); }
    //void fun2() { foreach (i; 0 .. 1000) fill2(a, 6); }
    //writeln(benchmark!(fun0, fun1, fun2)(10000));

    with (DummyRanges!())
    {
        // fill should accept InputRange
        alias InputRange = DummyRange!(ReturnBy.Ref, Length.No, RangeType.Input);
        enum filler = uint.max;
        InputRange range;
        fill(range, filler);
        foreach (value; range.arr)
            assert(value == filler);
    }
}
unittest
{
    //ER8638_1 IS_NOT self assignable
    static struct ER8638_1
    {
        void opAssign(int){}
    }

    //ER8638_1 IS self assignable
    static struct ER8638_2
    {
        void opAssign(ER8638_2){}
        void opAssign(int){}
    }

    auto er8638_1 = new ER8638_1[](10);
    auto er8638_2 = new ER8638_2[](10);
    er8638_1.fill(5); //generic case
    er8638_2.fill(5); //opSlice(T.init) case
}
unittest
{
    {
        int[] a = [1, 2, 3];
        immutable(int) b = 0;
        static assert(__traits(compiles, a.fill(b)));
    }
    {
        double[] a = [1, 2, 3];
        immutable(int) b = 0;
        static assert(__traits(compiles, a.fill(b)));
    }
}

/**
 * Fills $(D range) with a pattern copied from $(D filler). The length of
 * $(D range) does not have to be a multiple of the length of $(D
 * filler). If $(D filler) is empty, an exception is thrown.
 */
void fill(Range1, Range2)(Range1 range, Range2 filler)
if (isInputRange!Range1 &&
    (isForwardRange!Range2 || isInputRange!Range2 && isInfinite!Range2) &&
    is(typeof(Range1.init.front = Range2.init.front)))
{
    import std.exception : enforce;

    static if (isInfinite!Range2)
    {
        //Range2 is infinite, no need for bounds checking or saving
        static if (hasSlicing!Range2 && hasLength!Range1 &&
                   is(typeof(filler[0 .. range.length])))
        {
            copy(filler[0 .. range.length], range);
        }
        else
        {
            //manual feed
            for (; !range.empty; range.popFront(), filler.popFront())
            {
                range.front = filler.front;
            }
        }
    }
    else
    {
        enforce(!filler.empty, "Cannot fill range with an empty filler");

        static if (hasLength!Range1 && hasLength!Range2 &&
                   is(typeof(range.length > filler.length)))
        {
            //Case we have access to length
            auto len = filler.length;
            //Start by bulk copies
            while (range.length > len)
            {
                range = copy(filler.save, range);
            }

            //and finally fill the partial range. No need to save here.
            static if (hasSlicing!Range2 && is(typeof(filler[0 .. range.length])))
            {
                //use a quick copy
                auto len2 = range.length;
                range = copy(filler[0 .. len2], range);
            }
            else
            {
                //iterate. No need to check filler, it's length is longer than range's
                for (; !range.empty; range.popFront(), filler.popFront())
                {
                    range.front = filler.front;
                }
            }
        }
        else
        {
            //Most basic case.
            auto bck = filler.save;
            for (; !range.empty; range.popFront(), filler.popFront())
            {
                if (filler.empty)
                    filler = bck.save;
                range.front = filler.front;
            }
        }
    }
}
/**
 */
unittest
{
    int[] a = [ 1, 2, 3, 4, 5 ];
    int[] b = [ 8, 9 ];
    fill(a, b);
    assert(a == [ 8, 9, 8, 9, 8 ]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.exception : assertThrown;

    int[] a = [ 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2 ];
    fill(a, b);
    assert(a == [ 1, 2, 1, 2, 1 ]);

    // fill should accept InputRange
    with (DummyRanges!())
    {
        alias InputRange = DummyRange!(ReturnBy.Ref, Length.No, RangeType.Input);
        InputRange range;
        fill(range, [1, 2]);
        foreach (i, value; range.arr)
            assert(value == (i%2==0?1:2));
    }

    //test with a input being a "reference forward" range
    fill(a, new ReferenceForwardRange!int([8, 9]));
    assert(a == [8, 9, 8, 9, 8]);

    //test with a input being an "infinite input" range
    fill(a, new ReferenceInfiniteInputRange!int());
    assert(a == [0, 1, 2, 3, 4]);

    //empty filler test
    assertThrown(fill(a, a[$..$]));

}

/**
 * Fills a range with a value. Assumes that the range does not currently
 * contain meaningful content. This is of interest for structs that
 * define copy constructors (for all other types, fill and
 * uninitializedFill are equivalent).
 *
 * uninitializedFill will only operate on ranges that expose references to its
 * members and have assignable elements.
 *
 * Example:
 * ----
 * struct S { ... }
 * S[] s = (cast(S*) malloc(5 * S.sizeof))[0 .. 5];
 * uninitializedFill(s, 42);
 * assert(s == [ 42, 42, 42, 42, 42 ]);
 * ----
 */
void uninitializedFill(Range, Value)(Range range, Value filler)
if (isInputRange!Range &&
    hasLvalueElements!Range &&
    is(typeof(range.front = filler)))
{
    import std.conv : emplace;

    alias E = ElementType!Range;
    static if (hasElaborateAssign!E)
    {
        // Must construct stuff by the book
        for (; !range.empty; range.popFront())
            emplace(&range.front(), filler);
    }
    else
    {
        // Doesn't matter whether fill is initialized or not
        return fill(range, filler);
    }
}

deprecated("Cannot reliably call uninitializedFill on range that does not expose references. Use fill instead.")
void uninitializedFill(Range, Value)(Range range, Value filler)
if (isInputRange!Range &&
    !hasLvalueElements!Range &&
    is(typeof(range.front = filler)))
{
    alias E = ElementType!Range;
    static assert(hasElaborateAssign!E,
        "Cannot execute uninitializedFill a range that does not expose references, and whose objects have an elaborate assign.");
    return fill(range, filler);
}

/**
 * Initializes all elements of a range with their $(D .init)
 * value. Assumes that the range does not currently contain meaningful
 * content.
 *
 * initializeAll will operate on ranges that expose references to its
 * members and have assignable elements, as well as on (mutable) strings.
 *
 * Example:
 * ----
 * struct S { ... }
 * S[] s = (cast(S*) malloc(5 * S.sizeof))[0 .. 5];
 * initializeAll(s);
 * assert(s == [ 0, 0, 0, 0, 0 ]);
 * ----
 */
void initializeAll(Range)(Range range)
if (isInputRange!Range &&
    hasLvalueElements!Range &&
    hasAssignableElements!Range)
{
    import core.stdc.string : memcpy, memset;

    alias E = ElementType!Range;
    static if (hasElaborateAssign!E)
    {
        //Elaborate opAssign. Must go the memcpy road.
        //We avoid calling emplace here, because our goal is to initialize to
        //the static state of E.init,
        //So we want to avoid any un-necassarilly CC'ing of E.init
        auto p = typeid(E).init().ptr;
        if (p)
            for ( ; !range.empty ; range.popFront() )
                memcpy(&range.front(), p, E.sizeof);
        else
            static if (isDynamicArray!Range)
                memset(range.ptr, 0, range.length * E.sizeof);
            else
                for ( ; !range.empty ; range.popFront() )
                    memset(&range.front(), 0, E.sizeof);
    }
    else
        fill(range, E.init);
}

// ditto
void initializeAll(Range)(Range range)
if (is(Range == char[]) || is(Range == wchar[]))
{
    alias E = ElementEncodingType!Range;
    range[] = E.init;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    //Test strings:
    //Must work on narrow strings.
    //Must reject const
    char[3] a = void;
    a[].initializeAll();
    assert(a[] == [char.init, char.init, char.init]);
    string s;
    assert(!__traits(compiles, s.initializeAll()));

    //Note: Cannot call uninitializedFill on narrow strings

    enum e { e1, e2 }
    e[3] b1 = void;
    b1[].initializeAll();
    assert(b1[] == [e.e1, e.e1, e.e1]);
    e[3] b2 = void;
    b2[].uninitializedFill(e.e2);
    assert(b2[] == [e.e2, e.e2, e.e2]);

    static struct S1
    {
        int i;
    }
    static struct S2
    {
        int i = 1;
    }
    static struct S3
    {
        int i;
        this(this){};
    }
    static struct S4
    {
        int i = 1;
        this(this){};
    }
    static assert(!hasElaborateAssign!S1);
    static assert(!hasElaborateAssign!S2);
    static assert( hasElaborateAssign!S3);
    static assert( hasElaborateAssign!S4);
    assert(!typeid(S1).init().ptr);
    assert( typeid(S2).init().ptr);
    assert(!typeid(S3).init().ptr);
    assert( typeid(S4).init().ptr);

    foreach (S; TypeTuple!(S1, S2, S3, S4))
    {
        //initializeAll
        {
            //Array
            S[3] ss1 = void;
            ss1[].initializeAll();
            assert(ss1[] == [S.init, S.init, S.init]);

            //Not array
            S[3] ss2 = void;
            auto sf = ss2[].filter!"true"();

            sf.initializeAll();
            assert(ss2[] == [S.init, S.init, S.init]);
        }
        //uninitializedFill
        {
            //Array
            S[3] ss1 = void;
            ss1[].uninitializedFill(S(2));
            assert(ss1[] == [S(2), S(2), S(2)]);

            //Not array
            S[3] ss2 = void;
            auto sf = ss2[].filter!"true"();
            sf.uninitializedFill(S(2));
            assert(ss2[] == [S(2), S(2), S(2)]);
        }
    }
}
