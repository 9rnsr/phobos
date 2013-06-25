module std.algorithm.until;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
}

/**
 * Interval option specifier for $(D until) (below) and others.
 */
enum OpenRight
{
    no, /// Interval is closed to the right (last element included)
    yes /// Interval is open to the right (last element is not included)
}

/**
 * Lazily iterates $(D range) until value $(D sentinel) is found, at
 * which point it stops.
 */
struct Until(alias pred, Range, Sentinel)
if (isInputRange!Range)
{
    private Range _input;
    static if (!is(Sentinel == void))
        private Sentinel _sentinel;
    // mixin(bitfields!(
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    //             uint, "", 6));
    //             OpenRight, "_openRight", 1,
    //             bool,  "_done", 1,
    OpenRight _openRight;
    bool _done;

    static if (!is(Sentinel == void))
        this(Range input, Sentinel sentinel,
                OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _sentinel = sentinel;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }
    else
        this(Range input, OpenRight openRight = OpenRight.yes)
        {
            _input = input;
            _openRight = openRight;
            _done = _input.empty || openRight && predSatisfied();
        }

    @property bool empty()
    {
        return _done;
    }

    @property ElementType!Range front()
    {
        assert(!empty);
        return _input.front;
    }

    private bool predSatisfied()
    {
        static if (is(Sentinel == void))
            return unaryFun!pred(_input.front);
        else
            return startsWith!pred(_input, _sentinel);
    }

    void popFront()
    {
        assert(!empty);
        if (!_openRight)
        {
            if (predSatisfied())
            {
                _done = true;
                return;
            }
            _input.popFront();
            _done = _input.empty;
        }
        else
        {
            _input.popFront();
            _done = _input.empty || predSatisfied();
        }
    }

    static if (isForwardRange!Range)
    {
        @property Until save()
        {
            Until result = this;
            result._input     = _input.save;
          static if (!is(Sentinel == void))
            result._sentinel  = _sentinel;
            result._openRight = _openRight;
            result._done      = _done;
            return result;
        }
    }
}

/// Ditto
Until!(pred, Range, Sentinel)
until(alias pred = "a == b", Range, Sentinel)
(Range range, Sentinel sentinel, OpenRight openRight = OpenRight.yes)
if (!is(Sentinel == OpenRight))
{
    return typeof(return)(range, sentinel, openRight);
}

/// Ditto
Until!(pred, Range, void)
until(alias pred, Range)
(Range range, OpenRight openRight = OpenRight.yes)
{
    return typeof(return)(range, openRight);
}

///
unittest
{
    int[] a = [ 1, 2, 4, 7, 7, 2, 4, 7, 3, 5 ];
    assert(equal(a.until(7), [ 1, 2, 4 ]));
    assert(equal(a.until(7, OpenRight.no), [ 1, 2, 4, 7 ]));
    assert(equal(a.until([7, 2]), [ 1, 2, 4, 7 ]));
    assert(equal(until!"a == 2"(a, OpenRight.no), [ 1, 2 ]));
}

/**
 * Returns the common prefix of two ranges.
 */
unittest
{
    assert(commonPrefix("hello, world", "hello, there") == "hello, ");
}
/**
 * If the first argument is a string, then the result is a slice of $(D r1) which
 * contains the characters that both ranges start with. For all other types, the
 * type of the result is the same as the result of $(D takeExactly(r1, n)), where
 * $(D n) is the number of elements that both ranges start with.
 *
 * See_Also:
 *     $(XREF range, takeExactly)
 */
auto commonPrefix(alias pred = "a == b", R1, R2)(R1 r1, R2 r2)
if (isForwardRange!R1 && !isNarrowString!R1 &&
    isInputRange!R2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    static if (isRandomAccessRange!R1 && hasLength!R1 && hasSlicing!R1 &&
               isRandomAccessRange!R2 && hasLength!R2)
    {
        immutable limit = min(r1.length, r2.length);
        foreach (i; 0 .. limit)
        {
            if (!binaryFun!pred(r1[i], r2[i]))
            {
                return r1[0 .. i];
            }
        }
        return r1[0 .. limit];
    }
    else
    {
        auto result = r1.save;
        size_t i = 0;
        for (;
             !r1.empty && !r2.empty && binaryFun!pred(r1.front, r2.front);
             ++i, r1.popFront(), r2.popFront())
        {}
        return takeExactly(result, i);
    }
}

auto commonPrefix(alias pred, R1, R2)(R1 r1, R2 r2)
if (isNarrowString!R1 &&
    isInputRange!R2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    import std.utf : decode;

    auto result = r1.save;
    immutable len = r1.length;
    size_t i = 0;

    for (size_t j = 0; i < len && !r2.empty; r2.popFront(), i = j)
    {
        immutable f = decode(r1, j);
        if (!binaryFun!pred(f, r2.front))
            break;
    }

    return result[0 .. i];
}

auto commonPrefix(R1, R2)(R1 r1, R2 r2)
if ( isNarrowString!R1 &&
    !isNarrowString!R2 && isInputRange!R2 &&
    is(typeof(r1.front == r2.front)))
{
    return commonPrefix!"a == b"(r1, r2);
}

auto commonPrefix(R1, R2)(R1 r1, R2 r2)
if (isNarrowString!R1 &&
    isNarrowString!R2)
{
    import std.utf : UTFException, stride;

    static if (ElementEncodingType!R1.sizeof == ElementEncodingType!R2.sizeof)
    {
        immutable limit = min(r1.length, r2.length);
        for (size_t i = 0; i < limit;)
        {
            immutable codeLen = std.utf.stride(r1, i);
            size_t j = 0;

            for (; j < codeLen && i < limit; ++i, ++j)
            {
                if (r1[i] != r2[i])
                    return r1[0 .. i - j];
            }

            if (i == limit && j < codeLen)
                throw new UTFException("Invalid UTF-8 sequence", i);
        }
        return r1[0 .. limit];
    }
    else
        return commonPrefix!"a == b"(r1, r2);
}

unittest
{
    import std.typetuple : TypeTuple;
    import std.conv : to;
    import std.utf : UTFException;
    import std.exception : assertThrown;

    assert(commonPrefix([1, 2, 3], [1, 2, 3, 4, 5]) == [1, 2, 3]);
    assert(commonPrefix([1, 2, 3, 4, 5], [1, 2, 3]) == [1, 2, 3]);
    assert(commonPrefix([1, 2, 3, 4], [1, 2, 3, 4]) == [1, 2, 3, 4]);
    assert(commonPrefix([1, 2, 3], [7, 2, 3, 4, 5]).empty);
    assert(commonPrefix([7, 2, 3, 4, 5], [1, 2, 3]).empty);
    assert(commonPrefix([1, 2, 3], cast(int[])null).empty);
    assert(commonPrefix(cast(int[])null, [1, 2, 3]).empty);
    assert(commonPrefix(cast(int[])null, cast(int[])null).empty);

    foreach (S; TypeTuple!( char[], const( char)[],  string,
                           wchar[], const(wchar)[], wstring,
                           dchar[], const(dchar)[], dstring))
    {
        foreach (T; TypeTuple!(string, wstring, dstring))
        {
            assert(commonPrefix(to!S(""), to!T("")).empty);
            assert(commonPrefix(to!S(""), to!T("hello")).empty);
            assert(commonPrefix(to!S("hello"), to!T("")).empty);
            assert(commonPrefix(to!S("hello, world"), to!T("hello, there")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, there"), to!T("hello, world")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, "), to!T("hello, world")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, world"), to!T("hello, ")) == to!S("hello, "));
            assert(commonPrefix(to!S("hello, world"), to!T("hello, world")) == to!S("hello, world"));

            //Bug# 8890
            assert(commonPrefix(to!S("Пиво"), to!T("Пони"))== to!S("П"));
            assert(commonPrefix(to!S("Пони"), to!T("Пиво"))== to!S("П"));
            assert(commonPrefix(to!S("Пиво"), to!T("Пиво"))== to!S("Пиво"));
            assert(commonPrefix(to!S("\U0010FFFF\U0010FFFB\U0010FFFE"),
                                to!T("\U0010FFFF\U0010FFFB\U0010FFFC")) == to!S("\U0010FFFF\U0010FFFB"));
            assert(commonPrefix(to!S("\U0010FFFF\U0010FFFB\U0010FFFC"),
                                to!T("\U0010FFFF\U0010FFFB\U0010FFFE")) == to!S("\U0010FFFF\U0010FFFB"));
            assert(commonPrefix!"a != b"(to!S("Пиво"), to!T("онво")) == to!S("Пи"));
            assert(commonPrefix!"a != b"(to!S("онво"), to!T("Пиво")) == to!S("он"));
        }

        static assert(is(typeof(commonPrefix(to!S("Пиво"), filter!"true"("Пони"))) == S));
        assert(equal(commonPrefix(to!S("Пиво"), filter!"true"("Пони")), to!S("П")));

        static assert(is(typeof(commonPrefix(filter!"true"("Пиво"), to!S("Пони"))) ==
                      typeof(takeExactly(filter!"true"("П"), 1))));
        assert(equal(commonPrefix(filter!"true"("Пиво"), to!S("Пони")), takeExactly(filter!"true"("П"), 1)));
    }

    assertThrown!UTFException(commonPrefix("\U0010FFFF\U0010FFFB", "\U0010FFFF\U0010FFFB"[0 .. $ - 1]));

    assert(commonPrefix("12345"d, [49, 50, 51, 60, 60]) == "123"d);
    assert(commonPrefix([49, 50, 51, 60, 60], "12345" ) == [49, 50, 51]);
    assert(commonPrefix([49, 50, 51, 60, 60], "12345"d) == [49, 50, 51]);

    assert(commonPrefix!"a == ('0' + b)"("12345" , [1, 2, 3, 9, 9]) == "123");
    assert(commonPrefix!"a == ('0' + b)"("12345"d, [1, 2, 3, 9, 9]) == "123"d);
    assert(commonPrefix!"('0' + a) == b"([1, 2, 3, 9, 9], "12345" ) == [1, 2, 3]);
    assert(commonPrefix!"('0' + a) == b"([1, 2, 3, 9, 9], "12345"d) == [1, 2, 3]);
}
