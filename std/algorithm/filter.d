module std.algorithm.filter;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;

version(unittest)
{
}

/**
 * $(D auto filter(Range)(Range rs) if (isInputRange!(Unqual!Range));)
 *
 * Implements the homonym function present in various programming
 * languages of functional flavor. The call $(D filter!(predicate)(range))
 * returns a new range only containing elements $(D x) in $(D range) for
 * which $(D predicate(x)) is $(D true).
 */
unittest
{
    int[] arr = [ 1, 2, 3, 4, 5 ];

    // Sum all elements
    auto small = filter!(a => a < 3)(arr);
    assert(equal(small, [ 1, 2 ]));

    // Sum again, but with Uniform Function Call Syntax (UFCS)
    auto sum = arr.filter!(a => a < 3)();
    assert(equal(sum, [ 1, 2 ]));

    // In combination with chain() to span multiple ranges
    int[] a = [ 3, -2, 400 ];
    int[] b = [ 100, -101, 102 ];
    auto r = chain(a, b).filter!(a => a > 0)();
    assert(equal(r, [ 3, 400, 100, 102 ]));

    // Mixing convertible types is fair game, too
    double[] c = [ 2.5, 3.0 ];
    auto r1 = chain(c, a, b).filter!(a => cast(int) a != a)();
    assert(approxEqual(r1, [ 2.5 ]));
}
///
template filter(alias pred) if (is(typeof(unaryFun!pred)))
{
    ///
    auto filter(Range)(Range rs) if (isInputRange!(Unqual!Range))
    {
        return FilterResult!(unaryFun!pred, Range)(rs);
    }
}

private struct FilterResult(alias pred, Range)
{
    alias R = Unqual!Range;
    R _input;

    this(R r)
    {
        _input = r;
        while (!_input.empty && !pred(_input.front))
        {
            _input.popFront();
        }
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;
    }
    else
    {
        @property bool empty() { return _input.empty; }
    }

    @property auto ref front()
    {
        return _input.front;
    }

    void popFront()
    {
        do
        {
            _input.popFront();
        } while (!_input.empty && !pred(_input.front));
    }

    static if (isForwardRange!R)
    {
        @property auto save()
        {
            return typeof(this)(_input);
        }
    }

    auto opSlice() { return this; }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 3, 4, 2 ];
    auto r = filter!("a > 3")(a);
    static assert(isForwardRange!(typeof(r)));
    assert(equal(r, [ 4 ]));

    a = [ 1, 22, 3, 42, 5 ];
    auto under10 = filter!("a < 10")(a);
    assert(equal(under10, [1, 3, 5]));
    static assert(isForwardRange!(typeof(under10)));
    under10.front = 4;
    assert(equal(under10, [4, 3, 5]));
    under10.front = 40;
    assert(equal(under10, [40, 3, 5]));
    under10.front = 1;

    auto infinite = filter!"a > 2"(repeat(3));
    static assert(isInfinite!(typeof(infinite)));
    static assert(isForwardRange!(typeof(infinite)));

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        DummyType d;
        auto f = filter!"a & 1"(d);
        assert(equal(f, [1,3,5,7,9]));

        static if (isForwardRange!DummyType)
        {
            static assert(isForwardRange!(typeof(f)));
        }
    }

    // With delegates
    int x = 10;
    int overX(int a) { return a > x; }
    typeof(filter!overX(a)) getFilter()
    {
        return filter!overX(a);
    }
    auto r1 = getFilter();
    assert(equal(r1, [22, 42]));

    // With chain
    auto nums = [0,1,2,3,4];
    assert(equal(filter!overX(chain(a, nums)), [22, 42]));

    // With copying of inner struct Filter to Map
    auto arr = [1,2,3,4,5];
    auto m = map!"a + 1"(filter!"a < 4"(arr));
}

unittest
{
    int[] a = [ 3, 4 ];
    const aConst = a;
    auto r = filter!("a > 3")(aConst);
    assert(equal(r, [ 4 ]));

    a = [ 1, 22, 3, 42, 5 ];
    auto under10 = filter!("a < 10")(a);
    assert(equal(under10, [1, 3, 5]));
    assert(equal(under10.save, [1, 3, 5]));
    assert(equal(under10.save, under10));

    // With copying of inner struct Filter to Map
    auto arr = [1,2,3,4,5];
    auto m = map!"a + 1"(filter!"a < 4"(arr));
}

unittest
{
    assert(equal(compose!(map!"2 * a", filter!"a & 1")([1, 2, 3,4, 5]), [2, 6, 10]));
    assert(equal(pipe!(filter!"a & 1", map!"2 * a")([1, 2, 3, 4, 5]), [2, 6, 10]));
}

unittest
{
    int x = 10;
    int underX(int a) { return a < x; }
    const(int)[] list = [ 1, 2, 10, 11, 3, 4 ];
    assert(equal(filter!underX(list), [ 1, 2, 3, 4 ]));
}

/**
 * $(D auto filterBidirectional(Range)(Range r) if (isBidirectionalRange!(Unqual!Range));)
 *
 * Similar to $(D filter), except it defines a bidirectional
 * range. There is a speed disadvantage - the constructor spends time
 * finding the last element in the range that satisfies the filtering
 * condition (in addition to finding the first one). The advantage is
 * that the filtered range can be spanned from both directions. Also,
 * $(XREF range, retro) can be applied against the filtered range.
 */
unittest
{
    int[] arr = [ 1, 2, 3, 4, 5 ];
    auto small = filterBidirectional!("a < 3")(arr);
    assert(small.back == 2);
    assert(equal(small, [ 1, 2 ]));
    assert(equal(retro(small), [ 2, 1 ]));

    // In combination with chain() to span multiple ranges
    int[] a = [ 3, -2, 400 ];
    int[] b = [ 100, -101, 102 ];
    auto r = filterBidirectional!("a > 0")(chain(a, b));
    assert(r.back == 102);
}
///
template filterBidirectional(alias pred)
{
    auto filterBidirectional(Range)(Range r) if (isBidirectionalRange!(Unqual!Range))
    {
        return FilterBidiResult!(unaryFun!pred, Range)(r);
    }
}

private struct FilterBidiResult(alias pred, Range)
{
    alias R = Unqual!Range;
    R _input;

    this(R r)
    {
        _input = r;
        while (!_input.empty && !pred(_input.front))
            _input.popFront();
        while (!_input.empty && !pred(_input.back))
            _input.popBack();
    }

    @property bool empty() { return _input.empty; }

    @property auto ref front()
    {
        return _input.front;
    }

    void popFront()
    {
        do
        {
            _input.popFront();
        } while (!_input.empty && !pred(_input.front));
    }

    @property auto save()
    {
        return typeof(this)(_input.save);
    }

    @property auto ref back()
    {
        return _input.back;
    }

    void popBack()
    {
        do
        {
            _input.popBack();
        } while (!_input.empty && !pred(_input.back));
    }
}
