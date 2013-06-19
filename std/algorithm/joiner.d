module std.algorithm.joiner;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
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
