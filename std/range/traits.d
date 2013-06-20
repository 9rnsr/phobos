module std.range.traits;

import std.range;
import std.traits;


/**
 * Returns $(D true) if $(D R) is an input range. An input range must
 * define the primitives $(D empty), $(D popFront), and $(D front). The
 * following code should compile for any input range.
 *
 * ----
 * R r;              // can define a range object
 * if (r.empty) {}   // can test for empty
 * r.popFront();     // can invoke popFront()
 * auto h = r.front; // can get the front of the range of non-void type
 * ----
 *
 * The semantics of an input range (not checkable during compilation) are
 * assumed to be the following ($(D r) is an object of type $(D R)):
 *
 * $(UL $(LI $(D r.empty) returns $(D false) iff there is more data
 * available in the range.)  $(LI $(D r.front) returns the current
 * element in the range. It may return by value or by reference. Calling
 * $(D r.front) is allowed only if calling $(D r.empty) has, or would
 * have, returned $(D false).) $(LI $(D r.popFront) advances to the next
 * element in the range. Calling $(D r.popFront) is allowed only if
 * calling $(D r.empty) has, or would have, returned $(D false).))
 */
template isInputRange(R)
{
    enum bool isInputRange = is(typeof(
    (inout int = 0)
    {
        R r = void;       // can define a range object
        if (r.empty) {}   // can test for empty
        r.popFront();     // can invoke popFront()
        auto h = r.front; // can get the front of the range
    }));
}

unittest
{
    struct A {}
    struct B
    {
        void popFront();
        @property bool empty();
        @property int front();
    }
    static assert(!isInputRange!(A));
    static assert( isInputRange!(B));
    static assert( isInputRange!(int[]));
    static assert( isInputRange!(char[]));
    static assert(!isInputRange!(char[4]));
    static assert( isInputRange!(inout(int)[])); // bug 7824
}


/**
 * Outputs $(D e) to $(D r). The exact effect is dependent upon the two
 * types. Several cases are accepted, as described below. The code snippets
 * are attempted in order, and the first to compile "wins" and gets
 * evaluated.
 *
 * $(BOOKTABLE ,
 * $(TR $(TH Code Snippet) $(TH Scenario
 * ))
 * $(TR $(TD $(D r.put(e);)) $(TD $(D R) specifically defines a method
 *     $(D put) accepting an $(D E).
 * ))
 * $(TR $(TD $(D r.put([ e ]);)) $(TD $(D R) specifically defines a
 *     method $(D put) accepting an $(D E[]).
 * ))
 * $(TR $(TD $(D r.front = e; r.popFront();)) $(TD $(D R) is an input
 *     range and $(D e) is assignable to $(D r.front).
 * ))
 * $(TR $(TD $(D for (; !e.empty; e.popFront()) put(r, e.front);)) $(TD
 *     Copying range $(D E) to range $(D R).
 * ))
 * $(TR $(TD $(D r(e);)) $(TD $(D R) is e.g. a delegate accepting an $(D
 *     E).
 * ))
 * $(TR $(TD $(D r([ e ]);)) $(TD $(D R) is e.g. a $(D delegate)
 *     accepting an $(D E[]).
 * ))
 * )
 */
void put(R, E)(ref R r, E e)
{
    static if (is(PointerTarget!R == struct))
        enum usingPut = hasMember!(PointerTarget!R, "put");
    else
        enum usingPut = hasMember!(R, "put");

    enum usingFront = !usingPut && isInputRange!R;
    enum usingCall = !usingPut && !usingFront;

    static if (usingPut && is(typeof(r.put(e))))
    {
        r.put(e);
    }
    else static if (usingPut && is(typeof(r.put((E[]).init))))
    {
        r.put((&e)[0..1]);
    }
    else static if (usingFront && is(typeof(r.front = e, r.popFront())))
    {
        r.front = e;
        r.popFront();
    }
    else static if ((usingPut || usingFront) && isInputRange!E && is(typeof(put(r, e.front))))
    {
        for (; !e.empty; e.popFront()) put(r, e.front);
    }
    else static if (usingCall && is(typeof(r(e))))
    {
        r(e);
    }
    else static if (usingCall && is(typeof(r((E[]).init))))
    {
        r((&e)[0..1]);
    }
    else
    {
        static assert(false,
                "Cannot put a "~E.stringof~" into a "~R.stringof);
    }
}

unittest
{
    struct A {}
    static assert(!isInputRange!(A));
    struct B
    {
        void put(int) {}
    }
    B b;
    put(b, 5);
}

unittest
{
    int[] a = [1, 2, 3], b = [10, 20];
    auto c = a;
    put(a, b);
    assert(c == [10, 20, 3]);
    assert(a == [3]);
}

unittest
{
    int[] a = new int[10];
    int b;
    static assert(isInputRange!(typeof(a)));
    put(a, b);
}

unittest
{
    void myprint(in char[] s) { }
    auto r = &myprint;
    put(r, 'a');
}

unittest
{
    int[] a = new int[10];
    static assert(!__traits(compiles, put(a, 1.0L)));
    static assert( __traits(compiles, put(a, 1)));
    /*
     * a[0] = 65;       // OK
     * a[0] = 'A';      // OK
     * a[0] = "ABC"[0]; // OK
     * put(a, "ABC");   // OK
     */
    static assert( __traits(compiles, put(a, "ABC")));
}

unittest
{
    char[] a = new char[10];
    static assert(!__traits(compiles, put(a, 1.0L)));
    static assert(!__traits(compiles, put(a, 1)));
    // char[] is NOT output range.
    static assert(!__traits(compiles, put(a, 'a')));
    static assert(!__traits(compiles, put(a, "ABC")));
}

unittest
{
    // Test fix for bug 7476.
    struct LockingTextWriter
    {
        void put(dchar c){}
    }
    struct RetroResult
    {
        bool end = false;
        @property bool empty() const { return end; }
        @property dchar front(){ return 'a'; }
        void popFront(){ end = true; }
    }
    LockingTextWriter w;
    RetroResult r;
    put(w, r);
}


/**
 * Returns $(D true) if $(D R) is an output range for elements of type
 * $(D E). An output range is defined functionally as a range that
 * supports the operation $(D put(r, e)) as defined above.
 */
template isOutputRange(R, E)
{
    enum bool isOutputRange = is(typeof(
    (inout int = 0)
    {
        R r = void;
        E e;
        put(r, e);
    }));
}

unittest
{
    void myprint(in char[] s) {}
    static assert(isOutputRange!(typeof(&myprint), char));

    auto app = appender!string();
    string s;
    static assert( isOutputRange!(Appender!string, string));
    static assert( isOutputRange!(Appender!string*, string));
    static assert(!isOutputRange!(Appender!string, int));
    static assert(!isOutputRange!(char[], char));
    static assert(!isOutputRange!(wchar[], wchar));
    static assert( isOutputRange!(dchar[], char));
    static assert( isOutputRange!(dchar[], wchar));
    static assert( isOutputRange!(dchar[], dchar));

    static assert(!isOutputRange!(const(int)[], int));
    static assert(!isOutputRange!(inout(int)[], int));
}


/**
 * Returns $(D true) if $(D R) is a forward range. A forward range is an
 * input range $(D r) that can save "checkpoints" by saving $(D r.save)
 * to another value of type $(D R). Notable examples of input ranges that
 * are $(I not) forward ranges are file/socket ranges; copying such a
 * range will not save the position in the stream, and they most likely
 * reuse an internal buffer as the entire stream does not sit in
 * memory. Subsequently, advancing either the original or the copy will
 * advance the stream, so the copies are not independent.
 *
 * The following code should compile for any forward range.
 *
 * ----
 * static assert(isInputRange!R);
 * R r1;
 * static assert (is(typeof(r1.save) == R));
 * ----
 *
 * Saving a range is not duplicating it; in the example above, $(D r1)
 * and $(D r2) still refer to the same underlying data. They just
 * navigate that data independently.
 *
 * The semantics of a forward range (not checkable during compilation)
 * are the same as for an input range, with the additional requirement
 * that backtracking must be possible by saving a copy of the range
 * object with $(D save) and using it later.
 */
template isForwardRange(R)
{
    enum bool isForwardRange = isInputRange!R && is(typeof(
    (inout int = 0)
    {
        R r1 = void;
        static assert(is(typeof(r1.save) == R));
    }));
}

unittest
{
    static assert(!isForwardRange!(int));
    static assert( isForwardRange!(int[]));
    static assert( isForwardRange!(inout(int)[]));
}


/**
 * Returns $(D true) if $(D R) is a bidirectional range. A bidirectional
 * range is a forward range that also offers the primitives $(D back) and
 * $(D popBack). The following code should compile for any bidirectional
 * range.
 *
 * ----
 * R r;
 * static assert(isForwardRange!R);           // is forward range
 * r.popBack();                               // can invoke popBack
 * auto t = r.back;                           // can get the back of the range
 * auto w = r.front;
 * static assert(is(typeof(t) == typeof(w))); // same type for front and back
 * ----
 *
 * The semantics of a bidirectional range (not checkable during
 * compilation) are assumed to be the following ($(D r) is an object of
 * type $(D R)):
 *
 * $(UL $(LI $(D r.back) returns (possibly a reference to) the last
 * element in the range. Calling $(D r.back) is allowed only if calling
 * $(D r.empty) has, or would have, returned $(D false).))
 */
template isBidirectionalRange(R)
{
    enum bool isBidirectionalRange = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        r.popBack();
        auto t = r.back;
        auto w = r.front;
        static assert(is(typeof(t) == typeof(w)));
    }));
}

unittest
{
    struct A {}
    struct B
    {
        void popFront();
        @property bool empty();
        @property int front();
    }
    struct C
    {
        @property bool empty();
        @property C save();
        void popFront();
        @property int front();
        void popBack();
        @property int back();
    }
    static assert(!isBidirectionalRange!(A));
    static assert(!isBidirectionalRange!(B));
    static assert( isBidirectionalRange!(C));
    static assert( isBidirectionalRange!(int[]));
    static assert( isBidirectionalRange!(char[]));
    static assert( isBidirectionalRange!(inout(int)[]));
}


/**
 * Returns $(D true) if $(D R) is a random-access range. A random-access
 * range is a bidirectional range that also offers the primitive $(D
 * opIndex), OR an infinite forward range that offers $(D opIndex). In
 * either case, the range must either offer $(D length) or be
 * infinite. The following code should compile for any random-access
 * range.
 *
 * ----
 * // range is finite and bidirectional or infinite and forward.
 * static assert(isBidirectionalRange!R ||
 *               isForwardRange!R && isInfinite!R);
 *
 * R r = void;
 * auto e = r[1]; // can index
 * static assert(is(typeof(e) == typeof(r.front))); // same type for indexed and front
 * static assert(!isNarrowString!R); // narrow strings cannot be indexed as ranges
 * static assert(hasLength!R || isInfinite!R); // must have length or be infinite
 *
 * // $ must work as it does with arrays if opIndex works with $
 * static if(is(typeof(r[$])))
 * {
 *     static assert(is(typeof(r.front) == typeof(r[$])));
 *
 *     // $ - 1 doesn't make sense with infinite ranges but needs to work
 *     // with finite ones.
 *     static if(!isInfinite!R)
 *         static assert(is(typeof(r.front) == typeof(r[$ - 1])));
 * }
 * ----
 *
 * The semantics of a random-access range (not checkable during
 * compilation) are assumed to be the following ($(D r) is an object of
 * type $(D R)): $(UL $(LI $(D r.opIndex(n)) returns a reference to the
 * $(D n)th element in the range.))
 *
 * Although $(D char[]) and $(D wchar[]) (as well as their qualified
 * versions including $(D string) and $(D wstring)) are arrays, $(D
 * isRandomAccessRange) yields $(D false) for them because they use
 * variable-length encodings (UTF-8 and UTF-16 respectively). These types
 * are bidirectional ranges only.
 */
template isRandomAccessRange(R)
{
    enum bool isRandomAccessRange = is(typeof(
    (inout int = 0)
    {
        static assert(isBidirectionalRange!R ||
                      isForwardRange!R && isInfinite!R);
        R r = void;
        auto e = r[1];
        static assert(is(typeof(e) == typeof(r.front)));
        static assert(!isNarrowString!R);
        static assert(hasLength!R || isInfinite!R);

        static if (is(typeof(r[$])))
        {
            static assert(is(typeof(r.front) == typeof(r[$])));

            static if (!isInfinite!R)
                static assert(is(typeof(r.front) == typeof(r[$ - 1])));
        }
    }));
}

unittest
{
    struct A {}
    struct B
    {
        void popFront();
        @property bool empty();
        @property int front();
    }
    struct C
    {
        void popFront();
        @property bool empty();
        @property int front();
        void popBack();
        @property int back();
    }
    struct D
    {
        @property bool empty();
        @property D save();
        @property int front();
        void popFront();
        @property int back();
        void popBack();
        ref int opIndex(uint);
        @property size_t length();
        alias opDollar = length;
        //int opSlice(uint, uint);
    }
    static assert(!isRandomAccessRange!(A));
    static assert(!isRandomAccessRange!(B));
    static assert(!isRandomAccessRange!(C));
    static assert( isRandomAccessRange!(D));
    static assert( isRandomAccessRange!(int[]));
    static assert( isRandomAccessRange!(inout(int)[]));
}

unittest
{
    // Test fix for bug 6935.
    struct R
    {
        @disable this();

        @disable static @property R init();

        @property bool empty() const { return false; }
        @property int front() const { return 0; }
        void popFront() {}

        @property R save() { return this; }

        @property int back() const { return 0; }
        void popBack(){}

        int opIndex(size_t n) const { return 0; }
        @property size_t length() const { return 0; }
        alias opDollar = length;

        void put(int e){  }
    }
    static assert(isInputRange!R);
    static assert(isForwardRange!R);
    static assert(isBidirectionalRange!R);
    static assert(isRandomAccessRange!R);
    static assert(isOutputRange!(R, int));
}


/**
 * Returns $(D true) iff $(D R) supports the $(D moveFront) primitive,
 * as well as $(D moveBack) and $(D moveAt) if it's a bidirectional or
 * random access range.  These may be explicitly implemented, or may work
 * via the default behavior of the module level functions $(D moveFront)
 * and friends.
 */
template hasMobileElements(R)
{
    enum bool hasMobileElements = is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveFront(r);
    }))
    && (!isBidirectionalRange!R || is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveBack(r);
    })))
    && (!isRandomAccessRange!R || is(typeof(
    (inout int = 0)
    {
        R r = void;
        return moveAt(r, 0);
    })));
}

unittest
{
    import std.algorithm;

    static struct HasPostblit
    {
        this(this) {}
    }

    auto nonMobile = map!"a"(repeat(HasPostblit.init));
    static assert(!hasMobileElements!(typeof(nonMobile)));
    static assert( hasMobileElements!(int[]));
    static assert( hasMobileElements!(inout(int)[]));
    static assert( hasMobileElements!(typeof(iota(1000))));
}


/**
 * The element type of $(D R). $(D R) does not have to be a range. The
 * element type is determined as the type yielded by $(D r.front) for an
 * object $(D r) of type $(D R). For example, $(D ElementType!(T[])) is
 * $(D T) if $(D T[]) isn't a narrow string; if it is, the element type is
 * $(D dchar). If $(D R) doesn't have $(D front), $(D ElementType!R) is
 * $(D void).
 */
template ElementType(R)
{
    static if (is(typeof((inout int = 0){ R r = void; return r.front; }()) T))
        alias ElementType = T;
    else
        alias ElementType = void;
}

unittest
{
    enum XYZ : string { a = "foo" }
    auto x = XYZ.a.front;
    immutable char[3] a = "abc";
    int[] i;
    void[] buf;
    static assert(is(ElementType!(XYZ) : dchar));
    static assert(is(ElementType!(typeof(a)) : dchar));
    static assert(is(ElementType!(typeof(i)) : int));
    static assert(is(ElementType!(typeof(buf)) : void));
    static assert(is(ElementType!(inout(int)[]) : inout(int)));
}


/**
 * The encoding element type of $(D R). For narrow strings ($(D char[]),
 * $(D wchar[]) and their qualified variants including $(D string) and
 * $(D wstring)), $(D ElementEncodingType) is the character type of the
 * string. For all other types, $(D ElementEncodingType) is the same as
 * $(D ElementType).
 */
template ElementEncodingType(R)
{
    static if (isNarrowString!R)
        alias ElementEncodingType = typeof((inout int = 0){ R r = void; return r[0]; }());
    else
        alias ElementEncodingType = ElementType!R;
}

unittest
{
    enum XYZ : string { a = "foo" }
    auto x = XYZ.a.front;
    immutable char[3] a = "abc";
    int[] i;
    void[] buf;
    static assert(is(ElementType!(XYZ) : dchar));
    static assert(is(ElementEncodingType!(char[]) == char));
    static assert(is(ElementEncodingType!(string) == immutable char));
    static assert(is(ElementType!(typeof(a)) : dchar));
    static assert(is(ElementType!(typeof(i)) == int));
    static assert(is(ElementEncodingType!(typeof(i)) == int));
    static assert(is(ElementType!(typeof(buf)) : void));

    static assert(is(ElementEncodingType!(inout char[]) : inout(char)));
}


/**
 * Returns $(D true) if $(D R) is a forward range and has swappable
 * elements. The following code should compile for any range
 * with swappable elements.
 *
 * ----
 * R r;
 * static assert(isForwardRange!(R));   // range is forward
 * swap(r.front, r.front);              // can swap elements of the range
 * ----
 */
template hasSwappableElements(R)
{
    enum bool hasSwappableElements = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        import std.algorithm : swap;

        R r = void;
        swap(r.front, r.front);             // can swap elements of the range
    }));
}

unittest
{
    static assert(!hasSwappableElements!(const int[]));
    static assert(!hasSwappableElements!(const(int)[]));
    static assert(!hasSwappableElements!(inout(int)[]));
    static assert( hasSwappableElements!(int[]));
  //static assert( hasSwappableElements!(char[]));
}


/**
 * Returns $(D true) if $(D R) is a forward range and has mutable
 * elements. The following code should compile for any range
 * with assignable elements.
 *
 * ----
 * R r;
 * static assert(isForwardRange!R);  // range is forward
 * auto e = r.front;
 * r.front = e;                      // can assign elements of the range
 * ----
 */
template hasAssignableElements(R)
{
    enum bool hasAssignableElements = isForwardRange!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        static assert(isForwardRange!R);   // range is forward
        auto e = r.front;
        r.front = e;                       // can assign elements of the range
    }));
}

unittest
{
    static assert(!hasAssignableElements!(const int[]));
    static assert(!hasAssignableElements!(const(int)[]));
    static assert( hasAssignableElements!(int[]));
    static assert(!hasAssignableElements!(inout(int)[]));
}


/**
 * Tests whether $(D R) has lvalue elements.  These are defined as elements that
 * can be passed by reference and have their address taken.
 */
template hasLvalueElements(R)
{
    enum bool hasLvalueElements = is(typeof(
    (inout int = 0)
    {
        void checkRef(ref ElementType!R stuff) {}
        R r = void;
        static assert(is(typeof(checkRef(r.front))));
    }));
}

unittest
{
    static assert( hasLvalueElements!(int[]));
    static assert( hasLvalueElements!(const(int)[]));
    static assert( hasLvalueElements!(inout(int)[]));
    static assert( hasLvalueElements!(immutable(int)[]));
    static assert(!hasLvalueElements!(typeof(iota(3))));

    auto c = chain([1, 2, 3], [4, 5, 6]);
    static assert( hasLvalueElements!(typeof(c)));

    // bugfix 6336
    struct S { immutable int value; }
    static assert( isInputRange!(S[]));
    static assert( hasLvalueElements!(S[]));
}


/**
 * Returns $(D true) if $(D R) has a $(D length) member that returns an
 * integral type. $(D R) does not have to be a range. Note that $(D
 * length) is an optional primitive as no range must implement it. Some
 * ranges do not store their length explicitly, some cannot compute it
 * without actually exhausting the range (e.g. socket streams), and some
 * other ranges may be infinite.
 *
 * Although narrow string types ($(D char[]), $(D wchar[]), and their
 * qualified derivatives) do define a $(D length) property, $(D
 * hasLength) yields $(D false) for them. This is because a narrow
 * string's length does not reflect the number of characters, but instead
 * the number of encoding units, and as such is not useful with
 * range-oriented algorithms.
 */
template hasLength(R)
{
    enum bool hasLength = !isNarrowString!R && is(typeof(
    (inout int = 0)
    {
        R r = void;
        static assert(is(typeof(r.length) : ulong));
    }));
}

unittest
{
    static assert(!hasLength!(char[]));
    static assert( hasLength!(int[]));
    static assert( hasLength!(inout(int)[]));

    struct A { ulong length; }
    struct B { size_t length() { return 0; } }
    struct C { @property size_t length() { return 0; } }
    static assert( hasLength!(A));
    static assert(!hasLength!(B));
    static assert( hasLength!(C));
}


/**
 * Returns $(D true) if $(D R) is an infinite input range. An
 * infinite input range is an input range that has a statically-defined
 * enumerated member called $(D empty) that is always $(D false),
 * for example:
 *
 * ----
 * struct MyInfiniteRange
 * {
 *     enum bool empty = false;
 *     ...
 * }
 * ----
 */

template isInfinite(R)
{
    static if (isInputRange!R && __traits(compiles, { enum e = R.empty; }))
        enum bool isInfinite = !R.empty;
    else
        enum bool isInfinite = false;
}

unittest
{
    static assert(!isInfinite!(int[]));
    static assert( isInfinite!(Repeat!(int)));
}


/**
 * Returns $(D true) if $(D R) offers a slicing operator with integral boundaries
 * that returns a forward range type.
 *
 * For finite ranges, the result of $(D opSlice) must be of the same type as the
 * original range type. If the range defines $(D opDollar), then it must support
 * subtraction.
 *
 * For infinite ranges, when $(I not) using $(D opDollar), the result of
 * $(D opSlice) must be the result of $(LREF take) or $(LREF takeExactly) on the
 * original range (they both return the same type for infinite ranges). However,
 * when using $(D opDollar), the result of $(D opSlice) must be that of the
 * original range type.
 *
 * The following code must compile for $(D hasSlicing) to be $(D true):
 *
 * ----
 * R r = void;
 *
 * static if(isInfinite!R)
 *     typeof(take(r, 1)) s = r[1 .. 2];
 * else
 * {
 *     static assert(is(typeof(r[1 .. 2]) == R));
 *     R s = r[1 .. 2];
 * }
 *
 * s = r[1 .. 2];
 *
 * static if(is(typeof(r[0 .. $])))
 * {
 *     static assert(is(typeof(r[0 .. $]) == R));
 *     R t = r[0 .. $];
 *     t = r[0 .. $];
 *
 *     static if(!isInfinite!R)
 *     {
 *         static assert(is(typeof(r[0 .. $ - 1]) == R));
 *         R u = r[0 .. $ - 1];
 *         u = r[0 .. $ - 1];
 *     }
 * }
 *
 * static assert(isForwardRange!(typeof(r[1 .. 2])));
 * static assert(hasLength!(typeof(r[1 .. 2])));
 * ----
 */
template hasSlicing(R)
{
    enum bool hasSlicing = isForwardRange!R && !isNarrowString!R && is(typeof(
    (inout int = 0)
    {
        R r = void;

        static if (isInfinite!R)
            typeof(take(r, 1)) s = r[1 .. 2];
        else
        {
            static assert(is(typeof(r[1 .. 2]) == R));
            R s = r[1 .. 2];
        }

        s = r[1 .. 2];

        static if (is(typeof(r[0 .. $])))
        {
            static assert(is(typeof(r[0 .. $]) == R));
            R t = r[0 .. $];
            t = r[0 .. $];

            static if (!isInfinite!R)
            {
                static assert(is(typeof(r[0 .. $ - 1]) == R));
                R u = r[0 .. $ - 1];
                u = r[0 .. $ - 1];
            }
        }

        static assert(isForwardRange!(typeof(r[1 .. 2])));
        static assert(hasLength!(typeof(r[1 .. 2])));
    }));
}

unittest
{
    static assert( hasSlicing!(int[]));
    static assert( hasSlicing!(const(int)[]));
    static assert(!hasSlicing!(const int[]));
    static assert( hasSlicing!(inout(int)[]));
    static assert(!hasSlicing!(inout int []));
    static assert( hasSlicing!(immutable(int)[]));
    static assert(!hasSlicing!(immutable int[]));
    static assert(!hasSlicing!string);
    static assert( hasSlicing!dstring);

    enum rangeFuncs = "@property int front();" ~
                      "void popFront();" ~
                      "@property bool empty();" ~
                      "@property auto save() { return this; }" ~
                      "@property size_t length();";

    struct A { mixin(rangeFuncs); int opSlice(size_t, size_t); }
    struct B { mixin(rangeFuncs); B opSlice(size_t, size_t); }
    struct C { mixin(rangeFuncs); @disable this(); C opSlice(size_t, size_t); }
    struct D { mixin(rangeFuncs); int[] opSlice(size_t, size_t); }
    static assert(!hasSlicing!(A));
    static assert( hasSlicing!(B));
    static assert( hasSlicing!(C));
    static assert(!hasSlicing!(D));

    struct InfOnes
    {
        enum empty = false;
        void popFront() {}
        @property int front() { return 1; }
        @property InfOnes save() { return this; }
        auto opSlice(size_t i, size_t j) { return takeExactly(this, j - i); }
        auto opSlice(size_t i, Dollar d) { return this; }

        struct Dollar {}
        Dollar opDollar() const { return Dollar.init; }
    }

    static assert(hasSlicing!InfOnes);
}
