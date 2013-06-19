// Written in the D programming language.

/**
 * <script type="text/javascript">inhibitQuickIndex = 1</script>
 *
 * $(BOOKTABLE ,
 *   $(TR $(TH Category) $(TH Functions))
 *   $(TR $(TDNW Searching)
 *        $(TD $(MYREF all) $(MYREF any) $(MYREF balancedParens)
 *             $(MYREF boyerMooreFinder) $(MYREF canFind) $(MYREF count)
 *             $(MYREF countUntil) $(MYREF commonPrefix) $(MYREF endsWith)
 *             $(MYREF find) $(MYREF findAdjacent) $(MYREF findAmong)
 *             $(MYREF findSkip) $(MYREF findSplit) $(MYREF findSplitAfter)
 *             $(MYREF findSplitBefore) $(MYREF indexOf) $(MYREF minCount)
 *             $(MYREF minPos) $(MYREF mismatch) $(MYREF skipOver)
 *             $(MYREF startsWith) $(MYREF until) ))
 *   $(TR $(TDNW Comparison)
 *        $(TD $(MYREF cmp) $(MYREF equal) $(MYREF levenshteinDistance)
 *             $(MYREF levenshteinDistanceAndPath) $(MYREF max) $(MYREF min)
 *             $(MYREF mismatch) ))
 *   $(TR $(TDNW Iteration)
 *        $(TD $(MYREF filter) $(MYREF filterBidirectional) $(MYREF group)
 *             $(MYREF joiner) $(MYREF map) $(MYREF reduce) $(MYREF splitter)
 *             $(MYREF uniq) ))
 *   $(TR $(TDNW Sorting)
 *        $(TD $(MYREF completeSort) $(MYREF isPartitioned) $(MYREF isSorted)
 *             $(MYREF makeIndex) $(MYREF nextPermutation)
 *             $(MYREF nextEvenPermutation) $(MYREF partialSort)
 *             $(MYREF partition) $(MYREF partition3) $(MYREF schwartzSort)
 *             $(MYREF sort) $(MYREF topN) $(MYREF topNCopy) ))
 *   $(TR $(TDNW Set&nbsp;operations)
 *        $(TD $(MYREF cartesianProduct) $(MYREF largestPartialIntersection)
 *             $(MYREF largestPartialIntersectionWeighted) $(MYREF nWayUnion)
 *             $(MYREF setDifference) $(MYREF setIntersection)
 *             $(MYREF setSymmetricDifference) $(MYREF setUnion) ))
 *   $(TR $(TDNW Mutation)
 *        $(TD $(MYREF bringToFront) $(MYREF copy) $(MYREF fill)
 *             $(MYREF initializeAll) $(MYREF move) $(MYREF moveAll)
 *             $(MYREF moveSome) $(MYREF remove) $(MYREF reverse)
 *             $(MYREF swap) $(MYREF swapRanges) $(MYREF uninitializedFill) ))
 * )
 *
 * Implements algorithms oriented mainly towards processing of
 * sequences. Some functions are semantic equivalents or supersets of
 * those found in the $(D $(LESS)_algorithm$(GREATER)) header in $(WEB
 * sgi.com/tech/stl/, Alexander Stepanov's Standard Template Library) for
 * C++.
 *
 * Many functions in this module are parameterized with a function or a
 * $(GLOSSARY predicate). The predicate may be passed either as a
 * function name, a delegate name, a $(GLOSSARY functor) name, or a
 * compile-time string. The string may consist of $(B any) legal D
 * expression that uses the symbol $(D a) (for unary functions) or the
 * symbols $(D a) and $(D b) (for binary functions). These names will NOT
 * interfere with other homonym symbols in user code because they are
 * evaluated in a different context. The default for all binary
 * comparison predicates is $(D "a == b") for unordered operations and
 * $(D "a < b") for ordered operations.
 *
 * Examples:
 * ----
 * int[] a = ...;
 * static bool greater(int a, int b)
 * {
 *     return a > b;
 * }
 * sort!(greater)(a);  // predicate as alias
 * sort!("a > b")(a);  // predicate as string
 *                     // (no ambiguity with array name)
 * sort(a);            // no predicate, "a < b" is implicit
 * ----
 *
 * $(BOOKTABLE Cheat Sheet,
 *   $(TR $(TH Function Name) $(TH Description))
 *
 *   $(LEADINGROW Searching)
 *
 *   $(TR $(TDNW $(LREF all))
 *        $(TD $(D all!"a > 0"([1, 2, 3, 4])) returns $(D true) because all elements are positive))
 *   $(TR $(TDNW $(LREF any))
 *        $(TD $(D any!"a > 0"([1, 2, -3, -4])) returns $(D true) because at least one element is positive))
 *   $(TR $(TDNW $(LREF balancedParens))
 *        $(TD $(D balancedParens("((1 + 1) / 2)")) returns $(D true) because the string has balanced parentheses.))
 *   $(TR $(TDNW $(LREF boyerMooreFinder))
 *        $(TD $(D find("hello world", boyerMooreFinder("or"))) returns $(D "orld") using the $(LUCKY Boyer-Moore
 *             _algorithm).))
 *   $(TR $(TDNW $(LREF canFind))
 *        $(TD $(D canFind("hello world", "or")) returns $(D true).))
 *   $(TR $(TDNW $(LREF count))
 *        $(TD Counts elements that are equal to a specified value or satisfy a predicate. $(D count([1, 2, 1], 1))
 *             returns $(D 2) and $(D count!"a < 0"([1, -3, 0])) returns $(D 1).))
 *   $(TR $(TDNW $(LREF countUntil))
 *        $(TD $(D countUntil(a, b)) returns the number of steps taken in $(D a) to reach $(D b); for example,
 *             $(D countUntil("hello!", "o")) returns $(D 4).))
 *   $(TR $(TDNW $(LREF endsWith))
 *        $(TD $(D endsWith("rocks", "ks")) returns $(D true).))
 *   $(TR $(TDNW $(LREF find))
 *        $(TD $(D find("hello world", "or")) returns $(D "orld") using linear search. (For binary search refer to
 *             $(XREF range,sortedRange).)))
 *   $(TR $(TDNW $(LREF findAdjacent))
 *        $(TD $(D findAdjacent([1, 2, 3, 3, 4])) returns the subrange starting with two equal adjacent elements,
 *             i.e. $(D [3, 3, 4]).))
 *   $(TR $(TDNW $(LREF findAmong))
 *        $(TD $(D findAmong("abcd", "qcx")) returns $(D "cd") because $(D 'c') is among $(D "qcx").))
 *   $(TR $(TDNW $(LREF findSkip))
 *        $(TD If $(D a = "abcde"), then $(D findSkip(a, "x")) returns $(D false) and leaves $(D a) unchanged,
 *             whereas $(D findSkip(a, 'c')) advances $(D a) to $(D "cde") and returns $(D true).))
 *   $(TR $(TDNW $(LREF findSplit))
 *        $(TD $(D findSplit("abcdefg", "de")) returns the three ranges $(D "abc"), $(D "de"), and $(D "fg").))
 *   $(TR $(TDNW $(LREF findSplitAfter))
 *        $(TD $(D findSplitAfter("abcdefg", "de")) returns the two ranges $(D "abcde") and $(D "fg").))
 *   $(TR $(TDNW $(LREF findSplitBefore))
 *        $(TD $(D findSplitBefore("abcdefg", "de")) returns the two ranges $(D "abc") and $(D "defg").))
 *   $(TR $(TDNW $(LREF minCount))
 *        $(TD $(D minCount([2, 1, 1, 4, 1])) returns $(D tuple(1, 3)).))
 *   $(TR $(TDNW $(LREF minPos))
 *        $(TD $(D minPos([2, 3, 1, 3, 4, 1])) returns the subrange $(D [1, 3, 4, 1]), i.e., positions the range
 *             at the first occurrence of its minimal element.))
 *   $(TR $(TDNW $(LREF skipOver))
 *        $(TD Assume $(D a = "blah"). Then $(D skipOver(a, "bi")) leaves $(D a) unchanged and returns $(D false),
 *             whereas $(D skipOver(a, "bl")) advances $(D a) to refer to $(D "ah") and returns $(D true).))
 *   $(TR $(TDNW $(LREF startsWith))
 *        $(TD $(D startsWith("hello, world", "hello")) returns $(D true).))
 *   $(TR $(TDNW $(LREF until))
 *        $(TD Lazily iterates a range until a specific value is found.))
 *
 *   $(LEADINGROW Comparison)
 *
 *   $(TR $(TDNW $(LREF cmp))
 *        $(TD $(D cmp("abc", "abcd")) is $(D -1), $(D cmp("abc", "aba")) is
 *             $(D 1), and $(D cmp("abc", "abc")) is $(D 0).))
 *   $(TR $(TDNW $(LREF equal))
 *        $(TD Compares ranges for element-by-element equality, e.g.
 *             $(D equal([1, 2, 3], [1.0, 2.0, 3.0])) returns $(D true).))
 *   $(TR $(TDNW $(LREF levenshteinDistance))
 *        $(TD $(D levenshteinDistance("kitten", "sitting")) returns $(D 3) by using the
 *             $(LUCKY Levenshtein distance _algorithm).))
 *   $(TR $(TDNW $(LREF levenshteinDistanceAndPath))
 *        $(TD $(D levenshteinDistanceAndPath("kitten", "sitting")) returns $(D tuple(3, "snnnsni")) by using
 *             the $(LUCKY Levenshtein distance _algorithm).))
 *   $(TR $(TDNW $(LREF max))
 *        $(TD $(D max(3, 4, 2)) returns $(D 4).))
 *   $(TR $(TDNW $(LREF min))
 *        $(TD $(D min(3, 4, 2)) returns $(D 2).))
 *   $(TR $(TDNW $(LREF mismatch))
 *        $(TD $(D mismatch("oh hi", "ohayo")) returns $(D tuple(" hi", "ayo")).))
 *
 *   $(LEADINGROW Iteration)
 *
 *   $(TR $(TDNW $(LREF filter))
 *        $(TD $(D filter!"a > 0"([1, -1, 2, 0, -3])) iterates over elements $(D 1) and $(D 2).))
 *   $(TR $(TDNW $(LREF filterBidirectional))
 *        $(TD Similar to $(D filter), but also provides $(D back) and $(D popBack) at a small increase in cost.))
 *   $(TR $(TDNW $(LREF group))
 *        $(TD $(D group([5, 2, 2, 3, 3])) returns a range containing the tuples $(D tuple(5, 1)), $(D tuple(2, 2)),
 *             and $(D tuple(3, 2)).))
 *   $(TR $(TDNW $(LREF joiner))
 *        $(TD $(D joiner(["hello", "world!"], ";")) returns a range that iterates over the characters
 *             $(D "hello; world!"). No new string is created - the existing inputs are iterated.))
 *   $(TR $(TDNW $(LREF map))
 *        $(TD $(D map!"2 * a"([1, 2, 3])) lazily returns a range with the numbers $(D 2), $(D 4), $(D 6).))
 *   $(TR $(TDNW $(LREF reduce))
 *        $(TD $(D reduce!"a + b"([1, 2, 3, 4])) returns $(D 10).))
 *   $(TR $(TDNW $(LREF splitter))
 *        $(TD Lazily splits a range by a separator.))
 *   $(TR $(TDNW $(LREF uniq))
 *        $(TD Iterates over the unique elements in a range, which is assumed sorted.))
 *
 *   $(LEADINGROW Sorting)
 *
 *   $(TR $(TDNW $(LREF completeSort))
 *        $(TD If $(D a = [10, 20, 30]) and $(D b = [40, 6, 15]), then $(D completeSort(a, b)) leaves
 *             $(D a = [6, 10, 15]) and $(D b = [20, 30, 40]). The range $(D a) must be sorted prior to the call,
 *             and as a result the combination $(D $(XREF range, chain)(a, b)) is sorted.))
 *   $(TR $(TDNW $(LREF isPartitioned))
 *        $(TD $(D isPartitioned!"a < 0"([-1, -2, 1, 0, 2])) returns $(D true) because the predicate is
 *             $(D true) for a portion of the range and $(D false) afterwards.))
 *   $(TR $(TDNW $(LREF isSorted))
 *        $(TD $(D isSorted([1, 1, 2, 3])) returns $(D true).))
 *   $(TR $(TDNW $(LREF makeIndex))
 *        $(TD Creates a separate index for a range.))
 *   $(TR $(TDNW $(LREF nextPermutation))
 *        $(TD Computes the next lexicographically greater permutation of a range in-place.))
 *   $(TR $(TDNW $(LREF nextEvenPermutation))
 *        $(TD Computes the next lexicographically greater even permutation of a range in-place.))
 *   $(TR $(TDNW $(LREF partialSort))
 *        $(TD If $(D a = [5, 4, 3, 2, 1]), then $(D partialSort(a, 3)) leaves
 *             $(D a[0 .. 3] = [1, 2, 3]). The other elements of $(D a) are left in an unspecified order.))
 *   $(TR $(TDNW $(LREF partition))
 *        $(TD Partitions a range according to a predicate.))
 *   $(TR $(TDNW $(LREF schwartzSort))
 *        $(TD Sorts with the help of the $(LUCKY Schwartzian transform).))
 *   $(TR $(TDNW $(LREF sort))
 *        $(TD Sorts.))
 *   $(TR $(TDNW $(LREF topN))
 *        $(TD Separates the top elements in a range.))
 *   $(TR $(TDNW $(LREF topNCopy))
 *        $(TD Copies out the top elements of a range.))
 *
 *   $(LEADINGROW Set operations)
 *
 *   $(TR $(TDNW $(LREF cartesianProduct))
 *        $(TD Computes Cartesian product of two ranges.))
 *   $(TR $(TDNW $(LREF largestPartialIntersection))
 *        $(TD Copies out the values that occur most frequently in a range of ranges.))
 *   $(TR $(TDNW $(LREF largestPartialIntersectionWeighted))
 *        $(TD Copies out the values that occur most frequently (multiplied by per-value weights) in a range of ranges.))
 *   $(TR $(TDNW $(LREF nWayUnion))
 *        $(TD Computes the union of a set of sets implemented as a range of sorted ranges.))
 *   $(TR $(TDNW $(LREF setDifference))
 *        $(TD Lazily computes the set difference of two or more sorted ranges.))
 *   $(TR $(TDNW $(LREF setIntersection))
 *        $(TD Lazily computes the intersection of two or more sorted ranges.))
 *   $(TR $(TDNW $(LREF setSymmetricDifference))
 *        $(TD Lazily computes the symmetric set difference of two or more sorted ranges.))
 *   $(TR $(TDNW $(LREF setUnion))
 *        $(TD Lazily computes the set union of two or more sorted ranges.))
 *
 *   $(LEADINGROW Mutation)
 *
 *   $(TR $(TDNW $(LREF bringToFront))
 *        $(TD If $(D a = [1, 2, 3]) and $(D b = [4, 5, 6, 7]), $(D bringToFront(a, b)) leaves $(D a = [4, 5, 6])
 *             and $(D b = [7, 1, 2, 3]).))
 *   $(TR $(TDNW $(LREF copy))
 *        $(TD Copies a range to another. If $(D a = [1, 2, 3]) and $(D b = new int[5]), then $(D copy(a, b)) leaves
 *             $(D b = [1, 2, 3, 0, 0]) and returns $(D b[3 .. $]).))
 *   $(TR $(TDNW $(LREF fill))
 *        $(TD Fills a range with a pattern, e.g., if $(D a = new int[3]), then $(D fill(a, 4)) leaves
 *        $(D a = [4, 4, 4]) and $(D fill(a, [3, 4])) leaves $(D a = [3, 4, 3]).))
 *   $(TR $(TDNW $(LREF initializeAll))
 *        $(TD If $(D a = [1.2, 3.4]), then $(D initializeAll(a)) leaves $(D a = [double.init, double.init]).))
 *   $(TR $(TDNW $(LREF move))
 *        $(TD $(D move(a, b)) moves $(D a) into $(D b). $(D move(a)) reads $(D a) destructively.))
 *   $(TR $(TDNW $(LREF moveAll))
 *        $(TD Moves all elements from one range to another.))
 *   $(TR $(TDNW $(LREF moveSome))
 *        $(TD Moves as many elements as possible from one range to another.))
 *   $(TR $(TDNW $(LREF reverse))
 *        $(TD If $(D a = [1, 2, 3]), $(D reverse(a)) changes it to $(D [3, 2, 1]).))
 *   $(TR $(TDNW $(LREF swap))
 *        $(TD Swaps two values.))
 *   $(TR $(TDNW $(LREF swapRanges))
 *        $(TD Swaps all elements of two ranges.))
 *   $(TR $(TDNW $(LREF uninitializedFill))
 *        $(TD Fills a range (assumed uninitialized) with a value.))
 *  )
 *
 * Macros:
 *  WIKI = Phobos/StdAlgorithm
 *  MYREF = <font face='Consolas, "Bitstream Vera Sans Mono", "Andale Mono", Monaco, "DejaVu Sans Mono", "Lucida Console", monospace'><a href="#$1">$1</a>&nbsp;</font>
 *
 * Copyright: Andrei Alexandrescu 2008-.
 *
 * License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 *
 * Authors: $(WEB erdani.com, Andrei Alexandrescu)
 *
 * Source: $(PHOBOSSRC std/_algorithm.d)
 */
module std.algorithm;

public
{
    import std.algorithm.iteration;     /// inherit
    import std.algorithm.searching;     /// inherit
    import std.algorithm.comparison;    /// inherit
    import std.algorithm.sorting;       /// inherit
    import std.algorithm.setop;         /// inherit
    import std.algorithm.mutation;      /// inherit
}

package
{
    T* addressOf(T)(ref T val) { return &val; }
}

// Internal random array generators
version(unittest)
{
    import std.range;
    import std.random : Random, unpredictableSeed, uniform;

    enum size_t maxArraySize = 50;
    enum size_t minArraySize = maxArraySize - 1;

  package:
    string[] rndstuff(T : string)()
    {
        static Random rnd;
        static bool first = true;
        if (first)
        {
            rnd = Random(unpredictableSeed);
            first = false;
        }
        string[] result = new string[uniform(minArraySize, maxArraySize, rnd)];
        string alpha = "abcdefghijABCDEFGHIJ";
        foreach (ref s; result)
        {
            foreach (i; 0 .. uniform(0u, 20u, rnd))
            {
                auto j = uniform(0, alpha.length - 1, rnd);
                s ~= alpha[j];
            }
        }
        return result;
    }

    int[] rndstuff(T : int)()
    {
        static Random rnd;
        static bool first = true;
        if (first)
        {
            rnd = Random(unpredictableSeed);
            first = false;
        }
        int[] result = new int[uniform(minArraySize, maxArraySize, rnd)];
        foreach (ref i; result)
        {
            i = uniform(-100, 100, rnd);
        }
        return result;
    }

    double[] rndstuff(T : double)()
    {
        double[] result;
        foreach (i; rndstuff!int())
        {
            result ~= i / 50.0;
        }
        return result;
    }

    // Reference type input range
    class ReferenceInputRange(T)
    {
        protected T[] _payload;

        this(Range)(Range r) if (isInputRange!Range) {_payload = array(r); }
        final @property bool empty() { return _payload.empty; }
        final @property ref T front() { return _payload.front; }
        final void popFront() { _payload.popFront(); }
    }

    // Reference forward range
    class ReferenceForwardRange(T) : ReferenceInputRange!T
    {
        this(Range)(Range r) if (isInputRange!Range) { super(r); }
        final @property ReferenceForwardRange save()
        { return new ReferenceForwardRange!T(_payload); }
    }

    // Infinite input range
    class ReferenceInfiniteInputRange(T)
    {
        protected T _val;
        this(T first = T.init) { _val = first; }
        enum bool empty = false;
        final @property T front() { return _val; }
        final void popFront() { ++_val; }
    }

    // Infinite forward range
    class ReferenceInfiniteForwardRange(T) : ReferenceInfiniteInputRange!T
    {
        this(T first = T.init) { super(first); }
        final @property ReferenceInfiniteForwardRange save()
        { return new ReferenceInfiniteForwardRange!T(_val); }
    }
}

