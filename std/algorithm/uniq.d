module std.algorithm.uniq;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
}

/**
 * Iterates unique consecutive elements of the given range (functionality
 * akin to the $(WEB wikipedia.org/wiki/_Uniq, _uniq) system
 * utility). Equivalence of elements is assessed by using the predicate
 * $(D pred), by default $(D "a == b"). If the given range is
 * bidirectional, $(D uniq) also yields a bidirectional range.
 */
auto uniq(alias pred = "a == b", Range)(Range r)
if (isInputRange!Range &&
    is(typeof(binaryFun!pred(r.front, r.front)) == bool))
{
    return UniqResult!(binaryFun!pred, Range)(r);
}

private struct UniqResult(alias pred, Range)
{
    Range _input;

    this(Range input)
    {
        _input = input;
    }

    auto opSlice()
    {
        return this;
    }

    void popFront()
    {
        auto last = _input.front;
        do
        {
            _input.popFront();
        }
        while (!_input.empty && pred(last, _input.front));
    }

    @property ElementType!Range front() { return _input.front; }

    static if (isBidirectionalRange!Range)
    {
        void popBack()
        {
            auto last = _input.back;
            do
            {
                _input.popBack();
            }
            while (!_input.empty && pred(last, _input.back));
        }

        @property ElementType!Range back() { return _input.back; }
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty() { return _input.empty; }
    }

    static if (isForwardRange!Range) {
        @property typeof(this) save() {
            return typeof(this)(_input.save);
        }
    }
}

///
unittest
{
    int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
    assert(equal(uniq(arr), [ 1, 2, 3, 4, 5 ]));
}
unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        DummyType d;
        auto u = uniq(d);
        assert(equal(u, [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]));

        static assert(d.rt == RangeType.Input || isForwardRange!(typeof(u)));

        static if (d.rt >= RangeType.Bidi)
        {
            assert(equal(retro(u), [ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 ]));
        }
    }
}

/*
 * Reduces $(D r) by shifting it to the left until no adjacent elements
 * $(D a), $(D b) remain in $(D r) such that $(D pred(a, b)). Shifting is
 * performed by evaluating $(D move(source, target)) as a primitive. The
 * algorithm is stable and runs in $(BIGOH r.length) time. Returns the
 * reduced range.
 *
 * The default $(XREF _algorithm, move) performs a potentially
 * destructive assignment of $(D source) to $(D target), so the objects
 * beyond the returned range should be considered "empty". By default $(D
 * pred) compares for equality, in which case $(D overwriteAdjacent)
 * collapses adjacent duplicate elements to one (functionality akin to
 * the $(WEB wikipedia.org/wiki/Uniq, uniq) system utility).
 *
 * Example:
 * ----
 * int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
 * auto r = overwriteAdjacent(arr);
 * assert(r == [ 1, 2, 3, 4, 5 ]);
 * ----
 */
// Range overwriteAdjacent(alias pred, alias move, Range)(Range r)
// {
//     if (r.empty) return r;
//     //auto target = begin(r), e = end(r);
//     auto target = r;
//     auto source = r;
//     source.popFront();
//     while (!source.empty)
//     {
//         if (!pred(target.front, source.front))
//         {
//             target.popFront();
//             continue;
//         }
//         // found an equal *source and *target
//         for (;;)
//         {
//             //@@@
//             //move(source.front, target.front);
//             target[0] = source[0];
//             source.popFront();
//             if (source.empty) break;
//             if (!pred(target.front, source.front)) target.popFront();
//         }
//         break;
//     }
//     return range(begin(r), target + 1);
// }

// /// Ditto
// Range overwriteAdjacent(
//     string fun = "a == b",
//     alias move = .move,
//     Range)(Range r)
// {
//     return .overwriteAdjacent!(binaryFun!(fun), move, Range)(r);
// }

// unittest
// {
//     int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
//     auto r = overwriteAdjacent(arr);
//     assert(r == [ 1, 2, 3, 4, 5 ]);
//     assert(arr == [ 1, 2, 3, 4, 5, 3, 4, 4, 4, 5 ]);
// }
