// Written in the D programming language.

module std.algorithm.iteration;
//debug = std_algorithm;

import std.algorithm;
import std.range, std.traits;
import std.functional : unaryFun, binaryFun, adjoin;
import std.typecons : Tuple, tuple;
import std.typetuple : TypeTuple, staticMap;


/**
 * $(D auto map(Range)(Range r) if (isInputRange!(Unqual!Range));)
 *
 * Implements the homonym function (also known as $(D transform)) present
 * in many languages of functional flavor. The call $(D map!fun(range))
 * returns a range of which elements are obtained by applying $(D fun(x))
 * left to right for all $(D x) in $(D range). The original ranges are
 * not changed. Evaluation is done lazily.
 *
 * Examples:
 * ----
 * int[] arr1 = [ 1, 2, 3, 4 ];
 * int[] arr2 = [ 5, 6 ];
 * auto squares = map!(a => a * a)(chain(arr1, arr2));
 * assert(equal(squares, [ 1, 4, 9, 16, 25, 36 ]));
 * ----
 *
 * Multiple functions can be passed to $(D map). In that case, the
 * element type of $(D map) is a tuple containing one element for each
 * function.
 *
 * Examples:
 * ----
 * auto arr1 = [ 1, 2, 3, 4 ];
 * foreach (e; map!("a + a", "a * a")(arr1))
 * {
 *     writeln(e[0], " ", e[1]);
 * }
 * ----
 *
 * You may alias $(D map) with some function(s) to a symbol and use
 * it separately:
 *
 * ----
 * alias map!(to!string) stringize;
 * assert(equal(stringize([ 1, 2, 3, 4 ]), [ "1", "2", "3", "4" ]));
 * ----
 */
template map(fun...) if (fun.length >= 1)
{
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

unittest
{
    int[] arr1 = [ 1, 2, 3, 4 ];
    int[] arr2 = [ 5, 6 ];
    auto squares = map!(a => a * a)(chain(arr1, arr2));
    assert(equal(squares, [ 1, 4, 9, 16, 25, 36 ]));
}

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

    static if (hasLength!R)
    {
        @property auto length()
        {
            return _input.length;
        }

        alias opDollar = length;
    }

    static if (hasSlicing!R)
    {
        static if (is(typeof(_input[ulong.max .. ulong.max])))
            private alias opSlice_t = ulong;
        else
            private alias opSlice_t = uint;

        static if (hasLength!R)
        {
            auto opSlice(opSlice_t low, opSlice_t high)
            {
                return typeof(this)(_input[low .. high]);
            }
        }
        else static if (is(typeof(_input[opSlice_t.max .. $])))
        {
            struct DollarToken{}
            enum opDollar = DollarToken.init;
            auto opSlice(opSlice_t low, DollarToken)
            {
                return typeof(this)(_input[low .. $]);
            }

            auto opSlice(opSlice_t low, opSlice_t high)
            {
                return this[low .. $].take(high - low);
            }
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
unittest
{
    //slicing infinites
    auto rr = iota(0, 5).cycle().map!"a * a"();
    alias RR = typeof(rr);
    static assert(hasSlicing!RR);
    rr = rr[6 .. $]; //Advances 1 cycle and 1 unit
    assert(equal(rr[0 .. 5], [1, 4, 9, 16, 0]));
}


/**
 * $(D auto reduce(Args...)(Args args)
 *     if (Args.length > 0 && Args.length <= 2 && isIterable!(Args[$ - 1]));)
 *
 * Implements the homonym function (also known as $(D accumulate), $(D
 * compress), $(D inject), or $(D foldl)) present in various programming
 * languages of functional flavor. The call $(D reduce!(fun)(seed,
 * range)) first assigns $(D seed) to an internal variable $(D result),
 * also called the accumulator. Then, for each element $(D x) in $(D
 * range), $(D result = fun(result, x)) gets evaluated. Finally, $(D
 * result) is returned. The one-argument version $(D reduce!(fun)(range))
 * works similarly, but it uses the first element of the range as the
 * seed (the range must be non-empty).
 *
 * Many aggregate range operations turn out to be solved with $(D reduce)
 * quickly and easily. The example below illustrates $(D reduce)'s
 * remarkable power and flexibility.
 *
 * Examples:
 * ----
 * int[] arr = [ 1, 2, 3, 4, 5 ];
 * // Sum all elements
 * auto sum = reduce!((a,b) => a + b)(0, arr);
 * assert(sum == 15);
 *
 * // Sum again, using a string predicate with "a" and "b"
 * sum = reduce!"a + b"(0, arr);
 * assert(sum == 15);
 *
 * // Compute the maximum of all elements
 * auto largest = reduce!(max)(arr);
 * assert(largest == 5);
 *
 * // Max again, but with Uniform Function Call Syntax (UFCS)
 * largest = arr.reduce!(max);
 * assert(largest == 5);
 *
 * // Compute the number of odd elements
 * auto odds = reduce!((a,b) => a + (b & 1))(0, arr);
 * assert(odds == 3);
 *
 * // Compute the sum of squares
 * auto ssquares = reduce!((a,b) => a + b * b)(0, arr);
 * assert(ssquares == 55);
 *
 * // Chain multiple ranges into seed
 * int[] a = [ 3, 4 ];
 * int[] b = [ 100 ];
 * auto r = reduce!("a + b")(chain(a, b));
 * assert(r == 107);
 *
 * // Mixing convertible types is fair game, too
 * double[] c = [ 2.5, 3.0 ];
 * auto r1 = reduce!("a + b")(chain(a, b, c));
 * assert(approxEqual(r1, 112.5));
 *
 * // To minimize nesting of parentheses, Uniform Function Call Syntax can be used
 * auto r2 = chain(a, b, c).reduce!("a + b");
 * assert(approxEqual(r2, 112.5));
 * ----
 *
 * $(DDOC_SECTION_H Multiple functions:) Sometimes it is very useful to
 * compute multiple aggregates in one pass. One advantage is that the
 * computation is faster because the looping overhead is shared. That's
 * why $(D reduce) accepts multiple functions. If two or more functions
 * are passed, $(D reduce) returns a $(XREF typecons, Tuple) object with
 * one member per passed-in function. The number of seeds must be
 * correspondingly increased.
 *
 * Examples:
 * ----
 * double[] a = [ 3.0, 4, 7, 11, 3, 2, 5 ];
 * // Compute minimum and maximum in one pass
 * auto r = reduce!(min, max)(a);
 * // The type of r is Tuple!(int, int)
 * assert(approxEqual(r[0], 2));  // minimum
 * assert(approxEqual(r[1], 11)); // maximum
 *
 * // Compute sum and sum of squares in one pass
 * r = reduce!("a + b", "a + b * b")(tuple(0.0, 0.0), a);
 * assert(approxEqual(r[0], 35));  // sum
 * assert(approxEqual(r[1], 233)); // sum of squares
 * // Compute average and standard deviation from the above
 * auto avg = r[0] / a.length;
 * auto stdev = sqrt(r[1] / a.length - avg * avg);
 * ----
 */
template reduce(fun...) if (fun.length >= 1)
{
    auto reduce(Args...)(Args args)
    if (Args.length > 0 && Args.length <= 2 && isIterable!(Args[$ - 1]))
    {
        import std.exception : enforce;
        import std.conv : emplace;

        static if (isInputRange!(Args[$ - 1]))
        {
            static if (Args.length == 2)
            {
                alias seed = args[0];
                alias r = args[1];

                Unqual!(Args[0]) result = seed;
                for (; !r.empty; r.popFront())
                {
                    static if (fun.length == 1)
                    {
                        result = binaryFun!(fun[0])(result, r.front);
                    }
                    else
                    {
                        foreach (i, Unused; Args[0].Types)
                        {
                            result[i] = binaryFun!(fun[i])(result[i], r.front);
                        }
                    }
                }
                return result;
            }
            else
            {
                enforce(!args[$ - 1].empty,
                    "Cannot reduce an empty range w/o an explicit seed value.");

                alias r = args[0];

                static if (fun.length == 1)
                {
                    auto seed = r.front;
                    r.popFront();
                    return reduce(seed, r);
                }
                else
                {
                    static assert(fun.length > 1);
                    Unqual!(typeof(r.front)) seed = r.front;
                    typeof(adjoin!(staticMap!(binaryFun, fun))(seed, seed))
                        result = void;
                    foreach (i, T; result.Types)
                    {
                        emplace(&result[i], seed);
                    }
                    r.popFront();
                    return reduce(result, r);
                }
            }
        }
        else
        {
            // opApply case.  Coded as a separate case because efficiently
            // handling all of the small details like avoiding unnecessary
            // copying, iterating by dchar over strings, and dealing with the
            // no explicit start value case would become an unreadable mess
            // if these were merged.
            alias r = args[$ - 1];
            alias R = Args[$ - 1];
            alias E = ForeachType!R;

            static if (args.length == 2)
            {
                static if (fun.length == 1)
                {
                    auto result = Tuple!(Unqual!(Args[0]))(args[0]);
                }
                else
                {
                    Unqual!(Args[0]) result = args[0];
                }

                enum bool initialized = true;
            }
            else static if (fun.length == 1)
            {
                Tuple!(typeof(binaryFun!fun(E.init, E.init))) result = void;
                bool initialized = false;
            }
            else
            {
                typeof(adjoin!(staticMap!(binaryFun, fun))(E.init, E.init)) result = void;
                bool initialized = false;
            }

            // For now, just iterate using ref to avoid unnecessary copying.
            // When Bug 2443 is fixed, this may need to change.
            foreach (ref elem; r)
            {
                if (initialized)
                {
                    foreach (i, T; result.Types)
                    {
                        result[i] = binaryFun!(fun[i])(result[i], elem);
                    }
                }
                else
                {
                    static if (is(typeof(&initialized)))
                    {
                        initialized = true;
                    }

                    foreach (i, T; result.Types)
                    {
                        emplace(&result[i], elem);
                    }
                }
            }

            enforce(initialized,
                "Cannot reduce an empty iterable w/o an explicit seed value.");

            static if (fun.length == 1)
            {
                return result[0];
            }
            else
            {
                return result;
            }
        }
    }
}

unittest
{
    import std.math : approxEqual;

    int[] arr = [ 1, 2, 3, 4, 5 ];
    // Sum all elements
    auto sum = reduce!((a,b) => a + b)(0, arr);
    assert(sum == 15);

    // Sum again, using a string predicate with "a" and "b"
    sum = reduce!"a + b"(0, arr);
    assert(sum == 15);

    // Compute the maximum of all elements
    auto largest = reduce!(max)(arr);
    assert(largest == 5);
    // Max again, but with Uniform Function Call Syntax (UFCS)
    largest = arr.reduce!(max)();
    assert(largest == 5);

    // Compute the number of odd elements
    auto odds = reduce!((a,b) => a + (b & 1))(0, arr);
    assert(odds == 3);

    // Compute the sum of squares
    auto ssquares = reduce!((a,b) => a + b * b)(0, arr);
    assert(ssquares == 55);

    // Chain multiple ranges into seed
    int[] a = [ 3, 4 ];
    int[] b = [ 100 ];
    auto r = reduce!("a + b")(chain(a, b));
    assert(r == 107);

    // Mixing convertible types is fair game, too
    double[] c = [ 2.5, 3.0 ];
    auto r1 = reduce!("a + b")(chain(a, b, c));
    assert(approxEqual(r1, 112.5));
    // To minimize nesting of parentheses, Uniform Function Call Syntax can be used
    auto r2 = chain(a, b, c).reduce!("a + b")();
    assert(approxEqual(r2, 112.5));
}

unittest
{
    import std.math : sqrt, approxEqual;

    double[] a = [ 3.0, 4, 7, 11, 3, 2, 5 ];
    // Compute minimum and maximum in one pass
    auto r = reduce!(min, max)(a);
    // The type of r is Tuple!(int, int)
    assert(approxEqual(r[0], 2));  // minimum
    assert(approxEqual(r[1], 11)); // maximum

    // Compute sum and sum of squares in one pass
    r = reduce!("a + b", "a + b * b")(tuple(0.0, 0.0), a);
    assert(approxEqual(r[0], 35));  // sum
    assert(approxEqual(r[1], 233)); // sum of squares
    // Compute average and standard deviation from the above
    auto avg = r[0] / a.length;
    auto stdev = sqrt(r[1] / a.length - avg * avg);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    double[] a = [ 3, 4 ];
    auto r = reduce!("a + b")(0.0, a);
    assert(r == 7);
    r = reduce!("a + b")(a);
    assert(r == 7);
    r = reduce!(min)(a);
    assert(r == 3);
    double[] b = [ 100 ];
    auto r1 = reduce!("a + b")(chain(a, b));
    assert(r1 == 107);

    // two funs
    auto r2 = reduce!("a + b", "a - b")(tuple(0.0, 0.0), a);
    assert(r2[0] == 7 && r2[1] == -7);
    auto r3 = reduce!("a + b", "a - b")(a);
    assert(r3[0] == 7 && r3[1] == -1);

    a = [ 1, 2, 3, 4, 5 ];
    // Stringize with commas
    string rep = reduce!("a ~ `, ` ~ to!(string)(b)")("", a);
    assert(rep[2 .. $] == "1, 2, 3, 4, 5", "["~rep[2 .. $]~"]");

    // Test the opApply case.
    static struct OpApply
    {
        bool actEmpty;

        int opApply(int delegate(ref int) dg)
        {
            int res;
            if (actEmpty)
                return res;

            foreach (i; 0..100)
            {
                res = dg(i);
                if (res)
                    break;
            }
            return res;
        }
    }

    OpApply oa;
    auto hundredSum = reduce!"a + b"(iota(100));
    assert(reduce!"a + b"(5, oa) == hundredSum + 5);
    assert(reduce!"a + b"(oa) == hundredSum);
    assert(reduce!("a + b", max)(oa) == tuple(hundredSum, 99));
    assert(reduce!("a + b", max)(tuple(5, 0), oa) == tuple(hundredSum + 5, 99));

    // Test for throwing on empty range plus no seed.
    try
    {
        reduce!"a + b"([1, 2][0..0]);
        assert(0);
    }
    catch(Exception) {}

    oa.actEmpty = true;
    try
    {
        reduce!"a + b"(oa);
        assert(0);
    }
    catch(Exception) {}
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    const float a = 0.0;
    const float[] b = [ 1.2, 3, 3.3 ];
    float[] c = [ 1.2, 3, 3.3 ];
    auto r = reduce!"a + b"(a, b);
    r = reduce!"a + b"(a, c);
}

unittest
{
    // Issue #10408 - Two-function reduce of a const array.
    const numbers = [10, 30, 20];
    immutable m = reduce!(min)(numbers);
    assert(m == 10);
    immutable minmax = reduce!(min, max)(numbers);
    assert(minmax == tuple(10, 30));
}


/**
 * $(D auto filter(Range)(Range rs) if (isInputRange!(Unqual!Range));)
 *
 * Implements the homonym function present in various programming
 * languages of functional flavor. The call $(D filter!(predicate)(range))
 * returns a new range only containing elements $(D x) in $(D range) for
 * which $(D predicate(x)) is $(D true).
 */
template filter(alias pred) if (is(typeof(unaryFun!pred)))
{
    auto filter(Range)(Range rs) if (isInputRange!(Unqual!Range))
    {
        return FilterResult!(unaryFun!pred, Range)(rs);
    }
}

///
unittest
{
    import std.math : approxEqual;

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
            return typeof(this)(_input.save);
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
    import std.functional : compose, pipe;
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
template filterBidirectional(alias pred)
{
    auto filterBidirectional(Range)(Range r) if (isBidirectionalRange!(Unqual!Range))
    {
        return FilterBidiResult!(unaryFun!pred, Range)(r);
    }
}

///
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


/**
 * Splits a range using an element as a separator. This can be used with
 * any narrow string type or sliceable range type, but is most popular
 * with string types.
 *
 * Two adjacent separators are considered to surround an empty element in
 * the split range.
 *
 * If the empty range is given, the result is a range with one empty
 * element. If a range with one separator is given, the result is a range
 * with two empty elements.
 */
auto splitter(Range, Separator)(Range r, Separator s)
if (is(typeof(ElementType!Range.init == Separator.init)) &&
    (isNarrowString!Range || hasSlicing!Range && hasLength!Range))
{
    import std.conv : unsigned;

    static struct Result
    {
    private:
        // Do we need hasLength!Range? popFront uses _input.length...
        alias IndexType = typeof(unsigned(_input.length));
        enum IndexType _unComputed = IndexType.max - 1, _atEnd = IndexType.max;

        Range _input;
        Separator _separator;
        IndexType _frontLength = _unComputed;
        IndexType _backLength = _unComputed;

        static if (isBidirectionalRange!Range)
        {
            static IndexType lastIndexOf(Range haystack, Separator needle)
            {
                auto r = haystack.retro().find(needle);
                return r.retro().length - 1;
            }
        }

    public:
        this(Range input, Separator separator)
        {
            _input = input;
            _separator = separator;
        }

        static if (isInfinite!Range)
        {
            enum bool empty = false;
        }
        else
        {
            @property bool empty()
            {
                return _frontLength == _atEnd;
            }
        }

        @property Range front()
        {
            assert(!empty);
            if (_frontLength == _unComputed)
            {
                auto r = _input.find(_separator);
                _frontLength = _input.length - r.length;
            }
            return _input[0 .. _frontLength];
        }

        void popFront()
        {
            assert(!empty);
            if (_frontLength == _unComputed)
            {
                front;
            }
            assert(_frontLength <= _input.length);
            if (_frontLength == _input.length)
            {
                // no more input and need to fetch => done
                _frontLength = _atEnd;

                // Probably don't need this, but just for consistency:
                _backLength = _atEnd;
            }
            else
            {
                _input = _input[_frontLength .. _input.length];
                skipOver(_input, _separator) || assert(false);
                _frontLength = _unComputed;
            }
        }

        static if (isForwardRange!Range)
        {
            @property typeof(this) save()
            {
                auto ret = this;
                ret._input = _input.save;
                return ret;
            }
        }

        static if (isBidirectionalRange!Range)
        {
            @property Range back()
            {
                assert(!empty);
                if (_backLength == _unComputed)
                {
                    immutable lastIndex = lastIndexOf(_input, _separator);
                    if (lastIndex == -1)
                    {
                        _backLength = _input.length;
                    }
                    else
                    {
                        _backLength = _input.length - lastIndex - 1;
                    }
                }
                return _input[_input.length - _backLength .. _input.length];
            }

            void popBack()
            {
                assert(!empty);
                if (_backLength == _unComputed)
                {
                    // evaluate back to make sure it's computed
                    back;
                }
                assert(_backLength <= _input.length);
                if (_backLength == _input.length)
                {
                    // no more input and need to fetch => done
                    _frontLength = _atEnd;
                    _backLength = _atEnd;
                }
                else
                {
                    _input = _input[0 .. _input.length - _backLength];
                    if (!_input.empty && _input.back == _separator)
                    {
                        _input.popBack();
                    }
                    else
                    {
                        assert(false);
                    }
                    _backLength = _unComputed;
                }
            }
        }
    }

    return Result(r, s);
}
///
unittest
{
    assert(equal(splitter("hello  world", ' '), [ "hello", "", "world" ]));

    int[] a = [ 1, 2, 0, 0, 3, 0, 4, 5, 0 ];
    int[][] w = [ [1, 2], [], [3], [4, 5], [] ];
    static assert(isForwardRange!(typeof(splitter(a, 0))));

    assert(equal(splitter(a, 0), w));
    a = null;
    assert(equal(splitter(a, 0), [ (int[]).init ][]));
    a = [ 0 ];
    assert(equal(splitter(a, 0), [ (int[]).init, (int[]).init ][]));
    a = [ 0, 1 ];
    assert(equal(splitter(a, 0), [ [], [1] ][]));
}

unittest
{
    // Thoroughly exercise the bidirectional stuff.
    auto str = "abc abcd abcde ab abcdefg abcdefghij ab ac ar an at ada";
    assert(equal(
        retro(splitter(str, 'a')),
        retro(array(splitter(str, 'a')))
    ));

    // Test interleaving front and back.
    auto split = splitter(str, 'a');
    assert(split.front == "");
    assert(split.back == "");
    split.popBack();
    assert(split.back == "d");
    split.popFront();
    assert(split.front == "bc ");
    assert(split.back == "d");
    split.popFront();
    split.popBack();
    assert(split.back == "t ");
    split.popBack();
    split.popBack();
    split.popFront();
    split.popFront();
    assert(split.front == "b ");
    assert(split.back == "r ");

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)    // Bug 4408
    {
        static if (isRandomAccessRange!DummyType)
        {
            static assert(isBidirectionalRange!DummyType);
            DummyType d;
            auto s = splitter(d, 5);
            assert(equal(s.front, [1,2,3,4]));
            assert(equal(s.back, [6,7,8,9,10]));

            auto s2 = splitter(d, [4, 5]);
            assert(equal(s2.front, [1,2,3]));
            assert(equal(s2.back, [6,7,8,9,10]));
        }
    }
}

unittest
{
    auto L = retro(iota(1L, 10L));
    auto s = splitter(L, 5L);
    assert(equal(s.front, [9L, 8L, 7L, 6L]));
    s.popFront();
    assert(equal(s.front, [4L, 3L, 2L, 1L]));
    s.popFront();
    assert(s.empty);
}

/**
 * Splits a range using another range as a separator. This can be used
 * with any narrow string type or sliceable range type, but is most popular
 * with string types.
 */
auto splitter(Range, Separator)(Range r, Separator s)
if (is(typeof(Range.init.front == Separator.init.front) : bool) &&
    (isNarrowString!Range || hasSlicing!Range) &&
    isForwardRange!Separator &&
    (isNarrowString!Separator || hasLength!Separator))
{
    import std.conv : unsigned;

    static struct Result
    {
    private:
        alias RIndexType = typeof(unsigned(_input.length));

        Range _input;
        Separator _separator;
        // _frontLength == size_t.max means empty
        RIndexType _frontLength = RIndexType.max;
        static if (isBidirectionalRange!Range)
            RIndexType _backLength = RIndexType.max;

        @property auto separatorLength() { return _separator.length; }

        void ensureFrontLength()
        {
            if (_frontLength != _frontLength.max)
                return;
            assert(!_input.empty);
            // compute front length
            _frontLength = _separator.empty ? 1 :
                           _input.length - find(_input, _separator).length;
            static if (isBidirectionalRange!Range)
            {
                if (_frontLength == _input.length)
                    _backLength = _frontLength;
            }
        }

        void ensureBackLength()
        {
            static if (isBidirectionalRange!Range)
            {
                if (_backLength != _backLength.max)
                    return;
            }
            assert(!_input.empty);
            // compute back length
            static if (isBidirectionalRange!Range && isBidirectionalRange!Separator)
            {
                _backLength = _input.length -
                    find(retro(_input), retro(_separator)).source.length;
            }
        }

    public:
        this(Range input, Separator separator)
        {
            _input = input;
            _separator = separator;
        }

        static if (isInfinite!Range)
        {
            enum bool empty = false;  // Propagate infiniteness
        }
        else
        {
            @property bool empty()
            {
                return _frontLength == RIndexType.max && _input.empty;
            }
        }

        @property Range front()
        {
            assert(!empty);
            ensureFrontLength();
            return _input[0 .. _frontLength];
        }

        void popFront()
        {
            assert(!empty);
            ensureFrontLength();
            if (_frontLength == _input.length)
            {
                // done, there's no separator in sight
                _input = _input[_frontLength .. _frontLength];
                _frontLength = _frontLength.max;
                static if (isBidirectionalRange!Range)
                    _backLength = _backLength.max;
                return;
            }
            if (_frontLength + separatorLength == _input.length)
            {
                // Special case: popping the first-to-last item; there is
                // an empty item right after this.
                _input = _input[_input.length .. _input.length];
                _frontLength = 0;
                static if (isBidirectionalRange!Range)
                    _backLength = 0;
                return;
            }
            // Normal case, pop one item and the separator, get ready for
            // reading the next item
            _input = _input[_frontLength + separatorLength .. _input.length];
            // mark _frontLength as uninitialized
            _frontLength = _frontLength.max;
        }

        static if (isForwardRange!Range)
        {
            @property typeof(this) save()
            {
                auto ret = this;
                ret._input = _input.save;
                return ret;
            }
        }

        // Bidirectional functionality as suggested by Brad Roberts.
        static if (isBidirectionalRange!Range && isBidirectionalRange!Separator)
        {
            @property Range back()
            {
                ensureBackLength();
                return _input[_input.length - _backLength .. _input.length];
            }

            void popBack()
            {
                ensureBackLength();
                if (_backLength == _input.length)
                {
                    // done
                    _input = _input[0 .. 0];
                    _frontLength = _frontLength.max;
                    _backLength = _backLength.max;
                    return;
                }
                if (_backLength + separatorLength == _input.length)
                {
                    // Special case: popping the first-to-first item; there is
                    // an empty item right before this. Leave the separator in.
                    _input = _input[0 .. 0];
                    _frontLength = 0;
                    _backLength = 0;
                    return;
                }
                // Normal case
                _input = _input[0 .. _input.length - _backLength - separatorLength];
                _backLength = _backLength.max;
            }
        }
    }

    return Result(r, s);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto s = ",abc, de, fg,hi,";
    auto sp0 = splitter(s, ',');
    // //foreach (e; sp0) writeln("[", e, "]");
    assert(equal(sp0, ["", "abc", " de", " fg", "hi", ""][]));

    auto s1 = ", abc, de,  fg, hi, ";
    auto sp1 = splitter(s1, ", ");
    //foreach (e; sp1) writeln("[", e, "]");
    assert(equal(sp1, ["", "abc", "de", " fg", "hi", ""][]));
    static assert(isForwardRange!(typeof(sp1)));

    int[] a = [ 1, 2, 0, 3, 0, 4, 5, 0 ];
    int[][] w = [ [1, 2], [3], [4, 5], [] ];
    uint i;
    foreach (e; splitter(a, 0))
    {
        assert(i < w.length);
        assert(e == w[i++]);
    }
    assert(i == w.length);
    // // Now go back
    // auto s2 = splitter(a, 0);

    // foreach (e; retro(s2))
    // {
    //     assert(i > 0);
    //     assert(equal(e, w[--i]), text(e));
    // }
    // assert(i == 0);

    wstring names = ",peter,paul,jerry,";
    auto words = split(names, ",");
    assert(walkLength(words) == 5);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    auto s6 = ",";
    auto sp6 = splitter(s6, ',');
    foreach (e; sp6)
    {
        //writeln("{", e, "}");
    }
    assert(equal(sp6, ["", ""][]));
}

unittest
{
    // Issue 10773
    auto s = splitter("abc", "");
    assert(s.equal(["a", "b", "c"]));
}

unittest
{
    // Test by-reference separator
    class RefSep
    {
        string _impl;
        this(string s) { _impl = s; }
        @property empty() { return _impl.empty; }
        @property auto front() { return _impl.front; }
        void popFront() { _impl = _impl[1..$]; }
        @property RefSep save() { return new RefSep(_impl); }
        @property auto length() { return _impl.length; }
    }
    auto sep = new RefSep("->");
    auto data = "i->am->pointing";
    auto words = splitter(data, sep);
    assert(words.equal([ "i", "am", "pointing" ]));
}

auto splitter(alias isTerminator, Range)(Range input)
if (is(typeof(unaryFun!isTerminator(ElementType!(Range).init))))
{
    return SplitterResult!(unaryFun!isTerminator, Range)(input);
}

private struct SplitterResult(alias isTerminator, Range)
{
    private Range _input;
    private size_t _end;

    this(Range input)
    {
        _input = input;
        if (_input.empty)
        {
            _end = _end.max;
        }
        else
        {
            // Chase first terminator
            while (_end < _input.length && !isTerminator(_input[_end]))
            {
                ++_end;
            }
        }
    }

    static if (isInfinite!Range)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty()
        {
            return _end == _end.max;
        }
    }

    @property Range front()
    {
        assert(!empty);
        return _input[0 .. _end];
    }

    void popFront()
    {
        assert(!empty);
        if (_input.empty)
        {
            _end = _end.max;
            return;
        }
        // Skip over existing word
        _input = _input[_end .. _input.length];
        // Skip terminator
        for (;;)
        {
            if (_input.empty)
            {
                // Nothing following the terminator - done
                _end = _end.max;
                return;
            }
            if (!isTerminator(_input.front))
            {
                // Found a legit next field
                break;
            }
            _input.popFront();
        }
        assert(!_input.empty && !isTerminator(_input.front));
        // Prepare _end
        _end = 1;
        while (_end < _input.length && !isTerminator(_input[_end]))
        {
            ++_end;
        }
    }

    static if (isForwardRange!Range)
    {
        @property typeof(this) save()
        {
            auto ret = this;
            ret._input = _input.save;
            return ret;
        }
    }
}

unittest
{
    auto L = iota(1L, 10L);
    auto s = splitter(L, [5L, 6L]);
    assert(equal(s.front, [1L, 2L, 3L, 4L]));
    s.popFront();
    assert(equal(s.front, [7L, 8L, 9L]));
    s.popFront();
    assert(s.empty);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    void compare(string sentence, string[] witness)
    {
        foreach (word; splitter!"a == ' '"(sentence))
        {
            assert(word == witness.front, word);
            witness.popFront();
        }
        assert(witness.empty, witness[0]);
    }

    compare(" Mary    has a little lamb.   ",
            ["", "Mary", "has", "a", "little", "lamb."]);
    compare("Mary    has a little lamb.   ",
            ["Mary", "has", "a", "little", "lamb."]);
    compare("Mary    has a little lamb.",
            ["Mary", "has", "a", "little", "lamb."]);
    compare("", []);
    compare(" ", [""]);

    static assert(isForwardRange!(typeof(splitter!"a == ' '"("ABC"))));

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        static if (isRandomAccessRange!DummyType)
        {
            auto rangeSplit = splitter!"a == 5"(DummyType.init);
            assert(equal(rangeSplit.front, [1,2,3,4]));
            rangeSplit.popFront();
            assert(equal(rangeSplit.front, [6,7,8,9,10]));
        }
    }
}

auto splitter(Range)(Range input)
if (isSomeString!Range)
{
    import std.uni : isWhite;

    return splitter!(std.uni.isWhite)(input);
}

unittest
{
    import std.string : strip;
    import std.conv : to;

    // TDPL example, page 8
    uint[string] dictionary;
    char[][3] lines;
    lines[0] = "line one".dup;
    lines[1] = "line \ttwo".dup;
    lines[2] = "yah            last   line\ryah".dup;
    foreach (line; lines)
    {
        foreach (word; splitter(strip(line)))
        {
            if (word in dictionary)
                continue; // Nothing to do
            auto newID = dictionary.length;
            dictionary[to!string(word)] = cast(uint)newID;
        }
    }
    assert(dictionary.length == 5);
    assert(dictionary["line"]== 0);
    assert(dictionary["one"]== 1);
    assert(dictionary["two"]== 2);
    assert(dictionary["yah"]== 3);
    assert(dictionary["last"]== 4);
}


/**
 * Lazily joins a range of ranges with a separator. The separator itself
 * is a range. If you do not provide a separator, then the ranges are
 * joined directly without anything in between them.
 */
auto joiner(RoR, Separator)(RoR r, Separator sep)
if (isInputRange!RoR && isInputRange!(ElementType!RoR) &&
    isForwardRange!Separator &&
    is(ElementType!Separator : ElementType!(ElementType!RoR)))
{
    static struct Result
    {
        private RoR _items;
        private ElementType!RoR _current;
        private Separator _sep, _currentSep;

        // This is a mixin instead of a function for the following reason (as
        // explained by Kenji Hara): "This is necessary from 2.061.  If a
        // struct has a nested struct member, it must be directly initialized
        // in its constructor to avoid leaving undefined state.  If you change
        // setItem to a function, the initialization of _current field is
        // wrapped into private member function, then compiler could not detect
        // that is correctly initialized while constructing.  To avoid the
        // compiler error check, string mixin is used."
        private enum setItem =
        q{
            if (!_items.empty)
            {
                // If we're exporting .save, we must not consume any of the
                // subranges, since RoR.save does not guarantee that the states
                // of the subranges are also saved.
                static if (isForwardRange!RoR &&
                           isForwardRange!(ElementType!RoR))
                    _current = _items.front.save;
                else
                    _current = _items.front;
            }
        };

        private void useSeparator()
        {
            // Separator must always come after an item.
            assert(_currentSep.empty && !_items.empty,
                    "joiner: internal error");
            _items.popFront();

            // If there are no more items, we're done, since separators are not
            // terminators.
            if (_items.empty) return;

            if (_sep.empty)
            {
                // Advance to the next range in the
                // input
                while (_items.front.empty)
                {
                    _items.popFront();
                    if (_items.empty) return;
                }
                mixin(setItem);
            }
            else
            {
                _currentSep = _sep.save;
                assert(!_currentSep.empty);
            }
        }

        private enum useItem =
        q{
            // FIXME: this will crash if either _currentSep or _current are
            // class objects, because .init is null when the ctor invokes this
            // mixin.
            //assert(_currentSep.empty && _current.empty,
            //        "joiner: internal error");

            // Use the input
            if (_items.empty) return;
            mixin(setItem);
            if (_current.empty)
            {
                // No data in the current item - toggle to use the separator
                useSeparator();
            }
        };

        this(RoR items, Separator sep)
        {
            _items = items;
            _sep = sep;
            mixin(useItem); // _current should be initialized in place
        }

        @property auto empty()
        {
            return _items.empty;
        }

        @property ElementType!(ElementType!RoR) front()
        {
            if (!_currentSep.empty) return _currentSep.front;
            assert(!_current.empty);
            return _current.front;
        }

        void popFront()
        {
            assert(!_items.empty);
            // Using separator?
            if (!_currentSep.empty)
            {
                _currentSep.popFront();
                if (!_currentSep.empty) return;
                mixin(useItem);
            }
            else
            {
                // we're using the range
                _current.popFront();
                if (!_current.empty) return;
                useSeparator();
            }
        }

        static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
        {
            @property auto save()
            {
                Result copy = this;
                copy._items = _items.save;
                copy._current = _current.save;
                copy._sep = _sep.save;
                copy._currentSep = _currentSep.save;
                return copy;
            }
        }
    }
    return Result(r, sep);
}

///
unittest
{
    assert(equal(joiner([""], "xyz"), ""));
    assert(equal(joiner(["", ""], "xyz"), "xyz"));
    assert(equal(joiner(["", "abc"], "xyz"), "xyzabc"));
    assert(equal(joiner(["abc", ""], "xyz"), "abcxyz"));
    assert(equal(joiner(["abc", "def"], "xyz"), "abcxyzdef"));
    assert(equal(joiner(["Mary", "has", "a", "little", "lamb"], "..."),
                 "Mary...has...a...little...lamb"));
    assert(equal(joiner(["abc", "def"]), "abcdef"));
}

unittest
{
    // joiner() should work for non-forward ranges too.
    InputRange!string r = inputRangeObject(["abc", "def"]);
    assert (equal(joiner(r, "xyz"), "abcxyzdef"));
}

unittest
{
    // Related to issue 8061
    auto r = joiner([
        inputRangeObject("abc"),
        inputRangeObject("def"),
    ], "-*-");

    assert(equal(r, "abc-*-def"));

    // Test case where separator is specified but is empty.
    auto s = joiner([
        inputRangeObject("abc"),
        inputRangeObject("def"),
    ], "");

    assert(equal(s, "abcdef"));

    // Test empty separator with some empty elements
    auto t = joiner([
        inputRangeObject("abc"),
        inputRangeObject(""),
        inputRangeObject("def"),
        inputRangeObject(""),
    ], "");

    assert(equal(t, "abcdef"));

    // Test empty elements with non-empty separator
    auto u = joiner([
        inputRangeObject(""),
        inputRangeObject("abc"),
        inputRangeObject(""),
        inputRangeObject("def"),
        inputRangeObject(""),
    ], "+-");

    assert(equal(u, "+-abc+-+-def+-"));
}

unittest
{
    // Transience correctness test
    struct TransientRange
    {
        int[][] src;
        int[] buf;

        this(int[][] _src)
        {
            src = _src;
            buf.length = 100;
        }
        @property bool empty() { return src.empty; }
        @property int[] front()
        {
            assert(src.front.length <= buf.length);
            buf[0 .. src.front.length] = src.front[0..$];
            return buf[0 .. src.front.length];
        }
        void popFront() { src.popFront(); }
    }

    // Test embedded empty elements
    auto tr1 = TransientRange([[], [1,2,3], [], [4]]);
    assert(equal(joiner(tr1, [0]), [0,1,2,3,0,0,4]));

    // Test trailing empty elements
    auto tr2 = TransientRange([[], [1,2,3], []]);
    assert(equal(joiner(tr2, [0]), [0,1,2,3,0]));

    // Test no empty elements
    auto tr3 = TransientRange([[1,2], [3,4]]);
    assert(equal(joiner(tr3, [0,1]), [1,2,0,1,3,4]));

    // Test consecutive empty elements
    auto tr4 = TransientRange([[1,2], [], [], [], [3,4]]);
    assert(equal(joiner(tr4, [0,1]), [1,2,0,1,0,1,0,1,0,1,3,4]));

    // Test consecutive trailing empty elements
    auto tr5 = TransientRange([[1,2], [3,4], [], []]);
    assert(equal(joiner(tr5, [0,1]), [1,2,0,1,3,4,0,1,0,1]));
}

/// Ditto
auto joiner(RoR)(RoR r)
if (isInputRange!RoR && isInputRange!(ElementType!RoR))
{
    static struct Result
    {
    private:
        RoR _items;
        ElementType!RoR _current;
        enum prepare =
        q{
            // Skip over empty subranges.
            if (_items.empty) return;
            while (_items.front.empty)
            {
                _items.popFront();
                if (_items.empty) return;
            }
            // We cannot export .save method unless we ensure subranges are not
            // consumed when a .save'd copy of ourselves is iterated over. So
            // we need to .save each subrange we traverse.
            static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
                _current = _items.front.save;
            else
                _current = _items.front;
        };
    public:
        this(RoR r)
        {
            _items = r;
            mixin(prepare); // _current should be initialized in place
        }
        static if (isInfinite!RoR)
        {
            enum bool empty = false;
        }
        else
        {
            @property auto empty()
            {
                return _items.empty;
            }
        }
        @property auto ref front()
        {
            assert(!empty);
            return _current.front;
        }
        void popFront()
        {
            assert(!_current.empty);
            _current.popFront();
            if (_current.empty)
            {
                assert(!_items.empty);
                _items.popFront();
                mixin(prepare);
            }
        }
        static if (isForwardRange!RoR && isForwardRange!(ElementType!RoR))
        {
            @property auto save()
            {
                Result copy = this;
                copy._items = _items.save;
                copy._current = _current.save;
                return copy;
            }
        }
    }
    return Result(r);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    static assert(isInputRange!(typeof(joiner([""]))));
    static assert(isForwardRange!(typeof(joiner([""]))));
    assert(equal(joiner([""]), ""));
    assert(equal(joiner(["", ""]), ""));
    assert(equal(joiner(["", "abc"]), "abc"));
    assert(equal(joiner(["abc", ""]), "abc"));
    assert(equal(joiner(["abc", "def"]), "abcdef"));
    assert(equal(joiner(["Mary", "has", "a", "little", "lamb"]),
                    "Maryhasalittlelamb"));
    assert(equal(joiner(std.range.repeat("abc", 3)), "abcabcabc"));

    // joiner allows in-place mutation!
    auto a = [ [1, 2, 3], [42, 43] ];
    auto j = joiner(a);
    j.front = 44;
    assert(a == [ [44, 2, 3], [42, 43] ]);

    // bugzilla 8240
    assert(equal(joiner([inputRangeObject("")]), ""));

    // issue 8792
    auto b = [[1], [2], [3]];
    auto jb = joiner(b);
    auto js = jb.save;
    assert(equal(jb, js));

    auto js2 = jb.save;
    jb.popFront();
    assert(!equal(jb, js));
    assert(equal(js2, js));
    js.popFront();
    assert(equal(jb, js));
    assert(!equal(js2, js));
}

unittest
{
    struct TransientRange
    {
        int[] _buf;
        int[][] _values;
        this(int[][] values)
        {
            _values = values;
            _buf = new int[128];
        }
        @property bool empty()
        {
            return _values.length == 0;
        }
        @property auto front()
        {
            foreach (i; 0 .. _values.front.length)
            {
                _buf[i] = _values[0][i];
            }
            return _buf[0 .. _values.front.length];
        }
        void popFront()
        {
            _values = _values[1 .. $];
        }
    }

    auto rr = TransientRange([[1,2], [3,4,5], [], [6,7]]);

    // Can't use array() or equal() directly because they fail with transient
    // .front.
    int[] result;
    foreach (c; rr.joiner()) {
        result ~= c;
    }

    assert(equal(result, [1,2,3,4,5,6,7]));
}

// Temporarily disable this unittest due to issue 9131 on OSX/64.
version = Issue9131;
version(Issue9131) {} else
unittest
{
    struct TransientRange
    {
        dchar[128] _buf;
        dstring[] _values;
        this(dstring[] values)
        {
            _values = values;
        }
        @property bool empty()
        {
            return _values.length == 0;
        }
        @property auto front()
        {
            foreach (i; 0 .. _values.front.length)
            {
                _buf[i] = _values[0][i];
            }
            return _buf[0 .. _values.front.length];
        }
        void popFront()
        {
            _values = _values[1 .. $];
        }
    }

    auto rr = TransientRange(["abc"d, "12"d, "def"d, "34"d]);

    // Can't use array() or equal() directly because they fail with transient
    // .front.
    dchar[] result;
    foreach (c; rr.joiner()) {
        result ~= c;
    }

    assert(equal(result, "abc12def34"d),
        "Unexpected result: '%s'"d.format(result));
}

// Issue 8061
unittest
{
    import std.conv : to;

    auto r = joiner([inputRangeObject("ab"), inputRangeObject("cd")]);
    assert(isForwardRange!(typeof(r)));

    auto str = to!string(r);
    assert(str == "abcd");
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


/**
 * Similarly to $(D uniq), $(D group) iterates unique consecutive
 * elements of the given range. The element type is $(D
 * Tuple!(ElementType!R, uint)) because it includes the count of
 * equivalent elements seen. Equivalence of elements is assessed by using
 * the predicate $(D pred), by default $(D "a == b").
 *
 * $(D Group) is an input range if $(D R) is an input range, and a
 * forward range in all other cases.
 */
struct Group(alias pred, R) if (isInputRange!R)
{
    private alias comp = binaryFun!pred;

    private R _input;
    private Tuple!(ElementType!R, uint) _current;

    this(R input)
    {
        _input = input;
        if (!_input.empty)
            popFront();
    }

    static if (isInfinite!R)
    {
        enum bool empty = false;  // Propagate infiniteness.
    }
    else
    {
        @property bool empty()
        {
            return _current[1] == 0;
        }
    }

    @property ref Tuple!(ElementType!R, uint) front()
    {
        assert(!empty);
        return _current;
    }

    void popFront()
    {
        if (_input.empty)
        {
            _current[1] = 0;
        }
        else
        {
            _current = tuple(_input.front, 1u);
            _input.popFront();
            while (!_input.empty && comp(_current[0], _input.front))
            {
                ++_current[1];
                _input.popFront();
            }
        }
    }

    static if (isForwardRange!R)
    {
        @property typeof(this) save()
        {
            typeof(this) ret = this;
            ret._input = this._input.save;
            ret._current = this._current;
            return ret;
        }
    }
}

/// Ditto
Group!(pred, Range) group(alias pred = "a == b", Range)(Range r)
{
    return typeof(return)(r);
}

///
unittest
{
    int[] arr = [ 1, 2, 2, 2, 2, 3, 4, 4, 4, 5 ];
    assert(equal(
        group(arr),
        [ tuple(1, 1u), tuple(2, 4u), tuple(3, 1u),
          tuple(4, 3u), tuple(5, 1u) ]));
    static assert(isForwardRange!(typeof(group(arr))));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    with (DummyRanges!())
    foreach (DummyType; AllDummyRanges)
    {
        DummyType d;
        auto g = group(d);

        static assert(d.rt == RangeType.Input || isForwardRange!(typeof(g)));

        assert(equal(
            g,
            [ tuple(1, 1u), tuple(2, 1u), tuple(3, 1u), tuple(4, 1u),
              tuple(5, 1u), tuple(6, 1u), tuple(7, 1u), tuple(8, 1u),
              tuple(9, 1u), tuple(10, 1u) ]));
    }
}
