module std.algorithm.find;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;

version(unittest)
{
}

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

