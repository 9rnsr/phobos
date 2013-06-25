module std.algorithm.count;

import std.algorithm;
import std.range, std.functional, std.traits;
import std.typecons : Tuple;

version(unittest)
{
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
    import std.uni : toLower;

    // count elements in range
    int[] a = [ 1, 2, 4, 3, 2, 5, 3, 2, 4 ];
    assert(count(a, 2) == 3);
    assert(count!("a > b")(a, 2) == 5);
    // count range in range
    assert(count("abcadfabf", "ab") == 2);
    assert(count("ababab", "abab") == 1);
    assert(count("ababab", "abx") == 0);
    // fuzzy count range in range
    assert(count!((a, b) => std.uni.toLower(a) == std.uni.toLower(b))("AbcAdFaBf", "ab") == 2);
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
    import std.uni, std.ascii;

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
 * Checks whether $(D r) has "balanced parentheses", i.e. all instances
 * of $(D lPar) are closed by corresponding instances of $(D rPar). The
 * parameter $(D maxNestingLevel) controls the nesting level allowed. The
 * most common uses are the default or $(D 0). In the latter case, no
 * nesting is allowed.
*/

bool balancedParens(Range, E)
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
