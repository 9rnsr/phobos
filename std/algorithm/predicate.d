module std.algorithm.predicate;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
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

