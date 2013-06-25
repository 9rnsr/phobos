module std.algorithm.splitter;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
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
    (isNarrowString!Range || hasSlicing!Range))
{
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
            _frontLength = _input.length - find(_input, _separator).length;
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
            static if (isBidirectionalRange!Range)
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
        static if (isBidirectionalRange!Range)
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
