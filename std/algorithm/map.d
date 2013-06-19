module std.algorithm.map;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;

/**
 * $(D auto map(Range)(Range r) if (isInputRange!(Unqual!Range));)
 *
 * Implements the homonym function (also known as $(D transform)) present
 * in many languages of functional flavor. The call $(D map!fun(range))
 * returns a range of which elements are obtained by applying $(D fun(x))
 * left to right for all $(D x) in $(D range). The original ranges are
 * not changed. Evaluation is done lazily.
 */
template map(fun...) if (fun.length >= 1)
{
    ///
    auto map(Range)(Range r)
    if (isInputRange!(Unqual!Range))
    {
        static if (fun.length > 1)
        {
            alias _fun = adjoin!(staticMap!(unaryFun, fun));
        }
        else
        {
            alias _fun = unaryFun!fun;
        }

        return MapResult!(_fun, Range)(r);
    }
}
/**
 */
unittest
{
    int[] arr1 = [ 1, 2, 3, 4 ];
    int[] arr2 = [ 5, 6 ];
    auto squares = map!(a => a * a)(chain(arr1, arr2));
    assert(equal(squares, [ 1, 4, 9, 16, 25, 36 ]));
}
/**
 * Multiple functions can be passed to $(D map). In that case, the
 * element type of $(D map) is a tuple containing one element for each
 * function.
 */
unittest
{
    import std.stdio;
    auto arr1 = [ 1, 2, 3, 4 ];
    uint i;
    foreach (e; map!("a + a", "a * a")(arr1))
    {
        ++i;
        assert(e[0] == i * 2);
        assert(e[1] == i * i);
        //writeln(e[0], " ", e[1]);
    }
}
/**
 * You may alias $(D map) with some function(s) to a symbol and use
 * it separately:
 */
unittest
{
    import std.conv;
    alias stringize = map!(to!string);
    assert(equal(stringize([ 1, 2, 3, 4 ]), [ "1", "2", "3", "4" ]));
}

private struct MapResult(alias fun, Range)
{
    alias R = Unqual!Range;

    R _input;

    this(R input)
    {
        _input = input;
    }

    static if (isInfinite!R)
    {
        // Propagate infinite-ness.
        enum bool empty = false;
    }
    else
    {
        @property bool empty()
        {
            return _input.empty;
        }
    }

    @property auto ref front()
    {
        return fun(_input.front);
    }

    void popFront()
    {
        _input.popFront();
    }

    static if (isForwardRange!R)
    {
        @property auto save()
        {
            auto result = this;
            result._input = result._input.save;
            return result;
        }
    }

    static if (isBidirectionalRange!R)
    {
        @property auto ref back()
        {
            return fun(_input.back);
        }

        void popBack()
        {
            _input.popBack();
        }
    }

    static if (isRandomAccessRange!R)
    {
        static if (is(typeof(_input[ulong.max])))
            private alias opIndex_t = ulong;
        else
            private alias opIndex_t = uint;

        auto ref opIndex(opIndex_t index)
        {
            return fun(_input[index]);
        }
    }

    static if (hasLength!R || isSomeString!R)
    {
        @property auto length()
        {
            return _input.length;
        }

        alias opDollar = length;
    }

    static if (!isInfinite!R && hasSlicing!R)
    {
        static if (is(typeof(_input[ulong.max .. ulong.max])))
            private alias opSlice_t = ulong;
        else
            private alias opSlice_t = uint;

        auto opSlice(opSlice_t lowerBound, opSlice_t upperBound)
        {
            return typeof(this)(_input[lowerBound .. upperBound]);
        }
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    uint counter;
    alias count = map!(a => counter++);
    assert(equal(count([10, 2, 30, 4]), [0, 1, 2, 3]));

    counter = 0;
    adjoin!(a => counter++, a => counter++)(1);

    alias countAndSquare = map!(a => counter++, a => counter++);
    //assert(equal(countAndSquare([ 10, 2 ]), [ tuple(0u, 100), tuple(1u, 4) ]));
}

unittest
{
    import std.ascii;

    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] arr1 = [1, 2, 3, 4];
    int[] arr2 = [ 5, 6 ];
    const int[] arr1Const = arr1;
    auto squares = map!("a * a")(arr1Const);
    assert(squares[$ - 1] == 16);
    assert(equal(squares, [1, 4, 9, 16]));

    // Test the caching stuff.
    assert(squares.back == 16);
    auto squares2 = squares.save;
    assert(squares2.back == 16);

    assert(squares2.front == 1);
    squares2.popFront();
    assert(squares2.front == 4);
    squares2.popBack();
    assert(squares2.front == 4);
    assert(squares2.back == 9);

    // Test length.
    assert(squares.length == 4);
    assert(map!"a * a"(chain(arr1, arr2)).length == 6);

    // Test indexing.
    assert(squares[0] == 1);
    assert(squares[1] == 4);
    assert(squares[2] == 9);
    assert(squares[3] == 16);

    // Test slicing.
    auto squareSlice = squares[1 .. squares.length - 1];
    assert(equal(squareSlice, [4, 9]));
    assert(squareSlice.back == 9);
    assert(squareSlice[1] == 9);

    // Test on a forward range to make sure it compiles when all the fancy
    // stuff is disabled.
    auto fibsSquares = map!"a * a"(recurrence!("a[n-1] + a[n-2]")(1, 1));
    assert(fibsSquares.front == 1);
    fibsSquares.popFront();
    fibsSquares.popFront();
    assert(fibsSquares.front == 4);
    fibsSquares.popFront();
    assert(fibsSquares.front == 9);

    auto repeatMap = map!"a"(repeat(1));
    static assert(isInfinite!(typeof(repeatMap)));

    auto intRange = map!"a"([1,2,3]);
    static assert(isRandomAccessRange!(typeof(intRange)));

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        DummyType d;
        auto m = map!"a * a"(d);

        static assert(propagatesRangeType!(typeof(m), DummyType));
        assert(equal(m, [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]));
    }

    //Test string access
    string  s1 = "hello world!";
    dstring s2 = "日本語";
    dstring s3 = "hello world!"d;
    auto ms1 = map!(std.ascii.toUpper)(s1);
    auto ms2 = map!(std.ascii.toUpper)(s2);
    auto ms3 = map!(std.ascii.toUpper)(s3);
    static assert(!is(ms1[0])); //narrow strings can't be indexed
    assert(ms2[0] == '日');
    assert(ms3[0] == 'H');
    static assert(!is(ms1[0 .. 1])); //narrow strings can't be sliced
    assert(equal(ms2[0 .. 2], "日本"w));
    assert(equal(ms3[0 .. 2], "HE"));
}
unittest
{
    auto LL = iota(1L, 4L);
    auto m = map!"a*a"(LL);
    assert(equal(m, [1L, 4L, 9L]));
}

unittest
{
    // Issue #10130 - map of iota with const step.
    const step = 2;
    static assert(__traits(compiles, map!(i => i)(iota(0, 10, step))));

    // Need these to all by const to repro the float case, due to the
    // CommonType template used in the float specialization of iota.
    const floatBegin = 0.0;
    const floatEnd = 1.0;
    const floatStep = 0.02;
    static assert(__traits(compiles, map!(i => i)(iota(floatBegin, floatEnd, floatStep))));
}
