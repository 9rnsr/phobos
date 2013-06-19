module std.algorithm.reduce;

import std.algorithm;
import std.range, std.functional, std.traits, std.typetuple;
import std.typecons : tuple, Tuple;

version(unittest)
{
    import std.complex : approxEqual;
    import std.math : sqrt;
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
 */
unittest
{
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
/**
 * $(DDOC_SECTION_H Multiple functions:) Sometimes it is very useful to
 * compute multiple aggregates in one pass. One advantage is that the
 * computation is faster because the looping overhead is shared. That's
 * why $(D reduce) accepts multiple functions. If two or more functions
 * are passed, $(D reduce) returns a $(XREF typecons, Tuple) object with
 * one member per passed-in function. The number of seeds must be
 * correspondingly increased.
 */
unittest
{
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
/**
 */
template reduce(fun...) if (fun.length >= 1)
{
    ///
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
                    typeof(adjoin!(staticMap!(binaryFun, fun))(r.front, r.front)) result = void;
                    foreach (i, T; result.Types)
                    {
                        emplace(&result[i], r.front);
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
