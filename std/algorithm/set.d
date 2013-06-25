module std.algorithm.set;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;
import std.typecons : Tuple, tuple;

version(unittest)
{
}

/**
 * Lazily computes the union of two or more ranges $(D rs). The ranges
 * are assumed to be sorted by $(D less). Elements in the output are not
 * unique; the length of the output is the sum of the lengths of the
 * inputs. (The $(D length) member is offered if all ranges also have
 * length.) The element types of all ranges must have a common type.
 */
struct SetUnion(alias less = "a < b", Rs...)
if (allSatisfy!(isInputRange, Rs))
{
private:
    alias comp = binaryFun!less;
    Rs _r;
    uint _crt;

    void adjustPosition(uint candidate = 0)()
    {
        static if (candidate == Rs.length)
        {
            _crt = _crt.max;
        }
        else
        {
            if (_r[candidate].empty)
            {
                adjustPosition!(candidate + 1)();
                return;
            }
            foreach (i, U; Rs[candidate + 1 .. $])
            {
                enum j = candidate + i + 1;
                if (_r[j].empty)
                    continue;
                if (comp(_r[j].front, _r[candidate].front))
                {
                    // a new candidate was found
                    adjustPosition!j();
                    return;
                }
            }
            // Found a successful candidate
            _crt = candidate;
        }
    }

public:
    alias ElementType = CommonType!(staticMap!(.ElementType, Rs));

    this(Rs rs)
    {
        this._r = rs;
        adjustPosition();
    }

    @property bool empty()
    {
        return _crt == _crt.max;
    }

    @property ElementType front()
    {
        assert(!empty);
        // Assume _crt is correct
        foreach (i, U; Rs)
        {
            if (i < _crt)
                continue;
            assert(!_r[i].empty);
            return _r[i].front;
        }
        assert(false);
    }

    void popFront()
    {
        // Assumes _crt is correct
        assert(!empty);
        foreach (i, U; Rs)
        {
            if (i < _crt)
                continue;
            // found _crt
            assert(!_r[i].empty);
            _r[i].popFront();
            adjustPosition();
            return;
        }
        assert(false);
    }

    static if (allSatisfy!(isForwardRange, Rs))
    {
        @property auto save()
        {
            auto ret = this;
            foreach (ti, elem; _r)
            {
                ret._r[ti] = elem.save;
            }
            return ret;
        }
    }

    static if (allSatisfy!(hasLength, Rs))
    {
        @property size_t length()
        {
            size_t result;
            foreach (i, U; Rs)
            {
                result += _r[i].length;
            }
            return result;
        }

        alias opDollar = length;
    }
}

/// Ditto
SetUnion!(less, Rs)
setUnion(alias less = "a < b", Rs...)
(Rs rs)
{
    return typeof(return)(rs);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    int[] c = [ 10 ];
    assert(setUnion(a, b).length == a.length + b.length);
    assert(equal(setUnion(a, b),    [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9]));
    assert(equal(setUnion(a, c, b), [0, 1, 1, 2, 2, 4, 4, 5, 7, 7, 8, 9, 10]));
    static assert(isForwardRange!(typeof(setUnion(a, b))));
}

/**
 * Lazily computes the intersection of two or more input ranges $(D
 * rs). The ranges are assumed to be sorted by $(D less). The element
 * types of all ranges must have a common type.
 */
struct SetIntersection(alias less = "a < b", Rs...)
if (allSatisfy!(isInputRange, Rs))
{
    static assert(Rs.length == 2);
private:
    Rs _input;
    alias comp = binaryFun!less;
    alias ElementType = CommonType!(staticMap!(.ElementType, Rs));

    void adjustPosition()
    {
        // Positions to the first two elements that are equal
        while (!empty)
        {
            if (comp(_input[0].front, _input[1].front))
            {
                _input[0].popFront();
            }
            else if (comp(_input[1].front, _input[0].front))
            {
                _input[1].popFront();
            }
            else
            {
                break;
            }
        }
    }

public:
    this(Rs input)
    {
        this._input = input;
        // position to the first element
        adjustPosition();
    }

    @property bool empty()
    {
        foreach (i, U; Rs)
        {
            if (_input[i].empty)
                return true;
        }
        return false;
    }

    void popFront()
    {
        assert(!empty);
        assert(!comp(_input[0].front, _input[1].front) &&
               !comp(_input[1].front, _input[0].front));
        _input[0].popFront();
        _input[1].popFront();
        adjustPosition();
    }

    @property ElementType front()
    {
        assert(!empty);
        return _input[0].front;
    }

    static if (allSatisfy!(isForwardRange, Rs))
    {
        @property auto save()
        {
            auto ret = this;
            foreach (ti, elem; _input)
            {
                ret._input[ti] = elem.save;
            }
            return ret;
        }
    }
}

/// Ditto
SetIntersection!(less, Rs)
setIntersection(alias less = "a < b", Rs...)
(Rs ranges)
if (allSatisfy!(isInputRange, Rs))
{
    return typeof(return)(ranges);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    int[] c = [ 0, 1, 4, 5, 7, 8 ];
    assert(equal(setIntersection(a, a), a));
    assert(equal(setIntersection(a, b), [1, 2, 4, 7]));
    static assert(isForwardRange!(typeof(setIntersection(a, a))));
}
unittest
{
    // int[] a = [ 1, 2, 4, 5, 7, 9 ];
    // int[] b = [ 0, 1, 2, 4, 7, 8 ];
    // int[] c = [ 0, 1, 4, 5, 7, 8 ];
    // assert(equal(setIntersection(a, b, b, a), [1, 2, 4, 7]));
    // assert(equal(setIntersection(a, b, c), [1, 4, 7]));
    // assert(equal(setIntersection(a, c, b), [1, 4, 7]));
    // assert(equal(setIntersection(b, a, c), [1, 4, 7]));
    // assert(equal(setIntersection(b, c, a), [1, 4, 7]));
    // assert(equal(setIntersection(c, a, b), [1, 4, 7]));
    // assert(equal(setIntersection(c, b, a), [1, 4, 7]));
}

/**
 * Lazily computes the difference of $(D r1) and $(D r2). The two ranges
 * are assumed to be sorted by $(D less). The element types of the two
 * ranges must have a common type.
 */
struct SetDifference(alias less = "a < b", R1, R2)
if (isInputRange!R1 && isInputRange!R2)
{
private:
    alias comp = binaryFun!less;
    R1 r1;
    R2 r2;

    void adjustPosition()
    {
        while (!r1.empty)
        {
            if (r2.empty || comp(r1.front, r2.front))
                break;
            if (comp(r2.front, r1.front))
            {
                r2.popFront();
            }
            else
            {
                // both are equal
                r1.popFront();
                r2.popFront();
            }
        }
    }

public:
    this(R1 r1, R2 r2)
    {
        this.r1 = r1;
        this.r2 = r2;
        // position to the first element
        adjustPosition();
    }

    @property bool empty() { return r1.empty; }

    @property ElementType!R1 front()
    {
        assert(!empty);
        return r1.front;
    }

    void popFront()
    {
        r1.popFront();
        adjustPosition();
    }

    static if (isForwardRange!R1 && isForwardRange!R2)
    {
        @property typeof(this) save()
        {
            auto ret = this;
            ret.r1 = r1.save;
            ret.r2 = r2.save;
            return ret;
        }
    }
}

/// Ditto
SetDifference!(less, R1, R2)
setDifference(alias less = "a < b", R1, R2)
(R1 r1, R2 r2)
{
    return typeof(return)(r1, r2);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    assert(equal(setDifference(a, b), [5, 9]));
    static assert(isForwardRange!(typeof(setDifference(a, b))));
}

/**
 * Lazily computes the symmetric difference of $(D r1) and $(D r2),
 * i.e. the elements that are present in exactly one of $(D r1) and $(D
 * r2). The two ranges are assumed to be sorted by $(D less), and the
 * output is also sorted by $(D less). The element types of the two
 * ranges must have a common type.
 */
struct SetSymmetricDifference(alias less = "a < b", R1, R2)
if (isInputRange!R1 && isInputRange!R2)
{
private:
    alias comp = binaryFun!less;
    R1 r1;
    R2 r2;
    //bool usingR2;

    void adjustPosition()
    {
        while (!r1.empty && !r2.empty)
        {
            if (comp(r1.front, r2.front) || comp(r2.front, r1.front))
            {
                break;
            }
            // equal, pop both
            r1.popFront();
            r2.popFront();
        }
    }

public:
    this(R1 r1, R2 r2)
    {
        this.r1 = r1;
        this.r2 = r2;
        // position to the first element
        adjustPosition();
    }

    @property bool empty() { return r1.empty && r2.empty; }

    @property ElementType!R1 front()
    {
        assert(!empty);
        if (r2.empty || !r1.empty && comp(r1.front, r2.front))
        {
            return r1.front;
        }
        assert(r1.empty || comp(r2.front, r1.front));
        return r2.front;
    }

    void popFront()
    {
        assert(!empty);
        if (r1.empty)
            r2.popFront();
        else if (r2.empty)
            r1.popFront();
        else
        {
            // neither is empty
            if (comp(r1.front, r2.front))
            {
                r1.popFront();
            }
            else
            {
                assert(comp(r2.front, r1.front));
                r2.popFront();
            }
        }
        adjustPosition();
    }

    static if (isForwardRange!R1 && isForwardRange!R2)
    {
        @property typeof(this) save()
        {
            auto ret = this;
            ret.r1 = r1.save;
            ret.r2 = r2.save;
            return ret;
        }
    }

    ref auto opSlice() { return this; }
}

/// Ditto
SetSymmetricDifference!(less, R1, R2)
setSymmetricDifference(alias less = "a < b", R1, R2)
(R1 r1, R2 r2)
{
    return typeof(return)(r1, r2);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 5, 7, 9 ];
    int[] b = [ 0, 1, 2, 4, 7, 8 ];
    assert(equal(setSymmetricDifference(a, b), [0, 5, 8, 9]));
    static assert(isForwardRange!(typeof(setSymmetricDifference(a, b))));
}

/**
 * Computes the union of multiple sets. The input sets are passed as a
 * range of ranges and each is assumed to be sorted by $(D
 * less). Computation is done lazily, one union element at a time. The
 * complexity of one $(D popFront) operation is $(BIGOH
 * log(ror.length)). However, the length of $(D ror) decreases as ranges
 * in it are exhausted, so the complexity of a full pass through $(D
 * NWayUnion) is dependent on the distribution of the lengths of ranges
 * contained within $(D ror). If all ranges have the same length $(D n)
 * (worst case scenario), the complexity of a full pass through $(D
 * NWayUnion) is $(BIGOH n * ror.length * log(ror.length)), i.e., $(D
 * log(ror.length)) times worse than just spanning all ranges in
 * turn. The output comes sorted (unstably) by $(D less).
 *
 * Warning: Because $(D NWayUnion) does not allocate extra memory, it
 * will leave $(D ror) modified. Namely, $(D NWayUnion) assumes ownership
 * of $(D ror) and discretionarily swaps and advances elements of it. If
 * you want $(D ror) to preserve its contents after the call, you may
 * want to pass a duplicate to $(D NWayUnion) (and perhaps cache the
 * duplicate in between calls).
 */
struct NWayUnion(alias less, RangeOfRanges)
{
private:
    import std.container : BinaryHeap;

    alias ElementType = .ElementType!(.ElementType!RangeOfRanges);
    alias comp = binaryFun!less;
    RangeOfRanges _ror;

public:
    static bool compFront(.ElementType!RangeOfRanges a, .ElementType!RangeOfRanges b)
    {
        // revert comparison order so we get the smallest elements first
        return comp(b.front, a.front);
    }
    BinaryHeap!(RangeOfRanges, compFront) _heap;

    this(RangeOfRanges ror)
    {
        // Preemptively get rid of all empty ranges in the input
        // No need for stability either
        _ror = remove!("a.empty", SwapStrategy.unstable)(ror);
        //Build the heap across the range
        _heap.acquire(_ror);
    }

    @property bool empty() { return _ror.empty; }

    @property auto ref front()
    {
        return _heap.front.front;
    }

    void popFront()
    {
        _heap.removeFront();
        // let's look at the guy just popped
        _ror.back.popFront();
        if (_ror.back.empty)
        {
            _ror.popBack();
            // nothing else to do: the empty range is not in the
            // heap and not in _ror
            return;
        }
        // Put the popped range back in the heap
        _heap.conditionalInsert(_ror.back) || assert(false);
    }
}

/// Ditto
NWayUnion!(less, RangeOfRanges)
nWayUnion
(alias less = "a < b", RangeOfRanges)
(RangeOfRanges ror)
{
    return typeof(return)(ror);
}

///
unittest
{
    double[][] a =
    [
        [ 1, 4, 7, 8 ],
        [ 1, 7 ],
        [ 1, 7, 8],
        [ 4 ],
        [ 7 ],
    ];
    auto witness = [
        1, 1, 1, 4, 4, 7, 7, 7, 7, 8, 8
    ];
    assert(equal(nWayUnion(a), witness[]));
}

/**
 * Given a range of sorted forward ranges $(D ror), copies to $(D tgt)
 * the elements that are common to most ranges, along with their number
 * of occurrences. All ranges in $(D ror) are assumed to be sorted by $(D
 * less). Only the most frequent $(D tgt.length) elements are returned.
 */
unittest
{
    // Figure which number can be found in most arrays of the set of
    // arrays below.
    double[][] a =
    [
        [ 1, 4, 7, 8 ],
        [ 1, 7 ],
        [ 1, 7, 8],
        [ 4 ],
        [ 7 ],
    ];
    auto b = new Tuple!(double, uint)[1];
    largestPartialIntersection(a, b);
    // First member is the item, second is the occurrence count
    assert(b[0] == tuple(7.0, 4u));
}
/**
 * $(D 7.0) is the correct answer because it occurs in $(D 4) out of the
 * $(D 5) inputs, more than any other number. The second member of the
 * resulting tuple is indeed $(D 4) (recording the number of occurrences
 * of $(D 7.0)). If more of the top-frequent numbers are needed, just
 * create a larger $(D tgt) range. In the axample above, creating $(D b)
 * with length $(D 2) yields $(D tuple(1.0, 3u)) in the second position.
 *
 * The function $(D largestPartialIntersection) is useful for
 * e.g. searching an $(LUCKY inverted index) for the documents most
 * likely to contain some terms of interest. The complexity of the search
 * is $(BIGOH n * log(tgt.length)), where $(D n) is the sum of lengths of
 * all input ranges. This approach is faster than keeping an associative
 * array of the occurrences and then selecting its top items, and also
 * requires less memory ($(D largestPartialIntersection) builds its
 * result directly in $(D tgt) and requires no extra memory).
 *
 * Warning: Because $(D largestPartialIntersection) does not allocate
 * extra memory, it will leave $(D ror) modified. Namely, $(D
 * largestPartialIntersection) assumes ownership of $(D ror) and
 * discretionarily swaps and advances elements of it. If you want $(D
 * ror) to preserve its contents after the call, you may want to pass a
 * duplicate to $(D largestPartialIntersection) (and perhaps cache the
 * duplicate in between calls).
 */
void largestPartialIntersection
(alias less = "a < b", RangeOfRanges, Range)
(RangeOfRanges ror, Range tgt, SortOutput sorted = SortOutput.no)
{
    struct UnitWeights
    {
        static int opIndex(ElementType!(ElementType!RangeOfRanges))
        {
            return 1;
        }
    }
    return largestPartialIntersectionWeighted!less(ror, tgt, UnitWeights(), sorted);
}

/**
 * Similar to $(D largestPartialIntersection), but associates a weight
 * with each distinct element in the intersection.
 */
unittest
{
    // Figure which number can be found in most arrays of the set of
    // arrays below, with specific per-element weights
    double[][] a =
    [
        [ 1, 4, 7, 8 ],
        [ 1, 7 ],
        [ 1, 7, 8],
        [ 4 ],
        [ 7 ],
    ];
    auto b = new Tuple!(double, uint)[1];
    double[double] weights = [ 1:1.2, 4:2.3, 7:1.1, 8:1.1 ];
    largestPartialIntersectionWeighted(a, b, weights);
    // First member is the item, second is the occurrence count
    assert(b[0] == tuple(4.0, 2u));
}
/**
The correct answer in this case is $(D 4.0), which, although only
appears two times, has a total weight $(D 4.6) (three times its weight
$(D 2.3)). The value $(D 7) is weighted with $(D 1.1) and occurs four
times for a total weight $(D 4.4).
 */
void largestPartialIntersectionWeighted
(alias less = "a < b", RangeOfRanges, Range, WeightsAA)
(RangeOfRanges ror, Range tgt, WeightsAA weights, SortOutput sorted = SortOutput.no)
{
    if (tgt.empty)
        return;
    alias InfoType = ElementType!Range;
    bool heapComp(InfoType a, InfoType b)
    {
        return weights[a[0]] * a[1] > weights[b[0]] * b[1];
    }
    topNCopy!heapComp(group(nWayUnion!less(ror)), tgt, sorted);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    double[][] a =
        [
            [ 1, 4, 7, 8 ],
            [ 1, 7 ],
            [ 1, 7, 8],
            [ 4 ],
            [ 7 ],
        ];
    auto b = new Tuple!(double, uint)[2];
    largestPartialIntersection(a, b, SortOutput.yes);
    //sort(b);
    //writeln(b);
    assert(b == [ tuple(7.0, 4u), tuple(1.0, 3u) ]);
    assert(a[0].empty);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    string[][] a =
        [
            [ "1", "4", "7", "8" ],
            [ "1", "7" ],
            [ "1", "7", "8"],
            [ "4" ],
            [ "7" ],
        ];
    auto b = new Tuple!(string, uint)[2];
    largestPartialIntersection(a, b, SortOutput.yes);
    //writeln(b);
    assert(b == [ tuple("7", 4u), tuple("1", 3u) ]);
}

unittest
{
    import std.container : Array;
    alias T = Tuple!(uint, uint);
    const Array!T arrayOne = Array!T( [ T(1,2), T(3,4) ] );
    const Array!T arrayTwo = Array!T( [ T(1,2), T(3,4) ] );
    assert(arrayOne == arrayTwo);
}

/**
 * Permutes $(D range) in-place to the next lexicographically greater
 * permutation.
 *
 * The predicate $(D less) defines the lexicographical ordering to be used on
 * the range.
 *
 * If the range is currently the lexicographically greatest permutation, it is
 * permuted back to the least permutation and false is returned.  Otherwise,
 * true is returned. One can thus generate all permutations of a range by
 * sorting it according to $(D less), which produces the lexicographically
 * least permutation, and then calling nextPermutation until it returns false.
 * This is guaranteed to generate all distinct permutations of the range
 * exactly once.  If there are $(I N) elements in the range and all of them are
 * unique, then $(I N)! permutations will be generated. Otherwise, if there are
 * some duplicated elements, fewer permutations will be produced.
 */
unittest
{
    // Enumerate all permutations
    int[] a = [1, 2, 3, 4, 5];
    while (nextPermutation(a))
    {
        // a now contains the next permutation of the array.
    }
}
/**
 * Returns: false if the range was lexicographically the greatest, in which
 * case the range is reversed back to the lexicographically smallest
 * permutation; otherwise returns true.
 */
unittest
{
    // Step through all permutations of a sorted array in lexicographic order
    int[] a = [1, 2, 3];
    assert( nextPermutation(a) && a == [1, 3, 2]);
    assert( nextPermutation(a) && a == [2, 1, 3]);
    assert( nextPermutation(a) && a == [2, 3, 1]);
    assert( nextPermutation(a) && a == [3, 1, 2]);
    assert( nextPermutation(a) && a == [3, 2, 1]);
    assert(!nextPermutation(a) && a == [1, 2, 3]);
}
///
unittest
{
    // Step through permutations of an array containing duplicate elements:
    int[] a = [1, 1, 2];
    assert( nextPermutation(a) && a == [1,2,1]);
    assert( nextPermutation(a) && a == [2,1,1]);
    assert(!nextPermutation(a) && a == [1,1,2]);
}
///
bool nextPermutation
(alias less="a<b", BidirectionalRange)
(ref BidirectionalRange range)
if (isBidirectionalRange!BidirectionalRange &&
    hasSwappableElements!BidirectionalRange)
{
    // Ranges of 0 or 1 element have no distinct permutations.
    if (range.empty)
        return false;

    auto i = retro(range);
    auto last = i.save;

    // Find last occurring increasing pair of elements
    size_t n = 1;
    for (i.popFront(); !i.empty; i.popFront(), last.popFront(), n++)
    {
        if (binaryFun!less(i.front, last.front))
            break;
    }

    if (i.empty)
    {
        // Entire range is decreasing: it's lexicographically the greatest. So
        // wrap it around.
        range.reverse();
        return false;
    }

    // Find last element greater than i.front.
    auto j = find!(a => binaryFun!less(i.front, a))
                  (takeExactly(retro(range), n));

    assert(!j.empty);   // shouldn't happen since i.front < last.front
    swap(i.front, j.front);
    reverse(takeExactly(retro(range), n));

    return true;
}

unittest
{
    // Boundary cases: arrays of 0 or 1 element.
    int[] a1 = [];
    assert(!nextPermutation(a1));
    assert(a1 == []);

    int[] a2 = [1];
    assert(!nextPermutation(a2));
    assert(a2 == [1]);
}

unittest
{
    auto a1 = [1, 2, 3, 4];
    assert( nextPermutation(a1) && equal(a1, [1, 2, 4, 3]));
    assert( nextPermutation(a1) && equal(a1, [1, 3, 2, 4]));
    assert( nextPermutation(a1) && equal(a1, [1, 3, 4, 2]));
    assert( nextPermutation(a1) && equal(a1, [1, 4, 2, 3]));
    assert( nextPermutation(a1) && equal(a1, [1, 4, 3, 2]));
    assert( nextPermutation(a1) && equal(a1, [2, 1, 3, 4]));
    assert( nextPermutation(a1) && equal(a1, [2, 1, 4, 3]));
    assert( nextPermutation(a1) && equal(a1, [2, 3, 1, 4]));
    assert( nextPermutation(a1) && equal(a1, [2, 3, 4, 1]));
    assert( nextPermutation(a1) && equal(a1, [2, 4, 1, 3]));
    assert( nextPermutation(a1) && equal(a1, [2, 4, 3, 1]));
    assert( nextPermutation(a1) && equal(a1, [3, 1, 2, 4]));
    assert( nextPermutation(a1) && equal(a1, [3, 1, 4, 2]));
    assert( nextPermutation(a1) && equal(a1, [3, 2, 1, 4]));
    assert( nextPermutation(a1) && equal(a1, [3, 2, 4, 1]));
    assert( nextPermutation(a1) && equal(a1, [3, 4, 1, 2]));
    assert( nextPermutation(a1) && equal(a1, [3, 4, 2, 1]));
    assert( nextPermutation(a1) && equal(a1, [4, 1, 2, 3]));
    assert( nextPermutation(a1) && equal(a1, [4, 1, 3, 2]));
    assert( nextPermutation(a1) && equal(a1, [4, 2, 1, 3]));
    assert( nextPermutation(a1) && equal(a1, [4, 2, 3, 1]));
    assert( nextPermutation(a1) && equal(a1, [4, 3, 1, 2]));
    assert( nextPermutation(a1) && equal(a1, [4, 3, 2, 1]));
    assert(!nextPermutation(a1) && equal(a1, [1, 2, 3, 4]));
}

unittest
{
    // Test with non-default sorting order
    int[] a = [3, 2, 1];
    assert( nextPermutation!"a > b"(a) && a == [3, 1, 2]);
    assert( nextPermutation!"a > b"(a) && a == [2, 3, 1]);
    assert( nextPermutation!"a > b"(a) && a == [2, 1, 3]);
    assert( nextPermutation!"a > b"(a) && a == [1, 3, 2]);
    assert( nextPermutation!"a > b"(a) && a == [1, 2, 3]);
    assert(!nextPermutation!"a > b"(a) && a == [3, 2, 1]);
}

/**
 * Permutes $(D range) in-place to the next lexicographically greater $(I even)
 * permutation.
 *
 * The predicate $(D less) defines the lexicographical ordering to be used on
 * the range.
 *
 * An even permutation is one which is produced by swapping an even number of
 * pairs of elements in the original range. The set of $(I even) permutations
 * is distinct from the set of $(I all) permutations only when there are no
 * duplicate elements in the range. If the range has $(I N) unique elements,
 * then there are exactly $(I N)!/2 even permutations.
 *
 * If the range is already the lexicographically greatest even permutation, it
 * is permuted back to the least even permutation and false is returned.
 * Otherwise, true is returned, and the range is modified in-place to be the
 * lexicographically next even permutation.
 *
 * One can thus generate the even permutations of a range with unique elements
 * by starting with the lexicographically smallest permutation, and repeatedly
 * calling nextEvenPermutation until it returns false.
 */
unittest
{
    // Enumerate even permutations
    int[] a = [1, 2, 3, 4, 5];
    while (nextEvenPermutation(a))
    {
        // a now contains the next even permutation of the array.
    }
}
/**
 * One can also generate the $(I odd) permutations of a range by noting that
 * permutations obey the rule that even + even = even, and odd + even = odd.
 * Thus, by swapping the last two elements of a lexicographically least range,
 * it is turned into the first odd permutation. Then calling
 * nextEvenPermutation on this first odd permutation will generate the next
 * even permutation relative to this odd permutation, which is actually the
 * next odd permutation of the original range. Thus, by repeatedly calling
 * nextEvenPermutation until it returns false, one enumerates the odd
 * permutations of the original range.
 */
unittest
{
    // Enumerate odd permutations
    int[] a = [1,2,3,4,5];
    swap(a[$-2], a[$-1]);    // a is now the first odd permutation of [1,2,3,4,5]
    while (nextEvenPermutation(a))
    {
        // a now contains the next odd permutation of the original array
        // (which is an even permutation of the first odd permutation).
    }
}
/**
 *
 * Warning: Since even permutations are only distinct from all permutations
 * when the range elements are unique, this function assumes that there are no
 * duplicate elements under the specified ordering. If this is not _true, some
 * permutations may fail to be generated. When the range has non-unique
 * elements, you should use $(MYREF nextPermutation) instead.
 *
 * Returns: false if the range was lexicographically the greatest, in which
 * case the range is reversed back to the lexicographically smallest
 * permutation; otherwise returns true.
 */
unittest
{
    // Step through even permutations of a sorted array in lexicographic order
    int[] a = [1, 2, 3];
    assert( nextEvenPermutation(a) && a == [2, 3, 1]);
    assert( nextEvenPermutation(a) && a == [3, 1, 2]);
    assert(!nextEvenPermutation(a) && a == [1, 2, 3]);
}
/**
 * Even permutations are useful for generating coordinates of certain geometric
 * shapes. Here's a non-trivial example:
 */
unittest
{
    // Print the 60 vertices of a uniform truncated icosahedron (soccer ball)
    import std.math, std.stdio;
    enum real Phi = (1.0 + sqrt(5.0)) / 2.0;    // Golden ratio
    real[][] seeds = [
        [0.0, 1.0, 3.0*Phi],
        [1.0, 2.0+Phi, 2.0*Phi],
        [Phi, 2.0, Phi^^3]
    ];
    size_t n;
    foreach (seed; seeds)
    {
        // Loop over even permutations of each seed
        do
        {
            // Loop over all sign changes of each permutation
            size_t i;
            do
            {
                // Generate all possible sign changes
                for (i=0; i < seed.length; i++)
                {
                    if (seed[i] != 0.0)
                    {
                        seed[i] = -seed[i];
                        if (seed[i] < 0.0)
                            break;
                    }
                }
                //writeln(seed);
                n++;
            } while (i < seed.length);
        } while (nextEvenPermutation(seed));
    }
    assert(n == 60);
}
///
bool nextEvenPermutation
(alias less="a<b", BidirectionalRange)
(ref BidirectionalRange range)
if (isBidirectionalRange!BidirectionalRange &&
    hasSwappableElements!BidirectionalRange)
{
    // Ranges of 0 or 1 element have no distinct permutations.
    if (range.empty)
        return false;

    bool oddParity = false;
    bool ret = true;
    do
    {
        auto i = retro(range);
        auto last = i.save;

        // Find last occurring increasing pair of elements
        size_t n = 1;
        for (i.popFront();
             !i.empty;
             i.popFront(), last.popFront(), n++)
        {
            if (binaryFun!less(i.front, last.front))
                break;
        }

        if (!i.empty)
        {
            // Find last element greater than i.front.
            auto j = find!(a => binaryFun!less(i.front, a))
                          (takeExactly(retro(range), n));

            // shouldn't happen since i.front < last.front
            assert(!j.empty);

            swap(i.front, j.front);
            oddParity = !oddParity;
        }
        else
        {
            // Entire range is decreasing: it's lexicographically
            // the greatest.
            ret = false;
        }

        reverse(takeExactly(retro(range), n));
        if ((n / 2) % 2 == 1)
            oddParity = !oddParity;
    } while(oddParity);

    return ret;
}

unittest
{
    auto a3 = [ 1, 2, 3, 4 ];
    int count = 1;
    while (nextEvenPermutation(a3)) count++;
    assert(count == 12);
}

unittest
{
    // Test with non-default sorting order
    auto a = [ 3, 2, 1 ];
    assert( nextEvenPermutation!"a > b"(a) && a == [ 2, 1, 3 ]);
    assert( nextEvenPermutation!"a > b"(a) && a == [ 1, 3, 2 ]);
    assert(!nextEvenPermutation!"a > b"(a) && a == [ 3, 2, 1 ]);
}

unittest
{
    // Test various cases of rollover
    auto a = [ 3, 1, 2 ];
    assert(nextEvenPermutation(a) == false);
    assert(a == [ 1, 2, 3 ]);

    auto b = [ 3, 2, 1 ];
    assert(nextEvenPermutation(b) == false);
    assert(b == [ 1, 3, 2 ]);
}

/**
 * Lazily computes the Cartesian product of two or more ranges. The product is a
 * _range of tuples of elements from each respective range.
 *
 * The conditions for the two-range case are as follows:
 *
 * If both ranges are finite, then one must be (at least) a forward range and the
 * other an input range.
 *
 * If one _range is infinite and the other finite, then the finite _range must
 * be a forward _range, and the infinite range can be an input _range.
 *
 * If both ranges are infinite, then both must be forward ranges.
 *
 * When there are more than two ranges, the above conditions apply to each
 * adjacent pair of ranges.
 */
unittest
{
    auto N = sequence!"n"(0);         // the range of natural numbers
    auto N2 = cartesianProduct(N, N); // the range of all pairs of natural numbers

    // Various arbitrary number pairs can be found in the range in finite time.
    assert(canFind(N2, tuple(0, 0)));
    assert(canFind(N2, tuple(123, 321)));
    assert(canFind(N2, tuple(11, 35)));
    assert(canFind(N2, tuple(279, 172)));
}
///
unittest
{
    auto B = [ 1, 2, 3 ];
    auto C = [ 4, 5, 6 ];
    auto BC = cartesianProduct(B, C);

    foreach (n; [[1, 4], [2, 4], [3, 4], [1, 5], [2, 5], [3, 5], [1, 6],
                 [2, 6], [3, 6]])
    {
        assert(canFind(BC, tuple(n[0], n[1])));
    }
}
///
unittest
{
    auto A = [ 1, 2, 3 ];
    auto B = [ 'a', 'b', 'c' ];
    auto C = [ "x", "y", "z" ];
    auto ABC = cartesianProduct(A, B, C);

    assert(ABC.equal([
        tuple(1, 'a', "x"), tuple(2, 'a', "x"), tuple(3, 'a', "x"),
        tuple(1, 'b', "x"), tuple(2, 'b', "x"), tuple(3, 'b', "x"),
        tuple(1, 'c', "x"), tuple(2, 'c', "x"), tuple(3, 'c', "x"),
        tuple(1, 'a', "y"), tuple(2, 'a', "y"), tuple(3, 'a', "y"),
        tuple(1, 'b', "y"), tuple(2, 'b', "y"), tuple(3, 'b', "y"),
        tuple(1, 'c', "y"), tuple(2, 'c', "y"), tuple(3, 'c', "y"),
        tuple(1, 'a', "z"), tuple(2, 'a', "z"), tuple(3, 'a', "z"),
        tuple(1, 'b', "z"), tuple(2, 'b', "z"), tuple(3, 'b', "z"),
        tuple(1, 'c', "z"), tuple(2, 'c', "z"), tuple(3, 'c', "z")
    ]));
}
///
auto cartesianProduct(R1, R2)(R1 range1, R2 range2)
{
    static if (isInfinite!R1 && isInfinite!R2)
    {
        static if (isForwardRange!R1 && isForwardRange!R2)
        {
            // This algorithm traverses the cartesian product by alternately
            // covering the right and bottom edges of an increasing square area
            // over the infinite table of combinations. This schedule allows us
            // to require only forward ranges.
            return zip(sequence!"n"(cast(size_t)0), range1.save, range2.save,
                       repeat(range1), repeat(range2))
                .map!(function(a) => chain(
                    zip(repeat(a[1]), take(a[4].save, a[0])),
                    zip(take(a[3].save, a[0]+1), repeat(a[2]))
                ))()
                .joiner();
        }
        else
            static assert(0, "cartesianProduct of infinite ranges requires "~
                             "forward ranges");
    }
    else static if (isInputRange!R2 && isForwardRange!R1 && !isInfinite!R1)
    {
        return joiner(map!((ElementType!R2 a) => zip(range1.save, repeat(a)))
                          (range2));
    }
    else static if (isInputRange!R1 && isForwardRange!R2 && !isInfinite!R2)
    {
        return joiner(map!((ElementType!R1 a) => zip(repeat(a), range2.save))
                          (range1));
    }
    else
        static assert(0, "cartesianProduct involving finite ranges must "~
                         "have at least one finite forward range");
}

unittest
{
    // Test cartesian product of two infinite ranges
    auto Even = sequence!"2*n"(0);
    auto Odd = sequence!"2*n+1"(0);
    auto EvenOdd = cartesianProduct(Even, Odd);

    foreach (pair; [[0, 1], [2, 1], [0, 3], [2, 3], [4, 1], [4, 3], [0, 5],
                    [2, 5], [4, 5], [6, 1], [6, 3], [6, 5]])
    {
        assert(canFind(EvenOdd, tuple(pair[0], pair[1])));
    }

    // This should terminate in finite time
    assert(canFind(EvenOdd, tuple(124, 73)));
    assert(canFind(EvenOdd, tuple(0, 97)));
    assert(canFind(EvenOdd, tuple(42, 1)));
}

unittest
{
    // Test cartesian product of an infinite input range and a finite forward
    // range.
    auto N = sequence!"n"(0);
    auto M = [100, 200, 300];
    auto NM = cartesianProduct(N,M);

    foreach (pair; [[0, 100], [0, 200], [0, 300], [1, 100], [1, 200], [1, 300],
                    [2, 100], [2, 200], [2, 300], [3, 100], [3, 200],
                    [3, 300]])
    {
        assert(canFind(NM, tuple(pair[0], pair[1])));
    }

    // We can't solve the halting problem, so we can only check a finite
    // initial segment here.
    assert(!canFind(NM.take(100), tuple(100, 0)));
    assert(!canFind(NM.take(100), tuple(1, 1)));
    assert(!canFind(NM.take(100), tuple(100, 200)));

    auto MN = cartesianProduct(M,N);
    foreach (pair; [[100, 0], [200, 0], [300, 0], [100, 1], [200, 1], [300, 1],
                    [100, 2], [200, 2], [300, 2], [100, 3], [200, 3],
                    [300, 3]])
    {
        assert(canFind(MN, tuple(pair[0], pair[1])));
    }

    // We can't solve the halting problem, so we can only check a finite
    // initial segment here.
    assert(!canFind(MN.take(100), tuple(0, 100)));
    assert(!canFind(MN.take(100), tuple(0, 1)));
    assert(!canFind(MN.take(100), tuple(100, 200)));
}

unittest
{
    // Test cartesian product of two finite ranges.
    auto X = [1, 2, 3];
    auto Y = [4, 5, 6];
    auto XY = cartesianProduct(X, Y);
    auto Expected = [[1, 4], [1, 5], [1, 6], [2, 4], [2, 5], [2, 6], [3, 4],
                     [3, 5], [3, 6]];

    // Verify Expected ⊆ XY
    foreach (pair; Expected)
    {
        assert(canFind(XY, tuple(pair[0], pair[1])));
    }

    // Verify XY ⊆ Expected
    foreach (pair; XY)
    {
        assert(canFind(Expected, [pair[0], pair[1]]));
    }

    // And therefore, by set comprehension, XY == Expected
}

unittest
{
    auto N = sequence!"n"(0);

    // To force the template to fall to the second case, we wrap N in a struct
    // that doesn't allow bidirectional access.
    struct FwdRangeWrapper(R)
    {
        R impl;

        // Input range API
        static if (isInfinite!R)
            enum empty = false;
        else
            @property bool empty() { return impl.empty; }
        @property auto front() { return impl.front; }
        void popFront() { impl.popFront(); }

        // Forward range API
        @property auto save() { return typeof(this)(impl.save); }
    }
    auto fwdWrap(R)(R range) { return FwdRangeWrapper!R(range); }

    // General test: two infinite bidirectional ranges
    auto N2 = cartesianProduct(N, N);

    assert(canFind(N2, tuple(0, 0)));
    assert(canFind(N2, tuple(123, 321)));
    assert(canFind(N2, tuple(11, 35)));
    assert(canFind(N2, tuple(279, 172)));

    // Test first case: forward range with bidirectional range
    auto fwdN = fwdWrap(N);
    auto N2_a = cartesianProduct(fwdN, N);

    assert(canFind(N2_a, tuple(0, 0)));
    assert(canFind(N2_a, tuple(123, 321)));
    assert(canFind(N2_a, tuple(11, 35)));
    assert(canFind(N2_a, tuple(279, 172)));

    // Test second case: bidirectional range with forward range
    auto N2_b = cartesianProduct(N, fwdN);

    assert(canFind(N2_b, tuple(0, 0)));
    assert(canFind(N2_b, tuple(123, 321)));
    assert(canFind(N2_b, tuple(11, 35)));
    assert(canFind(N2_b, tuple(279, 172)));

    // Test third case: finite forward range with (infinite) input range
    static struct InpRangeWrapper(R)
    {
        R impl;

        // Input range API
        static if (isInfinite!R)
            enum empty = false;
        else
            @property bool empty() { return impl.empty; }
        @property auto front() { return impl.front; }
        void popFront() { impl.popFront(); }
    }
    auto inpWrap(R)(R r) { return InpRangeWrapper!R(r); }

    auto inpN = inpWrap(N);
    auto B = [ 1, 2, 3 ];
    auto fwdB = fwdWrap(B);
    auto BN = cartesianProduct(fwdB, inpN);

    assert(equal(map!"[a[0],a[1]]"(BN.take(10)),
                 [[1, 0], [2, 0], [3, 0],
                  [1, 1], [2, 1], [3, 1],
                  [1, 2], [2, 2], [3, 2],
                  [1, 3]]));

    // Test fourth case: (infinite) input range with finite forward range
    auto NB = cartesianProduct(inpN, fwdB);

    assert(equal(map!"[a[0],a[1]]"(NB.take(10)),
                 [[0, 1], [0, 2], [0, 3],
                  [1, 1], [1, 2], [1, 3],
                  [2, 1], [2, 2], [2, 3],
                  [3, 1]]));

    // General finite range case
    auto C = [ 4, 5, 6 ];
    auto BC = cartesianProduct(B, C);

    foreach (n; [[1, 4], [2, 4], [3, 4], [1, 5], [2, 5], [3, 5], [1, 6],
                 [2, 6], [3, 6]])
    {
        assert(canFind(BC, tuple(n[0], n[1])));
    }
}

/// ditto
auto cartesianProduct(R1, R2, RR...)(R1 range1, R2 range2, RR otherRanges)
{
    import std.string : format;

    /* We implement the n-ary cartesian product by recursively invoking the
     * binary cartesian product. To make the resulting range nicer, we denest
     * one level of tuples so that a ternary cartesian product, for example,
     * returns 3-element tuples instead of nested 2-element tuples.
     */
    enum string denest = format("tuple(a[0], %(a[1][%d]%|,%))",
                                iota(0, otherRanges.length+1));
    return map!denest(
        cartesianProduct(range1, cartesianProduct(range2, otherRanges))
    );
}

unittest
{
    auto N = sequence!"n"(0);
    auto N3 = cartesianProduct(N, N, N);

    // Check that tuples are properly denested
    static assert(is(ElementType!(typeof(N3)) == Tuple!(size_t,size_t,size_t)));

    assert(canFind(N3, tuple(0, 27, 7)));
    assert(canFind(N3, tuple(50, 23, 71)));
    assert(canFind(N3, tuple(9, 3, 0)));
}

version(none)
// This unittest causes `make -f posix.mak unittest` to run out of memory. Why?
unittest
{
    auto N = sequence!"n"(0);
    auto N4 = cartesianProduct(N, N, N, N);

    // Check that tuples are properly denested
    static assert(is(ElementType!(typeof(N4)) == Tuple!(size_t,size_t,size_t,size_t)));

    assert(canFind(N4, tuple(1, 2, 3, 4)));
    assert(canFind(N4, tuple(4, 3, 2, 1)));
    assert(canFind(N4, tuple(10, 31, 7, 12)));
}

unittest
{
    auto A = [ 1, 2, 3 ];
    auto B = [ 'a', 'b', 'c' ];
    auto C = [ "x", "y", "z" ];
    auto ABC = cartesianProduct(A, B, C);

    assert(ABC.equal([
        tuple(1, 'a', "x"), tuple(2, 'a', "x"), tuple(3, 'a', "x"),
        tuple(1, 'b', "x"), tuple(2, 'b', "x"), tuple(3, 'b', "x"),
        tuple(1, 'c', "x"), tuple(2, 'c', "x"), tuple(3, 'c', "x"),
        tuple(1, 'a', "y"), tuple(2, 'a', "y"), tuple(3, 'a', "y"),
        tuple(1, 'b', "y"), tuple(2, 'b', "y"), tuple(3, 'b', "y"),
        tuple(1, 'c', "y"), tuple(2, 'c', "y"), tuple(3, 'c', "y"),
        tuple(1, 'a', "z"), tuple(2, 'a', "z"), tuple(3, 'a', "z"),
        tuple(1, 'b', "z"), tuple(2, 'b', "z"), tuple(3, 'b', "z"),
        tuple(1, 'c', "z"), tuple(2, 'c', "z"), tuple(3, 'c', "z"),
    ]));
}
