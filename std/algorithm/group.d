module std.algorithm.group;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
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
