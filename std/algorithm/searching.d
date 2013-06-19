// Written in the D programming language.

module std.algorithm.searching;
//debug = std_algorithm;

import std.algorithm;
import std.range, std.traits;
import std.functional : unaryFun, binaryFun;
import std.typetuple : TypeTuple, allSatisfy;


/**
 * Finds an individual element in an input range. Elements of $(D
 * haystack) are compared with $(D needle) by using predicate $(D
 * pred). Performs $(BIGOH walkLength(haystack)) evaluations of $(D
 * pred). See also $(WEB sgi.com/tech/stl/_find.html, STL's _find).
 *
 * To _find the last occurence of $(D needle) in $(D haystack), call $(D
 * find(retro(haystack), needle)). See also $(XREF range, retro).
 *
 * Params:
 *
 * haystack = The range searched in.
 * needle = The element searched for.
 *
 * Constraints:
 *
 * $(D isInputRange!R && is(typeof(binaryFun!pred(haystack.front, needle)
 * : bool)))
 *
 * Returns:
 *
 * $(D haystack) advanced such that $(D binaryFun!pred(haystack.front,
 * needle)) is $(D true) (if no such position exists, returns $(D
 * haystack) after exhaustion).
 */
R find(alias pred = "a == b", R, E)(R haystack, E needle)
if (isInputRange!R &&
    is(typeof(binaryFun!pred(haystack.front, needle)) : bool))
{
    for (; !haystack.empty; haystack.popFront())
    {
        if (binaryFun!pred(haystack.front, needle))
            break;
    }
    return haystack;
}

///
unittest
{
    import std.container : SList;

    assert(find("hello, world", ',') == ", world");
    assert(find([1, 2, 3, 5], 4) == []);
    assert(equal(find(SList!int(1, 2, 3, 4, 5)[], 4), [4, 5]));
    assert(find!"a > b"([1, 2, 3, 5], 2) == [3, 5]);

    auto a = [ 1, 2, 3 ];
    assert( find(a, 5).empty);      // not found
    assert(!find(a, 2).empty);      // found

    // Case-insensitive find of a string
    string[] s = [ "Hello", "world", "!" ];
    assert(!find!("toLower(a) == b")(s, "hello").empty);
}

unittest
{
    import std.container : SList;

    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto lst = SList!int(1, 2, 5, 7, 3);
    assert(lst.front == 1);
    auto r = find(lst[], 5);
    assert(equal(r, SList!int(5, 7, 3)[]));
    assert(find([1, 2, 3, 5], 4).empty);
}


/**
 * Finds a forward range in another. Elements are compared for
 * equality. Performs $(BIGOH walkLength(haystack) * walkLength(needle))
 * comparisons in the worst case. Specializations taking advantage of
 * bidirectional or random access (where present) may accelerate search
 * depending on the statistics of the two ranges' content.
 *
 * Params:
 *
 * haystack = The range searched in.
 * needle = The range searched for.
 *
 * Constraints:
 *
 * $(D isForwardRange!R1 && isForwardRange!R2 &&
 * is(typeof(binaryFun!pred(haystack.front, needle.front) : bool)))
 *
 * Returns:
 *
 * $(D haystack) advanced such that $(D needle) is a prefix of it (if no
 * such position exists, returns $(D haystack) advanced to termination).
 */
R1 find(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && !isRandomAccessRange!R1 &&
    isForwardRange!R2 &&
    is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool))
{
    static if (is(typeof(pred == "a == b")) && pred == "a == b" &&
               isSomeString!R1 && isSomeString!R2 &&
               haystack[0].sizeof == needle[0].sizeof)
    {
        //return cast(R1) find(representation(haystack), representation(needle));
        // Specialization for simple string search
        alias Representation =
                Select!(haystack[0].sizeof == 1, ubyte[],
                Select!(haystack[0].sizeof == 2, ushort[],
                                                 uint[]));
        // Will use the array specialization
        return cast(R1) .find!(pred, Representation, Representation)
            (cast(Representation) haystack, cast(Representation) needle);
    }
    else
    {
        return simpleMindedFind!pred(haystack, needle);
    }
}

///
unittest
{
    import std.container : SList;

    assert(find("hello, world", "World").empty);
    assert(find("hello, world", "wo") == "world");
    assert(find([1, 2, 3, 4], SList!int(2, 3)[]) == [2, 3, 4]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.container : SList;

    auto lst = SList!int(1, 2, 5, 7, 3);
    static assert(isForwardRange!(typeof(lst[])));
    auto r = find(lst[], [2, 5]);
    assert(equal(r, SList!int(2, 5, 7, 3)[]));
}

// Specialization for searching a random-access range for a
// bidirectional range
R1 find(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isRandomAccessRange!R1 &&
    isBidirectionalRange!R2 &&
    is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool))
{
    if (needle.empty)
        return haystack;
    const needleLength = walkLength(needle.save);
    if (needleLength > haystack.length)
    {
        // @@@BUG@@@
        //return haystack[$ .. $];
        return haystack[haystack.length .. haystack.length];
    }
    // @@@BUG@@@
    // auto needleBack = moveBack(needle);
    // Stage 1: find the step
    size_t step = 1;
    auto needleBack = needle.back;
    needle.popBack();
    for (auto i = needle.save; !i.empty && !binaryFun!pred(i.back, needleBack);
         i.popBack(), ++step)
    {
    }
    // Stage 2: linear find
    size_t scout = needleLength - 1;
    for (;;)
    {
        if (scout >= haystack.length)
        {
            // @@@BUG@@@
            //return haystack[$ .. $];
            return haystack[haystack.length .. haystack.length];
        }
        if (!binaryFun!pred(haystack[scout], needleBack))
        {
            ++scout;
            continue;
        }
        // Found a match with the last element in the needle
        auto cand = haystack[scout + 1 - needleLength .. haystack.length];
        if (startsWith!pred(cand, needle))
        {
            // found
            return cand;
        }
        // Continue with the stride
        scout += step;
    }
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // @@@BUG@@@ removing static below makes unittest fail
    static struct BiRange
    {
        int[] payload;
        @property bool empty() { return payload.empty; }
        @property BiRange save() { return this; }
        @property ref int front() { return payload[0]; }
        @property ref int back() { return payload[$ - 1]; }
        void popFront() { return payload.popFront(); }
        void popBack() { return payload.popBack(); }
    }
    //static assert(isBidirectionalRange!BiRange);
    auto r = BiRange([1, 2, 3, 10, 11, 4]);
    //assert(equal(find(r, [3, 10]), BiRange([3, 10, 11, 4])));
    //assert(find("abc", "bc").length == 2);
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    //assert(find!"a == b"("abc", "bc").length == 2);
}

// Leftover specialization: searching a random-access range for a
// non-bidirectional forward range
R1 find(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isRandomAccessRange!R1 &&
    isForwardRange!R2 && !isBidirectionalRange!R2 &&
    is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool))
{
    static if (!is(ElementType!R1 == ElementType!R2))
    {
        return simpleMindedFind!pred(haystack, needle);
    }
    else
    {
        // Prepare the search with needle's first element
        if (needle.empty)
            return haystack;

        haystack = .find!pred(haystack, needle.front);

        static if (hasLength!R1 && hasLength!R2 && is(typeof(takeNone(haystack)) == R1))
        {
            if (needle.length > haystack.length)
                return takeNone(haystack);
        }
        else
        {
            if (haystack.empty)
                return haystack;
        }

        needle.popFront();
        size_t matchLen = 1;

        // Loop invariant: haystack[0 .. matchLen] matches everything in
        // the initial needle that was popped out of needle.
        for (;;)
        {
            // Extend matchLength as much as possible
            for (;;)
            {
                if (needle.empty || haystack.empty)
                    return haystack;

                static if (hasLength!R1 && is(typeof(takeNone(haystack)) == R1))
                {
                    if (matchLen == haystack.length)
                        return takeNone(haystack);
                }

                if (!binaryFun!pred(haystack[matchLen], needle.front))
                    break;

                ++matchLen;
                needle.popFront();
            }

            auto bestMatch = haystack[0 .. matchLen];
            haystack.popFront();
            haystack = .find!pred(haystack, bestMatch);
        }
    }
}

unittest
{
    import std.container : SList;

    assert(find([ 1, 2, 3 ], SList!int(2, 3)[]) == [ 2, 3 ]);
    assert(find([ 1, 2, 1, 2, 3, 3 ], SList!int(2, 3)[]) == [ 2, 3, 3 ]);
}

//Bug# 8334
unittest
{
    auto haystack = [1, 2, 3, 4, 1, 9, 12, 42];
    auto needle = [12, 42, 27];

    //different overload of find, but it's the base case.
    assert(find(haystack, needle).empty);

    assert(find(haystack, takeExactly(filter!"true"(needle), 3)).empty);
    assert(find(haystack, filter!"true"(needle)).empty);
}

// Internally used by some find() overloads above. Can't make it
// private due to bugs in the compiler.
/*private*/ R1 simpleMindedFind(alias pred, R1, R2)(R1 haystack, R2 needle)
{
    enum estimateNeedleLength = hasLength!R1 && !hasLength!R2;

    static if (hasLength!R1)
    {
        static if (hasLength!R2)
            size_t estimatedNeedleLength = 0;
        else
            immutable size_t estimatedNeedleLength = needle.length;
    }

    bool haystackTooShort()
    {
        static if (estimateNeedleLength)
        {
            return haystack.length < estimatedNeedleLength;
        }
        else
        {
            return haystack.empty;
        }
    }

  searching:
    for (;; haystack.popFront())
    {
        if (haystackTooShort())
        {
            // Failed search
            static if (hasLength!R1)
            {
                static if (is(typeof(haystack[haystack.length .. haystack.length]) : R1))
                    return haystack[haystack.length .. haystack.length];
                else
                    return R1.init;
            }
            else
            {
                assert(haystack.empty);
                return haystack;
            }
        }
        static if (estimateNeedleLength)
            size_t matchLength = 0;
        for (auto h = haystack.save, n = needle.save;
             !n.empty;
             h.popFront(), n.popFront())
        {
            if (h.empty || !binaryFun!pred(h.front, n.front))
            {
                // Failed searching n in h
                static if (estimateNeedleLength)
                {
                    if (estimatedNeedleLength < matchLength)
                        estimatedNeedleLength = matchLength;
                }
                continue searching;
            }
            static if (estimateNeedleLength)
                ++matchLength;
        }
        break;
    }
    return haystack;
}

unittest
{
    // Test simpleMindedFind for the case where both haystack and needle have
    // length.
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    struct CustomString
    {
        string _impl;

        // This is what triggers issue 7992.
        @property size_t length() const { return _impl.length; }
        @property void length(size_t len) { _impl.length = len; }

        // This is for conformance to the forward range API (we deliberately
        // make it non-random access so that we will end up in
        // simpleMindedFind).
        @property bool empty() const { return _impl.empty; }
        @property dchar front() const { return _impl.front; }
        void popFront() { _impl.popFront(); }
        @property CustomString save() { return this; }
    }

    // If issue 7992 occurs, this will throw an exception from calling
    // popFront() on an empty range.
    auto r = find(CustomString("a"), CustomString("b"));
}


/**
 * Finds two or more $(D needles) into a $(D haystack). The predicate $(D
 * pred) is used throughout to compare elements. By default, elements are
 * compared for equality.
 *
 * Params:
 *
 * haystack = The target of the search. Must be an $(GLOSSARY input
 * range). If any of $(D needles) is a range with elements comparable to
 * elements in $(D haystack), then $(D haystack) must be a $(GLOSSARY
 * forward range) such that the search can backtrack.
 *
 * needles = One or more items to search for. Each of $(D needles) must
 * be either comparable to one element in $(D haystack), or be itself a
 * $(GLOSSARY forward range) with elements comparable with elements in
 * $(D haystack).
 *
 * Returns:
 *
 * A tuple containing $(D haystack) positioned to match one of the
 * needles and also the 1-based index of the matching element in $(D
 * needles) (0 if none of $(D needles) matched, 1 if $(D needles[0])
 * matched, 2 if $(D needles[1]) matched...). The first needle to be found
 * will be the one that matches. If multiple needles are found at the
 * same spot in the range, then the shortest one is the one which matches
 * (if multiple needles of the same length are found at the same spot (e.g
 * $(D "a") and $(D 'a')), then the left-most of them in the argument list
 * matches).
 *
 * The relationship between $(D haystack) and $(D needles) simply means
 * that one can e.g. search for individual $(D int)s or arrays of $(D
 * int)s in an array of $(D int)s. In addition, if elements are
 * individually comparable, searches of heterogeneous types are allowed
 * as well: a $(D double[]) can be searched for an $(D int) or a $(D
 * short[]), and conversely a $(D long) can be searched for a $(D float)
 * or a $(D double[]). This makes for efficient searches without the need
 * to coerce one side of the comparison into the other's side type.
 */
unittest
{
    int[] a = [ 1, 4, 2, 3 ];
    assert(find(a, 4) == [ 4, 2, 3 ]);
    assert(find(a, [ 1, 4 ]) == [ 1, 4, 2, 3 ]);
    assert(find(a, [ 1, 3 ], 4) == tuple([ 4, 2, 3 ], 2));
    // Mixed types allowed if comparable
    assert(find(a, 5, [ 1.2, 3.5 ], 2.0, [ 6 ]) == tuple([ 2, 3 ], 3));
}
/**
 * The complexity of the search is $(BIGOH haystack.length *
 * max(needles.length)). (For needles that are individual items, length
 * is considered to be 1.) The strategy used in searching several
 * subranges at once maximizes cache usage by moving in $(D haystack) as
 * few times as possible.
 */
Tuple!(Range, size_t)
find(alias pred = "a == b", Range, Ranges...)(Range haystack, Ranges needles)
if (Ranges.length > 1 &&
    is(typeof(startsWith!pred(haystack, needles))))
{
    for (;; haystack.popFront())
    {
        size_t r = startsWith!pred(haystack, needles);
        if (r || haystack.empty)
        {
            return tuple(haystack, r);
        }
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto s1 = "Mary has a little lamb";
    //writeln(find(s1, "has a", "has an"));
    assert(find(s1, "has a", "has an") == tuple("has a little lamb", 1));
    assert(find(s1, 't', "has a", "has an") == tuple("has a little lamb", 2));
    assert(find(s1, 't', "has a", 'y', "has an") == tuple("y has a little lamb", 3));
    assert(find("abc", "bc").length == 2);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.typetuple;
    import std.string : toUpper;

    int[] a = [ 1, 2, 3 ];
    assert(find(a, 5).empty);
    assert(find(a, 2) == [2, 3]);

    foreach (T; TypeTuple!(int, double))
    {
        auto b = rndstuff!T();
        if (!b.length)
            continue;
        b[$ / 2] = 200;
        b[$ / 4] = 200;
        assert(find(b, 200).length == b.length - b.length / 4);
    }

    // Case-insensitive find of a string
    string[] s = [ "Hello", "world", "!" ];
    //writeln(find!("toUpper(a) == toUpper(b)")(s, "hello"));
    assert(find!("toUpper(a) == toUpper(b)")(s, "hello").length == 3);

    static bool f(string a, string b) { return toUpper(a) == toUpper(b); }
    assert(find!(f)(s, "hello").length == 3);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.typetuple;

    int[] a = [ 1, 2, 3, 2, 6 ];
    assert(find(std.range.retro(a), 5).empty);
    assert(equal(find(std.range.retro(a), 2), [ 2, 3, 2, 1 ]));

    foreach (T; TypeTuple!(int, double))
    {
        auto b = rndstuff!T();
        if (!b.length)
            continue;
        b[$ / 2] = 200;
        b[$ / 4] = 200;
        assert(find(std.range.retro(b), 200).length ==
                b.length - (b.length - 1) / 2);
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    assert(find(a, b) == [ 1, 2, 3, 4, 5 ]);
    assert(find(b, a).empty);

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        DummyType d;
        auto findRes = find(d, 5);
        assert(equal(findRes, [5,6,7,8,9,10]));
    }
}

/// Ditto
struct BoyerMooreFinder(alias pred, Range)
{
private:
    size_t[] skip;
    ptrdiff_t[ElementType!Range] occ;
    Range needle;

    ptrdiff_t occurrence(ElementType!Range c)
    {
        auto p = c in occ;
        return p ? *p : -1;
    }

    /*
     * This helper function checks whether the last "portion" bytes of
     * "needle" (which is "nlen" bytes long) exist within the "needle" at
     * offset "offset" (counted from the end of the string), and whether the
     * character preceding "offset" is not a match.  Notice that the range
     * being checked may reach beyond the beginning of the string. Such range
     * is ignored.
     */
    static bool needlematch(R)(R needle, size_t portion, size_t offset)
    {
        ptrdiff_t virtual_begin = needle.length - offset - portion;
        ptrdiff_t ignore = 0;
        if (virtual_begin < 0)
        {
            ignore = -virtual_begin;
            virtual_begin = 0;
        }
        if (virtual_begin > 0 &&
            needle[virtual_begin - 1] == needle[$ - portion - 1])
        {
            return 0;
        }

        immutable delta = portion - ignore;
        return equal(needle[needle.length - delta .. needle.length],
                     needle[virtual_begin .. virtual_begin + delta]);
    }

public:
    this(Range needle)
    {
        if (!needle.length)
            return;
        this.needle = needle;
        /* Populate table with the analysis of the needle */
        /* But ignoring the last letter */
        foreach (i, n ; needle[0 .. $ - 1])
        {
            this.occ[n] = i;
        }
        /* Preprocess #2: init skip[] */
        /* Note: This step could be made a lot faster.
         * A simple implementation is shown here. */
        this.skip = new size_t[needle.length];
        foreach (a; 0 .. needle.length)
        {
            size_t value = 0;
            while (value < needle.length &&
                   !needlematch(needle, a, value))
            {
                ++value;
            }
            this.skip[needle.length - a - 1] = value;
        }
    }

    Range beFound(Range haystack)
    {
        if (!needle.length)
            return haystack;
        if (needle.length > haystack.length)
            return haystack[$ .. $];
        /* Search: */
        auto limit = haystack.length - needle.length;
        for (size_t hpos = 0; hpos <= limit; )
        {
            size_t npos = needle.length - 1;
            while (pred(needle[npos], haystack[npos+hpos]))
            {
                if (npos == 0)
                    return haystack[hpos .. $];
                --npos;
            }
            hpos += max(skip[npos], cast(sizediff_t) npos - occurrence(haystack[npos+hpos]));
        }
        return haystack[$ .. $];
    }

    @property size_t length()
    {
        return needle.length;
    }

    alias opDollar = length;
}

/// Ditto
BoyerMooreFinder!(binaryFun!(pred), Range)
boyerMooreFinder(alias pred = "a == b", Range)(Range needle)
if (isRandomAccessRange!Range || isSomeString!Range)
{
    return typeof(return)(needle);
}

// Oddly this is not disabled by bug 4759
Range1 find(Range1, alias pred, Range2)
           (Range1 haystack, BoyerMooreFinder!(pred, Range2) needle)
{
    return needle.beFound(haystack);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    string h = "/homes/aalexand/d/dmd/bin/../lib/libphobos.a(dmain2.o)"
        "(.gnu.linkonce.tmain+0x74): In function `main' undefined reference"
        " to `_Dmain':";
    string[] ns = ["libphobos", "function", " undefined", "`", ":"];
    foreach (n ; ns)
    {
        auto p = find(h, boyerMooreFinder(n));
        assert(!p.empty);
    }

    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    //writeln(find(a, boyerMooreFinder(b)));
    assert(find(a, boyerMooreFinder(b)) == [ 1, 2, 3, 4, 5 ]);
    assert(find(b, boyerMooreFinder(a)).empty);
}

unittest
{
    auto bm = boyerMooreFinder("for");
    auto match = find("Moor", bm);
    assert(match.empty);
}


/**
 * Advances the input range $(D haystack) by calling $(D haystack.popFront)
 * until either $(D pred(haystack.front)), or $(D
 * haystack.empty). Performs $(BIGOH haystack.length) evaluations of $(D
 * pred). See also $(WEB sgi.com/tech/stl/find_if.html, STL's find_if).
 *
 * To find the last element of a bidirectional $(D haystack) satisfying
 * $(D pred), call $(D find!(pred)(retro(haystack))). See also $(XREF
 * range, retro).
*/
Range find(alias pred, Range)(Range haystack)
if (isInputRange!(Range))
{
    alias predFun = unaryFun!pred;
    for (; !haystack.empty && !predFun(haystack.front); haystack.popFront())
    {
    }
    return haystack;
}

unittest
{
    auto arr = [ 1, 2, 3, 4, 1 ];
    assert(find!("a > 2")(arr) == [ 3, 4, 1 ]);

    // with predicate alias
    bool pred(int x) { return x + 1 > 1.5; }
    assert(find!(pred)(arr) == arr);
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ 1, 2, 3 ];
    assert(find!("a > 2")(a) == [3]);
    bool pred(int x) { return x + 1 > 1.5; }
    assert(find!(pred)(a) == a);
}

/**
 * If $(D needle) occurs in $(D haystack), positions $(D haystack)
 * right after the first occurrence of $(D needle) and returns $(D
 * true). Otherwise, leaves $(D haystack) as is and returns $(D
 * false).
 */
bool findSkip(alias pred = "a == b", R1, R2)(ref R1 haystack, R2 needle)
if (isForwardRange!R1 && isForwardRange!R2
        && is(typeof(binaryFun!pred(haystack.front, needle.front))))
{
    auto parts = findSplit!pred(haystack, needle);
    if (parts[1].empty) return false;
    // found
    haystack = parts[2];
    return true;
}

///
unittest
{
    string s = "abcdef";
    assert(findSkip(s, "cd") && s == "ef");
    s = "abcdef";
    assert(!findSkip(s, "cxd") && s == "abcdef");
    s = "abcdef";
    assert( findSkip(s, "def") && s.empty);
}


/**
 * These functions find the first occurrence of $(D needle) in $(D
 * haystack) and then split $(D haystack) as follows.
 *
 * $(D findSplit) returns a tuple $(D result) containing $(I three)
 * ranges. $(D result[0]) is the portion of $(D haystack) before $(D
 * needle), $(D result[1]) is the portion of $(D haystack) that matches
 * $(D needle), and $(D result[2]) is the portion of $(D haystack) after
 * the match. If $(D needle) was not found, $(D result[0])
 * comprehends $(D haystack) entirely and $(D result[1]) and $(D result[2])
 * are empty.
 *
 * $(D findSplitBefore) returns a tuple $(D result) containing two
 * ranges. $(D result[0]) is the portion of $(D haystack) before $(D
 * needle), and $(D result[1]) is the balance of $(D haystack) starting
 * with the match. If $(D needle) was not found, $(D result[0])
 * comprehends $(D haystack) entirely and $(D result[1]) is empty.
 *
 * $(D findSplitAfter) returns a tuple $(D result) containing two ranges.
 * $(D result[0]) is the portion of $(D haystack) up to and including the
 * match, and $(D result[1]) is the balance of $(D haystack) starting
 * after the match. If $(D needle) was not found, $(D result[0]) is empty
 * and $(D result[1]) is $(D haystack).
 *
 * In all cases, the concatenation of the returned ranges spans the
 * entire $(D haystack).
 *
 * If $(D haystack) is a random-access range, all three components of the
 * tuple have the same type as $(D haystack). Otherwise, $(D haystack)
 * must be a forward range and the type of $(D result[0]) and $(D
 * result[1]) is the same as $(XREF range,takeExactly).
 */
auto findSplit(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && isForwardRange!R2)
{
    static if (isSomeString!R1 && isSomeString!R2 ||
               isRandomAccessRange!R1 && hasLength!R2)
    {
        auto balance = find!pred(haystack, needle);
        immutable pos1 = haystack.length - balance.length;
        immutable pos2 = balance.empty ? pos1 : pos1 + needle.length;
        return tuple(haystack[0 .. pos1],
                     haystack[pos1 .. pos2],
                     haystack[pos2 .. haystack.length]);
    }
    else
    {
        auto original = haystack.save;
        auto h = haystack.save;
        auto n = needle.save;
        size_t pos1, pos2;
        while (!n.empty && !h.empty)
        {
            if (binaryFun!pred(h.front, n.front))
            {
                h.popFront();
                n.popFront();
                ++pos2;
            }
            else
            {
                haystack.popFront();
                n = needle.save;
                h = haystack.save;
                pos2 = ++pos1;
            }
        }
        return tuple(takeExactly(original, pos1),
                     takeExactly(haystack, pos2 - pos1),
                     h);
    }
}

/// Ditto
auto findSplitBefore(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && isForwardRange!R2)
{
    static if (isSomeString!R1 && isSomeString!R2 ||
               isRandomAccessRange!R1 && hasLength!R2)
    {
        auto balance = find!pred(haystack, needle);
        immutable pos = haystack.length - balance.length;
        return tuple(haystack[0 .. pos], haystack[pos .. haystack.length]);
    }
    else
    {
        auto original = haystack.save;
        auto h = haystack.save;
        auto n = needle.save;
        size_t pos;
        while (!n.empty && !h.empty)
        {
            if (binaryFun!pred(h.front, n.front))
            {
                h.popFront();
                n.popFront();
            }
            else
            {
                haystack.popFront();
                n = needle.save;
                h = haystack.save;
                ++pos;
            }
        }
        return tuple(takeExactly(original, pos), haystack);
    }
}

/// Ditto
auto findSplitAfter(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && isForwardRange!R2)
{
    static if (isSomeString!R1 && isSomeString!R2 ||
               isRandomAccessRange!R1 && hasLength!R2)
    {
        auto balance = find!pred(haystack, needle);
        immutable pos = balance.empty ? 0 : haystack.length - balance.length + needle.length;
        return tuple(haystack[0 .. pos], haystack[pos .. haystack.length]);
    }
    else
    {
        auto original = haystack.save;
        auto h = haystack.save;
        auto n = needle.save;
        size_t pos1, pos2;
        while (!n.empty)
        {
            if (h.empty)
            {
                // Failed search
                return tuple(takeExactly(original, 0), original);
            }
            if (binaryFun!pred(h.front, n.front))
            {
                h.popFront();
                n.popFront();
                ++pos2;
            }
            else
            {
                haystack.popFront();
                n = needle.save;
                h = haystack.save;
                pos2 = ++pos1;
            }
        }
        return tuple(takeExactly(original, pos2), h);
    }
}

///
unittest
{
    auto a = "Carl Sagan Memorial Station";
    auto r = findSplit(a, "Velikovsky");
    assert(r[0] == a);
    assert(r[1].empty);
    assert(r[2].empty);
    r = findSplit(a, " ");
    assert(r[0] == "Carl");
    assert(r[1] == " ");
    assert(r[2] == "Sagan Memorial Station");
    auto r1 = findSplitBefore(a, "Sagan");
    assert(r1[0] == "Carl ", r1[0]);
    assert(r1[1] == "Sagan Memorial Station");
    auto r2 = findSplitAfter(a, "Sagan");
    assert(r2[0] == "Carl Sagan");
    assert(r2[1] == " Memorial Station");
}

unittest
{
    auto a = [ 1, 2, 3, 4, 5, 6, 7, 8 ];
    auto r = findSplit(a, [9, 1]);
    assert(r[0] == a);
    assert(r[1].empty);
    assert(r[2].empty);
    r = findSplit(a, [3]);
    assert(r[0] == a[0 .. 2]);
    assert(r[1] == a[2 .. 3]);
    assert(r[2] == a[3 .. $]);

    auto r1 = findSplitBefore(a, [9, 1]);
    assert(r1[0] == a);
    assert(r1[1].empty);
    r1 = findSplitBefore(a, [3, 4]);
    assert(r1[0] == a[0 .. 2]);
    assert(r1[1] == a[2 .. $]);

    r1 = findSplitAfter(a, [9, 1]);
    assert(r1[0].empty);
    assert(r1[1] == a);
    r1 = findSplitAfter(a, [3, 4]);
    assert(r1[0] == a[0 .. 4]);
    assert(r1[1] == a[4 .. $]);
}

unittest
{
    auto a = [ 1, 2, 3, 4, 5, 6, 7, 8 ];
    auto fwd = filter!"a > 0"(a);
    auto r = findSplit(fwd, [9, 1]);
    assert(equal(r[0], a));
    assert(r[1].empty);
    assert(r[2].empty);
    r = findSplit(fwd, [3]);
    assert(equal(r[0],  a[0 .. 2]));
    assert(equal(r[1], a[2 .. 3]));
    assert(equal(r[2], a[3 .. $]));

    auto r1 = findSplitBefore(fwd, [9, 1]);
    assert(equal(r1[0], a));
    assert(r1[1].empty);
    r1 = findSplitBefore(fwd, [3, 4]);
    assert(equal(r1[0], a[0 .. 2]));
    assert(equal(r1[1], a[2 .. $]));

    r1 = findSplitAfter(fwd, [9, 1]);
    assert(r1[0].empty);
    assert(equal(r1[1], a));
    r1 = findSplitAfter(fwd, [3, 4]);
    assert(equal(r1[0], a[0 .. 4]));
    assert(equal(r1[1], a[4 .. $]));
}


/**
 * Returns the number of elements which must be popped from the front of
 * $(D haystack) before reaching an element for which
 * $(D startsWith!pred(haystack, needles)) is $(D true). If
 * $(D startsWith!pred(haystack, needles)) is not $(D true) for any element in
 * $(D haystack), then $(D -1) is returned.
 *
 * $(D needles) may be either an element or a range.
 */
ptrdiff_t countUntil(alias pred = "a == b", R, Rs...)(R haystack, Rs needles)
if (isForwardRange!R &&
    Rs.length > 0 && isForwardRange!(Rs[0]) == isInputRange!(Rs[0]) &&
    is(typeof(startsWith!pred(haystack, needles[0]))) &&
    (Rs.length == 1 || is(typeof(countUntil!pred(haystack, needles[1 .. $])))))
{
    typeof(return) result;

    static if (needles.length == 1)
    {
        static if (hasLength!R) //Note: Narrow strings don't have length.
        {
            //We delegate to find because find is very efficient.
            //We store the length of the haystack so we don't have to save it.
            auto len = haystack.length;
            auto r2 = find!pred(haystack, needles[0]);
            if (!r2.empty)
                return cast(typeof(return)) (len - r2.length);
        }
        else
        {
            if (needles[0].empty)
                return 0;

            //Default case, slower route doing startsWith iteration
            for ( ; !haystack.empty ; ++result )
            {
                //We compare the first elements of the ranges here before
                //forwarding to startsWith. This avoids making useless saves to
                //haystack/needle if they aren't even going to be mutated anyways.
                //It also cuts down on the amount of pops on haystack.
                if (binaryFun!pred(haystack.front, needles[0].front))
                {
                    //Here, we need to save the needle before popping it.
                    //haystack we pop in all paths, so we do that, and then save.
                    haystack.popFront();
                    if (startsWith!pred(haystack.save, needles[0].save.dropOne()))
                        return result;
                }
                else
                    haystack.popFront();
            }
        }
    }
    else
    {
        foreach (i, Ri; Rs)
        {
            static if (isForwardRange!Ri)
            {
                if (needles[i].empty)
                    return 0;
            }
        }
        Tuple!Rs t;
        foreach (i, Ri; Rs)
        {
            static if (!isForwardRange!Ri)
            {
                t[i] = needles[i];
            }
        }
        for (; !haystack.empty ; ++result, haystack.popFront())
        {
            foreach (i, Ri; Rs)
            {
                static if (isForwardRange!Ri)
                {
                    t[i] = needles[i].save;
                }
            }
            if (startsWith!pred(haystack.save, t.expand))
            {
                return result;
            }
        }
    }

    //Because of @@@8804@@@: Avoids both "unreachable code" or "no return statement"
    static if (isInfinite!R)
        assert(0);
    else
        return -1;
}

/// ditto
ptrdiff_t countUntil(alias pred = "a == b", R, N)(R haystack, N needle)
if (isInputRange!R &&
    is(typeof(binaryFun!pred(haystack.front, needle)) : bool))
{
    bool pred2(ElementType!R a) { return binaryFun!pred(a, needle); }
    return countUntil!pred2(haystack);
}

///
unittest
{
    assert(countUntil("hello world", "world") == 6);
    assert(countUntil("hello world", 'r') == 8);
    assert(countUntil("hello world", "programming") == -1);
    assert(countUntil("日本語", "本語") == 1);
    assert(countUntil("日本語", '語')   == 2);
    assert(countUntil("日本語", "五") == -1);
    assert(countUntil("日本語", '五') == -1);
    assert(countUntil([0, 7, 12, 22, 9], [12, 22]) == 2);
    assert(countUntil([0, 7, 12, 22, 9], 9) == 4);
    assert(countUntil!"a > b"([0, 7, 12, 22, 9], 20) == 3);
}
unittest
{
    assert(countUntil("日本語", "") == 0);
    assert(countUntil("日本語"d, "") == 0);

    assert(countUntil("", "") == 0);
    assert(countUntil("".filter!"true"(), "") == 0);

    auto rf = [0, 20, 12, 22, 9].filter!"true"();
    assert(rf.countUntil!"a > b"((int[]).init) == 0);
    assert(rf.countUntil!"a > b"(20) == 3);
    assert(rf.countUntil!"a > b"([20, 8]) == 3);
    assert(rf.countUntil!"a > b"([20, 10]) == -1);
    assert(rf.countUntil!"a > b"([20, 8, 0]) == -1);

    auto r = new ReferenceForwardRange!int([0, 1, 2, 3, 4, 5, 6]);
    auto r2 = new ReferenceForwardRange!int([3, 4]);
    auto r3 = new ReferenceForwardRange!int([3, 5]);
    assert(r.save.countUntil(3)  == 3);
    assert(r.save.countUntil(r2) == 3);
    assert(r.save.countUntil(7)  == -1);
    assert(r.save.countUntil(r3) == -1);
}

unittest
{
    assert(countUntil("hello world", "world", "asd") == 6);
    assert(countUntil("hello world", "world", "ello") == 1);
    assert(countUntil("hello world", "world", "") == 0);
    assert(countUntil("hello world", "world", 'l') == 2);
}


/**
 * Returns the number of elements which must be popped from $(D haystack)
 * before $(D pred(haystack.front)) is $(D true).
 */
ptrdiff_t countUntil(alias pred, R)(R haystack)
if (isInputRange!R &&
    is(typeof(unaryFun!pred(haystack.front)) : bool))
{
    typeof(return) i;

    static if (isRandomAccessRange!R)
    {
        //Optimized RA implementation. Since we want to count *and* iterate at
        //the same time, it is more efficient this way.
        static if (hasLength!R)
        {
            immutable len = cast(typeof(return)) haystack.length;
            for (; i < len; ++i)
            {
                if (unaryFun!pred(haystack[i]))
                    return i;
            }
        }
        else //if (isInfinite!R)
        {
            for ( ;  ; ++i )
            {
                if (unaryFun!pred(haystack[i]))
                    return i;
            }
        }
    }
    else static if (hasLength!R)
    {
        //For those odd ranges that have a length, but aren't RA.
        //It is faster to quick find, and then compare the lengths
        auto r2 = find!pred(haystack.save);
        if (!r2.empty)
            return cast(typeof(return)) (haystack.length - r2.length);
    }
    else //Everything else
    {
        alias ElementType!R T; //For narrow strings forces dchar iteration
        foreach (T elem; haystack)
        {
            if (unaryFun!pred(elem))
                return i;
            ++i;
        }
    }

    //Because of @@@8804@@@: Avoids both "unreachable code" or "no return statement"
    static if (isInfinite!R)
        assert(0);
    else
        return -1;
}

///
unittest
{
    assert(countUntil!(std.uni.isWhite)("hello world") == 5);
    assert(countUntil!(std.ascii.isDigit)("hello world") == -1);
    assert(countUntil!"a > 20"([0, 7, 12, 22, 9]) == 3);
}

unittest
{
    // References
    {
        // input
        ReferenceInputRange!int r;
        r = new ReferenceInputRange!int([0, 1, 2, 3, 4, 5, 6]);
        assert(r.countUntil(3) == 3);
        r = new ReferenceInputRange!int([0, 1, 2, 3, 4, 5, 6]);
        assert(r.countUntil(7) == -1);
    }
    {
        // forward
        auto r = new ReferenceForwardRange!int([0, 1, 2, 3, 4, 5, 6]);
        assert(r.save.countUntil([3, 4]) == 3);
        assert(r.save.countUntil(3) == 3);
        assert(r.save.countUntil([3, 7]) == -1);
        assert(r.save.countUntil(7) == -1);
    }
    {
        // infinite forward
        auto r = new ReferenceInfiniteForwardRange!int(0);
        assert(r.save.countUntil([3, 4]) == 3);
        assert(r.save.countUntil(3) == 3);
    }
}

// Explicitly undocumented. It will be removed in November 2013.
deprecated("Please use std.algorithm.countUntil instead.")
ptrdiff_t indexOf(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (is(typeof(startsWith!pred(haystack, needle))))
{
    return countUntil!pred(haystack, needle);
}


/**
 * Interval option specifier for $(D until) (below) and others.
 */
enum OpenRight
{
    no, /// Interval is closed to the right (last element included)
    yes /// Interval is open to the right (last element is not included)
}

/**
 * Lazily iterates $(D range) until value $(D sentinel) is found, at
 * which point it stops.
 */
struct Until(alias pred, Range, Sentinel)
if (isInputRange!Range)
{
    private Range _input;
    static if (!is(Sentinel == void))
        private Sentinel _sentinel;
    // mixin(bitfields!(
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    //             uint, "", 6));
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    OpenRight _openRight;
    bool _done;

    static if (!is(Sentinel == void))
        this(Range input, Sentinel sentinel,
                OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _sentinel = sentinel;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }
    else
        this(Range input, OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }

    @property bool empty()
    {
        return _done;
    }

    @property ElementType!Range front()
    {
        assert(!empty);
        return _input.front;
    }

    private bool predSatisfied()
    {
        static if (is(Sentinel == void))
            return unaryFun!pred(_input.front);
        else
            return startsWith!pred(_input, _sentinel);
    }

    void popFront()
    {
        assert(!empty);
        if (!_openRight)
        {
            if (predSatisfied())
            {
                _done = true;
                return;
            }
            _input.popFront();
            _done = _input.empty;
        }
        else
        {
            _input.popFront();
            _done = _input.empty || predSatisfied();
        }
    }

    static if (isForwardRange!Range)
    {
        @property Until save()
        {
            Until result = this;
            result._input     = _input.save;
          static if (!is(Sentinel == void))
            result._sentinel  = _sentinel;
            result._openRight = _openRight;
            result._done      = _done;
            return result;
        }
    }
}

/// Ditto
Until!(pred, Range, Sentinel)
until(alias pred = "a == b", Range, Sentinel)
(Range range, Sentinel sentinel, OpenRight openRight = OpenRight.yes)
if (!is(Sentinel == OpenRight))
{
    return typeof(return)(range, sentinel, openRight);
}

/// Ditto
Until!(pred, Range, void)
until(alias pred, Range)
(Range range, OpenRight openRight = OpenRight.yes)
{
    return typeof(return)(range, openRight);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 7, 7, 2, 4, 7, 3, 5 ];
    assert(equal(a.until(7), [ 1, 2, 4 ]));
    assert(equal(a.until(7, OpenRight.no), [ 1, 2, 4, 7 ]));
    assert(equal(a.until([7, 2]), [ 1, 2, 4, 7 ]));
    assert(equal(until!"a == 2"(a, OpenRight.no), [ 1, 2 ]));
}


/**
 * If the range $(D doesThisStart) starts with $(I any) of the $(D
 * withOneOfThese) ranges or elements, returns 1 if it starts with $(D
 * withOneOfThese[0]), 2 if it starts with $(D withOneOfThese[1]), and so
 * on. If none match, returns 0. In the case where $(D doesThisStart) starts
 * with multiple of the ranges or elements in $(D withOneOfThese), then the
 * shortest one matches (if there are two which match which are of the same
 * length (e.g. $(D "a") and $(D 'a')), then the left-most of them in the argument
 * list matches).
 */
uint startsWith(alias pred = "a == b", Range, Needles...)(Range doesThisStart, Needles withOneOfThese)
if (isInputRange!Range && Needles.length > 1 &&
    is(typeof(.startsWith!pred(doesThisStart, withOneOfThese[0])) : bool ) &&
    is(typeof(.startsWith!pred(doesThisStart, withOneOfThese[1 .. $])) : uint))
{
    alias haystack = doesThisStart;
    alias needles = withOneOfThese;

    // Make one pass looking for empty ranges in needles
    foreach (i, Unused; Needles)
    {
        // Empty range matches everything
        static if (!is(typeof(binaryFun!pred(haystack.front, needles[i])) : bool))
        {
            if (needles[i].empty)
                return i + 1;
        }
    }

    for (; !haystack.empty; haystack.popFront())
    {
        foreach (i, Unused; Needles)
        {
            static if (is(typeof(binaryFun!pred(haystack.front, needles[i])) : bool))
            {
                // Single-element
                if (binaryFun!pred(haystack.front, needles[i]))
                {
                    // found, but instead of returning, we just stop searching.
                    // This is to account for one-element
                    // range matches (consider startsWith("ab", "a",
                    // 'a') should return 1, not 2).
                    break;
                }
            }
            else
            {
                if (binaryFun!pred(haystack.front, needles[i].front))
                {
                    continue;
                }
            }

            // This code executed on failure to match
            // Out with this guy, check for the others
            uint result = startsWith!pred(haystack, needles[0 .. i], needles[i + 1 .. $]);
            if (result > i)
                ++result;
            return result;
        }

        // If execution reaches this point, then the front matches for all
        // needle ranges, or a needle element has been matched.
        // What we need to do now is iterate, lopping off the front of
        // the range and checking if the result is empty, or finding an
        // element needle and returning.
        // If neither happens, we drop to the end and loop.
        foreach (i, Unused; Needles)
        {
            static if (is(typeof(binaryFun!pred(haystack.front, needles[i])) : bool))
            {
                // Test has passed in the previous loop
                return i + 1;
            }
            else
            {
                needles[i].popFront();
                if (needles[i].empty)
                    return i + 1;
            }
        }
    }
    return 0;
}

/// Ditto
bool startsWith(alias pred = "a == b", R1, R2)(R1 doesThisStart, R2 withThis)
if (isInputRange!R1 &&
    isInputRange!R2 &&
    is(typeof(binaryFun!pred(doesThisStart.front, withThis.front)) : bool))
{
    alias haystack = doesThisStart;
    alias needle = withThis;

    static if (is(typeof(pred) : string))
        enum isDefaultPred = pred == "a == b";
    else
        enum isDefaultPred = false;

    //Note: While narrow strings don't have a "true" length, for a narrow string to start with another
    //narrow string *of the same type*, it must have *at least* as many code units.
    static if ((hasLength!R1 && hasLength!R2) ||
        (isNarrowString!R1 && isNarrowString!R2 && ElementEncodingType!R1.sizeof == ElementEncodingType!R2.sizeof))
    {
        if (haystack.length < needle.length)
            return false;
    }

    static if (isDefaultPred && isArray!R1 && isArray!R2 &&
               is(Unqual!(ElementEncodingType!R1) == Unqual!(ElementEncodingType!R2)))
    {
        //Array slice comparison mode
        return haystack[0 .. needle.length] == needle;
    }
    else static if (isRandomAccessRange!R1 && isRandomAccessRange!R2 && hasLength!R2)
    {
        //RA dual indexing mode
        foreach (j; 0 .. needle.length)
        {
            if (!binaryFun!pred(needle[j], haystack[j]))
                return false;   // not found
        }
        return true;    // found!
    }
    else
    {
        //Standard input range mode
        if (needle.empty)
            return true;
        static if (hasLength!R1 && hasLength!R2)
        {
            //We have previously checked that haystack.length > needle.length,
            //So no need to check haystack.empty during iteration
            for ( ; ; haystack.popFront() )
            {
                if (!binaryFun!pred(haystack.front, needle.front))
                    break;
                needle.popFront();
                if (needle.empty)
                    return true;
            }
        }
        else
        {
            for (; !haystack.empty ; haystack.popFront())
            {
                if (!binaryFun!pred(haystack.front, needle.front))
                    break;
                needle.popFront();
                if (needle.empty)
                    return true;
            }
        }
        return false;
    }
}

/// Ditto
bool startsWith(alias pred = "a == b", R, E)(R doesThisStart, E withThis)
if (isInputRange!R &&
    is(typeof(binaryFun!pred(doesThisStart.front, withThis)) : bool))
{
    return doesThisStart.empty
        ? false
        : binaryFun!pred(doesThisStart.front, withThis);
}

///
unittest
{
    assert( startsWith("abc", ""));
    assert( startsWith("abc", "a"));
    assert(!startsWith("abc", "b"));
    assert( startsWith("abc", 'a', "b") == 1);
    assert( startsWith("abc", "b", "a") == 2);
    assert( startsWith("abc", "a", "a") == 1);
    assert( startsWith("abc", "ab", "a") == 2);
    assert( startsWith("abc", "x", "a", "b") == 2);
    assert( startsWith("abc", "x", "aa", "ab") == 3);
    assert( startsWith("abc", "x", "aaa", "sab") == 0);
    assert( startsWith("abc", "x", "aaa", "a", "sab") == 3);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.typetuple : TypeTuple;
    import std.conv : to;

    foreach (S; TypeTuple!(char[], wchar[], dchar[], string, wstring, dstring))
    {
        assert(!startsWith(to!S("abc"), 'c'));
        assert( startsWith(to!S("abc"), 'a', 'c') == 1);
        assert(!startsWith(to!S("abc"), 'x', 'n', 'b'));
        assert( startsWith(to!S("abc"), 'x', 'n', 'a') == 3);
        assert( startsWith(to!S("\uFF28abc"), 'a', '\uFF28', 'c') == 2);

        foreach (T; TypeTuple!(char[], wchar[], dchar[], string, wstring, dstring))
        {
            //Lots of strings
            assert( startsWith(to!S("abc"), to!T("")));
            assert( startsWith(to!S("ab"), to!T("a")));
            assert( startsWith(to!S("abc"), to!T("a")));
            assert(!startsWith(to!S("abc"), to!T("b")));
            assert(!startsWith(to!S("abc"), to!T("b"), "bc", "abcd", "xyz"));
            assert( startsWith(to!S("abc"), to!T("ab"), 'a') == 2);
            assert( startsWith(to!S("abc"), to!T("a"), "b") == 1);
            assert( startsWith(to!S("abc"), to!T("b"), "a") == 2);
            assert( startsWith(to!S("abc"), to!T("a"), 'a') == 1);
            assert( startsWith(to!S("abc"), 'a', to!T("a")) == 1);
            assert( startsWith(to!S("abc"), to!T("x"), "a", "b") == 2);
            assert( startsWith(to!S("abc"), to!T("x"), "aa", "ab") == 3);
            assert( startsWith(to!S("abc"), to!T("x"), "aaa", "sab") == 0);
            assert( startsWith(to!S("abc"), 'a'));
            assert(!startsWith(to!S("abc"), to!T("sab")));
            assert( startsWith(to!S("abc"), 'x', to!T("aaa"), 'a', "sab") == 3);

            //Unicode
            assert( startsWith(to!S("\uFF28el\uFF4co"), to!T("\uFF28el")));
            assert( startsWith(to!S("\uFF28el\uFF4co"), to!T("Hel"), to!T("\uFF28el")) == 2);
            assert( startsWith(to!S("日本語"), to!T("日本")));
            assert( startsWith(to!S("日本語"), to!T("日本語")));
            assert(!startsWith(to!S("日本"), to!T("日本語")));

            //Empty
            assert( startsWith(to!S(""),  T.init));
            assert(!startsWith(to!S(""), 'a'));
            assert( startsWith(to!S("a"), T.init));
            assert( startsWith(to!S("a"), T.init, "") == 1);
            assert( startsWith(to!S("a"), T.init, 'a') == 1);
            assert( startsWith(to!S("a"), 'a', T.init) == 2);
        }
    }

    //Length but no RA
    assert(!startsWith("abc".takeExactly(3), "abcd".takeExactly(4)));
    assert( startsWith("abc".takeExactly(3), "abcd".takeExactly(3)));
    assert( startsWith("abc".takeExactly(3), "abcd".takeExactly(1)));

    foreach (T; TypeTuple!(int, short))
    {
        immutable arr = cast(T[])[0, 1, 2, 3, 4, 5];

        //RA range
        assert(startsWith(arr, cast(int[])null));
        assert(!startsWith(arr, 5));
        assert(!startsWith(arr, 1));
        assert( startsWith(arr, 0));
        assert( startsWith(arr, 5, 0, 1) == 2);
        assert( startsWith(arr, [0]));
        assert( startsWith(arr, [0, 1]));
        assert( startsWith(arr, [0, 1], 7) == 1);
        assert(!startsWith(arr, [0, 1, 7]));
        assert( startsWith(arr, [0, 1, 7], [0, 1, 2]) == 2);

        //Normal input range
        assert(!startsWith(filter!"true"(arr), 1));
        assert( startsWith(filter!"true"(arr), 0));
        assert( startsWith(filter!"true"(arr), [0]));
        assert( startsWith(filter!"true"(arr), [0, 1]));
        assert( startsWith(filter!"true"(arr), [0, 1], 7) == 1);
        assert(!startsWith(filter!"true"(arr), [0, 1, 7]));
        assert( startsWith(filter!"true"(arr), [0, 1, 7], [0, 1, 2]) == 2);
        assert( startsWith(arr, filter!"true"([0, 1])));
        assert( startsWith(arr, filter!"true"([0, 1]), 7) == 1);
        assert(!startsWith(arr, filter!"true"([0, 1, 7])));
        assert( startsWith(arr, [0, 1, 7], filter!"true"([0, 1, 2])) == 2);

        //Non-default pred
        assert(startsWith!("a%10 == b%10")(arr, [10, 11]));
        assert(!startsWith!("a%10 == b%10")(arr, [10, 12]));
    }
}


/**
 * If $(D startsWith(r1, r2)), consume the corresponding elements off $(D
 * r1) and return $(D true). Otherwise, leave $(D r1) unchanged and
 * return $(D false).
 */
bool skipOver(alias pred = "a == b", R1, R2)(ref R1 r1, R2 r2)
if (is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    auto r = r1.save;
    while (!r2.empty && !r.empty && binaryFun!pred(r.front, r2.front))
    {
        r.popFront();
        r2.popFront();
    }
    return r2.empty ? (r1 = r, true) : false;
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto s1 = "Hello world";
    assert(!skipOver(s1, "Ha"));
    assert(s1 == "Hello world");
    assert(skipOver(s1, "Hell") && s1 == "o world");

    string[]  r1 = ["abc", "def", "hij"];
    dstring[] r2 = ["abc"d];
    assert(!skipOver!((a, b) => a.equal(b))(r1, ["def"d]));
    assert(r1 == ["abc", "def", "hij"]);
    assert(skipOver!((a, b) => a.equal(b))(r1, r2));
    assert(r1 == ["def", "hij"]);
}


/**
 * Checks whether a range starts with an element, and if so, consume that
 * element off $(D r) and return $(D true). Otherwise, leave $(D r)
 * unchanged and return $(D false).
 */
bool skipOver(alias pred = "a == b", R, E)(ref R r, E e)
if (is(typeof(binaryFun!pred(r.front, e))))
{
    return binaryFun!pred(r.front, e)
        ? (r.popFront(), true)
        : false;
}

unittest
{
    auto s1 = "Hello world";
    assert(!skipOver(s1, 'a'));
    assert(s1 == "Hello world");
    assert(skipOver(s1, 'H') && s1 == "ello world");

    string[] r = ["abc", "def", "hij"];
    dstring e = "abc"d;
    assert(!skipOver!((a, b) => a.equal(b))(r, "def"d));
    assert(r == ["abc", "def", "hij"]);
    assert(skipOver!((a, b) => a.equal(b))(r, e));
    assert(r == ["def", "hij"]);
}


/* (Not yet documented.)
 * Consume all elements from $(D r) that are equal to one of the elements
 * $(D es).
 */
void skipAll(alias pred = "a == b", R, Es...)(ref R r, Es es)
//if (is(typeof(binaryFun!pred(r1.front, es[0]))))
{
  loop:
    for (; !r.empty; r.popFront())
    {
        foreach (i, E; Es)
        {
            if (binaryFun!pred(r.front, es[i]))
            {
                continue loop;
            }
        }
        break;
    }
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    auto s1 = "Hello world";
    skipAll(s1, 'H', 'e');
    assert(s1 == "llo world");
}


/**
 * The reciprocal of $(D startsWith).
 */
uint endsWith(alias pred = "a == b", Range, Needles...)(Range doesThisEnd, Needles withOneOfThese)
if (isBidirectionalRange!Range && Needles.length > 1 &&
    is(typeof(.endsWith!pred(doesThisEnd, withOneOfThese[0])) : bool) &&
    is(typeof(.endsWith!pred(doesThisEnd, withOneOfThese[1 .. $])) : uint))
{
    alias haystack = doesThisEnd;
    alias needles = withOneOfThese;

    // Make one pass looking for empty ranges in needles
    foreach (i, Unused; Needles)
    {
        // Empty range matches everything
        static if (!is(typeof(binaryFun!pred(haystack.back, needles[i])) : bool))
        {
            if (needles[i].empty)
                return i + 1;
        }
    }

    for (; !haystack.empty; haystack.popBack())
    {
        foreach (i, Unused; Needles)
        {
            static if (is(typeof(binaryFun!pred(haystack.back, needles[i])) : bool))
            {
                // Single-element
                if (binaryFun!pred(haystack.back, needles[i]))
                {
                    // found, but continue to account for one-element
                    // range matches (consider endsWith("ab", "b",
                    // 'b') should return 1, not 2).
                    continue;
                }
            }
            else
            {
                if (binaryFun!pred(haystack.back, needles[i].back))
                    continue;
            }

            // This code executed on failure to match
            // Out with this guy, check for the others
            uint result = endsWith!pred(haystack, needles[0 .. i], needles[i + 1 .. $]);
            if (result > i)
                ++result;
            return result;
        }

        // If execution reaches this point, then the back matches for all
        // needles ranges. What we need to do now is to lop off the back of
        // all ranges involved and recurse.
        foreach (i, Unused; Needles)
        {
            static if (is(typeof(binaryFun!pred(haystack.back, needles[i])) : bool))
            {
                // Test has passed in the previous loop
                return i + 1;
            }
            else
            {
                needles[i].popBack();
                if (needles[i].empty)
                    return i + 1;
            }
        }
    }
    return 0;
}

/// Ditto
bool endsWith(alias pred = "a == b", R1, R2)(R1 doesThisEnd, R2 withThis)
if (isBidirectionalRange!R1 &&
    isBidirectionalRange!R2 &&
    is(typeof(binaryFun!pred(doesThisEnd.back, withThis.back)) : bool))
{
    alias haystack = doesThisEnd;
    alias needle = withThis;

    static if (is(typeof(pred) : string))
        enum isDefaultPred = pred == "a == b";
    else
        enum isDefaultPred = false;

    static if (isDefaultPred && isArray!R1 && isArray!R2 &&
               is(Unqual!(ElementEncodingType!R1) == Unqual!(ElementEncodingType!R2)))
    {
        if (haystack.length < needle.length)
            return false;
        return haystack[$ - needle.length .. $] == needle;
    }
    else
    {
        return startsWith!pred(retro(doesThisEnd), retro(withThis));
    }
}

/// Ditto
bool endsWith(alias pred = "a == b", R, E)(R doesThisEnd, E withThis)
if (isBidirectionalRange!R &&
    is(typeof(binaryFun!pred(doesThisEnd.back, withThis)) : bool))
{
    return doesThisEnd.empty
        ? false
        : binaryFun!pred(doesThisEnd.back, withThis);
}

///
unittest
{
    assert( endsWith("abc", ""));
    assert(!endsWith("abc", "b"));
    assert( endsWith("abc", "a", 'c') == 2);
    assert( endsWith("abc", "c", "a") == 1);
    assert( endsWith("abc", "c", "c") == 1);
    assert( endsWith("abc", "bc", "c") == 2);
    assert( endsWith("abc", "x", "c", "b") == 2);
    assert( endsWith("abc", "x", "aa", "bc") == 3);
    assert( endsWith("abc", "x", "aaa", "sab") == 0);
    assert( endsWith("abc", "x", "aaa", 'c', "sab") == 3);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.typetuple : TypeTuple;
    import std.conv : to;

    foreach (S; TypeTuple!(char[], wchar[], dchar[], string, wstring, dstring))
    {
        assert(!endsWith(to!S("abc"), 'a'));
        assert( endsWith(to!S("abc"), 'a', 'c') == 2);
        assert(!endsWith(to!S("abc"), 'x', 'n', 'b'));
        assert( endsWith(to!S("abc"), 'x', 'n', 'c') == 3);
        assert( endsWith(to!S("abc\uFF28"), 'a', '\uFF28', 'c') == 2);

        foreach (T; TypeTuple!(char[], wchar[], dchar[], string, wstring, dstring))
        {
            //Lots of strings
            assert( endsWith(to!S("abc"), to!T("")));
            assert(!endsWith(to!S("abc"), to!T("a")));
            assert(!endsWith(to!S("abc"), to!T("b")));
            assert( endsWith(to!S("abc"), to!T("bc"), 'c') == 2);
            assert( endsWith(to!S("abc"), to!T("a"), "c") == 2);
            assert( endsWith(to!S("abc"), to!T("c"), "a") == 1);
            assert( endsWith(to!S("abc"), to!T("c"), "c") == 1);
            assert( endsWith(to!S("abc"), to!T("x"), 'c', "b") == 2);
            assert( endsWith(to!S("abc"), 'x', to!T("aa"), "bc") == 3);
            assert( endsWith(to!S("abc"), to!T("x"), "aaa", "sab") == 0);
            assert( endsWith(to!S("abc"), to!T("x"), "aaa", "c", "sab") == 3);
            assert( endsWith(to!S("\uFF28el\uFF4co"), to!T("l\uFF4co")));
            assert( endsWith(to!S("\uFF28el\uFF4co"), to!T("lo"), to!T("l\uFF4co")) == 2);

            //Unicode
            assert( endsWith(to!S("\uFF28el\uFF4co"), to!T("l\uFF4co")));
            assert( endsWith(to!S("\uFF28el\uFF4co"), to!T("lo"), to!T("l\uFF4co")) == 2);
            assert( endsWith(to!S("日本語"), to!T("本語")));
            assert( endsWith(to!S("日本語"), to!T("日本語")));
            assert(!endsWith(to!S("本語"), to!T("日本語")));

            //Empty
            assert( endsWith(to!S(""),  T.init));
            assert(!endsWith(to!S(""), 'a'));
            assert( endsWith(to!S("a"), T.init));
            assert( endsWith(to!S("a"), T.init, "") == 1);
            assert( endsWith(to!S("a"), T.init, 'a') == 1);
            assert( endsWith(to!S("a"), 'a', T.init) == 2);
        }
    }

    foreach (T; TypeTuple!(int, short))
    {
        immutable arr = cast(T[])[0, 1, 2, 3, 4, 5];

        //RA range
        assert( endsWith(arr, cast(int[])null));
        assert(!endsWith(arr, 0));
        assert(!endsWith(arr, 4));
        assert( endsWith(arr, 5));
        assert( endsWith(arr, 0, 4, 5) == 3);
        assert( endsWith(arr, [5]));
        assert( endsWith(arr, [4, 5]));
        assert( endsWith(arr, [4, 5], 7) == 1);
        assert(!endsWith(arr, [2, 4, 5]));
        assert( endsWith(arr, [2, 4, 5], [3, 4, 5]) == 2);

        //Normal input range
        assert(!endsWith(filterBidirectional!"true"(arr), 4));
        assert( endsWith(filterBidirectional!"true"(arr), 5));
        assert( endsWith(filterBidirectional!"true"(arr), [5]));
        assert( endsWith(filterBidirectional!"true"(arr), [4, 5]));
        assert( endsWith(filterBidirectional!"true"(arr), [4, 5], 7) == 1);
        assert(!endsWith(filterBidirectional!"true"(arr), [2, 4, 5]));
        assert( endsWith(filterBidirectional!"true"(arr), [2, 4, 5], [3, 4, 5]) == 2);
        assert( endsWith(arr, filterBidirectional!"true"([4, 5])));
        assert( endsWith(arr, filterBidirectional!"true"([4, 5]), 7) == 1);
        assert(!endsWith(arr, filterBidirectional!"true"([2, 4, 5])));
        assert( endsWith(arr, [2, 4, 5], filterBidirectional!"true"([3, 4, 5])) == 2);

        //Non-default pred
        assert( endsWith!("a%10 == b%10")(arr, [14, 15]));
        assert(!endsWith!("a%10 == b%10")(arr, [15, 14]));
    }
}


/**
 * Returns the common prefix of two ranges.
 */
unittest
{
    assert(commonPrefix("hello, world", "hello, there") == "hello, ");
}
/**
 * If the first argument is a string, then the result is a slice of $(D r1) which
 * contains the characters that both ranges start with. For all other types, the
 * type of the result is the same as the result of $(D takeExactly(r1, n)), where
 * $(D n) is the number of elements that both ranges start with.
 *
 * See_Also:
 *     $(XREF range, takeExactly)
 */
auto commonPrefix(alias pred = "a == b", R1, R2)(R1 r1, R2 r2)
if (isForwardRange!R1 && !isNarrowString!R1 &&
    isInputRange!R2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    static if (isRandomAccessRange!R1 && hasLength!R1 && hasSlicing!R1 &&
               isRandomAccessRange!R2 && hasLength!R2)
    {
        immutable limit = min(r1.length, r2.length);
        foreach (i; 0 .. limit)
        {
            if (!binaryFun!pred(r1[i], r2[i]))
            {
                return r1[0 .. i];
            }
        }
        return r1[0 .. limit];
    }
    else
    {
        auto result = r1.save;
        size_t i = 0;
        for (;
             !r1.empty && !r2.empty && binaryFun!pred(r1.front, r2.front);
             ++i, r1.popFront(), r2.popFront())
        {}
        return takeExactly(result, i);
    }
}

auto commonPrefix(alias pred, R1, R2)(R1 r1, R2 r2)
if (isNarrowString!R1 &&
    isInputRange!R2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    import std.utf : decode;

    auto result = r1.save;
    immutable len = r1.length;
    size_t i = 0;

    for (size_t j = 0; i < len && !r2.empty; r2.popFront(), i = j)
    {
        immutable f = decode(r1, j);
        if (!binaryFun!pred(f, r2.front))
            break;
    }

    return result[0 .. i];
}

auto commonPrefix(R1, R2)(R1 r1, R2 r2)
if ( isNarrowString!R1 &&
    !isNarrowString!R2 && isInputRange!R2 &&
    is(typeof(r1.front == r2.front)))
{
    return commonPrefix!"a == b"(r1, r2);
}

auto commonPrefix(R1, R2)(R1 r1, R2 r2)
if (isNarrowString!R1 &&
    isNarrowString!R2)
{
    import std.utf : UTFException;

    static if (ElementEncodingType!R1.sizeof == ElementEncodingType!R2.sizeof)
    {
        immutable limit = min(r1.length, r2.length);
        for (size_t i = 0; i < limit;)
        {
            immutable codeLen = std.utf.stride(r1, i);
            size_t j = 0;

            for (; j < codeLen && i < limit; ++i, ++j)
            {
                if (r1[i] != r2[i])
                    return r1[0 .. i - j];
            }

            if (i == limit && j < codeLen)
                throw new UTFException("Invalid UTF-8 sequence", i);
        }
        return r1[0 .. limit];
    }
    else
        return commonPrefix!"a == b"(r1, r2);
}

unittest
{
    import std.typetuple : TypeTuple;
    import std.conv : to;
    import std.utf : UTFException;
    import std.exception : assertThrown;

    assert(commonPrefix([1, 2, 3], [1, 2, 3, 4, 5]) == [1, 2, 3]);
    assert(commonPrefix([1, 2, 3, 4, 5], [1, 2, 3]) == [1, 2, 3]);
    assert(commonPrefix([1, 2, 3, 4], [1, 2, 3, 4]) == [1, 2, 3, 4]);
    assert(commonPrefix([1, 2, 3], [7, 2, 3, 4, 5]).empty);
    assert(commonPrefix([7, 2, 3, 4, 5], [1, 2, 3]).empty);
    assert(commonPrefix([1, 2, 3], cast(int[])null).empty);
    assert(commonPrefix(cast(int[])null, [1, 2, 3]).empty);
    assert(commonPrefix(cast(int[])null, cast(int[])null).empty);

    foreach (S; TypeTuple!( char[], const( char)[],  string,
                           wchar[], const(wchar)[], wstring,
                           dchar[], const(dchar)[], dstring))
    {
        foreach (T; TypeTuple!(string, wstring, dstring))
        {
            assert(commonPrefix(to!S(""), to!T("")).empty);
            assert(commonPrefix(to!S(""), to!T("hello")).empty);
            assert(commonPrefix(to!S("hello"), to!T("")).empty);
            assert(commonPrefix(to!S("hello, world"), to!T("hello, there")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, there"), to!T("hello, world")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, "), to!T("hello, world")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, world"), to!T("hello, ")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, world"), to!T("hello, world")) == to!S("hello, world"));

            //Bug# 8890
            assert(commonPrefix(to!S("Пиво"), to!T("Пони"))== to!S("П"));
            assert(commonPrefix(to!S("Пони"), to!T("Пиво"))== to!S("П"));
            assert(commonPrefix(to!S("Пиво"), to!T("Пиво"))== to!S("Пиво"));
            assert(commonPrefix(to!S("\U0010FFFF\U0010FFFB\U0010FFFE"),
                                to!T("\U0010FFFF\U0010FFFB\U0010FFFC")) == to!S("\U0010FFFF\U0010FFFB"));
            assert(commonPrefix(to!S("\U0010FFFF\U0010FFFB\U0010FFFC"),
                                to!T("\U0010FFFF\U0010FFFB\U0010FFFE")) == to!S("\U0010FFFF\U0010FFFB"));
            assert(commonPrefix!"a != b"(to!S("Пиво"), to!T("онво")) == to!S("Пи"));
            assert(commonPrefix!"a != b"(to!S("онво"), to!T("Пиво")) == to!S("он"));
        }

        static assert(is(typeof(commonPrefix(to!S("Пиво"), filter!"true"("Пони"))) == S));
        assert(equal(commonPrefix(to!S("Пиво"), filter!"true"("Пони")), to!S("П")));

        static assert(is(typeof(commonPrefix(filter!"true"("Пиво"), to!S("Пони"))) ==
                      typeof(takeExactly(filter!"true"("П"), 1))));
        assert(equal(commonPrefix(filter!"true"("Пиво"), to!S("Пони")), takeExactly(filter!"true"("П"), 1)));
    }

    assertThrown!UTFException(commonPrefix("\U0010FFFF\U0010FFFB", "\U0010FFFF\U0010FFFB"[0 .. $ - 1]));

    assert(commonPrefix("12345"d, [49, 50, 51, 60, 60]) == "123"d);
    assert(commonPrefix([49, 50, 51, 60, 60], "12345" ) == [49, 50, 51]);
    assert(commonPrefix([49, 50, 51, 60, 60], "12345"d) == [49, 50, 51]);

    assert(commonPrefix!"a == ('0' + b)"("12345" , [1, 2, 3, 9, 9]) == "123");
    assert(commonPrefix!"a == ('0' + b)"("12345"d, [1, 2, 3, 9, 9]) == "123"d);
    assert(commonPrefix!"('0' + a) == b"([1, 2, 3, 9, 9], "12345" ) == [1, 2, 3]);
    assert(commonPrefix!"('0' + a) == b"([1, 2, 3, 9, 9], "12345"d) == [1, 2, 3]);
}


/**
 * Advances $(D r) until it finds the first two adjacent elements $(D a),
 * $(D b) that satisfy $(D pred(a, b)). Performs $(BIGOH r.length)
 * evaluations of $(D pred). See also $(WEB
 * sgi.com/tech/stl/adjacent_find.html, STL's adjacent_find).
 */
Range findAdjacent(alias pred = "a == b", Range)(Range r)
if (isForwardRange!Range)
{
    auto ahead = r.save;
    if (!ahead.empty)
    {
        for (ahead.popFront(); !ahead.empty; r.popFront(), ahead.popFront())
        {
            if (binaryFun!pred(r.front, ahead.front))
                return r;
        }
    }
    static if (!isInfinite!Range)
        return ahead;
}

///
unittest
{
    int[] a = [ 11, 10, 10, 9, 8, 8, 7, 8, 9 ];
    auto r = findAdjacent(a);
    assert(r == [ 10, 10, 9, 8, 8, 7, 8, 9 ]);
    auto p = findAdjacent!("a < b")(a);
    assert(p == [ 7, 8, 9 ]);
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    // empty
    int[] a = [];
    auto p = findAdjacent(a);
    assert(p.empty);
    // not found
    a = [ 1, 2, 3, 4, 5 ];
    p = findAdjacent(a);
    assert(p.empty);
    p = findAdjacent!"a > b"(a);
    assert(p.empty);
    ReferenceForwardRange!int rfr = new ReferenceForwardRange!int([1, 2, 3, 2, 2, 3]);
    assert(equal(findAdjacent(rfr), [2, 2, 3]));

    // Issue 9350
    assert(!repeat(1).findAdjacent().empty);
}


/**
 * Advances $(D seq) by calling $(D seq.popFront) until either $(D
 * find!pred(choices, seq.front)) is $(D true), or $(D seq) becomes
 * empty. Performs $(BIGOH seq.length * choices.length) evaluations of
 * $(D pred). See also $(WEB sgi.com/tech/stl/find_first_of.html, STL's
 * find_first_of).
 */
Range1 findAmong(alias pred = "a == b", Range1, Range2)(Range1 seq, Range2 choices)
if (isInputRange!Range1 && isForwardRange!Range2)
{
    for (; !seq.empty && find!pred(choices, seq.front).empty; seq.popFront())
    {
    }
    return seq;
}

///
unittest
{
    int[] a = [ -1, 0, 1, 2, 3, 4, 5 ];
    int[] b = [ 3, 1, 2 ];
    assert(findAmong(a, b) == [ 1, 2, 3, 4, 5 ]);
}

unittest
{
    //scope(success) writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    int[] a = [ -1, 0, 2, 1, 2, 3, 4, 5 ];
    int[] b = [ 1, 2, 3 ];
    assert(findAmong(b, [ 4, 6, 7 ]).empty);
    assert(findAmong!("a==b")(a, b).length == a.length - 2);
    assert(findAmong!("a==b")(b, [ 4, 6, 7 ]).empty);
}


/**
 * The first version counts the number of elements $(D x) in $(D r) for
 * which $(D pred(x, value)) is $(D true). $(D pred) defaults to
 * equality. Performs $(BIGOH r.length) evaluations of $(D pred).
 *
 * The second version returns the number of times $(D needle) occurs in
 * $(D haystack). Throws an exception if $(D needle.empty), as the _count
 * of the empty range in any range would be infinite. Overlapped counts
 * are not considered, for example $(D count("aaa", "aa")) is $(D 1), not
 * $(D 2).
 *
 * The third version counts the elements for which $(D pred(x)) is $(D
 * true). Performs $(BIGOH r.length) evaluations of $(D pred).
 *
 * Note: Regardless of the overload, $(D count) will not accept
 * infinite ranges for $(D haystack).
 */
size_t count(alias pred = "a == b", Range, E)(Range haystack, E needle)
if (isInputRange!Range && !isInfinite!Range &&
    is(typeof(binaryFun!pred(haystack.front, needle)) : bool))
{
    bool pred2(ElementType!Range a) { return binaryFun!pred(a, needle); }
    return count!pred2(haystack);
}

///
unittest
{
    // count elements in range
    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count(a, 2) == 3);
    assert(count!("a > b")(a, 2) == 5);
    // count range in range
    assert(count("abcadfabf", "ab") == 2);
    assert(count("ababab", "abab") == 1);
    assert(count("ababab", "abx") == 0);
    // fuzzy count range in range
    assert(count!"std.uni.toLower(a) == std.uni.toLower(b)"("AbcAdFaBf", "ab") == 2);
    // count predicate in range
    assert(count!("a > 1")(a) == 8);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count(a, 2) == 3);
    assert(count!("a > b")(a, 2) == 5);

    // check strings
    assert(count("日本語")  == 3);
    assert(count("日本語"w) == 3);
    assert(count("日本語"d) == 3);

    assert(count!("a == '日'")("日本語")  == 1);
    assert(count!("a == '本'")("日本語"w) == 1);
    assert(count!("a == '語'")("日本語"d) == 1);
}

unittest
{
    debug(std_algorithm) printf("algorithm.count.unittest\n");

    string s = "This is a fofofof list";
    string sub = "fof";
    assert(count(s, sub) == 2);
}

/// Ditto
size_t count(alias pred = "a == b", R1, R2)(R1 haystack, R2 needle)
if (isForwardRange!R1 && !isInfinite!R1 &&
    isForwardRange!R2 &&
    is(typeof(binaryFun!pred(haystack.front, needle.front)) : bool))
{
    import std.exception : enforce;

    enforce(!needle.empty, "Cannot count occurrences of an empty range");

    static if (isInfinite!R2)
    {
        //Note: This is the special case of looking for an infinite inside a finite...
        //"How many instances of the Fibonacci sequence can you count in [1, 2, 3]?" - "None."
        return 0;
    }
    else
    {
        size_t result;
        //Note: haystack is not saved, because findskip is designed to modify it
        for (; findSkip!pred(haystack, needle.save) ; ++result)
        {}
        return result;
    }
}

/// Ditto
size_t count(alias pred = "true", R)(R haystack)
if (isInputRange!R && !isInfinite!R &&
    is(typeof(unaryFun!pred(haystack.front)) : bool))
{
    size_t result;
    alias E = ElementType!R; //For narrow strings forces dchar iteration
    foreach (E elem; haystack)
    {
        if (unaryFun!pred(elem))
            ++result;
    }
    return result;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count!("a == 3")(a) == 2);
    assert(count("日本語") == 3);
}


/**
 * Checks whether $(D r) has "balanced parentheses", i.e. all instances
 * of $(D lPar) are closed by corresponding instances of $(D rPar). The
 * parameter $(D maxNestingLevel) controls the nesting level allowed. The
 * most common uses are the default or $(D 0). In the latter case, no
 * nesting is allowed.
 */
bool balancedParens
(Range, E)
(Range r, E lPar, E rPar, size_t maxNestingLevel = size_t.max)
if (isInputRange!(Range) &&
    is(typeof(r.front == lPar)))
{
    size_t count;
    for (; !r.empty; r.popFront())
    {
        if (r.front == lPar)
        {
            if (count > maxNestingLevel)
                return false;
            ++count;
        }
        else if (r.front == rPar)
        {
            if (!count)
                return false;
            --count;
        }
    }
    return count == 0;
}

///
unittest
{
    auto s = "1 + (2 * (3 + 1 / 2)";
    assert(!balancedParens(s, '(', ')'));
    s = "1 + (2 * (3 + 1) / 2)";
    assert(balancedParens(s, '(', ')'));
    s = "1 + (2 * (3 + 1) / 2)";
    assert(balancedParens(s, '(', ')', 1));
    s = "1 + (2 * 3 + 1) / (2 - 5)";
    assert(balancedParens(s, '(', ')', 1));
}

unittest
{
    auto s = "1 + (2 * (3 + 1 / 2)";
    assert(!balancedParens(s, '(', ')'));
    s = "1 + (2 * (3 + 1) / 2)";
    assert(balancedParens(s, '(', ')'));
    s = "1 + (2 * (3 + 1) / 2)";
    assert(!balancedParens(s, '(', ')', 0));
    s = "1 + (2 * 3 + 1) / (2 - 5)";
    assert(balancedParens(s, '(', ')', 0));
}


/**
 * Returns the minimum element of a range together with the number of
 * occurrences. The function can actually be used for counting the
 * maximum or any other ordering predicate (that's why $(D maxCount) is
 * not provided).
 */
Tuple!(ElementType!Range, size_t) minCount
(alias pred = "a < b", Range)(Range range)
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
 * Returns $(D true) if and only if $(D value) can be found in $(D
 * range). Performs $(BIGOH needle.length) evaluations of $(D pred).
 */
bool canFind(alias pred = "a == b", R, E)(R haystack, E needle)
if (is(typeof(find!pred(haystack, needle))))
{
    return !find!pred(haystack, needle).empty;
}

/**
 * Returns the 1-based index of the first needle found in $(D haystack). If no
 * needle is found, then $(D 0) is returned.
 *
 * So, if used directly in the condition of an if statement or loop, the result
 * will be $(D true) if one of the needles is found and $(D false) if none are
 * found, whereas if the result is used elsewhere, it can either be cast to
 * $(D bool) for the same effect or used to get which needle was found first
 * without having to deal with the tuple that $(D LREF find) returns for the
 * same operation.
 */
size_t canFind(alias pred = "a == b", Range, Ranges...)(Range haystack, Ranges needles)
if (Ranges.length > 1 &&
    allSatisfy!(isForwardRange, Ranges) &&
    is(typeof(find!pred(haystack, needles))))
{
    return find!pred(haystack, needles)[1];
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto a = rndstuff!int();
    if (a.length)
    {
        auto b = a[a.length / 2];
        assert(canFind(a, b));
    }

    assert( canFind([0, 1, 2, 3], 2) == true);
    assert( canFind([0, 1, 2, 3], [1, 2], [2, 3]));
    assert( canFind([0, 1, 2, 3], [1, 2], [2, 3]) == 1);
    assert( canFind([0, 1, 2, 3], [1, 7], [2, 3]));
    assert( canFind([0, 1, 2, 3], [1, 7], [2, 3]) == 2);

    assert( canFind([0, 1, 2, 3], 4) == false);
    assert(!canFind([0, 1, 2, 3], [1, 3], [2, 4]));
    assert( canFind([0, 1, 2, 3], [1, 3], [2, 4]) == 0);
}

//Explictly Undocumented. Do not use. It may be deprecated in the future.
//Use any instead.
bool canFind(alias pred, Range)(Range range)
{
    return any!pred(range);
}


/**
 * Returns $(D true) if and only if a value $(D v) satisfying the
 * predicate $(D pred) can be found in the forward range $(D
 * range). Performs $(BIGOH r.length) evaluations of $(D pred).
 */
bool any(alias pred, Range)(Range range)
if (is(typeof(find!pred(range))))
{
    return !find!pred(range).empty;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto a = [ 1, 2, 0, 4 ];
    assert(any!"a == 2"(a));
}


/**
 * Returns $(D true) if and only if all values in $(D range) satisfy the
 * predicate $(D pred).  Performs $(BIGOH r.length) evaluations of $(D pred).
 */
bool all(alias pred, R)(R range)
if (isInputRange!R && is(typeof(unaryFun!pred(range.front))))
{
    // dmd @@@BUG9578@@@ workaround
    // return find!(not!(unaryFun!pred))(range).empty;
    bool notPred(ElementType!R a) { return !unaryFun!pred(a); }
    return find!notPred(range).empty;
}

///
unittest
{
    assert( all!"a & 1"([1, 3, 5, 7, 9]));
    assert(!all!"a & 1"([1, 2, 3, 5, 7, 9]));
}

unittest
{
    int x = 1;
    assert( all!(a => a > x)([2, 3]));
}
