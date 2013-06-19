// Written in the D programming language.

module std.algorithm.comparison;
//debug = std_algorithm;

import std.algorithm;
import std.range, std.traits;
import std.functional : unaryFun, binaryFun;
import std.typecons : Tuple, tuple;


/**
 * Returns $(D true) if and only if the two ranges compare equal element
 * for element, according to binary predicate $(D pred). The ranges may
 * have different element types, as long as $(D pred(a, b)) evaluates to
 * $(D bool) for $(D a) in $(D r1) and $(D b) in $(D r2). Performs
 * $(BIGOH min(r1.length, r2.length)) evaluations of $(D pred). See also
 * $(WEB sgi.com/tech/stl/_equal.html, STL's _equal).
 */
bool equal(Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2 &&
    is(typeof(r1.front == r2.front)))
{
    static if (isArray!Range1 &&
               isArray!Range2 &&
               is(typeof(r1 == r2)))
    {
        //Ranges are comparable. Let the compiler do the comparison.
        return r1 == r2;
    }
    else
    {
        //Need to do an actual compare, delegate to predicate version
        return equal!"a==b"(r1, r2);
    }
}

/// Ditto
bool equal(alias pred, Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2 &&
    is(typeof(binaryFun!pred(r1.front, r2.front))))
{
    //Try a fast implementation when the ranges have comparable lengths
    static if (hasLength!Range1 &&
               hasLength!Range2 &&
               is(typeof(r1.length == r2.length)))
    {
        auto len1 = r1.length;
        auto len2 = r2.length;
        if (len1 != len2)
            return false; //Short circuit return

        //Lengths are the same, so we need to do an actual comparison
        //Good news is we can sqeeze out a bit of performance by not checking if r2 is empty
        for (; !r1.empty; r1.popFront(), r2.popFront())
        {
            if (!binaryFun!pred(r1.front, r2.front))
                return false;
        }
        return true;
    }
    else
    {
        //Generic case, we have to walk both ranges making sure neither is empty
        for (; !r1.empty; r1.popFront(), r2.popFront())
        {
            if (r2.empty)
                return false;
            if (!binaryFun!pred(r1.front, r2.front))
                return false;
        }
        return r2.empty;
    }
}

///
unittest
{
    import std.math : approxEqual;

    int[] a = [ 1, 2, 4, 3 ];
    assert(!equal(a, a[1 .. $]));
    assert( equal(a, a));

    // different types
    double[] b = [ 1.0, 2, 4, 3 ];
    assert(!equal(a, b[1 .. $]));
    assert( equal(a, b));

    // predicated: ensure that two vectors are approximately equal
    double[] c = [ 1.005, 2, 4, 3 ];
    assert( equal!approxEqual(b, c));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.math : approxEqual;

    int[] a = [ 1, 2, 4, 3];
    assert(!equal(a, a[1..$]));
    assert( equal(a, a));
    // test with different types
    double[] b = [ 1.0, 2, 4, 3];
    assert(!equal(a, b[1..$]));
    assert( equal(a, b));

    // predicated
    double[] c = [ 1.005, 2, 4, 3];
    assert( equal!approxEqual(b, c));

    // various strings
    assert( equal("æøå", "æøå"));       //UTF8 vs UTF8
    assert(!equal("???", "æøå"));       //UTF8 vs UTF8
    assert( equal("æøå"w, "æøå"d));     //UTF16 vs UTF32
    assert(!equal("???"w, "æøå"d));     //UTF16 vs UTF32
    assert( equal("æøå"d, "æøå"d));     //UTF32 vs UTF32
    assert(!equal("???"d, "æøå"d));     //UTF32 vs UTF32
    assert(!equal("hello", "world"));

    // same strings, but "explicit non default" comparison (to test the non optimized array comparison)
    assert( equal!"a==b"("æøå", "æøå"));    //UTF8 vs UTF8
    assert(!equal!"a==b"("???", "æøå"));    //UTF8 vs UTF8
    assert( equal!"a==b"("æøå"w, "æøå"d));  //UTF16 vs UTF32
    assert(!equal!"a==b"("???"w, "æøå"d));  //UTF16 vs UTF32
    assert( equal!"a==b"("æøå"d, "æøå"d));  //UTF32 vs UTF32
    assert(!equal!"a==b"("???"d, "æøå"d));  //UTF32 vs UTF32
    assert(!equal!"a==b"("hello", "world"));

    //Array of string
    assert( equal(["hello", "world"], ["hello", "world"]));
    assert(!equal(["hello", "world"], ["hello"]));
    assert(!equal(["hello", "world"], ["hello", "Bob!"]));

    //Should not compile, because "string == dstring" is illegal
    static assert(!is(typeof(equal(["hello", "world"], ["hello"d, "world"d]))));
    //However, arrays of non-matching string can be compared using equal!equal. Neat-o!
    equal!equal(["hello", "world"], ["hello"d, "world"d]);

    //Tests, with more fancy map ranges
    assert( equal([2, 4, 8, 6], map!"a*2"(a)));
    assert( equal!approxEqual(map!"a*2"(b), map!"a*2"(c)));
    assert(!equal([2, 4, 1, 3], map!"a*2"(a)));
    assert(!equal([2, 4, 1], map!"a*2"(a)));
    assert(!equal!approxEqual(map!"a*3"(b), map!"a*2"(c)));

    //Tests with some fancy reference ranges.
    ReferenceInputRange!int cir = new ReferenceInputRange!int([1, 2, 4, 3]);
    ReferenceForwardRange!int cfr = new ReferenceForwardRange!int([1, 2, 4, 3]);
    assert(equal(cir, a));
    cir = new ReferenceInputRange!int([1, 2, 4, 3]);
    assert(equal(cir, cfr.save));
    assert(equal(cfr.save, cfr.save));
    cir = new ReferenceInputRange!int([1, 2, 8, 1]);
    assert(!equal(cir, cfr));

    //Test with an infinte range
    ReferenceInfiniteForwardRange!int ifr = new ReferenceInfiniteForwardRange!int;
    assert(!equal(a, ifr));
}


/**********************************
 * Performs three-way lexicographical comparison on two input ranges
 * according to predicate $(D pred). Iterating $(D r1) and $(D r2) in
 * lockstep, $(D cmp) compares each element $(D e1) of $(D r1) with the
 * corresponding element $(D e2) in $(D r2). If $(D binaryFun!pred(e1,
 * e2)), $(D cmp) returns a negative value. If $(D binaryFun!pred(e2,
 * e1)), $(D cmp) returns a positive value. If one of the ranges has been
 * finished, $(D cmp) returns a negative value if $(D r1) has fewer
 * elements than $(D r2), a positive value if $(D r1) has more elements
 * than $(D r2), and $(D 0) if the ranges have the same number of
 * elements.
 *
 * If the ranges are strings, $(D cmp) performs UTF decoding
 * appropriately and compares the ranges one code point at a time.
 */
int cmp(alias pred = "a < b", R1, R2)(R1 r1, R2 r2)
if (isInputRange!R1 && !isSomeString!R1 &&
    isInputRange!R2 && !isSomeString!R2)
{
    for (; ; r1.popFront(), r2.popFront())
    {
        if (r1.empty)
            return -cast(int)!r2.empty;
        if (r2.empty)
            return !r1.empty;
        auto a = r1.front, b = r2.front;
        if (binaryFun!pred(a, b))
            return -1;
        if (binaryFun!pred(b, a))
            return 1;
    }
}

// Specialization for strings (for speed purposes)
int cmp(alias pred = "a < b", R1, R2)(R1 r1, R2 r2)
if (isSomeString!R1 && isSomeString!R2)
{
    static if (is(typeof(pred) : string))
        enum isLessThan = pred == "a < b";
    else
        enum isLessThan = false;

    // For speed only
    static int threeWay(size_t a, size_t b)
    {
        static if (size_t.sizeof == int.sizeof && isLessThan)
            return a - b;
        else
            return binaryFun!pred(b, a) ? 1 : binaryFun!pred(a, b) ? -1 : 0;
    }
    // For speed only
    // @@@BUG@@@ overloading should be allowed for nested functions
    static int threeWayInt(int a, int b)
    {
        static if (isLessThan)
            return a - b;
        else
            return binaryFun!pred(b, a) ? 1 : binaryFun!pred(a, b) ? -1 : 0;
    }

    static if (typeof(r1[0]).sizeof == typeof(r2[0]).sizeof && isLessThan)
    {
        static if (typeof(r1[0]).sizeof == 1)
        {
            import core.stdc.string : memcmp;

            immutable len = min(r1.length, r2.length);
            immutable result = __ctfe ?
                {
                    foreach (i; 0 .. len)
                    {
                        if (r1[i] != r2[i])
                            return threeWayInt(r1[i], r2[i]);
                    }
                    return 0;
                }()
                : std.c.string.memcmp(r1.ptr, r2.ptr, len);
            if (result)
                return result;
        }
        else
        {
            auto p1 = r1.ptr, p2 = r2.ptr;
            auto pEnd = p1 + min(r1.length, r2.length);
            for (; p1 != pEnd; ++p1, ++p2)
            {
                if (*p1 != *p2)
                    return threeWayInt(cast(int) *p1, cast(int) *p2);
            }
        }
        return threeWay(r1.length, r2.length);
    }
    else
    {
        import std.utf : decode;

        for (size_t i1, i2; ; )
        {
            if (i1 == r1.length)
                return threeWay(i2, r2.length);
            if (i2 == r2.length)
                return threeWay(r1.length, i1);
            immutable c1 = std.utf.decode(r1, i1),
                c2 = std.utf.decode(r2, i2);
            if (c1 != c2)
                return threeWayInt(cast(int) c1, cast(int) c2);
        }
    }
}

unittest
{
    debug(string) printf("string.cmp.unittest\n");

    assert(cmp("abc", "abc") == 0);
  //assert(cmp(null, null) == 0);
    assert(cmp("", "") == 0);
    assert(cmp("abc", "abcd") < 0);
    assert(cmp("abcd", "abc") > 0);
    assert(cmp("abc"d, "abd") < 0);
    assert(cmp("bbc", "abc"w) > 0);
    assert(cmp("aaa", "aaaa"d) < 0);
    assert(cmp("aaaa", "aaa"d) > 0);
    assert(cmp("aaa", "aaa"d) == 0);
    assert(cmp((int[]).init, (int[]).init) == 0);
    assert(cmp([1, 2, 3], [1, 2, 3]) == 0);
    assert(cmp([1, 3, 2], [1, 2, 3]) > 0);
    assert(cmp([1, 2, 3], [1L, 2, 3, 4]) < 0);
    assert(cmp([1L, 2, 3], [1, 2]) > 0);
}


// MinType
template MinType(T...)
{
    static assert(T.length >= 2);

    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
        {
            alias MinType = CommonType!(T[0 .. 2]);
        }
        else
        {
            enum hasMostNegative = is(typeof(mostNegative!(T[0]))) &&
                                   is(typeof(mostNegative!(T[1])));
            static if (hasMostNegative && mostNegative!(T[1]) < mostNegative!(T[0]))
            {
                alias MinType = T[1];
            }
            else static if (hasMostNegative && mostNegative!(T[1]) > mostNegative!(T[0]))
            {
                alias MinType = T[0];
            }
            else static if (T[1].max < T[0].max)
            {
                alias MinType = T[1];
            }
            else
                alias MinType = T[0];
        }
    }
    else
    {
        alias MinType = MinType!(MinType!(T[0 .. 2]), T[2 .. $]);
    }
}

/**
 * Returns the minimum of the passed-in values. The type of the result is
 * computed by using $(XREF traits, CommonType).
 */
MinType!(T1, T2, T)
min(T1, T2, T...)(T1 a, T2 b, T xs)
if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 &&
                   isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
            {
                immutable chooseB = b < a && a > 0;
            }
            else
                immutable chooseB = b < a || b < 0;
        }
        else
            immutable chooseB = b < a;

        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return min(min(a, b), xs);
    }
}

///
unittest
{
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = min(a, b);
    static assert(is(typeof(d) == int));
    assert(d == 5);
    auto e = min(a, b, c);
    static assert(is(typeof(e) == double));
    assert(e == 2);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    // mixed signedness test
    int a = -10;
    uint f = 10;
    static assert(is(typeof(min(a, f)) == int));
    assert(min(a, f) == -10);

    //Test user-defined types
    import std.datetime;
    assert(min(Date(2012, 12, 21), Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(min(Date(1982, 1, 4), Date(2012, 12, 21)) == Date(1982, 1, 4));
    assert(min(Date(1982, 1, 4), Date.min) == Date.min);
    assert(min(Date.min, Date(1982, 1, 4)) == Date.min);
    assert(min(Date(1982, 1, 4), Date.max) == Date(1982, 1, 4));
    assert(min(Date.max, Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(min(Date.min, Date.max) == Date.min);
    assert(min(Date.max, Date.min) == Date.min);
}


// MaxType
template MaxType(T...)
{
    static assert(T.length >= 2);

    static if (T.length == 2)
    {
        static if (!is(typeof(T[0].min)))
        {
            alias MaxType = CommonType!(T[0 .. 2]);
        }
        else static if (T[1].max > T[0].max)
        {
            alias MaxType = T[1];
        }
        else
            alias MaxType = T[0];
    }
    else
    {
        alias MaxType = MaxType!(MaxType!(T[0], T[1]), T[2 .. $]);
    }
}

/**
 * Returns the maximum of the passed-in values. The type of the result is
 * computed by using $(XREF traits, CommonType).
 */
MaxType!(T1, T2, T)
max(T1, T2, T...)(T1 a, T2 b, T xs)
if (is(typeof(a < b)))
{
    static if (T.length == 0)
    {
        static if (isIntegral!T1 &&
                   isIntegral!T2 &&
                   (mostNegative!T1 < 0) != (mostNegative!T2 < 0))
        {
            static if (mostNegative!T1 < 0)
            {
                immutable chooseB = b > a || a < 0;
            }
            else
                immutable chooseB = b > a && b > 0;
        }
        else
            immutable chooseB = b > a;

        return cast(typeof(return)) (chooseB ? b : a);
    }
    else
    {
        return max(max(a, b), xs);
    }
}

///
unittest
{
    int a = 5;
    short b = 6;
    double c = 2;
    auto d = max(a, b);
    static assert(is(typeof(d) == int));
    assert(d == 6);
    auto e = max(a, b, c);
    static assert(is(typeof(e) == double));
    assert(e == 6);
}
unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    // mixed sign
    int a = -5;
    uint f = 5;
    static assert(is(typeof(max(a, f)) == uint));
    assert(max(a, f) == 5);

    //Test user-defined types
    import std.datetime;
    assert(max(Date(2012, 12, 21), Date(1982, 1, 4)) == Date(2012, 12, 21));
    assert(max(Date(1982, 1, 4), Date(2012, 12, 21)) == Date(2012, 12, 21));
    assert(max(Date(1982, 1, 4), Date.min) == Date(1982, 1, 4));
    assert(max(Date.min, Date(1982, 1, 4)) == Date(1982, 1, 4));
    assert(max(Date(1982, 1, 4), Date.max) == Date.max);
    assert(max(Date.max, Date(1982, 1, 4)) == Date.max);
    assert(max(Date.min, Date.max) == Date.max);
    assert(max(Date.max, Date.min) == Date.max);
}


/**
 * Sequentially compares elements in $(D r1) and $(D r2) in lockstep, and
 * stops at the first mismatch (according to $(D pred), by default
 * equality). Returns a tuple with the reduced ranges that start with the
 * two mismatched values. Performs $(BIGOH min(r1.length, r2.length))
 * evaluations of $(D pred). See also $(WEB
 * sgi.com/tech/stl/_mismatch.html, STL's _mismatch).
 */
Tuple!(Range1, Range2)
mismatch(alias pred = "a == b", Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 &&
    isInputRange!Range2)
{
    for (; !r1.empty && !r2.empty; r1.popFront(), r2.popFront())
    {
        if (!binaryFun!pred(r1.front, r2.front))
            break;
    }
    return tuple(r1, r2);
}

///
unittest
{
    int[]    x = [ 1,  5, 2, 7,   4, 3 ];
    double[] y = [ 1.0, 5, 2, 7.3, 4, 8 ];
    auto m = mismatch(x, y);
    assert(m[0] == x[3 .. $]);
    assert(m[1] == y[3 .. $]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    // doc example
    int[]    x = [ 1,  5, 2, 7,   4, 3 ];
    double[] y = [ 1.0, 5, 2, 7.3, 4, 8 ];
    auto m = mismatch(x, y);
    assert(m[0] == [ 7, 4, 3 ]);
    assert(m[1] == [ 7.3, 4, 8 ]);

    int[] a = [ 1, 2, 3 ];
    int[] b = [ 1, 2, 4, 5 ];
    auto mm = mismatch(a, b);
    assert(mm[0] == [3]);
    assert(mm[1] == [4, 5]);
}


/**
 * Encodes $(WEB realityinteractive.com/rgrzywinski/archives/000249.html,
 * edit operations) necessary to transform one sequence into
 * another. Given sequences $(D s) (source) and $(D t) (target), a
 * sequence of $(D EditOp) encodes the steps that need to be taken to
 * convert $(D s) into $(D t). For example, if $(D s = "cat") and $(D
 * "cars"), the minimal sequence that transforms $(D s) into $(D t) is:
 * skip two characters, replace 't' with 'r', and insert an 's'. Working
 * with edit operations is useful in applications such as spell-checkers
 * (to find the closest word to a given misspelled word), approximate
 * searches, diff-style programs that compute the difference between
 * files, efficient encoding of patches, DNA sequence analysis, and
 * plagiarism detection.
 */
enum EditOp : char
{
    /** Current items are equal; no editing is necessary. */
    none = 'n',
    /** Substitute current item in target with current item in source. */
    substitute = 's',
    /** Insert current item from the source into the target. */
    insert = 'i',
    /** Remove current item from the target. */
    remove = 'r'
}

struct Levenshtein(Range, alias equals, CostType = size_t)
{
    void deletionIncrement(CostType n)
    {
        _deletionIncrement = n;
        InitMatrix();
    }

    void insertionIncrement(CostType n)
    {
        _insertionIncrement = n;
        InitMatrix();
    }

    CostType distance(Range s, Range t)
    {
        auto slen = walkLength(s.save);
        auto tlen = walkLength(t.save);

        allocMatrix(slen + 1, tlen + 1);
        foreach (i; 1 .. rows)
        {
            auto sfront = s.front;
            s.popFront();
            auto tt = t;
            foreach (j; 1 .. cols)
            {
                auto cSub = _matrix[i - 1][j - 1]
                    + (equals(sfront, tt.front) ? 0 : _substitutionIncrement);
                tt.popFront();
                auto cIns = _matrix[i][j - 1] + _insertionIncrement;
                auto cDel = _matrix[i - 1][j] + _deletionIncrement;
                switch (min_index(cSub, cIns, cDel))
                {
                case 0:
                    _matrix[i][j] = cSub;
                    break;
                case 1:
                    _matrix[i][j] = cIns;
                    break;
                default:
                    _matrix[i][j] = cDel;
                    break;
                }
            }
        }
        return _matrix[slen][tlen];
    }

    EditOp[] path(Range s, Range t)
    {
        distance(s, t);
        return path();
    }

    EditOp[] path()
    {
        EditOp[] result;
        size_t i = rows - 1, j = cols - 1;
        // restore the path
        while (i || j)
        {
            auto cIns = j == 0 ? CostType.max : _matrix[i][j - 1];
            auto cDel = i == 0 ? CostType.max : _matrix[i - 1][j];
            auto cSub = i == 0 || j == 0
                ? CostType.max
                : _matrix[i - 1][j - 1];
            switch (min_index(cSub, cIns, cDel))
            {
            case 0:
                result ~= _matrix[i - 1][j - 1] == _matrix[i][j]
                    ? EditOp.none
                    : EditOp.substitute;
                --i;
                --j;
                break;
            case 1:
                result ~= EditOp.insert;
                --j;
                break;
            default:
                result ~= EditOp.remove;
                --i;
                break;
            }
        }
        reverse(result);
        return result;
    }

private:
    CostType _deletionIncrement = 1,
             _insertionIncrement = 1,
             _substitutionIncrement = 1;
    CostType[][] _matrix;
    size_t rows, cols;

    void allocMatrix(size_t r, size_t c)
    {
        rows = r;
        cols = c;
        if (!_matrix || _matrix.length < r || _matrix[0].length < c)
        {
            delete _matrix;
            _matrix = new CostType[][](r, c);
            InitMatrix();
        }
    }

    void InitMatrix()
    {
        foreach (i, row; _matrix)
        {
            row[0] = i * _deletionIncrement;
        }
        if (!_matrix)
            return;
        for (auto i = 0u; i != _matrix[0].length; ++i)
        {
            _matrix[0][i] = i * _insertionIncrement;
        }
    }

    static uint min_index(CostType i0, CostType i1, CostType i2)
    {
        if (i0 <= i1)
        {
            return i0 <= i2 ? 0 : 2;
        }
        else
        {
            return i1 <= i2 ? 1 : 2;
        }
    }
}

/**
 * Returns the $(WEB wikipedia.org/wiki/Levenshtein_distance, Levenshtein
 * distance) between $(D s) and $(D t). The Levenshtein distance computes
 * the minimal amount of edit operations necessary to transform $(D s)
 * into $(D t).  Performs $(BIGOH s.length * t.length) evaluations of $(D
 * equals) and occupies $(BIGOH s.length * t.length) storage.
 */
size_t levenshteinDistance(alias equals = "a == b", Range1, Range2)(Range1 s, Range2 t)
if (isForwardRange!Range1 && isForwardRange!Range2)
{
    Levenshtein!(Range1, binaryFun!equals, size_t) lev;
    return lev.distance(s, t);
}

///
unittest
{
    import std.uni : toUpper;

    assert(levenshteinDistance("cat", "rat") == 1);
    assert(levenshteinDistance("parks", "spark") == 2);
    assert(levenshteinDistance("kitten", "sitting") == 3);
    assert(levenshteinDistance!((a, b) => toUpper(a) == toUpper(b))("parks", "SPARK") == 2);
}


/**
 * Returns the Levenshtein distance and the edit path between $(D s) and
 * $(D t).
 */
Tuple!(size_t, EditOp[])
levenshteinDistanceAndPath(alias equals = "a == b", Range1, Range2)(Range1 s, Range2 t)
if (isForwardRange!Range1 && isForwardRange!Range2)
{
    Levenshtein!(Range1, binaryFun!(equals)) lev;
    auto d = lev.distance(s, t);
    return tuple(d, lev.path());
}

///
unittest
{
    string a = "Saturday", b = "Sunday";
    auto p = levenshteinDistanceAndPath(a, b);
    assert(p[0] == 3);
    assert(equal(p[1], "nrrnsnnn"));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(levenshteinDistance("a", "a") == 0);
    assert(levenshteinDistance("a", "b") == 1);
    assert(levenshteinDistance("aa", "ab") == 1);
    assert(levenshteinDistance("aa", "abc") == 2);
    assert(levenshteinDistance("Saturday", "Sunday") == 3);
    assert(levenshteinDistance("kitten", "sitting") == 3);
    //lev.deletionIncrement = 2;
    //lev.insertionIncrement = 100;
    string a = "Saturday", b = "Sunday";
    auto p = levenshteinDistanceAndPath(a, b);
    assert(cast(string) p[1] == "nrrnsnnn");
}
