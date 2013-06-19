module std.algorithm.compare;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
}

/**
 * Returns $(D true) if and only if the two ranges compare equal element
 * for element, according to binary predicate $(D pred). The ranges may
 * have different element types, as long as $(D pred(a, b)) evaluates to
 * $(D bool) for $(D a) in $(D r1) and $(D b) in $(D r2). Performs
 * $(BIGOH min(r1.length, r2.length)) evaluations of $(D pred). See also
 * $(WEB sgi.com/tech/stl/_equal.html, STL's _equal).
 */
bool equal(Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2 &&
    is(typeof(r1.front == r2.front)))
{
    static if (isArray!Range1 &&
               isArray!Range2 &&
               is(typeof(r1 == r2)))
    {
        //Ranges are comparable. Let the compiler do the comparison.
        return r1 == r2;
    }
    else
    {
        //Need to do an actual compare, delegate to predicate version
        return equal!"a==b"(r1, r2);
    }
}

/// Ditto
bool equal(alias pred, Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    //Try a fast implementation when the ranges have comparable lengths
    static if (hasLength!Range1 &&
               hasLength!Range2 &&
               is(typeof(r1.length == r2.length)))
    {
        auto len1 = r1.length;
        auto len2 = r2.length;
        if (len1 != len2)
            return false; //Short circuit return

        //Lengths are the same, so we need to do an actual comparison
        //Good news is we can sqeeze out a bit of performance by not checking if r2 is empty
        for (; !r1.empty; r1.popFront(), r2.popFront())
        {
            if (!binaryFun!pred(r1.front, r2.front))
                return false;
        }
        return true;
    }
    else
    {
        //Generic case, we have to walk both ranges making sure neither is empty
        for (; !r1.empty; r1.popFront(), r2.popFront())
        {
            if (r2.empty)
                return false;
            if (!binaryFun!pred(r1.front, r2.front))
                return false;
        }
        return r2.empty;
    }
}

unittest
{
    int[] a = [ 1, 2, 4, 3 ];
    assert(!equal(a, a[1 .. $]));
    assert( equal(a, a));

    // different types
    double[] b = [ 1.0, 2, 4, 3 ];
    assert(!equal(a, b[1 .. $]));
    assert( equal(a, b));

    // predicated: ensure that two vectors are approximately equal
    double[] c = [ 1.005, 2, 4, 3 ];
    assert( equal!approxEqual(b, c));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 4, 3];
    assert(!equal(a, a[1..$]));
    assert( equal(a, a));
    // test with different types
    double[] b = [ 1.0, 2, 4, 3];
    assert(!equal(a, b[1..$]));
    assert( equal(a, b));

    // predicated
    double[] c = [ 1.005, 2, 4, 3];
    assert( equal!approxEqual(b, c));

    // various strings
    assert( equal("æøå", "æøå"));       //UTF8 vs UTF8
    assert(!equal("???", "æøå"));       //UTF8 vs UTF8
    assert( equal("æøå"w, "æøå"d));     //UTF16 vs UTF32
    assert(!equal("???"w, "æøå"d));     //UTF16 vs UTF32
    assert( equal("æøå"d, "æøå"d));     //UTF32 vs UTF32
    assert(!equal("???"d, "æøå"d));     //UTF32 vs UTF32
    assert(!equal("hello", "world"));

    // same strings, but "explicit non default" comparison (to test the non optimized array comparison)
    assert( equal!"a==b"("æøå", "æøå"));    //UTF8 vs UTF8
    assert(!equal!"a==b"("???", "æøå"));    //UTF8 vs UTF8
    assert( equal!"a==b"("æøå"w, "æøå"d));  //UTF16 vs UTF32
    assert(!equal!"a==b"("???"w, "æøå"d));  //UTF16 vs UTF32
    assert( equal!"a==b"("æøå"d, "æøå"d));  //UTF32 vs UTF32
    assert(!equal!"a==b"("???"d, "æøå"d));  //UTF32 vs UTF32
    assert(!equal!"a==b"("hello", "world"));

    //Array of string
    assert( equal(["hello", "world"], ["hello", "world"]));
    assert(!equal(["hello", "world"], ["hello"]));
    assert(!equal(["hello", "world"], ["hello", "Bob!"]));

    //Should not compile, because "string == dstring" is illegal
    static assert(!is(typeof(equal(["hello", "world"], ["hello"d, "world"d]))));
    //However, arrays of non-matching string can be compared using equal!equal. Neat-o!
    equal!equal(["hello", "world"], ["hello"d, "world"d]);

    //Tests, with more fancy map ranges
    assert( equal([2, 4, 8, 6], map!"a*2"(a)));
    assert( equal!approxEqual(map!"a*2"(b), map!"a*2"(c)));
    assert(!equal([2, 4, 1, 3], map!"a*2"(a)));
    assert(!equal([2, 4, 1], map!"a*2"(a)));
    assert(!equal!approxEqual(map!"a*3"(b), map!"a*2"(c)));

    //Tests with some fancy reference ranges.
    ReferenceInputRange!int cir = new ReferenceInputRange!int([1, 2, 4, 3]);
    ReferenceForwardRange!int cfr = new ReferenceForwardRange!int([1, 2, 4, 3]);
    assert(equal(cir, a));
    cir = new ReferenceInputRange!int([1, 2, 4, 3]);
    assert(equal(cir, cfr.save));
    assert(equal(cfr.save, cfr.save));
    cir = new ReferenceInputRange!int([1, 2, 8, 1]);
    assert(!equal(cir, cfr));

    //Test with an infinte range
    ReferenceInfiniteForwardRange!int ifr = new ReferenceInfiniteForwardRange!int;
    assert(!equal(a, ifr));
}

/**********************************
 * Performs three-way lexicographical comparison on two input ranges
 * according to predicate $(D pred). Iterating $(D r1) and $(D r2) in
 * lockstep, $(D cmp) compares each element $(D e1) of $(D r1) with the
 * corresponding element $(D e2) in $(D r2). If $(D binaryFun!pred(e1,
 * e2)), $(D cmp) returns a negative value. If $(D binaryFun!pred(e2,
 * e1)), $(D cmp) returns a positive value. If one of the ranges has been
 * finished, $(D cmp) returns a negative value if $(D r1) has fewer
 * elements than $(D r2), a positive value if $(D r1) has more elements
 * than $(D r2), and $(D 0) if the ranges have the same number of
 * elements.
 *
 * If the ranges are strings, $(D cmp) performs UTF decoding
 * appropriately and compares the ranges one code point at a time.
 */
int cmp(alias pred = "a < b", R1, R2)(R1 r1, R2 r2)
if (isInputRange!R1 && !isSomeString!R1 &&
    isInputRange!R2 && !isSomeString!R2)
{
    for (; ; r1.popFront(), r2.popFront())
    {
        if (r1.empty)
            return -cast(int)!r2.empty;
        if (r2.empty)
            return !r1.empty;
        auto a = r1.front, b = r2.front;
        if (binaryFun!pred(a, b))
            return -1;
        if (binaryFun!pred(b, a))
            return 1;
    }
}

// Specialization for strings (for speed purposes)
int cmp(alias pred = "a < b", R1, R2)(R1 r1, R2 r2)
if (isSomeString!R1 && isSomeString!R2)
{
    static if (is(typeof(pred) : string))
        enum isLessThan = pred == "a < b";
    else
        enum isLessThan = false;

    // For speed only
    static int threeWay(size_t a, size_t b)
    {
        static if (size_t.sizeof == int.sizeof && isLessThan)
            return a - b;
        else
            return binaryFun!pred(b, a) ? 1 : binaryFun!pred(a, b) ? -1 : 0;
    }
    // For speed only
    // @@@BUG@@@ overloading should be allowed for nested functions
    static int threeWayInt(int a, int b)
    {
        static if (isLessThan)
            return a - b;
        else
            return binaryFun!pred(b, a) ? 1 : binaryFun!pred(a, b) ? -1 : 0;
    }

    static if (typeof(r1[0]).sizeof == typeof(r2[0]).sizeof && isLessThan)
    {
        static if (typeof(r1[0]).sizeof == 1)
        {
            immutable len = min(r1.length, r2.length);
            immutable result = std.c.string.memcmp(r1.ptr, r2.ptr, len);
            if (result)
                return result;
        }
        else
        {
            auto p1 = r1.ptr, p2 = r2.ptr;
            auto pEnd = p1 + min(r1.length, r2.length);
            for (; p1 != pEnd; ++p1, ++p2)
            {
                if (*p1 != *p2)
                    return threeWayInt(cast(int) *p1, cast(int) *p2);
            }
        }
        return threeWay(r1.length, r2.length);
    }
    else
    {
        for (size_t i1, i2; ; )
        {
            if (i1 == r1.length)
                return threeWay(i2, r2.length);
            if (i2 == r2.length)
                return threeWay(r1.length, i1);
            immutable c1 = std.utf.decode(r1, i1),
                c2 = std.utf.decode(r2, i2);
            if (c1 != c2)
                return threeWayInt(cast(int) c1, cast(int) c2);
        }
    }
}

unittest
{
    debug(string) printf("string.cmp.unittest\n");

    assert(cmp("abc", "abc") == 0);
  //assert(cmp(null, null) == 0);
    assert(cmp("", "") == 0);
    assert(cmp("abc", "abcd") < 0);
    assert(cmp("abcd", "abc") > 0);
    assert(cmp("abc"d, "abd") < 0);
    assert(cmp("bbc", "abc"w) > 0);
    assert(cmp("aaa", "aaaa"d) < 0);
    assert(cmp("aaaa", "aaa"d) > 0);
    assert(cmp("aaa", "aaa"d) == 0);
    assert(cmp((int[]).init, (int[]).init) == 0);
    assert(cmp([1, 2, 3], [1, 2, 3]) == 0);
    assert(cmp([1, 3, 2], [1, 2, 3]) > 0);
    assert(cmp([1, 2, 3], [1L, 2, 3, 4]) < 0);
    assert(cmp([1L, 2, 3], [1, 2]) > 0);
}

// MinType
template MinType(T...)
{
    static assert(T.length >= 2);

    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
        {
            alias MinType = CommonType!(T[0 .. 2]);
        }
        else
        {
            enum hasMostNegative = is(typeof(mostNegative!(T[0]))) &&
                                   is(typeof(mostNegative!(T[1])));
            static if (hasMostNegative && mostNegative!(T[1]) < mostNegative!(T[0]))
            {
                alias MinType = T[1];
            }
            else static if (hasMostNegative && mostNegative!(T[1]) > mostNegative!(T[0]))
            {
                alias MinType = T[0];
            }
            else static if (T[1].max < T[0].max)
            {
                alias MinType = T[1];
            }
            else
                alias MinType = T[0];
        }
    }
    else
    {
        alias MinType = MinType!(MinType!(T[0 .. 2]), T[2 .. $]);
    }
}

/**
 * Returns the minimum of the passed-in values. The type of the result is
 * computed by using $(XREF traits, CommonType).
 */
MinType!(T1, T2, T)
min(T1, T2, T...)(T1 a, T2 b, T xs)
if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 &&
                   isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
            {
                immutable chooseB = b < a && a > 0;
            }
            else
                immutable chooseB = b < a || b < 0;
        }
        else
            immutable chooseB = b < a;

        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return min(min(a, b), xs);
    }
}

///
unittest
{
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = min(a, b);
    static assert(is(typeof(d) == int));
    assert(d == 5);
    auto e = min(a, b, c);
    static assert(is(typeof(e) == double));
    assert(e == 2);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    // mixed signedness test
    int a = -10;
    uint f = 10;
    static assert(is(typeof(min(a, f)) == int));
    assert(min(a, f) == -10);

    //Test user-defined types
    import std.datetime;
    assert(min(Date(2012, 12, 21), Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(min(Date(1982, 1, 4), Date(2012, 12, 21)) == Date(1982, 1, 4));
    assert(min(Date(1982, 1, 4), Date.min) == Date.min);
    assert(min(Date.min, Date(1982, 1, 4)) == Date.min);
    assert(min(Date(1982, 1, 4), Date.max) == Date(1982, 1, 4));
    assert(min(Date.max, Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(min(Date.min, Date.max) == Date.min);
    assert(min(Date.max, Date.min) == Date.min);
}

// MaxType
template MaxType(T...)
{
    static assert(T.length >= 2);

    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
        {
            alias MaxType = CommonType!(T[0 .. 2]);
        }
        else static if (T[1].max > T[0].max)
        {
            alias MaxType = T[1];
        }
        else
            alias MaxType = T[0];
    }
    else
    {
        alias MaxType = MaxType!(MaxType!(T[0], T[1]), T[2 .. $]);
    }
}

/**
 * Returns the maximum of the passed-in values. The type of the result is
 * computed by using $(XREF traits, CommonType).
 */
MaxType!(T1, T2, T)
max(T1, T2, T...)(T1 a, T2 b, T xs)
if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 &&
                   isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
            {
                immutable chooseB = b > a || a < 0;
            }
            else
                immutable chooseB = b > a && b > 0;
        }
        else
            immutable chooseB = b > a;

        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return max(max(a, b), xs);
    }
}

///
unittest
{
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = max(a, b);
    static assert(is(typeof(d) == int));
    assert(d == 6);
    auto e = max(a, b, c);
    static assert(is(typeof(e) == double));
    assert(e == 6);
}
unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    // mixed sign
    int a = -5;
    uint f = 5;
    static assert(is(typeof(max(a, f)) == uint));
    assert(max(a, f) == 5);

    //Test user-defined types
    import std.datetime;
    assert(max(Date(2012, 12, 21), Date(1982, 1, 4)) == Date(2012, 12, 21));
    assert(max(Date(1982, 1, 4), Date(2012, 12, 21)) == Date(2012, 12, 21));
    assert(max(Date(1982, 1, 4), Date.min) == Date(1982, 1, 4));
    assert(max(Date.min, Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(max(Date(1982, 1, 4), Date.max) == Date.max);
    assert(max(Date.max, Date(1982, 1, 4)) == Date.max);
    assert(max(Date.min, Date.max) == Date.max);
    assert(max(Date.max, Date.min) == Date.max);
}

/**
 * Returns the minimum element of a range together with the number of
 * occurrences. The function can actually be used for counting the
 * maximum or any other ordering predicate (that's why $(D maxCount) is
 * not provided).
 */
Tuple!(ElementType!Range, size_t)
minCount(alias pred = "a < b", Range)(Range range)
if (isInputRange!Range && !isInfinite!Range &&
    is(typeof(binaryFun!pred(range.front, range.front))))
{
    import std.exception : enforce;

    enforce(!range.empty, "Can't count elements from an empty range");
    size_t occurrences = 1;
    auto v = range.front;
    for (range.popFront(); !range.empty; range.popFront())
    {
        auto v2 = range.front;
        if (binaryFun!pred(v, v2))
            continue;
        if (binaryFun!pred(v2, v))
        {
            // change the min
            move(v2, v);
            occurrences = 1;
        }
        else
        {
            ++occurrences;
        }
    }
    return typeof(return)(v, occurrences);
}

///
unittest
{
    int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
    // Minimum is 1 and occurs 3 times
    assert(minCount(a) == tuple(1, 3));
    // Maximum is 4 and occurs 2 times
    assert(minCount!("a > b")(a) == tuple(4, 2));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.exception : assertThrown;

    int[][] b = [ [4], [2, 4], [4], [4] ];
    auto c = minCount!("a[0] < b[0]")(b);
    assert(c == tuple([2, 4], 1));

    //Test empty range
    int[] a = [ 2 ];
    assertThrown(minCount(a[$..$]));

    //test with reference ranges. Test both input and forward.
    assert(minCount(new ReferenceInputRange!int([1, 2, 1, 0, 2, 0])) == tuple(0, 2));
    assert(minCount(new ReferenceForwardRange!int([1, 2, 1, 0, 2, 0])) == tuple(0, 2));

}

/**
 * Returns the position of the minimum element of forward range $(D
 * range), i.e. a subrange of $(D range) starting at the position of its
 * smallest element and with the same ending as $(D range). The function
 * can actually be used for counting the maximum or any other ordering
 * predicate (that's why $(D maxPos) is not provided).
 */
Range minPos(alias pred = "a < b", Range)(Range range)
if (isForwardRange!Range && !isInfinite!Range &&
    is(typeof(binaryFun!pred(range.front, range.front))))
{
    if (range.empty)
        return range;
    auto result = range.save;

    for (range.popFront(); !range.empty; range.popFront())
    {
        //Note: Unlike minCount, we do not care to find equivalence, so a single pred call is enough
        if (binaryFun!pred(range.front, result.front))
        {
            // change the min
            result = range.save;
        }
    }
    return result;
}

///
unittest
{
    int[] a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
    // Minimum is 1 and first occurs in position 3
    assert(minPos(a) == [ 1, 2, 4, 1, 1, 2 ]);
    // Maximum is 4 and first occurs in position 5
    assert(minPos!("a > b")(a) == [ 4, 1, 2, 4, 1, 1, 2 ]);
}
unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    //Test that an empty range works
    int[] a = [ 2 ];
    int[] b = a[$ .. $];
    assert(equal(minPos(b), b));

    //test with reference range.
    assert(equal(minPos(new ReferenceForwardRange!int([1, 2, 1, 0, 2, 0])), [0, 2, 0]));
}
unittest
{
    //Rvalue range
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.container : Array;

    assert(Array!int(2, 3, 4, 1, 2, 4, 1, 1, 2)
               []
               .minPos()
               .equal([ 1, 2, 4, 1, 1, 2 ]));
}
unittest
{
    //BUG 9299
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    immutable a = [ 2, 3, 4, 1, 2, 4, 1, 1, 2 ];
    // Minimum is 1 and first occurs in position 3
    assert(minPos(a) == [ 1, 2, 4, 1, 1, 2 ]);
    // Maximum is 4 and first occurs in position 5
    assert(minPos!("a > b")(a) == [ 4, 1, 2, 4, 1, 1, 2 ]);

    immutable(int[])[] b = [ [4], [2, 4], [4], [4] ];
    //assert(minPos!("a[0] < b[0]")(b) == [ [2, 4], [4], [4] ]);    // @@@BUG@@@ why doesn't work?
}

/**
 * Sequentially compares elements in $(D r1) and $(D r2) in lockstep, and
 * stops at the first mismatch (according to $(D pred), by default
 * equality). Returns a tuple with the reduced ranges that start with the
 * two mismatched values. Performs $(BIGOH min(r1.length, r2.length))
 * evaluations of $(D pred). See also $(WEB
 * sgi.com/tech/stl/_mismatch.html, STL's _mismatch).
 */
Tuple!(Range1, Range2)
mismatch(alias pred = "a == b", Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2)
{
    for (; !r1.empty && !r2.empty; r1.popFront(), r2.popFront())
    {
        if (!binaryFun!pred(r1.front, r2.front))
            break;
    }
    return tuple(r1, r2);
}

///
unittest
{
    int[]    x = [ 1,  5, 2, 7,   4, 3 ];
    double[] y = [ 1.0, 5, 2, 7.3, 4, 8 ];
    auto m = mismatch(x, y);
    assert(m[0] == x[3 .. $]);
    assert(m[1] == y[3 .. $]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // doc example
    int[]    x = [ 1,  5, 2, 7,   4, 3 ];
    double[] y = [ 1.0, 5, 2, 7.3, 4, 8 ];
    auto m = mismatch(x, y);
    assert(m[0] == [ 7, 4, 3 ]);
    assert(m[1] == [ 7.3, 4, 8 ]);

    int[] a = [ 1, 2, 3 ];
    int[] b = [ 1, 2, 4, 5 ];
    auto mm = mismatch(a, b);
    assert(mm[0] == [3]);
    assert(mm[1] == [4, 5]);
}
