module std.algorithm.sort;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
}

/**
 * Sorts a random-access range according to the predicate $(D less). Performs
 * $(BIGOH r.length * log(r.length)) (if unstable) or $(BIGOH r.length *
 * log(r.length) * log(r.length)) (if stable) evaluations of $(D less)
 * and $(D swap). See also STL's $(WEB sgi.com/tech/stl/_sort.html, _sort)
 * and $(WEB sgi.com/tech/stl/stable_sort.html, stable_sort).
 *
 * $(D sort) returns a $(XREF range, SortedRange) over the original range, which
 * functions that can take advantage of sorted data can then use to know that the
 * range is sorted and adjust accordingly. The $(XREF range, SortedRange) is a
 * wrapper around the original range, so both it and the original range are sorted,
 * but other functions won't know that the original range has been sorted, whereas
 * they $(I can) know that $(XREF range, SortedRange) has been sorted.
 *
 * See_Also:
 *     $(XREF range, assumeSorted)
 *
 * Remark: Stable sort is implementated as Timsort, the original code at
 * $(WEB github.com/Xinok/XSort, XSort) by Xinok, public domain.
 */
SortedRange!(Range, less)
sort(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range)
(Range r)
if (((ss == SwapStrategy.unstable && (hasSwappableElements!Range || hasAssignableElements!Range)) ||
     (ss != SwapStrategy.unstable && hasAssignableElements!Range)) &&
    isRandomAccessRange!Range && hasSlicing!Range && hasLength!Range)
    /+ Unstable sorting uses the quicksort algorithm, which uses swapAt,
       which either uses swap(...), requiring swappable elements, or just
       swaps using assignment.
       Stable sorting uses TimSort, which needs to copy elements into a buffer,
       requiring assignable elements. +/
{
    import std.conv : text;

    alias lessFun = binaryFun!less;
    alias LessRet = typeof(lessFun(r.front, r.front));    // instantiate lessFun
    static if (is(LessRet == bool))
    {
        static if (ss == SwapStrategy.unstable)
        {
            quickSortImpl!lessFun(r);
        }
        else //use Tim Sort for semistable & stable
        {
            TimSortImpl!(lessFun, Range).sort(r, null);
        }

        enum maxLen = 8;
        assert(isSorted!lessFun(r),
               text("Failed to sort range of type ",
                    Range.stringof, ". Actual result is: ",
                    r[0 .. (r.length > maxLen ? maxLen : r.length)],
                    r.length > maxLen ? "..." : ""));
    }
    else
    {
        static assert(false, "Invalid predicate passed to sort: " ~ less);
    }
    return assumeSorted!less(r);
}

///
unittest
{
    int[] array = [ 1, 2, 3, 4 ];

    // sort in descending order
    sort!("a > b")(array);
    assert(array == [ 4, 3, 2, 1 ]);

    // sort in ascending order
    sort(array);
    assert(array == [ 1, 2, 3, 4 ]);

    // sort with a delegate
    bool myComp(int x, int y) { return x > y; }
    sort!(myComp)(array);
    assert(array == [ 4, 3, 2, 1 ]);

    // Showcase stable sorting
    string[] words = [ "aBc", "a", "abc", "b", "ABC", "c" ];
    sort!("toUpper(a) < toUpper(b)", SwapStrategy.stable)(words);
    assert(words == [ "a", "aBc", "abc", "ABC", "b", "c" ]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.random : uniform, unpredictableSeed, Random;
    import std.string : toUpper;

    // sort using delegate
    int a[] = new int[100];
    auto rnd = Random(unpredictableSeed);
    foreach (ref e; a)
        e = uniform(-100, 100, rnd);

    int i = 0;
    bool greater2(int a, int b) { return a + i > b + i; }
    bool delegate(int, int) greater = &greater2;
    sort!greater(a);
    assert(isSorted!greater(a));

    // sort using string
    sort!("a < b")(a);
    assert(isSorted!("a < b")(a));

    // sort using function; all elements equal
    foreach (ref e; a)
        e = 5;

    static bool less(int a, int b) { return a < b; }
    sort!less(a);
    assert(isSorted!less(a));

    string[] words = [ "aBc", "a", "abc", "b", "ABC", "c" ];
    bool lessi(string a, string b) { return toUpper(a) < toUpper(b); }
    sort!(lessi, SwapStrategy.stable)(words);
    assert(words == [ "a", "aBc", "abc", "ABC", "b", "c" ]);

    // sort using ternary predicate
    //sort!("b - a")(a);
    //assert(isSorted!less(a));

    a = rndstuff!int();
    sort(a);
    assert(isSorted(a));
    auto b = rndstuff!string();
    sort!("toLower(a) < toLower(b)")(b);
    assert(isSorted!("toUpper(a) < toUpper(b)")(b));

    {
        // Issue 10317
        enum E_10317 { a, b }
        auto a_10317 = new E_10317[10];
        sort(a_10317);
    }
}

private template validPredicates(E, less...)
{
    static if (less.length == 0)
    {
        enum validPredicates = true;
    }
    else static if (less.length == 1 && is(typeof(less[0]) == SwapStrategy))
    {
        enum validPredicates = true;
    }
    else
    {
        enum validPredicates =
            is(typeof((E a, E b){ bool r = binaryFun!(less[0])(a, b); })) &&
            validPredicates!(E, less[1 .. $]);
    }
}

/**
 * $(D void multiSort(Range)(Range r)
 *     if (validPredicates!(ElementType!Range, less));)
 *
 * Sorts a range by multiple keys. The call $(D multiSort!("a.id < b.id",
 * "a.date > b.date")(r)) sorts the range $(D r) by $(D id) ascending,
 * and sorts elements that have the same $(D id) by $(D date)
 * descending. Such a call is equivalent to $(D sort!"a.id != b.id ? a.id
 * < b.id : a.date > b.date"(r)), but $(D multiSort) is faster because it
 * does fewer comparisons (in addition to being more convenient).
 */
template multiSort(less...) //if (less.length > 1)
{
    void multiSort(Range)(Range r)
    if (validPredicates!(ElementType!Range, less))
    {
        static if (is(typeof(less[$ - 1]) == SwapStrategy))
        {
            enum ss = less[$ - 1];
            alias funs = less[0 .. $ - 1];
        }
        else
        {
            alias ss = SwapStrategy.unstable;
            alias funs = less;
        }
        alias lessFun = binaryFun!(funs[0]);

        static if (funs.length > 1)
        {
            while (r.length > 1)
            {
                auto p = getPivot!lessFun(r);
                auto t = partition3!(less[0], ss)(r, r[p]);
                if (t[0].length <= t[2].length)
                {
                    .multiSort!less(t[0]);
                    .multiSort!(less[1 .. $])(t[1]);
                    r = t[2];
                }
                else
                {
                    .multiSort!(less[1 .. $])(t[1]);
                    .multiSort!less(t[2]);
                    r = t[0];
                }
            }
        }
        else
        {
            sort!(lessFun, ss)(r);
        }
    }
}

///
unittest
{
    static struct Point { int x, y; }
    auto pts1 = [ Point(0, 0), Point(5, 5), Point(0, 1), Point(0, 2) ];
    auto pts2 = [ Point(0, 0), Point(0, 1), Point(0, 2), Point(5, 5) ];
    multiSort!("a.x < b.x", "a.y < b.y", SwapStrategy.unstable)(pts1);
    assert(pts1 == pts2);
}

unittest
{
    static struct Point { int x, y; }
    auto pts1 = [ Point(5, 6), Point(1, 0), Point(5, 7), Point(1, 1), Point(1, 2), Point(0, 1) ];
    auto pts2 = [ Point(0, 1), Point(1, 0), Point(1, 1), Point(1, 2), Point(5, 6), Point(5, 7) ];
    static assert(validPredicates!(Point, "a.x < b.x", "a.y < b.y"));
    multiSort!("a.x < b.x", "a.y < b.y", SwapStrategy.unstable)(pts1);
    assert(pts1 == pts2);

    auto pts3 = indexed(pts1, iota(pts1.length));
    multiSort!("a.x < b.x", "a.y < b.y", SwapStrategy.unstable)(pts3);
    assert(equal(pts3, pts2));
}

unittest //issue 9160 (L-value only comparators)
{
    static struct A
    {
        int x;
        int y;
    }

    static bool byX(const ref A lhs, const ref A rhs)
    {
        return lhs.x < rhs.x;
    }

    static bool byY(const ref A lhs, const ref A rhs)
    {
        return lhs.y < rhs.y;
    }

    auto points = [ A(4, 1), A(2, 4)];
    multiSort!(byX, byY)(points);
    assert(points[0] == A(2, 4));
    assert(points[1] == A(4, 1));
}

private size_t getPivot(alias less, Range)(Range r)
{
    // This algorithm sorts the first, middle and last elements of r,
    // then returns the index of the middle element.  In effect, it uses the
    // median-of-three heuristic.

    alias pred = binaryFun!less;
    immutable len = r.length;
    immutable size_t mid = len / 2;
    immutable uint result =
        ((cast(uint) pred(r[0],   r[mid]    )) << 2) |
        ((cast(uint) pred(r[0],   r[len - 1])) << 1) |
         (cast(uint) pred(r[mid], r[len - 1]));

    switch(result)
    {
        case 0b001:
            swapAt(r, 0, len - 1);
            swapAt(r, 0, mid);
            break;
        case 0b110:
            swapAt(r, mid, len - 1);
            break;
        case 0b011:
            swapAt(r, 0, mid);
            break;
        case 0b100:
            swapAt(r, mid, len - 1);
            swapAt(r, 0, mid);
            break;
        case 0b000:
            swapAt(r, 0, len - 1);
            break;
        case 0b111:
            break;
        default:
            assert(0);
    }

    return mid;
}

private void optimisticInsertionSort(alias less, Range)(Range r)
{
    alias pred = binaryFun!less;
    if (r.length < 2)
        return;

    immutable maxJ = r.length - 1;
    for (size_t i = r.length - 2; i != size_t.max; --i)
    {
        size_t j = i;
        auto temp = r[i];

        for (; j < maxJ && pred(r[j + 1], temp); ++j)
        {
            r[j] = r[j + 1];
        }

        r[j] = temp;
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.random : uniform, Random;

    auto rnd = Random(1);
    int a[] = new int[uniform(100, 200, rnd)];
    foreach (ref e; a)
        e = uniform(-100, 100, rnd);

    optimisticInsertionSort!(binaryFun!("a < b"), int[])(a);
    assert(isSorted(a));
}

//private
void swapAt(R)(R r, size_t i1, size_t i2)
{
    static if (is(typeof(&r[i1])))
    {
        swap(r[i1], r[i2]);
    }
    else
    {
        if (i1 == i2)
            return;
        auto t1 = moveAt(r, i1);
        auto t2 = moveAt(r, i2);
        r[i2] = t1;
        r[i1] = t2;
    }
}

private void quickSortImpl(alias less, Range)(Range r)
{
    enum size_t optimisticInsertionSortGetsBetter = 25;
    static assert(optimisticInsertionSortGetsBetter >= 1);

    // partition
    while (r.length > optimisticInsertionSortGetsBetter)
    {
        const pivotIdx = getPivot!(less)(r);
        auto pivot = r[pivotIdx];

        alias pred = binaryFun!less;

        // partition
        swapAt(r, pivotIdx, r.length - 1);
        size_t lessI = size_t.max, greaterI = r.length - 1;

        while (true)
        {
            while (pred(r[++lessI], pivot)) {}
            while (greaterI > 0 && pred(pivot, r[--greaterI])) {}

            if (lessI >= greaterI)
            {
                break;
            }
            swapAt(r, lessI, greaterI);
        }

        swapAt(r, r.length - 1, lessI);
        auto right = r[lessI + 1 .. r.length];

        auto left = r[0 .. min(lessI, greaterI + 1)];
        if (right.length > left.length)
        {
            swap(left, right);
        }
        .quickSortImpl!(less, Range)(right);
        r = left;
    }
    // residual sort
    static if (optimisticInsertionSortGetsBetter > 1)
    {
        optimisticInsertionSort!(less, Range)(r);
    }
}

/+
    Tim Sort for Random-Access Ranges

    Written and tested for DMD 2.059 and Phobos

    Authors:  Xinok
    License:  Public Domain
+/

// Tim Sort implementation
private template TimSortImpl(alias pred, R)
{
    import core.bitop : bsr;

    static assert(isRandomAccessRange!R);
    static assert(hasLength!R);
    static assert(hasSlicing!R);
    static assert(hasAssignableElements!R);

    alias T = ElementType!R;

    alias less = binaryFun!pred;
    bool greater(T a, T b){ return less(b, a); }
    bool greaterEqual(T a, T b){ return !less(a, b); }
    bool lessEqual(T a, T b){ return !less(b, a); }

    enum minimalMerge = 128;
    enum minimalGallop = 7;
    enum minimalStorage = 256;
    enum stackSize = 40;

    struct Slice
    {
        size_t base, length;
    }

    // Entry point for tim sort
    void sort(R range, T[] temp)
    {
        // Do insertion sort on small range
        if (range.length <= minimalMerge)
        {
            binaryInsertionSort(range);
            return;
        }

        immutable minRun = minRunLength(range.length);
        immutable minTemp = min(range.length / 2, minimalStorage);
        size_t minGallop = minimalGallop;
        Slice[stackSize] stack = void;
        size_t stackLen = 0;

        // Allocate temporary memory if not provided by user
        if (temp.length < minTemp)
        {
            if (__ctfe) temp.length = minTemp;
            else temp = uninitializedArray!(T[])(minTemp);
        }

        for (size_t i = 0; i < range.length; )
        {
            // Find length of first run in list
            size_t runLen = firstRun(range[i .. range.length]);

            // If run has less than minRun elements, extend using insertion sort
            if (runLen < minRun)
            {
                // Do not run farther than the length of the range
                immutable force = range.length - i > minRun ? minRun : range.length - i;
                binaryInsertionSort(range[i .. i + force], runLen);
                runLen = force;
            }

            // Push run onto stack
            stack[stackLen++] = Slice(i, runLen);
            i += runLen;

            // Collapse stack so that (e1 >= e2 + e3 && e2 >= e3)
            // STACK is | ... e1 e2 e3 >
            while (stackLen > 1)
            {
                immutable run3 = stackLen - 1;
                immutable run2 = stackLen - 2;
                immutable run1 = stackLen - 3;
                if (stackLen >= 3 && stack[run1].length <= stack[run2].length + stack[run3].length)
                {
                    immutable at = stack[run1].length <= stack[run3].length
                        ? run1 : run2;
                    mergeAt(range, stack[0 .. stackLen], at, minGallop, temp);
                    --stackLen;
                }
                else if (stack[run2].length <= stack[run3].length)
                {
                    mergeAt(range, stack[0 .. stackLen], run2, minGallop, temp);
                    --stackLen;
                }
                else break;
            }
        }

        // Force collapse stack until there is only one run left
        while (stackLen > 1)
        {
            immutable run3 = stackLen - 1;
            immutable run2 = stackLen - 2;
            immutable run1 = stackLen - 3;
            immutable at = stackLen >= 3 && stack[run1].length <= stack[run3].length
                ? run1 : run2;
            mergeAt(range, stack[0 .. stackLen], at, minGallop, temp);
            --stackLen;
        }
    }

    // Calculates optimal value for minRun:
    // take first 6 bits of n and add 1 if any lower bits are set
    pure size_t minRunLength(size_t n)
    {
        immutable shift = bsr(n) - 5;
        auto result = (n>>shift) + !!(n & ~((1<<shift)-1));
        return result;
    }

    // Returns length of first run in range
    size_t firstRun(R range)
    out(ret)
    {
        assert(ret <= range.length);
    }
    body
    {
        if (range.length < 2)
            return range.length;

        size_t i = 2;
        if (lessEqual(range[0], range[1]))
        {
            while (i < range.length && lessEqual(range[i-1], range[i]))
                ++i;
        }
        else
        {
            while (i < range.length && greater(range[i-1], range[i]))
                ++i;
            reverse(range[0 .. i]);
        }
        return i;
    }

    // A binary insertion sort for building runs up to minRun length
    void binaryInsertionSort(R range, size_t sortedLen = 1)
    out
    {
        if (!__ctfe)
            assert(isSorted!pred(range));
    }
    body
    {
        for (; sortedLen < range.length; ++sortedLen)
        {
            T item = moveAt(range, sortedLen);
            size_t lower = 0;
            size_t upper = sortedLen;
            while (upper != lower)
            {
                size_t center = (lower + upper) / 2;
                if (less(item, range[center]))
                    upper = center;
                else
                    lower = center + 1;
            }
            //Currently (DMD 2.061) moveAll+retro is slightly less
            //efficient then stright 'for' loop
            //11 instructions vs 7 in the innermost loop [checked on Win32]
            //moveAll(retro(range[lower .. sortedLen]),
            //            retro(range[lower+1 .. sortedLen+1]));
            for (upper = sortedLen; upper>lower; upper--)
                range[upper] = moveAt(range, upper-1);
            range[lower] = move(item);
        }
    }

    // Merge two runs in stack (at, at + 1)
    void mergeAt(R range, Slice[] stack, immutable size_t at, ref size_t minGallop, ref T[] temp)
    in
    {
        assert(stack.length >= 2);
        assert(at == stack.length - 2 || at == stack.length - 3);
    }
    body
    {
        immutable base = stack[at].base;
        immutable mid  = stack[at].length;
        immutable len  = stack[at + 1].length + mid;

        // Pop run from stack
        stack[at] = Slice(base, len);
        if (at == stack.length - 3)
            stack[$ - 2] = stack[$ - 1];

        // Merge runs (at, at + 1)
        return merge(range[base .. base + len], mid, minGallop, temp);
    }

    // Merge two runs in a range. Mid is the starting index of the second run.
    // minGallop and temp are references; The calling function must receive the updated values.
    void merge(R range, size_t mid, ref size_t minGallop, ref T[] temp)
    in
    {
        if (!__ctfe)
        {
            assert(isSorted!pred(range[0 .. mid]));
            assert(isSorted!pred(range[mid .. range.length]));
        }
    }
    body
    {
        assert(mid < range.length);

        // Reduce range of elements
        immutable firstElement = gallopForwardUpper(range[0 .. mid], range[mid]);
        immutable lastElement  = gallopReverseLower(range[mid .. range.length], range[mid - 1]) + mid;
        range = range[firstElement .. lastElement];
        mid -= firstElement;

        if (mid == 0 || mid == range.length)
            return;

        // Call function which will copy smaller run into temporary memory
        if (mid <= range.length / 2)
        {
            temp = ensureCapacity(mid, temp);
            minGallop = mergeLo(range, mid, minGallop, temp);
        }
        else
        {
            temp = ensureCapacity(range.length - mid, temp);
            minGallop = mergeHi(range, mid, minGallop, temp);
        }
    }

    // Enlarge size of temporary memory if needed
    T[] ensureCapacity(size_t minCapacity, T[] temp)
    out(ret)
    {
        assert(ret.length >= minCapacity);
    }
    body
    {
        if (temp.length < minCapacity)
        {
            size_t newSize = 1<<(bsr(minCapacity)+1);
            //Test for overflow
            if (newSize < minCapacity)
                newSize = minCapacity;

            if (__ctfe)
                temp.length = newSize;
            else
                temp = uninitializedArray!(T[])(newSize);
        }
        return temp;
    }

    // Merge front to back. Returns new value of minGallop.
    // temp must be large enough to store range[0 .. mid]
    size_t mergeLo(R range, immutable size_t mid, size_t minGallop, T[] temp)
    out
    {
        if (!__ctfe)
            assert(isSorted!pred(range));
    }
    body
    {
        assert(mid <= range.length);
        assert(temp.length >= mid);

        // Copy run into temporary memory
        temp = temp[0 .. mid];
        copy(range[0 .. mid], temp);

        // Move first element into place
        range[0] = range[mid];

        size_t i = 1, lef = 0, rig = mid + 1;
        size_t count_lef, count_rig;
        immutable lef_end = temp.length - 1;

        if (lef < lef_end && rig < range.length)
        {
          outer:
            while (true)
            {
                count_lef = 0;
                count_rig = 0;

                // Linear merge
                while ((count_lef | count_rig) < minGallop)
                {
                    if (lessEqual(temp[lef], range[rig]))
                    {
                        range[i++] = temp[lef++];
                        if (lef >= lef_end)
                            break outer;
                        ++count_lef;
                        count_rig = 0;
                    }
                    else
                    {
                        range[i++] = range[rig++];
                        if (rig >= range.length)
                            break outer;
                        count_lef = 0;
                        ++count_rig;
                    }
                }

                // Gallop merge
                do
                {
                    count_lef = gallopForwardUpper(temp[lef .. $], range[rig]);
                    foreach (j; 0 .. count_lef)
                        range[i++] = temp[lef++];
                    if (lef >= temp.length)
                        break outer;

                    count_rig = gallopForwardLower(range[rig .. range.length], temp[lef]);
                    foreach (j; 0 .. count_rig)
                        range[i++] = range[rig++];
                    if (rig >= range.length)
                    {
                        while(true)
                        {
                            range[i++] = temp[lef++];
                            if (lef >= temp.length)
                                break outer;
                        }
                    }

                    if (minGallop > 0)
                        --minGallop;
                }
                while (count_lef >= minimalGallop || count_rig >= minimalGallop);

                minGallop += 2;
            }
        }

        // Move remaining elements from right
        while (rig < range.length)
            range[i++] = range[rig++];

        // Move remaining elements from left
        while (lef < temp.length)
            range[i++] = temp[lef++];

        return minGallop > 0 ? minGallop : 1;
    }

    // Merge back to front. Returns new value of minGallop.
    // temp must be large enough to store range[mid .. range.length]
    size_t mergeHi(R range, immutable size_t mid, size_t minGallop, T[] temp)
    out
    {
        if (!__ctfe)
            assert(isSorted!pred(range));
    }
    body
    {
        assert(mid <= range.length);
        assert(temp.length >= range.length - mid);

        // Copy run into temporary memory
        temp = temp[0 .. range.length - mid];
        copy(range[mid .. range.length], temp);

        // Move first element into place
        range[range.length - 1] = range[mid - 1];

        size_t i = range.length - 2, lef = mid - 2, rig = temp.length - 1;
        size_t count_lef, count_rig;

        outer:
        while (true)
        {
            count_lef = 0;
            count_rig = 0;

            // Linear merge
            while ((count_lef | count_rig) < minGallop)
            {
                if (greaterEqual(temp[rig], range[lef]))
                {
                    range[i--] = temp[rig];
                    if (rig == 1)
                    {
                        // Move remaining elements from left
                        while (true)
                        {
                            range[i--] = range[lef];
                            if (lef == 0)
                                break;
                            --lef;
                        }

                        // Move last element into place
                        range[i] = temp[0];

                        break outer;
                    }
                    --rig;
                    count_lef = 0;
                    ++count_rig;
                }
                else
                {
                    range[i--] = range[lef];
                    if (lef == 0)
                    {
                        while(true)
                        {
                            range[i--] = temp[rig];
                            if (rig == 0)
                                break outer;
                            --rig;
                        }
                    }
                    --lef;
                    ++count_lef;
                    count_rig = 0;
                }
            }

            // Gallop merge
            do
            {
                count_rig = rig - gallopReverseLower(temp[0 .. rig], range[lef]);
                foreach(j; 0 .. count_rig)
                {
                    range[i--] = temp[rig];
                    if (rig == 0)
                        break outer;
                    --rig;
                }

                count_lef = lef - gallopReverseUpper(range[0 .. lef], temp[rig]);
                foreach(j; 0 .. count_lef)
                {
                    range[i--] = range[lef];
                    if (lef == 0)
                    {
                        while(true)
                        {
                            range[i--] = temp[rig];
                            if (rig == 0)
                                break outer;
                            --rig;
                        }
                    }
                    --lef;
                }

                if (minGallop > 0)
                    --minGallop;
            }
            while (count_lef >= minimalGallop || count_rig >= minimalGallop);

            minGallop += 2;
        }

        return minGallop > 0 ? minGallop : 1;
    }

    // false = forward / lower, true = reverse / upper
    template gallopSearch(bool forwardReverse, bool lowerUpper)
    {
        // Gallop search on range according to attributes forwardReverse and lowerUpper
        size_t gallopSearch(R)(R range, T value)
        out(ret)
        {
            assert(ret <= range.length);
        }
        body
        {
            size_t lower = 0, center = 1, upper = range.length;
            alias gap = center;

            static if (forwardReverse)
            {
                alias comp = Select!(lowerUpper, less, lessEqual);

                // Gallop Search Reverse
                while (gap <= upper)
                {
                    if (comp(value, range[upper - gap]))
                    {
                        upper -= gap;
                        gap *= 2;
                    }
                    else
                    {
                        lower = upper - gap;
                        break;
                    }
                }

                // Binary Search Reverse
                while (upper != lower)
                {
                    center = lower + (upper - lower) / 2;
                    if (comp(value, range[center]))
                        upper = center;
                    else
                        lower = center + 1;
                }
            }
            else
            {
                alias comp = Select!(lowerUpper, greaterEqual, greater);

                // Gallop Search Forward
                while (lower + gap < upper)
                {
                    if (comp(value, range[lower + gap]))
                    {
                        lower += gap;
                        gap *= 2;
                    }
                    else
                    {
                        upper = lower + gap;
                        break;
                    }
                }

                // Binary Search Forward
                while (lower != upper)
                {
                    center = lower + (upper - lower) / 2;
                    if (comp(value, range[center]))
                        lower = center + 1;
                    else
                        upper = center;
                }
            }

            return lower;
        }
    }

    alias gallopForwardLower = gallopSearch!(false, false);
    alias gallopForwardUpper = gallopSearch!(false, true);
    alias gallopReverseLower = gallopSearch!(true, false);
    alias gallopReverseUpper = gallopSearch!(true, true);
}

unittest
{
    import std.random;

    // Element type with two fields
    static struct E
    {
        size_t value, index;
    }

    // Generates data especially for testing sorting with Timsort
    static E[] genSampleData(uint seed)
    {
        auto rnd = Random(seed);

        E[] arr;
        arr.length = 64 * 64;

        // We want duplicate values for testing stability
        foreach (i, ref v; arr)
            v.value = i / 64;

        // Swap ranges at random middle point (test large merge operation)
        immutable mid = uniform(arr.length / 4, arr.length / 4 * 3, rnd);
        swapRanges(arr[0 .. mid], arr[mid .. $]);

        // Shuffle last 1/8 of the array (test insertion sort and linear merge)
        randomShuffle(arr[$ / 8 * 7 .. $], rnd);

        // Swap few random elements (test galloping mode)
        foreach (i; 0 .. arr.length / 64)
        {
            immutable a = uniform(0, arr.length, rnd);
            immutable b = uniform(0, arr.length, rnd);
            swap(arr[a], arr[b]);
        }

        // Now that our test array is prepped, store original index value
        // This will allow us to confirm the array was sorted stably
        foreach (i, ref v; arr)
            v.index = i;

        return arr;
    }

    // Tests the Timsort function for correctness and stability
    static bool testSort(uint seed)
    {
        auto arr = genSampleData(seed);

        // Now sort the array!
        static bool comp(E a, E b)
        {
            return a.value < b.value;
        }

        sort!(comp, SwapStrategy.stable)(arr);

        // Test that the array was sorted correctly
        assert(isSorted!comp(arr));

        // Test that the array was sorted stably
        foreach (i; 0 .. arr.length - 1)
        {
            if (arr[i].value == arr[i + 1].value)
                assert(arr[i].index < arr[i + 1].index);
        }

        return true;
    }

    enum seed = 310614065;
    testSort(seed);

    //@@BUG: Timsort fails with CTFE as of DMD 2.060
    // enum result = testSort(seed);
}

unittest
{
    // bugzilla 4584
    assert(isSorted!"a<b"(sort!("a<b", SwapStrategy.stable)(
       [83, 42, 85, 86, 87, 22, 89, 30, 91, 46, 93, 94, 95, 6,
         97, 14, 33, 10, 101, 102, 103, 26, 105, 106, 107, 6]
    )));
}

unittest
{
    //test stable sort + zip
    auto x = [10, 50, 60, 60, 20];
    dchar[] y = "abcde"d.dup;

    sort!("a[0] < b[0]", SwapStrategy.stable)(zip(x, y));
    assert(x == [10, 20, 50, 60, 60]);
    assert(y == "aebcd"d);
}

/**
 * Sorts a range using an algorithm akin to the $(WEB
 * wikipedia.org/wiki/Schwartzian_transform, Schwartzian transform), also
 * known as the decorate-sort-undecorate pattern in Python and Lisp. (Not
 * to be confused with $(WEB youtube.com/watch?v=UHw6KXbvazs, the other
 * Schwartz).) This function is helpful when the sort comparison includes
 * an expensive computation. The complexity is the same as that of the
 * corresponding $(D sort), but $(D schwartzSort) evaluates $(D
 * transform) only $(D r.length) times (less than half when compared to
 * regular sorting). The usage can be best illustrated with an example.
 *
 * Examples:
 * ----
 * uint hashFun(string) { ... expensive computation ... }
 * string[] array = ...;
 * // Sort strings by hash, slow
 * sort!((a, b) => hashFun(a) < hashFun(b))(array);
 * // Sort strings by hash, fast (only computes arr.length hashes):
 * schwartzSort!(hashFun, "a < b")(array);
 * ----
 *
 * The $(D schwartzSort) function might require less temporary data and
 * be faster than the Perl idiom or the decorate-sort-undecorate idiom
 * present in Python and Lisp. This is because sorting is done in-place
 * and only minimal extra data (one array of transformed elements) is
 * created.
 *
 * To check whether an array was sorted and benefit of the speedup of
 * Schwartz sorting, a function $(D schwartzIsSorted) is not provided
 * because the effect can be achieved by calling $(D
 * isSorted!less(map!transform(r))).
 *
 * Returns: The initial range wrapped as a $(D SortedRange) with the
 * predicate $(D (a, b) => binaryFun!less(transform(a),
 * transform(b))).
 */
SortedRange!(R, ((a, b) => binaryFun!less(unaryFun!transform(a),
                                          unaryFun!transform(b))))
schwartzSort
(alias transform, alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, R)
(R r)
if (isRandomAccessRange!R && hasLength!R)
{
    import core.stdc.stdlib;
    import std.conv : emplace;
    import std.string : representation;

    alias E = typeof(unaryFun!transform(r.front));

    auto xform1 = (cast(E*) malloc(r.length * E.sizeof))[0 .. r.length];
    size_t length;
    scope(exit)
    {
        static if (hasElaborateDestructor!E)
        {
            foreach (i; 0 .. length)
                collectException(destroy(xform1[i]));
        }
        free(xform1.ptr);
    }
    for (; length != r.length; ++length)
    {
        emplace(xform1.ptr + length, unaryFun!transform(r[length]));
    }
    // Make sure we use ubyte[] and ushort[], not char[] and wchar[]
    // for the intermediate array, lest zip gets confused.
    static if (isNarrowString!(typeof(xform1)))
    {
        auto xform = xform1.representation();
    }
    else
    {
        alias xform = xform1;
    }
    zip(xform, r).sort!((a, b) => binaryFun!less(a[0], b[0]), ss)();
    return typeof(return)(r);
}

unittest
{
    // issue 4909
    Tuple!(char)[] chars;
    schwartzSort!"a[0]"(chars);
}

unittest
{
    // issue 5924
    Tuple!(char)[] chars;
    schwartzSort!((Tuple!(char) c){ return c[0]; })(chars);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.math : log2;

    static double entropy(double[] probs)
    {
        double result = 0;
        foreach (p; probs)
        {
            if (!p)
                continue;
            //enforce(p > 0 && p <= 1, "Wrong probability passed to entropy");
            result -= p * log2(p);
        }
        return result;
    }

    auto lowEnt = ([ 1.0, 0, 0 ]).dup,
         midEnt = ([ 0.1, 0.1, 0.8 ]).dup,
         highEnt = ([ 0.31, 0.29, 0.4 ]).dup;
    double arr[][] = new double[][3];
    arr[0] = midEnt;
    arr[1] = lowEnt;
    arr[2] = highEnt;

    schwartzSort!(entropy, q{a > b})(arr);
    assert(arr[0] == highEnt);
    assert(arr[1] == midEnt);
    assert(arr[2] == lowEnt);
    assert(isSorted!("a > b")(map!entropy(arr)));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.math : log2;

    static double entropy(double[] probs)
    {
        double result = 0;
        foreach (p; probs)
        {
            if (!p)
                continue;
            //enforce(p > 0 && p <= 1, "Wrong probability passed to entropy");
            result -= p * log2(p);
        }
        return result;
    }

    auto lowEnt = ([ 1.0, 0, 0 ]).dup,
         midEnt = ([ 0.1, 0.1, 0.8 ]).dup,
         highEnt = ([ 0.31, 0.29, 0.4 ]).dup;
    double arr[][] = new double[][3];
    arr[0] = midEnt;
    arr[1] = lowEnt;
    arr[2] = highEnt;

    schwartzSort!(entropy, q{a < b})(arr);
    assert(arr[0] == lowEnt);
    assert(arr[1] == midEnt);
    assert(arr[2] == highEnt);
    assert(isSorted!("a < b")(map!entropy(arr)));
}

/**
 * Reorders the random-access range $(D r) such that the range $(D r[0
 * .. mid]) is the same as if the entire $(D r) were sorted, and leaves
 * the range $(D r[mid .. r.length]) in no particular order. Performs
 * $(BIGOH r.length * log(mid)) evaluations of $(D pred). The
 * implementation simply calls $(D topN!(less, ss)(r, n)) and then $(D
 * sort!(less, ss)(r[0 .. n])).
 */
void partialSort
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range)
(Range r, size_t n)
if (isRandomAccessRange!Range && hasLength!Range && hasSlicing!Range)
{
    topN!(less, ss)(r, n);
    sort!(less, ss)(r[0 .. n]);
}
///
unittest
{
    int[] a = [ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 ];
    partialSort(a, 5);
    assert(a[0 .. 5] == [ 0, 1, 2, 3, 4 ]);
}

/**
 * Sorts the random-access range $(D chain(lhs, rhs)) according to
 * predicate $(D less). The left-hand side of the range $(D lhs) is
 * assumed to be already sorted; $(D rhs) is assumed to be unsorted. The
 * exact strategy chosen depends on the relative sizes of $(D lhs) and
 * $(D rhs).  Performs $(BIGOH lhs.length + rhs.length * log(rhs.length))
 * (best case) to $(BIGOH (lhs.length + rhs.length) * log(lhs.length +
 * rhs.length)) (worst-case) evaluations of $(D swap).
 */
void completeSort
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range1, Range2)
(SortedRange!(Range1, less) lhs, Range2 rhs)
if (hasLength!Range2 && hasSlicing!Range2)
{
    // Probably this algorithm can be optimized by using in-place
    // merge
    auto lhsOriginal = lhs.release();
    foreach (i; 0 .. rhs.length)
    {
        auto sortedSoFar = chain(lhsOriginal, rhs[0 .. i]);
        auto ub = assumeSorted!less(sortedSoFar).upperBound(rhs[i]);
        if (!ub.length)
            continue;
        bringToFront(ub.release(), rhs[i .. i + 1]);
    }
}

///
unittest
{
    int[] a = [ 1, 2, 3 ];
    int[] b = [ 4, 0, 6, 5 ];
    completeSort(assumeSorted(a), b);
    assert(a == [ 0, 1, 2 ]);
    assert(b == [ 3, 4, 5, 6 ]);
}

/**
 * Checks whether a forward range is sorted according to the comparison
 * operation $(D less). Performs $(BIGOH r.length) evaluations of $(D
 * less).
 */
bool isSorted(alias less = "a < b", Range)(Range r)
if (isForwardRange!Range)
{
    import std.conv : text;

    if (r.empty)
        return true;

    static if (isRandomAccessRange!Range && hasLength!Range)
    {
        immutable limit = r.length - 1;
        foreach (i; 0 .. limit)
        {
            if (!binaryFun!less(r[i + 1], r[i]))
                continue;
            assert(!binaryFun!less(r[i], r[i + 1]),
                   text("Predicate for isSorted is not antisymmetric. Both"
                        " pred(a, b) and pred(b, a) are true for a=", r[i],
                        " and b=", r[i+1], " in positions ", i, " and ",
                        i + 1));
            return false;
        }
    }
    else
    {
        auto ahead = r;
        ahead.popFront();
        size_t i;

        for (; !ahead.empty; ahead.popFront(), r.popFront(), ++i)
        {
            if (!binaryFun!less(ahead.front, r.front))
                continue;
            // Check for antisymmetric predicate
            assert(!binaryFun!less(r.front, ahead.front),
                   text("Predicate for isSorted is not antisymmetric. Both"
                        " pred(a, b) and pred(b, a) are true for a=", r.front,
                        " and b=", ahead.front, " in positions ", i, " and ",
                        i + 1));
            return false;
        }
    }
    return true;
}

///
unittest
{
    int[] arr = [4, 3, 2, 1];
    assert(!isSorted(arr));
    sort(arr);
    assert(isSorted(arr));
    sort!("a > b")(arr);
    assert(isSorted!("a > b")(arr));
}

unittest
{
    import std.conv : to;

    // Issue 9457
    auto x = "abcd";
    assert(isSorted(x));
    auto y = "acbd";
    assert(!isSorted(y));

    int[] a = [1, 2, 3];
    assert(isSorted(a));
    int[] b = [1, 3, 2];
    assert(!isSorted(b));

    dchar[] ds = "コーヒーが好きです"d.dup;
    sort(ds);
    string s = to!string(ds);
    assert(isSorted(ds));  // random-access
    assert(isSorted(s));   // bidirectional
}

/**
 * Computes an index for $(D r) based on the comparison $(D less). The
 * index is a sorted array of pointers or indices into the original
 * range. This technique is similar to sorting, but it is more flexible
 * because (1) it allows "sorting" of immutable collections, (2) allows
 * binary search even if the original collection does not offer random
 * access, (3) allows multiple indexes, each on a different predicate,
 * and (4) may be faster when dealing with large objects. However, using
 * an index may also be slower under certain circumstances due to the
 * extra indirection, and is always larger than a sorting-based solution
 * because it needs space for the index in addition to the original
 * collection. The complexity is the same as $(D sort)'s.
 *
 * The first overload of $(D makeIndex) writes to a range containing
 * pointers, and the second writes to a range containing offsets. The
 * first overload requires $(D Range) to be a forward range, and the
 * latter requires it to be a random-access range.
 *
 * $(D makeIndex) overwrites its second argument with the result, but
 * never reallocates it.
 *
 * Returns: The pointer-based version returns a $(D SortedRange) wrapper
 * over index, of type $(D SortedRange!(RangeIndex, (a, b) =>
 * binaryFun!less(*a, *b))) thus reflecting the ordering of the
 * index. The index-based version returns $(D void) because the ordering
 * relation involves not only $(D index) but also $(D r).
 *
 * Throws: If the second argument's length is less than that of the range
 * indexed, an exception is thrown.

Example:
----
immutable(int[]) arr = [ 2, 3, 1, 5, 0 ];
// index using pointers
auto index1 = new immutable(int)*[arr.length];
makeIndex!("a < b")(arr, index1);
assert(isSorted!("*a < *b")(index1));
// index using offsets
auto index2 = new size_t[arr.length];
makeIndex!("a < b")(arr, index2);
assert(isSorted!
    ((size_t a, size_t b){ return arr[a] < arr[b];})
    (index2));
----
 */
SortedRange!(RangeIndex, (a, b) => binaryFun!less(*a, *b))
makeIndex
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range, RangeIndex)
(Range r, RangeIndex index)
if (isForwardRange!Range &&
    isRandomAccessRange!RangeIndex &&
    is(ElementType!RangeIndex : ElementType!Range*))
{
    import std.exception : enforce;

    // assume collection already ordered
    size_t i;
    for (; !r.empty; r.popFront(), ++i)
        index[i] = &(r.front);
    enforce(index.length == i);
    // sort the index
    sort!((a, b) => binaryFun!less(*a, *b), ss)(index);
    return typeof(return)(index);
}

/// Ditto
void makeIndex
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range, RangeIndex)
(Range r, RangeIndex index)
if (isRandomAccessRange!Range && !isInfinite!Range &&
    isRandomAccessRange!RangeIndex && !isInfinite!RangeIndex &&
    isIntegral!(ElementType!RangeIndex))
{
    import std.exception : enforce;
    import std.conv : to;
    alias IndexType = Unqual!(ElementType!RangeIndex);

    enforce(r.length == index.length,
        "r and index must be same length for makeIndex.");
    static if (IndexType.sizeof < size_t.sizeof)
    {
        enforce(r.length <= IndexType.max,
            "Cannot create an index" ~
            " with element type " ~ IndexType.stringof ~
            " with length " ~ to!string(r.length) ~ ".");
    }

    for (IndexType i = 0; i < r.length; ++i)
    {
        index[cast(size_t) i] = i;
    }

    // sort the index
    sort!((a, b) => binaryFun!less(r[cast(size_t) a], r[cast(size_t) b]), ss)(index);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    immutable(int)[] arr = [ 2, 3, 1, 5, 0 ];
    // index using pointers
    auto index1 = new immutable(int)*[arr.length];
    alias ImmRange = typeof(arr);
    alias ImmIndex = typeof(index1);
    static assert(isForwardRange!ImmRange);
    static assert(isRandomAccessRange!ImmIndex);
    static assert(!isIntegral!(ElementType!ImmIndex));
    static assert(is(ElementType!ImmIndex : ElementType!ImmRange*));
    makeIndex!("a < b")(arr, index1);
    assert(isSorted!("*a < *b")(index1));

    // index using offsets
    auto index2 = new long[arr.length];
    makeIndex(arr, index2);
    assert(isSorted!((long a, long b) => arr[cast(size_t) a] < arr[cast(size_t) b])(index2));

    // index strings using offsets
    string[] arr1 = ["I", "have", "no", "chocolate"];
    auto index3 = new byte[arr1.length];
    makeIndex(arr1, index3);
    assert(isSorted!((byte a, byte b) => arr1[a] < arr1[b])(index3));
}

/**
 * Specifies whether the output of certain algorithm is desired in sorted
 * format.
 */
enum SortOutput
{
    no,  /// Don't sort output
    yes, /// Sort output
}

void topNIndex
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range, RangeIndex)
(Range r, RangeIndex index, SortOutput sorted = SortOutput.no)
if (isIntegral!(ElementType!RangeIndex))
{
    import std.exception : enforce;
    import std.container : BinaryHeap;
    alias E = ElementType!RangeIndex;

    if (index.empty)
        return;

    enforce(E.max >= index.length, "Index type too small");

    bool indirectLess(E a, E b)
    {
        return binaryFun!less(r[a], r[b]);
    }
    auto heap = BinaryHeap!(RangeIndex, indirectLess)(index, 0);
    foreach (i; 0 .. r.length)
    {
        heap.conditionalInsert(cast(E) i);
    }
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty)
            heap.removeFront();
    }
}

void topNIndex
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range, RangeIndex)
(Range r, RangeIndex index, SortOutput sorted = SortOutput.no)
if (is(ElementType!RangeIndex == ElementType!Range*))
{
    import std.container : BinaryHeap;
    alias E = ElementType!RangeIndex;

    if (index.empty)
        return;
    static bool indirectLess(const E a, const E b)  // TODO: static is not good?
    {
        return binaryFun!less(*a, *b);
    }
    auto heap = BinaryHeap!(RangeIndex, indirectLess)(index, 0);
    foreach (i; 0 .. r.length)
    {
        heap.conditionalInsert(&r[i]);
    }
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty)
            heap.removeFront();
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    {
        int[] a = [ 10, 8, 9, 2, 4, 6, 7, 1, 3, 5 ];
        int*[] b = new int*[5];
        topNIndex!("a > b")(a, b, SortOutput.yes);
        //foreach (e; b) writeln(*e);
        assert(b == [ &a[0], &a[2], &a[1], &a[6], &a[5]]);
    }
    {
        int[] a = [ 10, 8, 9, 2, 4, 6, 7, 1, 3, 5 ];
        auto b = new ubyte[5];
        topNIndex!("a > b")(a, b, SortOutput.yes);
        //foreach (e; b) writeln(e, ":", a[e]);
        assert(b == [ cast(ubyte) 0, cast(ubyte)2, cast(ubyte)1, cast(ubyte)6, cast(ubyte)5 ]);
    }
}

/+
// @@@BUG1904
/*private*/
void topNIndexImpl
(alias less, bool sortAfter, SwapStrategy ss, SRange, TRange)
(SRange source, TRange target)
{
    import std.exception : enforce;

    alias lessFun = binaryFun!less;
    static assert(ss == SwapStrategy.unstable,
            "Stable indexing not yet implemented");
    alias SIter = Iterator!SRange;
    alias TElem = std.iterator.ElementType!TRange;
    enum usingInt = isIntegral!TElem;

    static if (usingInt)
    {
        enforce(source.length <= TElem.max,
                "Numeric overflow at risk in computing topNIndexImpl");
    }

    // types and functions used within
    SIter index2iter(TElem a)
    {
        static if (!usingInt)
            return a;
        else
            return begin(source) + a;
    }
    bool indirectLess(TElem a, TElem b)
    {
        return lessFun(*index2iter(a), *index2iter(b));
    }
    void indirectCopy(SIter from, ref TElem to)
    {
        static if (!usingInt)
            to = from;
        else
            to = cast(TElem)(from - begin(source));
    }

    // copy beginning of collection into the target
    auto sb = begin(source), se = end(source),
         tb = begin(target), te = end(target);
    for (; sb != se; ++sb, ++tb)
    {
        if (tb == te)
            break;
        indirectCopy(sb, *tb);
    }

    // if the index's size is same as the source size, just quicksort it
    // otherwise, heap-insert stuff in it.
    if (sb == se)
    {
        // everything in source is now in target... just sort the thing
        static if (sortAfter)
        {
            sort!(indirectLess, ss)(target);
        }
    }
    else
    {
        // heap-insert
        te = tb;
        tb = begin(target);
        target = range(tb, te);
        makeHeap!indirectLess(target);
        // add stuff to heap
        for (; sb != se; ++sb)
        {
            if (!lessFun(*sb, *index2iter(*tb)))
                continue;
            // copy the source over the smallest
            indirectCopy(sb, *tb);
            heapify!indirectLess(target, tb);
        }
        static if (sortAfter)
        {
            sortHeap!indirectLess(target);
        }
    }
}

/**
 * topNIndex
 */
void topNIndex
(alias less, SwapStrategy ss = SwapStrategy.unstable, SRange, TRange)
(SRange source, TRange target)
{
    return .topNIndexImpl!(binaryFun!less, false, ss)(source, target);
}

// partialIndex
/**
 * Computes an index for $(D source) based on the comparison $(D less)
 * and deposits the result in $(D target). It is acceptable that $(D
 * target.length < source.length), in which case only the smallest $(D
 * target.length) elements in $(D source) get indexed. The target
 * provides a sorted "view" into $(D source). This technique is similar
 * to sorting and partial sorting, but it is more flexible because (1) it
 * allows "sorting" of immutable collections, (2) allows binary search
 * even if the original collection does not offer random access, (3)
 * allows multiple indexes, each on a different comparison criterion, (4)
 * may be faster when dealing with large objects. However, using an index
 * may also be slower under certain circumstances due to the extra
 * indirection, and is always larger than a sorting-based solution
 * because it needs space for the index in addition to the original
 * collection. The complexity is $(BIGOH source.length *
 * log(target.length)).
 *
 * Two types of indexes are accepted. They are selected by simply passing
 * the appropriate $(D target) argument: $(OL $(LI Indexes of type $(D
 * Iterator!(Source)), in which case the index will be sorted with the
 * predicate $(D less(*a, *b));) $(LI Indexes of an integral type
 * (e.g. $(D size_t)), in which case the index will be sorted with the
 * predicate $(D less(source[a], source[b])).))

Example:
----
immutable arr = [ 2, 3, 1 ];
int* index[3];
partialIndex(arr, index);
assert(*index[0] == 1 && *index[1] == 2 && *index[2] == 3);
assert(isSorted!("*a < *b")(index));
----
 */
void partialIndex
(alias less, SwapStrategy ss = SwapStrategy.unstable, SRange, TRange)
(SRange source, TRange target)
{
    return .topNIndexImpl!(less, true, ss)(source, target);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    immutable arr = [ 2, 3, 1 ];
    auto index = new immutable(int)*[3];
    partialIndex!("a < b")(arr, index);
    assert(*index[0] == 1 && *index[1] == 2 && *index[2] == 3);
    assert(isSorted!("*a < *b")(index));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    static bool less(int a, int b) { return a < b; }

    {
        string[] x = ([ "c", "a", "b", "d" ]).dup;
        // test with integrals
        auto index1 = new size_t[x.length];
        partialIndex!(q{a < b})(x, index1);
        assert(index1[0] == 1 &&
               index1[1] == 2 &&
               index1[2] == 0 &&
               index1[3] == 3);
        // half-sized
        index1 = new size_t[x.length / 2];
        partialIndex!(q{a < b})(x, index1);
        assert(index1[0] == 1 &&
               index1[1] == 2);

        // and with iterators
        auto index = new string*[x.length];
        partialIndex!(q{a < b})(x, index);
        assert(isSorted!(q{*a < *b})(index));
        assert(*index[0] == "a" &&
               *index[1] == "b" &&
               *index[2] == "c" &&
               *index[3] == "d");
    }

    {
        immutable arr = [ 2, 3, 1 ];
        auto index = new immutable(int)*[arr.length];
        partialIndex!(less)(arr, index);
        assert(*index[0] == 1 &&
               *index[1] == 2 &&
               *index[2] == 3);
        assert(isSorted!(q{*a < *b})(index));
    }

    // random data
    auto b = rndstuff!(string)();
    auto index = new string*[b.length];
    partialIndex!("std.uni.toUpper(a) < std.uni.toUpper(b)")(b, index);
    assert(isSorted!("std.uni.toUpper(*a) < std.uni.toUpper(*b)")(index));

    // random data with indexes
    auto index1 = new size_t[b.length];
    bool cmp(string x, string y) { return std.uni.toUpper(x) < std.uni.toUpper(y); }
    partialIndex!(cmp)(b, index1);
    bool check(size_t x, size_t y) { return std.uni.toUpper(b[x]) < std.uni.toUpper(b[y]); }
    assert(isSorted!(check)(index1));
}

// Commented out for now, needs reimplementation

// // schwartzMakeIndex
// /**
// Similar to $(D makeIndex) but using $(D schwartzSort) to sort the
// index.

// Example:

// ----
// string[] arr = [ "ab", "c", "Ab", "C" ];
// auto index = schwartzMakeIndex!(toUpper, less, SwapStrategy.stable)(arr);
// assert(*index[0] == "ab" && *index[1] == "Ab"
//     && *index[2] == "c" && *index[2] == "C");
// assert(isSorted!("toUpper(*a) < toUpper(*b)")(index));
// ----
// */
// Iterator!(Range)[] schwartzMakeIndex(
//     alias transform,
//     alias less,
//     SwapStrategy ss = SwapStrategy.unstable,
//     Range)(Range r)
// {
//     alias Iterator!(Range) Iter;
//     auto result = new Iter[r.length];
//     // assume collection already ordered
//     size_t i = 0;
//     foreach (it; begin(r) .. end(r))
//     {
//         result[i++] = it;
//     }
//     // sort the index
//     alias typeof(transform(*result[0])) Transformed;
//     static bool indirectLess(Transformed a, Transformed b)
//     {
//         return less(a, b);
//     }
//     static Transformed indirectTransform(Iter a)
//     {
//         return transform(*a);
//     }
//     schwartzSort!(indirectTransform, less, ss)(result);
//     return result;
// }

// /// Ditto
// Iterator!(Range)[] schwartzMakeIndex(
//     alias transform,
//     string less = q{a < b},
//     SwapStrategy ss = SwapStrategy.unstable,
//     Range)(Range r)
// {
//     return .schwartzMakeIndex!(
//         transform, binaryFun!(less), ss, Range)(r);
// }

// version (wyda) unittest
// {
//     string[] arr = [ "D", "ab", "c", "Ab", "C" ];
//     auto index = schwartzMakeIndex!(toUpper, "a < b",
//                                     SwapStrategy.stable)(arr);
//     assert(isSorted!(q{toUpper(*a) < toUpper(*b)})(index));
//     assert(*index[0] == "ab" && *index[1] == "Ab"
//            && *index[2] == "c" && *index[3] == "C");

//     // random data
//     auto b = rndstuff!(string)();
//     auto index1 = schwartzMakeIndex!(toUpper)(b);
//     assert(isSorted!("toUpper(*a) < toUpper(*b)")(index1));
// }

+/


/**
 * Copies the top $(D n) elements of the input range $(D source) into the
 * random-access range $(D target), where $(D n =
 * target.length). Elements of $(D source) are not touched. If $(D
 * sorted) is $(D true), the target is sorted. Otherwise, the target
 * respects the $(WEB en.wikipedia.org/wiki/Binary_heap, heap property).
 */
TRange topNCopy(alias less = "a < b", SRange, TRange)
(SRange source, TRange target, SortOutput sorted = SortOutput.no)
if (isInputRange!SRange &&
    isRandomAccessRange!TRange && hasLength!TRange && hasSlicing!TRange)
{
    import std.container : BinaryHeap;

    if (target.empty)
        return target;

    auto heap = BinaryHeap!(TRange, less)(target, 0);
    foreach (e; source)
        heap.conditionalInsert(e);

    auto result = target[0 .. heap.length];
    if (sorted == SortOutput.yes)
    {
        while (!heap.empty)
            heap.removeFront();
    }
    return result;
}

///
unittest
{
    int[] a = [ 10, 16, 2, 3, 1, 5, 0 ];
    int[] b = new int[3];
    topNCopy(a, b, SortOutput.yes);
    assert(b == [ 0, 1, 2 ]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.random : unpredictableSeed, Random, uniform, randomShuffle;

    auto r = Random(unpredictableSeed);
    ptrdiff_t[] a = new ptrdiff_t[uniform(1, 1000, r)];
    foreach (i, ref e; a)
        e = i;
    randomShuffle(a, r);
    auto n = uniform(0, a.length, r);
    ptrdiff_t[] b = new ptrdiff_t[n];
    topNCopy!("a < b")(a, b, SortOutput.yes);
    assert(isSorted!("a < b")(b));
}

