module std.algorithm.move;

import std.algorithm;
import std.range, std.functional, std.traits;
import std.typecons : Tuple, tuple;

version(unittest)
{
}

/**
 * Moves $(D source) into $(D target) via a destructive
 * copy. Specifically: $(UL $(LI If $(D hasAliasing!T) is true (see
 * $(XREF traits, hasAliasing)), then the representation of $(D source)
 * is bitwise copied into $(D target) and then $(D source = T.init) is
 * evaluated.)  $(LI Otherwise, $(D target = source) is evaluated.)) See
 * also $(XREF exception, pointsTo).
 *
 * Preconditions:
 * $(D &source == &target || !pointsTo(source, source))
 */
void move(T)(ref T source, ref T target)
{
    import std.exception : pointsTo;
    import core.stdc.string : memcpy;

    assert(!pointsTo(source, source));
    static if (is(T == struct))
    {
        if (&source == &target)
            return;
        // Most complicated case. Destroy whatever target had in it
        // and bitblast source over it
        static if (hasElaborateDestructor!T)
        {
            typeid(T).destroy(&target);
        }

        memcpy(&target, &source, T.sizeof);

        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
        static if (hasElaborateDestructor!T || hasElaborateCopyConstructor!T)
        {
            static T empty;
            static if (T.tupleof.length > 0 &&
                       T.tupleof[$-1].stringof.endsWith("this"))
            {
                // If T is nested struct, keep original context pointer
                memcpy(&source, &empty, T.sizeof - (void*).sizeof);
            }
            else
            {
                memcpy(&source, &empty, T.sizeof);
            }
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        target = source;
        // static if (is(typeof(source = null)))
        // {
        //     // Nullify the source to help the garbage collector
        //     source = null;
        // }
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    Object obj1 = new Object;
    Object obj2 = obj1;
    Object obj3;
    move(obj2, obj3);
    assert(obj3 is obj1);

    static struct S1 { int a = 1, b = 2; }
    S1 s11 = { 10, 11 };
    S1 s12;
    move(s11, s12);
    assert(s11.a == 10 && s11.b == 11 && s12.a == 10 && s12.b == 11);

    static struct S2 { int a = 1; int * b; }
    S2 s21 = { 10, null };
    s21.b = new int;
    S2 s22;
    move(s21, s22);
    assert(s21 == s22);

    // Issue 5661 test(1)
    static struct S3
    {
        static struct X { int n = 0; ~this(){n = 0;} }
        X x;
    }
    static assert(hasElaborateDestructor!S3);
    S3 s31, s32;
    s31.x.n = 1;
    move(s31, s32);
    assert(s31.x.n == 0);
    assert(s32.x.n == 1);

    // Issue 5661 test(2)
    static struct S4
    {
        static struct X { int n = 0; this(this){n = 0;} }
        X x;
    }
    static assert(hasElaborateCopyConstructor!S4);
    S4 s41, s42;
    s41.x.n = 1;
    move(s41, s42);
    assert(s41.x.n == 0);
    assert(s42.x.n == 1);
}

/// Ditto
T move(T)(ref T source)
{
    import core.stdc.string : memcpy;

    // Can avoid to check aliasing.

    T result = void;
    static if (is(T == struct))
    {
        // Can avoid destructing result.

        memcpy(&result, &source, T.sizeof);

        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
        static if (hasElaborateDestructor!T || hasElaborateCopyConstructor!T)
        {
            static T empty;
            static if (T.tupleof.length > 0 &&
                       T.tupleof[$-1].stringof.endsWith("this"))
            {
                // If T is nested struct, keep original context pointer
                memcpy(&source, &empty, T.sizeof - (void*).sizeof);
            }
            else
            {
                memcpy(&source, &empty, T.sizeof);
            }
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        result = source;
    }
    return result;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    Object obj1 = new Object;
    Object obj2 = obj1;
    Object obj3 = move(obj2);
    assert(obj3 is obj1);

    static struct S1 { int a = 1, b = 2; }
    S1 s11 = { 10, 11 };
    S1 s12 = move(s11);
    assert(s11.a == 10 && s11.b == 11 && s12.a == 10 && s12.b == 11);

    static struct S2 { int a = 1; int * b; }
    S2 s21 = { 10, null };
    s21.b = new int;
    S2 s22 = move(s21);
    assert(s21 == s22);

    // Issue 5661 test(1)
    static struct S3
    {
        static struct X { int n = 0; ~this(){n = 0;} }
        X x;
    }
    static assert(hasElaborateDestructor!S3);
    S3 s31;
    s31.x.n = 1;
    S3 s32 = move(s31);
    assert(s31.x.n == 0);
    assert(s32.x.n == 1);

    // Issue 5661 test(2)
    static struct S4
    {
        static struct X { int n = 0; this(this){n = 0;} }
        X x;
    }
    static assert(hasElaborateCopyConstructor!S4);
    S4 s41;
    s41.x.n = 1;
    S4 s42 = move(s41);
    assert(s41.x.n == 0);
    assert(s42.x.n == 1);
}

unittest//Issue 6217
{
    auto x = map!"a"([1,2,3]);
    x = move(x);
}

unittest// Issue 8055
{
    static struct S
    {
        int x;
        ~this()
        {
            assert(x == 0);
        }
    }
    S foo(S s)
    {
        return move(s);
    }
    S a;
    a.x = 0;
    auto b = foo(a);
    assert(b.x == 0);
}

unittest// Issue 8057
{
    int n = 10;
    struct S
    {
        int x;
        ~this()
        {
            // Access to enclosing scope
            assert(n == 10);
        }
    }
    S foo(S s)
    {
        // Move nested struct
        return move(s);
    }
    S a;
    a.x = 1;
    auto b = foo(a);
    assert(b.x == 1);

    // Regression 8171
    static struct Array(T)
    {
        // nested struct has no member
        struct Payload
        {
            ~this() {}
        }
    }
    Array!int.Payload x = void;
    static assert(__traits(compiles, move(x)    ));
    static assert(__traits(compiles, move(x, x) ));
}

/**
 * For each element $(D a) in $(D src) and each element $(D b) in $(D
 * tgt) in lockstep in increasing order, calls $(D move(a, b)). Returns
 * the leftover portion of $(D tgt). Throws an exeption if there is not
 * enough room in $(D tgt) to acommodate all of $(D src).
 *
 * Preconditions:
 * $(D walkLength(src) <= walkLength(tgt))
 */
Range2 moveAll(Range1, Range2)(Range1 src, Range2 tgt)
if (isInputRange!Range1 && isInputRange!Range2 &&
    is(typeof(move(src.front, tgt.front))))
{
    import std.exception : enforce;

    static if (isRandomAccessRange!Range1 && hasLength!Range1 &&
               isRandomAccessRange!Range2 && hasLength!Range2 && hasSlicing!Range2)
    {
        auto toMove = src.length;
        enforce(toMove <= tgt.length);  // shouldn't this be an assert?
        foreach (idx; 0 .. toMove)
            move(src[idx], tgt[idx]);
        return tgt[toMove .. tgt.length];
    }
    else
    {
        for (; !src.empty; src.popFront(), tgt.popFront())
        {
            enforce(!tgt.empty);  //ditto?
            move(src.front, tgt.front);
        }
        return tgt;
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 3 ];
    int[] b = new int[5];
    assert(moveAll(a, b) is b[3 .. $]);
    assert(a == b[0 .. 3]);
    assert(a == [ 1, 2, 3 ]);
}

/**
 * For each element $(D a) in $(D src) and each element $(D b) in $(D
 * tgt) in lockstep in increasing order, calls $(D move(a, b)). Stops
 * when either $(D src) or $(D tgt) have been exhausted. Returns the
 * leftover portions of the two ranges.
 */
Tuple!(Range1, Range2) moveSome(Range1, Range2)(Range1 src, Range2 tgt)
if (isInputRange!Range1 &&
    isInputRange!Range2 &&
    is(typeof(move(src.front, tgt.front))))
{
    import std.exception : enforce;

    for (; !src.empty && !tgt.empty; src.popFront(), tgt.popFront())
    {
        enforce(!tgt.empty);
        move(src.front, tgt.front);
    }
    return tuple(src, tgt);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 3, 4, 5 ];
    int[] b = new int[3];
    assert(moveSome(a, b)[0] is a[3 .. $]);
    assert(a[0 .. 3] == b);
    assert(a == [ 1, 2, 3, 4, 5 ]);
}

/**
 * Swaps $(D lhs) and $(D rhs). See also $(XREF exception, pointsTo).
 *
 * Preconditions:
 * $(D !pointsTo(lhs, lhs) && !pointsTo(lhs, rhs) && !pointsTo(rhs, lhs)
 * && !pointsTo(rhs, rhs))
 */
void swap(T)(ref T lhs, ref T rhs) @trusted pure nothrow
if (isMutable!T && !is(typeof(T.init.proxySwap(T.init))))
{
    import std.exception : pointsTo;

    static if (hasElaborateAssign!T)
    {
        if (&lhs == &rhs)
            return;

        // For structs with non-trivial assignment, move memory directly
        // First check for undue aliasing
        assert(!pointsTo(lhs, rhs) && !pointsTo(rhs, lhs) &&
               !pointsTo(lhs, lhs) && !pointsTo(rhs, rhs));
        // Swap bits
        ubyte[T.sizeof] t = void;
        auto a = (cast(ubyte*) &lhs)[0 .. T.sizeof];
        auto b = (cast(ubyte*) &rhs)[0 .. T.sizeof];
        t[] = a[];
        a[] = b[];
        b[] = t[];
    }
    else
    {
        //Avoid assigning overlapping arrays. Dynamic arrays are fine, because
        //it's their ptr and length properties which get assigned rather
        //than their elements when assigning them, but static arrays are value
        //types and therefore all of their elements get copied as part of
        //assigning them, which would be assigning overlapping arrays if lhs
        //and rhs were the same array.
        static if (isStaticArray!T)
        {
            if (lhs.ptr == rhs.ptr)
                return;
        }

        // For non-struct types, suffice to do the classic swap
        auto tmp = lhs;
        lhs = rhs;
        rhs = tmp;
    }
}

// Not yet documented
void swap(T)(T lhs, T rhs)
if (is(typeof(T.init.proxySwap(T.init))))
{
    lhs.proxySwap(rhs);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int a = 42, b = 34;
    swap(a, b);
    assert(a == 34 && b == 42);

    static struct S { int x; char c; int[] y; }
    S s1 = { 0, 'z', [ 1, 2 ] };
    S s2 = { 42, 'a', [ 4, 6 ] };
    //writeln(s2.tupleof.stringof);
    swap(s1, s2);
    assert(s1.x == 42);
    assert(s1.c == 'a');
    assert(s1.y == [ 4, 6 ]);

    assert(s2.x == 0);
    assert(s2.c == 'z');
    assert(s2.y == [ 1, 2 ]);

    immutable int imm1, imm2;
    static assert(!__traits(compiles, swap(imm1, imm2)));
}

unittest
{
    static struct NoCopy
    {
        this(this) { assert(0); }
        int n;
        string s;
    }
    NoCopy nc1, nc2;
    nc1.n = 127; nc1.s = "abc";
    nc2.n = 513; nc2.s = "uvwxyz";
    swap(nc1, nc2);
    assert(nc1.n == 513 && nc1.s == "uvwxyz");
    assert(nc2.n == 127 && nc2.s == "abc");
    swap(nc1, nc1);
    swap(nc2, nc2);
    assert(nc1.n == 513 && nc1.s == "uvwxyz");
    assert(nc2.n == 127 && nc2.s == "abc");

    static struct NoCopyHolder
    {
        NoCopy noCopy;
    }
    NoCopyHolder h1, h2;
    h1.noCopy.n = 31; h1.noCopy.s = "abc";
    h2.noCopy.n = 65; h2.noCopy.s = null;
    swap(h1, h2);
    assert(h1.noCopy.n == 65 && h1.noCopy.s == null);
    assert(h2.noCopy.n == 31 && h2.noCopy.s == "abc");
    swap(h1, h1);
    swap(h2, h2);
    assert(h1.noCopy.n == 65 && h1.noCopy.s == null);
    assert(h2.noCopy.n == 31 && h2.noCopy.s == "abc");

    const NoCopy const1, const2;
    static assert(!__traits(compiles, swap(const1, const2)));
}

unittest
{
    //Bug# 4789
    int[1] s = [1];
    swap(s, s);
}

void swapFront(R1, R2)(R1 r1, R2 r2)
if (isInputRange!R1 && isInputRange!R2)
{
    static if (is(typeof(swap(r1.front, r2.front))))
    {
        swap(r1.front, r2.front);
    }
    else
    {
        auto t1 = moveFront(r1), t2 = moveFront(r2);
        r1.front = move(t2);
        r2.front = move(t1);
    }
}

/**
 * Forwards function arguments with saving ref-ness.
 */
template forward(args...)
{
    import std.typetuple;

    static if (args.length)
    {
        alias arg = args[0];
        static if (__traits(isRef, arg))
            alias fwd = arg;
        else
            @property fwd()(){ return move(arg); }
        alias forward = TypeTuple!(fwd, forward!(args[1..$]));
    }
    else
        alias forward = TypeTuple!();
}
///
unittest
{
    class C
    {
        static int foo(int n) { return 1; }
        static int foo(ref int n) { return 2; }
    }
    int bar()(auto ref int x) { return C.foo(forward!x); }

    assert(bar(1) == 1);
    int i;
    assert(bar(i) == 2);
}
///
unittest
{
    void foo(int n, ref string s) { s = null; foreach (i; 0..n) s ~= "Hello"; }

    // forwards all arguments which are bound to parameter tuple
    void bar(Args...)(auto ref Args args) { return foo(forward!args); }

    // forwards all arguments with swapping order
    void baz(Args...)(auto ref Args args) { return foo(forward!args[$/2..$], forward!args[0..$/2]); }

    string s;
    bar(1, s);
    assert(s == "Hello");
    baz(s, 2);
    assert(s == "HelloHello");
}

unittest
{
    auto foo(TL...)(auto ref TL args)
    {
        string result = "";
        foreach (i, _; args)
        {
            //pragma(msg, "[",i,"] ", __traits(isRef, args[i]) ? "L" : "R");
            result ~= __traits(isRef, args[i]) ? "L" : "R";
        }
        return result;
    }

    string bar(TL...)(auto ref TL args)
    {
        return foo(forward!args);
    }
    string baz(TL...)(auto ref TL args)
    {
        int x;
        return foo(forward!args[3], forward!args[2], 1, forward!args[1], forward!args[0], x);
    }

    struct S {}
    S makeS(){ return S(); }
    int n;
    string s;
    assert(bar(S(), makeS(), n, s) == "RRLL");
    assert(baz(S(), makeS(), n, s) == "LLRRRL");
}

unittest
{
    ref int foo(ref int a) { return a; }
    ref int bar(Args)(auto ref Args args)
    {
        return foo(forward!args);
    }
    static assert(!__traits(compiles, { auto x1 = bar(3); })); // case of NG
    int value = 3;
    auto x2 = bar(value); // case of OK
}


/**
 * Copies the content of $(D source) into $(D target) and returns the
 * remaining (unfilled) part of $(D target). See also $(WEB
 * sgi.com/tech/stl/_copy.html, STL's _copy). If a behavior similar to
 * $(WEB sgi.com/tech/stl/copy_backward.html, STL's copy_backward) is
 * needed, use $(D copy(retro(source), retro(target))). See also $(XREF
 * range, retro).
 */
unittest
{
    int[] a = [ 1, 5 ];
    int[] b = [ 9, 8 ];
    int[] c = new int[a.length + b.length + 10];
    auto d = copy(b, copy(a, c));
    assert(c[0 .. a.length + b.length] == a ~ b);
    assert(d.length == 10);
}
/**
 * As long as the target range elements support assignment from source
 * range elements, different types of ranges are accepted.
 */
unittest
{
    float[] a = [ 1.0f, 5 ];
    double[] b = new double[a.length];
    auto d = copy(a, b);
}
/**
 * To copy at most $(D n) elements from range $(D a) to range $(D b), you
 * may want to use $(D copy(take(a, n), b)). To copy those elements from
 * range $(D a) that satisfy predicate $(D pred) to range $(D b), you may
 * want to use $(D copy(filter!(pred)(a), b)).
 */
unittest
{
    int[] a = [ 1, 5, 8, 9, 10, 1, 2, 0 ];
    auto b = new int[a.length];
    auto c = copy(filter!("(a & 1) == 1")(a), b);
    assert(b[0 .. $ - c.length] == [ 1, 5, 9, 1 ]);
}
/**
 */
Range2 copy(Range1, Range2)(Range1 source, Range2 target)
if (isInputRange!Range1 &&
    isOutputRange!(Range2, ElementType!Range1))
{
    import std.exception : enforce;

    static Range2 genericImpl(Range1 source, Range2 target)
    {
        // Specialize for 2 random access ranges.
        // Typically 2 random access ranges are faster iterated by common
        // index then by x.popFront(), y.popFront() pair
        static if (isRandomAccessRange!Range1 && hasLength!Range1 &&
                   isRandomAccessRange!Range2 && hasLength!Range2 && hasSlicing!Range2)
        {
            auto len = source.length;
            foreach (idx; 0 .. len)
                target[idx] = source[idx];
            return target[len .. target.length];
        }
        else
        {
            put(target, source);
            return target;
        }
    }

    static if (isArray!Range1 &&
               isArray!Range2 &&
               is(Unqual!(typeof(source[0])) == Unqual!(typeof(target[0]))))
    {
        immutable overlaps = source.ptr < target.ptr + target.length &&
                             target.ptr < source.ptr + source.length;
        if (overlaps)
        {
            return genericImpl(source, target);
        }
        else
        {
            // Array specialization.  This uses optimized memory copying
            // routines under the hood and is about 10-20x faster than the
            // generic implementation.
            enforce(target.length >= source.length,
                "Cannot copy a source array into a smaller target array.");
            target[0..source.length] = source[];

            return target[source.length..$];
        }
    }
    else
    {
        return genericImpl(source, target);
    }
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.exception : assertCTFEable;

    {
        int[] a = [ 1, 5 ];
        int[] b = [ 9, 8 ];
        int[] c = new int[a.length + b.length + 10];
        auto d = copy(b, copy(a, c));
        assert(c[0 .. a.length + b.length] == a ~ b);
        assert(d.length == 10);
    }
    {
        int[] a = [ 1, 5 ];
        int[] b = [ 9, 8 ];
        auto e = copy(filter!("a > 1")(a), b);
        assert(b[0] == 5 && e.length == 1);
    }

    {
        int[] a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        copy(a[5..10], a[4..9]);
        assert(a[4..9] == [6, 7, 8, 9, 10]);
    }

    // Test for bug 7898
    assertCTFEable!(
    {
        import std.algorithm;
        int[] arr1 = [10, 20, 30, 40, 50];
        int[] arr2 = arr1.dup;
        copy(arr1, arr2);
        return 35;
    });
}

/**
 * Swaps all elements of $(D r1) with successive elements in $(D r2).
 * Returns a tuple containing the remainder portions of $(D r1) and $(D
 * r2) that were not swapped (one of them will be empty). The ranges may
 * be of different types but must have the same element type and support
 * swapping.
 */
Tuple!(Range1, Range2)
swapRanges(Range1, Range2)(Range1 r1, Range2 r2)
if (isInputRange!Range1 && hasSwappableElements!Range1 &&
    isInputRange!Range2 && hasSwappableElements!Range2 &&
    is(ElementType!Range1 == ElementType!Range2))
{
    for (; !r1.empty && !r2.empty; r1.popFront(), r2.popFront())
    {
        swap(r1.front, r2.front);
    }
    return tuple(r1, r2);
}

///
unittest
{
    int[] a = [ 100, 101, 102, 103 ];
    int[] b = [ 0, 1, 2, 3 ];
    auto c = swapRanges(a[1 .. 3], b[2 .. 4]);
    assert(c[0].empty && c[1].empty);
    assert(a == [ 100, 2, 3, 103 ]);
    assert(b == [ 0, 1, 101, 102 ]);
}

/**
 * Reverses $(D r) in-place.  Performs $(D r.length / 2) evaluations of $(D
 * swap). See also $(WEB sgi.com/tech/stl/_reverse.html, STL's _reverse).
 */
void reverse(Range)(Range r)
if (isBidirectionalRange!Range && !isRandomAccessRange!Range &&
    hasSwappableElements!Range)
{
    while (!r.empty)
    {
        swap(r.front, r.back);
        r.popFront();
        if (r.empty)
            break;
        r.popBack();
    }
}

///ditto
void reverse(Range)(Range r)
if (isRandomAccessRange!Range && hasLength!Range)
{
    //swapAt is in fact the only way to swap non lvalue ranges
    immutable last = r.length-1;
    immutable steps = r.length/2;
    for (size_t i = 0; i < steps; i++)
    {
        swapAt(r, i, last-i);
    }
}

///
unittest
{
    int[] arr = [ 1, 2, 3 ];
    reverse(arr);
    assert(arr == [ 3, 2, 1 ]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] range = null;
    reverse(range);
    range = [ 1 ];
    reverse(range);
    assert(range == [1]);
    range = [1, 2];
    reverse(range);
    assert(range == [2, 1]);
    range = [1, 2, 3];
    reverse(range);
    assert(range == [3, 2, 1]);
}

/**
 * Reverses $(D r) in-place, where $(D r) is a narrow string (having
 * elements of type $(D char) or $(D wchar)). UTF sequences consisting of
 * multiple code units are preserved properly.
 */
void reverse(Char)(Char[] s)
if (isNarrowString!(Char[]) &&
    !is(Char == const) && !is(Char == immutable))   // isMutable?
{
    import std.string : representation;
    import std.utf : stride;

    auto r = representation(s);
    for (size_t i = 0; i < s.length; )
    {
        immutable step = std.utf.stride(s, i);
        if (step > 1)
        {
            .reverse(r[i .. i + step]);
            i += step;
        }
        else
        {
            ++i;
        }
    }
    reverse(r);
}

///
unittest
{
    char[] arr = "hello\U00010143\u0100\U00010143".dup;
    reverse(arr);
    assert(arr == "\U00010143\u0100\U00010143olleh");
}

unittest
{
    void test(string a, string b)
    {
        auto c = a.dup;
        reverse(c);
        assert(c == b, c ~ " != " ~ b);
    }

    test("a", "a");
    test(" ", " ");
    test("\u2029", "\u2029");
    test("\u0100", "\u0100");
    test("\u0430", "\u0430");
    test("\U00010143", "\U00010143");
    test("abcdefcdef", "fedcfedcba");
}

/**
 * The $(D bringToFront) function has considerable flexibility and
 * usefulness. It can rotate elements in one buffer left or right, swap
 * buffers of equal length, and even move elements across disjoint
 * buffers of different types and different lengths.
 *
 * $(D bringToFront) takes two ranges $(D front) and $(D back), which may
 * be of different types. Considering the concatenation of $(D front) and
 * $(D back) one unified range, $(D bringToFront) rotates that unified
 * range such that all elements in $(D back) are brought to the beginning
 * of the unified range. The relative ordering of elements in $(D front)
 * and $(D back), respectively, remains unchanged.
 *
 * The simplest use of $(D bringToFront) is for rotating elements in a
 * buffer. For example:
 */
unittest
{
    auto arr = [4, 5, 6, 7, 1, 2, 3];
    auto p = bringToFront(arr[0 .. 4], arr[4 .. $]);
    assert(p == arr.length - 4);
    assert(arr == [ 1, 2, 3, 4, 5, 6, 7 ]);
}
/**
 * The $(D front) range may actually "step over" the $(D back)
 * range. This is very useful with forward ranges that cannot compute
 * comfortably right-bounded subranges like $(D arr[0 .. 4]) above. In
 * the example below, $(D r2) is a right subrange of $(D r1).
 */
unittest
{
    import std.container : SList;

    auto list = SList!int(4, 5, 6, 7, 1, 2, 3);
    auto r1 = list[];
    auto r2 = list[]; popFrontN(r2, 4);
    assert(equal(r2, [ 1, 2, 3 ]));
    bringToFront(r1, r2);
    assert(equal(list[], [ 1, 2, 3, 4, 5, 6, 7 ]));
}
/**
 * Elements can be swapped across ranges of different types:
 */
unittest
{
    import std.container : SList;

    auto list = SList!int(4, 5, 6, 7);
    auto vec = [ 1, 2, 3 ];
    bringToFront(list[], vec);
    assert(equal(list[], [ 1, 2, 3, 4 ]));
    assert(equal(vec, [ 5, 6, 7 ]));
}
/**
 * Performs $(BIGOH max(front.length, back.length)) evaluations of $(D
 * swap). See also $(WEB sgi.com/tech/stl/_rotate.html, STL's rotate).
 *
 * Preconditions:
 *
 * Either $(D front) and $(D back) are disjoint, or $(D back) is
 * reachable from $(D front) and $(D front) is not reachable from $(D
 * back).
 *
 * Returns:
 *
 * The number of elements brought to the front, i.e., the length of $(D
 * back).
 */
size_t bringToFront(Range1, Range2)(Range1 front, Range2 back)
if (isInputRange!Range1 &&
    isForwardRange!Range2)
{
    enum bool sameHeadExists = is(typeof(front.sameHead(back)));

    size_t result;
    for (bool semidone; !front.empty && !back.empty; )
    {
        static if (sameHeadExists)
        {
            if (front.sameHead(back))
                break; // shortcut
        }
        // Swap elements until front and/or back ends.
        auto back0 = back.save;
        size_t nswaps;
        do
        {
            static if (sameHeadExists)
            {
                // Detect the stepping-over condition.
                if (front.sameHead(back0))
                    back0 = back.save;
            }
            swapFront(front, back);
            ++nswaps;
            front.popFront();
            back.popFront();
        }
        while (!front.empty && !back.empty);

        if (!semidone)
            result += nswaps;

        // Now deal with the remaining elements.
        if (back.empty)
        {
            if (front.empty)
                break;
            // Right side was shorter, which means that we've brought
            // all the back elements to the front.
            semidone = true;
            // Next pass: bringToFront(front, back0) to adjust the rest.
            back = back0;
        }
        else
        {
            assert(front.empty);
            // Left side was shorter. Let's step into the back.
            static if (is(Range1 == Take!Range2))
            {
                front = take(back0, nswaps);
            }
            else
            {
                immutable subresult = bringToFront(take(back0, nswaps), back);
                if (!semidone)
                    result += subresult;
                break; // done
            }
        }
    }
    return result;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.random : uniform, unpredictableSeed, Random;

    // a more elaborate test
    {
        auto rnd = Random(unpredictableSeed);
        int[] a = new int[uniform(100, 200, rnd)];
        int[] b = new int[uniform(100, 200, rnd)];
        foreach (ref e; a) e = uniform(-100, 100, rnd);
        foreach (ref e; b) e = uniform(-100, 100, rnd);
        int[] c = a ~ b;
        // writeln("a= ", a);
        // writeln("b= ", b);
        auto n = bringToFront(c[0 .. a.length], c[a.length .. $]);
        //writeln("c= ", c);
        assert(n == b.length);
        assert(c == b ~ a);
    }
    // different types, moveFront, no sameHead
    {
        static struct R(T)
        {
            T[] data;
            size_t i;
            @property
            {
                R save() { return this; }
                bool empty() { return i >= data.length; }
                T front() { return data[i]; }
                T front(real e) { return data[i] = cast(T) e; }
            }
            void popFront() { ++i; }
        }
        auto a = R!int([1, 2, 3, 4, 5]);
        auto b = R!real([6, 7, 8, 9]);
        auto n = bringToFront(a, b);
        assert(n == 4);
        assert(a.data == [6, 7, 8, 9, 1]);
        assert(b.data == [2, 3, 4, 5]);
    }
    // front steps over back
    {
        int[] arr, r1, r2;

        // back is shorter
        arr = [4, 5, 6, 7, 1, 2, 3];
        r1 = arr;
        r2 = arr[4 .. $];
        bringToFront(r1, r2) == 3 || assert(0);
        assert(equal(arr, [1, 2, 3, 4, 5, 6, 7]));

        // front is shorter
        arr = [5, 6, 7, 1, 2, 3, 4];
        r1 = arr;
        r2 = arr[3 .. $];
        bringToFront(r1, r2) == 4 || assert(0);
        assert(equal(arr, [1, 2, 3, 4, 5, 6, 7]));
    }
}

/**
 * Defines the swapping strategy for algorithms that need to swap
 * elements in a range (such as partition and sort). The strategy
 * concerns the swapping of elements that are not the core concern of the
 * algorithm. For example, consider an algorithm that sorts $(D [ "abc",
 * "b", "aBc" ]) according to $(D toUpper(a) < toUpper(b)). That
 * algorithm might choose to swap the two equivalent strings $(D "abc")
 * and $(D "aBc"). That does not affect the sorting since both $(D [
 * "abc", "aBc", "b" ]) and $(D [ "aBc", "abc", "b" ]) are valid
 * outcomes.
 *
 * Some situations require that the algorithm must NOT ever change the
 * relative ordering of equivalent elements (in the example above, only
 * $(D [ "abc", "aBc", "b" ]) would be the correct result). Such
 * algorithms are called $(B stable). If the ordering algorithm may swap
 * equivalent elements discretionarily, the ordering is called $(B
 * unstable).
 *
 * Yet another class of algorithms may choose an intermediate tradeoff by
 * being stable only on a well-defined subrange of the range. There is no
 * established terminology for such behavior; this library calls it $(B
 * semistable).
 *
 * Generally, the $(D stable) ordering strategy may be more costly in
 * time and/or space than the other two because it imposes additional
 * constraints. Similarly, $(D semistable) may be costlier than $(D
 * unstable). As (semi-)stability is not needed very often, the ordering
 * algorithms in this module parameterized by $(D SwapStrategy) all
 * choose $(D SwapStrategy.unstable) as the default.
 */
enum SwapStrategy
{
    /**
     * Allows freely swapping of elements as long as the output
     * satisfies the algorithm's requirements.
     */
    unstable,

    /**
     * In algorithms partitioning ranges in two, preserve relative
     * ordering of elements only to the left of the partition point.
     */
    semistable,

    /**
     * Preserve the relative ordering of elements to the largest
     * extent allowed by the algorithm's requirements.
     */
    stable,
}

/**
 * Eliminates elements at given offsets from $(D range) and returns the
 * shortened range. In the simplest call, one element is removed.
 */
unittest
{
    int[] a = [ 3, 5, 7, 8 ];
    assert(remove(a, 1) == [ 3, 7, 8 ]);
    assert(a == [ 3, 7, 8, 8 ]);
}
/**
 * In the case above the element at offset $(D 1) is removed and $(D
 * remove) returns the range smaller by one element. The original array
 * has remained of the same length because all functions in $(D
 * std.algorithm) only change $(I content), not $(I topology). The value
 * $(D 8) is repeated because $(XREF algorithm, move) was invoked to move
 * elements around and on integers $(D move) simply copies the source to
 * the destination. To replace $(D a) with the effect of the removal,
 * simply assign $(D a = remove(a, 1)). The slice will be rebound to the
 * shorter array and the operation completes with maximal efficiency.
 *
 * Multiple indices can be passed into $(D remove). In that case,
 * elements at the respective indices are all removed. The indices must
 * be passed in increasing order, otherwise an exception occurs.
 */
unittest
{
    int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove(a, 1, 3, 5) ==
        [ 0, 2, 4, 6, 7, 8, 9, 10 ]);
}
/**
 * (Note how all indices refer to slots in the $(I original) array, not
 * in the array as it is being progressively shortened.) Finally, any
 * combination of integral offsets and tuples composed of two integral
 * offsets can be passed in.
 */
unittest
{
    int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove(a, 1, tuple(3, 5), 9) == [ 0, 2, 5, 6, 7, 8, 10 ]);
}
/**
 * In this case, the slots at positions 1, 3, 4, and 9 are removed from
 * the array. The tuple passes in a range closed to the left and open to
 * the right (consistent with built-in slices), e.g. $(D tuple(3, 5))
 * means indices $(D 3) and $(D 4) but not $(D 5).
 *
 * If the need is to remove some elements in the range but the order of
 * the remaining elements does not have to be preserved, you may want to
 * pass $(D SwapStrategy.unstable) to $(D remove).
 */
unittest
{
    int[] a = [ 0, 1, 2, 3 ];
    //assert(remove!(SwapStrategy.unstable)(a, 1) == [ 0, 3, 2 ]);  // @@@BUG@@@ doesn't work
}
/**
 * In the case above, the element at slot $(D 1) is removed, but replaced
 * with the last element of the range. Taking advantage of the relaxation
 * of the stability requirement, $(D remove) moved elements from the end
 * of the array over the slots to be removed. This way there is less data
 * movement to be done which improves the execution time of the function.
 *
 * The function $(D remove) works on any forward range. The moving
 * strategy is (listed from fastest to slowest): $(UL $(LI If $(D s ==
 * SwapStrategy.unstable && isRandomAccessRange!Range &&
 * hasLength!Range), then elements are moved from the end of the range
 * into the slots to be filled. In this case, the absolute minimum of
 * moves is performed.)  $(LI Otherwise, if $(D s ==
 * SwapStrategy.unstable && isBidirectionalRange!Range &&
 * hasLength!Range), then elements are still moved from the end of the
 * range, but time is spent on advancing between slots by repeated calls
 * to $(D range.popFront).)  $(LI Otherwise, elements are moved incrementally
 * towards the front of $(D range); a given element is never moved
 * several times, but more elements are moved than in the previous
 * cases.))
 */
Range remove
(SwapStrategy ss = SwapStrategy.stable, Range, Offset...)
(Range range, Offset offset)
if (isBidirectionalRange!Range && hasLength!Range &&
    ss != SwapStrategy.stable &&
    Offset.length >= 1)
{
    enum bool tupleLeft = is(typeof(offset[0][0])) &&
                          is(typeof(offset[0][1]));
    enum bool tupleRight = is(typeof(offset[$ - 1][0])) &&
                           is(typeof(offset[$ - 1][1]));
    static if (!tupleLeft)
    {
        alias lStart = offset[0];
        auto lEnd = lStart + 1;
    }
    else
    {
        auto lStart = offset[0][0];
        auto lEnd = offset[0][1];
    }
    static if (!tupleRight)
    {
        alias rStart = offset[$ - 1];
        auto rEnd = rStart + 1;
    }
    else
    {
        auto rStart = offset[$ - 1][0];
        auto rEnd = offset[$ - 1][1];
    }
    // Begin. Test first to see if we need to remove the rightmost
    // element(s) in the range. In that case, life is simple - chop
    // and recurse.
    if (rEnd == range.length)
    {
        // must remove the last elements of the range
        range.popBackN(rEnd - rStart);
        static if (Offset.length > 1)
        {
            return .remove!(ss, Range, Offset[0 .. $ - 1])
                (range, offset[0 .. $ - 1]);
        }
        else
        {
            return range;
        }
    }

    // Ok, there are "live" elements at the end of the range
    auto t = range;
    auto lDelta = lEnd - lStart, rDelta = rEnd - rStart;
    auto rid = min(lDelta, rDelta);
    foreach (i; 0 .. rid)
    {
        move(range.back, t.front);
        range.popBack();
        t.popFront();
    }
    if (rEnd - rStart == lEnd - lStart)
    {
        // We got rid of both left and right
        static if (Offset.length > 2)
        {
            return .remove!(ss, Range, Offset[1 .. $ - 1])
                (range, offset[1 .. $ - 1]);
        }
        else
        {
            return range;
        }
    }
    else if (rEnd - rStart < lEnd - lStart)
    {
        // We got rid of the entire right subrange
        static if (Offset.length > 2)
        {
            return .remove!(ss, Range)
                (range, tuple(lStart + rid, lEnd),
                        offset[1 .. $ - 1]);
        }
        else
        {
            auto tmp = tuple(lStart + rid, lEnd);
            return .remove!(ss, Range, typeof(tmp))
                (range, tmp);
        }
    }
    else
    {
        // We got rid of the entire left subrange
        static if (Offset.length > 2)
        {
            return .remove!(ss, Range)
                (range, offset[1 .. $ - 1],
                        tuple(rStart, lEnd - rid));
        }
        else
        {
            auto tmp = tuple(rStart, lEnd - rid);
            return .remove!(ss, Range, typeof(tmp))
                (range, tmp);
        }
    }
}

// Ditto
Range remove
(SwapStrategy ss = SwapStrategy.stable, Range, Offset...)
(Range range, Offset offset)
if ((isForwardRange!Range && !isBidirectionalRange!Range ||
     !hasLength!Range ||
     ss == SwapStrategy.stable) &&
    Offset.length >= 1)
{
    auto result = range;
    auto src = range, tgt = range;
    size_t pos;
    foreach (i; offset)
    {
        static if (is(typeof(i[0])) && is(typeof(i[1])))
        {
            auto from = i[0], delta = i[1] - i[0];
        }
        else
        {
            auto from = i;
            enum delta = 1;
        }
        assert(pos <= from);
        for (; pos < from; ++pos, src.popFront(), tgt.popFront())
        {
            move(src.front, tgt.front);
        }
        // now skip source to the "to" position
        src.popFrontN(delta);
        pos += delta;
        foreach (j; 0 .. delta)
            result.popBack();
    }
    // leftover move
    moveAll(src, tgt);
    return result;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1) ==
        [ 0, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.unstable)(a, 0, 10) ==
            [ 9, 1, 2, 3, 4, 5, 6, 7, 8 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.unstable)(a, 0, tuple(9, 11)) ==
            [ 8, 1, 2, 3, 4, 5, 6, 7 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, 5));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, 5) ==
        [ 0, 2, 3, 4, 6, 7, 8, 9, 10 ]);

    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, 3, 5));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, 3, 5)
            == [ 0, 2, 4, 6, 7, 8, 9, 10]);
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    //writeln(remove!(SwapStrategy.stable)(a, 1, tuple(3, 5)));
    a = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    assert(remove!(SwapStrategy.stable)(a, 1, tuple(3, 5))
            == [ 0, 2, 5, 6, 7, 8, 9, 10]);
}

/**
Reduces the length of the bidirectional range $(D range) by removing
elements that satisfy $(D pred). If $(D ss = SwapStrategy.unstable),
elements are moved from the right end of the range over the elements
to eliminate. If $(D ss = SwapStrategy.stable) (the default),
elements are moved progressively to front such that their relative
order is preserved. Returns the filtered range.

Example:
----
int[] a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
assert(remove!("a == 2")(a) == [ 1, 3, 3, 4, 5, 5, 6 ]);
----
 */
Range remove(alias pred, SwapStrategy ss = SwapStrategy.stable, Range)
(Range range)
if (isBidirectionalRange!Range)
{
    auto result = range;
    static if (ss != SwapStrategy.stable)
    {
        for (;!range.empty;)
        {
            if (!unaryFun!pred(range.front))
            {
                range.popFront();
                continue;
            }
            move(range.back, range.front);
            range.popBack();
            result.popBack();
        }
    }
    else
    {
        auto tgt = range;
        for (; !range.empty; range.popFront())
        {
            if (unaryFun!pred(range.front))
            {
                // yank this guy
                result.popBack();
                continue;
            }
            // keep this guy
            move(range.front, tgt.front);
            tgt.popFront();
        }
    }
    return result;
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    int[] a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
    assert(remove!("a == 2", SwapStrategy.unstable)(a) ==
            [ 1, 6, 3, 5, 3, 4, 5 ]);
    a = [ 1, 2, 3, 2, 3, 4, 5, 2, 5, 6 ];
    //writeln(remove!("a != 2", SwapStrategy.stable)(a));
    assert(remove!("a == 2", SwapStrategy.stable)(a) ==
            [ 1, 3, 3, 4, 5, 5, 6 ]);
}

// eliminate
/* *
Reduces $(D r) by overwriting all elements $(D x) that satisfy $(D
pred(x)). Returns the reduced range.

Example:
----
int[] arr = [ 1, 2, 3, 4, 5 ];
// eliminate even elements
auto r = eliminate!("(a & 1) == 0")(arr);
assert(r == [ 1, 3, 5 ]);
assert(arr == [ 1, 3, 5, 4, 5 ]);
----
*/
// Range eliminate(alias pred,
//                 SwapStrategy ss = SwapStrategy.unstable,
//                 alias move = .move,
//                 Range)(Range r)
// {
//     alias It = Iterator!Range;
//     static void assignIter(It a, It b) { move(*b, *a); }
//     return range(begin(r), partitionold!(not!pred, ss, assignIter, Range)(r));
// }

// unittest
// {
//     int[] arr = [ 1, 2, 3, 4, 5 ];
// // eliminate even elements
//     auto r = eliminate!("(a & 1) == 0")(arr);
//     assert(find!("(a & 1) == 0")(r).empty);
// }

/* *
Reduces $(D r) by overwriting all elements $(D x) that satisfy $(D
pred(x, v)). Returns the reduced range.

Example:
----
int[] arr = [ 1, 2, 3, 2, 4, 5, 2 ];
// keep elements different from 2
auto r = eliminate(arr, 2);
assert(r == [ 1, 3, 4, 5 ]);
assert(arr == [ 1, 3, 4, 5, 4, 5, 2  ]);
----
*/
// Range eliminate(alias pred = "a == b",
//                 SwapStrategy ss = SwapStrategy.semistable,
//                 Range, Value)(Range r, Value v)
// {
//     alias It = Iterator!Range;
//     bool comp(typeof(*It) a) { return !binaryFun!pred(a, v); }
//     static void assignIterB(It a, It b) { *a = *b; }
//     return range(begin(r),
//             partitionold!(comp,
//                     ss, assignIterB, Range)(r));
// }

// unittest
// {
//     int[] arr = [ 1, 2, 3, 2, 4, 5, 2 ];
// // keep elements different from 2
//     auto r = eliminate(arr, 2);
//     assert(r == [ 1, 3, 4, 5 ]);
//     assert(arr == [ 1, 3, 4, 5, 4, 5, 2  ]);
// }

/**
 * Partitions a range in two using $(D pred) as a
 * predicate. Specifically, reorders the range $(D r = [left,
 * right$(RPAREN)) using $(D swap) such that all elements $(D i) for
 * which $(D pred(i)) is $(D true) come before all elements $(D j) for
 * which $(D pred(j)) returns $(D false).
 *
 * Performs $(BIGOH r.length) (if unstable or semistable) or $(BIGOH
 * r.length * log(r.length)) (if stable) evaluations of $(D less) and $(D
 * swap). The unstable version computes the minimum possible evaluations
 * of $(D swap) (roughly half of those performed by the semistable
 * version).
 *
 * See also STL's $(WEB sgi.com/tech/stl/_partition.html, _partition) and
 * $(WEB sgi.com/tech/stl/stable_partition.html, stable_partition).
 *
 * Returns:
 *
 * The right part of $(D r) after partitioning.
 *
 * If $(D ss == SwapStrategy.stable), $(D partition) preserves the
 * relative ordering of all elements $(D a), $(D b) in $(D r) for which
 * $(D pred(a) == pred(b)). If $(D ss == SwapStrategy.semistable), $(D
 * partition) preserves the relative ordering of all elements $(D a), $(D
 * b) in the left part of $(D r) for which $(D pred(a) == pred(b)).
 */
Range partition(alias predicate, SwapStrategy ss = SwapStrategy.unstable, Range)(Range r)
if ((ss == SwapStrategy.stable && isRandomAccessRange!Range)||
    (ss != SwapStrategy.stable && isForwardRange!Range))
{
    alias pred = unaryFun!predicate;

    if (r.empty)
        return r;
    static if (ss == SwapStrategy.stable)
    {
        if (r.length == 1)
        {
            if (pred(r.front)) r.popFront();
            return r;
        }
        const middle = r.length / 2;
        alias .partition!(pred, ss, Range) recurse;
        auto lower = recurse(r[0 .. middle]);
        auto upper = recurse(r[middle .. $]);
        bringToFront(lower, r[middle .. r.length - upper.length]);
        return r[r.length - lower.length - upper.length .. r.length];
    }
    else static if (ss == SwapStrategy.semistable)
    {
        for (; !r.empty; r.popFront())
        {
            // skip the initial portion of "correct" elements
            if (pred(r.front)) continue;
            // hit the first "bad" element
            auto result = r;
            for (r.popFront(); !r.empty; r.popFront())
            {
                if (!pred(r.front)) continue;
                swap(result.front, r.front);
                result.popFront();
            }
            return result;
        }
        return r;
    }
    else // ss == SwapStrategy.unstable
    {
        // Inspired from www.stepanovpapers.com/PAM3-partition_notes.pdf,
        // section "Bidirectional Partition Algorithm (Hoare)"
        auto result = r;
        for (;;)
        {
            for (;;)
            {
                if (r.empty)
                    return result;
                if (!pred(r.front))
                    break;
                r.popFront();
                result.popFront();
            }
            // found the left bound
            assert(!r.empty);
            for (;;)
            {
                if (pred(r.back))
                    break;
                r.popBack();
                if (r.empty)
                    return result;
            }
            // found the right bound, swap & make progress
            static if (is(typeof(swap(r.front, r.back))))
            {
                swap(r.front, r.back);
            }
            else
            {
                auto t1 = moveFront(r);
                auto t2 = moveBack(r);
                r.front = t2;
                r.back = t1;
            }
            r.popFront();
            result.popFront();
            r.popBack();
        }
    }
}

///
unittest
{
    auto Arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    auto arr = Arr.dup;
    static bool even(int a) { return (a & 1) == 0; }

    // Partition arr such that even numbers come first
    auto r = partition!even(arr);
    // Now arr is separated in evens and odds.
    // Numbers may have become shuffled due to instability
    assert(r == arr[5 .. $]);
    assert(count!even(arr[0 .. $ - r.length]) == r.length);
    assert(find!even(r).empty);

    // Notice that numbers have become shuffled due to instability

    // Can also specify the predicate as a string.
    // Use 'a' as the predicate argument name
    arr[] = Arr[];
    r = partition!(q{(a & 1) == 0})(arr);
    assert(r == arr[5 .. $]);

    // Same result as above. Now for a stable partition:
    arr[] = Arr[];
    r = partition!(q{(a & 1) == 0}, SwapStrategy.stable)(arr);
    // Now arr is [2 4 6 8 10 1 3 5 7 9], and r points to 1
    assert(arr == [2, 4, 6, 8, 10, 1, 3, 5, 7, 9] && r == arr[5 .. $]);

    // In case the predicate needs to hold its own state, use a delegate:
    arr[] = Arr[];
    int x = 3;
    // Put stuff greater than 3 on the left
    bool fun(int a) { return a > x; }
    r = partition!(fun, SwapStrategy.semistable)(arr);
    // Now arr is [4 5 6 7 8 9 10 2 3 1] and r points to 2
    assert(arr == [4, 5, 6, 7, 8, 9, 10, 2, 3, 1] && r == arr[7 .. $]);
}

unittest
{
    static bool even(int a) { return (a & 1) == 0; }

    // test with random data
    auto a = rndstuff!int();
    partition!even(a);
    assert(isPartitioned!even(a));
    auto b = rndstuff!string();
    partition!(`a.length < 5`)(b);
    assert(isPartitioned!`a.length < 5`(b));
}

/**
 * Returns $(D true) if $(D r) is partitioned according to predicate $(D pred).
 */
bool isPartitioned(alias pred, Range)(Range r)
if (isForwardRange!Range)
{
    for (; !r.empty; r.popFront())
    {
        if (unaryFun!pred(r.front))
            continue;
        for (r.popFront(); !r.empty; r.popFront())
        {
            if (unaryFun!pred(r.front))
                return false;
        }
        break;
    }
    return true;
}

///
unittest
{
    int[] r = [ 1, 3, 5, 7, 8, 2, 4, ];
    assert(isPartitioned!("a & 1")(r));
}

/**
 * Rearranges elements in $(D r) in three adjacent ranges and returns
 * them. The first and leftmost range only contains elements in $(D r)
 * less than $(D pivot). The second and middle range only contains
 * elements in $(D r) that are equal to $(D pivot). Finally, the third
 * and rightmost range only contains elements in $(D r) that are greater
 * than $(D pivot). The less-than test is defined by the binary function
 * $(D less).
 *
 * BUGS: stable $(D partition3) has not been implemented yet.
 */
auto partition3
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range, E)
(Range r, E pivot)
if (ss == SwapStrategy.unstable &&
    isRandomAccessRange!Range && hasSwappableElements!Range && hasLength!Range &&
    is(typeof(binaryFun!less(r.front, pivot)) == bool) &&
    is(typeof(binaryFun!less(pivot, r.front)) == bool) &&
    is(typeof(binaryFun!less(r.front, r.front)) == bool))
{
    // The algorithm is described in "Engineering a sort function" by
    // Jon Bentley et al, pp 1257.

    alias lessFun = binaryFun!less;
    size_t i, j, k = r.length, l = k;

 bigloop:
    for (;;)
    {
        for (;; ++j)
        {
            if (j == k)
                break bigloop;
            assert(j < r.length);
            if (lessFun(r[j], pivot))
                continue;
            if (lessFun(pivot, r[j]))
                break;
            swap(r[i++], r[j]);
        }
        assert(j < k);
        for (;;)
        {
            assert(k > 0);
            if (!lessFun(pivot, r[--k]))
            {
                if (lessFun(r[k], pivot))
                    break;
                swap(r[k], r[--l]);
            }
            if (j == k)
                break bigloop;
        }
        // Here we know r[j] > pivot && r[k] < pivot
        swap(r[j++], r[k]);
    }

    // Swap the equal ranges from the extremes into the middle
    auto strictlyLess = j - i, strictlyGreater = l - k;
    auto swapLen = min(i, strictlyLess);
    swapRanges(r[0 .. swapLen], r[j - swapLen .. j]);
    swapLen = min(r.length - l, strictlyGreater);
    swapRanges(r[k .. k + swapLen], r[r.length - swapLen .. r.length]);
    return tuple(r[0 .. strictlyLess],
                 r[strictlyLess .. r.length - strictlyGreater],
                 r[r.length - strictlyGreater .. r.length]);
}

///
unittest
{
    auto a = [ 8, 3, 4, 1, 4, 7, 4 ];
    auto pieces = partition3(a, 4);
    assert(a == [ 1, 3, 4, 4, 4, 8, 7 ]);
    assert(pieces[0] == [ 1, 3 ]);
    assert(pieces[1] == [ 4, 4, 4 ]);
    assert(pieces[2] == [ 8, 7 ]);
}
unittest
{
    import std.random : uniform;

    int[] a = null;
    auto pieces = partition3(a, 4);
    assert(a.empty);
    assert(pieces[0].empty);
    assert(pieces[1].empty);
    assert(pieces[2].empty);

    a.length = uniform(0, 100);
    foreach (ref e; a)
    {
        e = uniform(0, 50);
    }
    pieces = partition3(a, 25);
    assert(pieces[0].length + pieces[1].length + pieces[2].length == a.length);
    foreach (e; pieces[0])
    {
        assert(e < 25);
    }
    foreach (e; pieces[1])
    {
        assert(e == 25);
    }
    foreach (e; pieces[2])
    {
        assert(e > 25);
    }
}

/**
 * Reorders the range $(D r) using $(D swap) such that $(D r[nth]) refers
 * to the element that would fall there if the range were fully
 * sorted. In addition, it also partitions $(D r) such that all elements
 * $(D e1) from $(D r[0]) to $(D r[nth]) satisfy $(D !less(r[nth], e1)),
 * and all elements $(D e2) from $(D r[nth]) to $(D r[r.length]) satisfy
 * $(D !less(e2, r[nth])). Effectively, it finds the nth smallest
 * (according to $(D less)) elements in $(D r). Performs an expected
 * $(BIGOH r.length) (if unstable) or $(BIGOH r.length * log(r.length))
 * (if stable) evaluations of $(D less) and $(D swap). See also $(WEB
 * sgi.com/tech/stl/nth_element.html, STL's nth_element).
 *
 * If $(D n >= r.length), the algorithm has no effect.
 *
 * BUGS: Stable topN has not been implemented yet.
 */
void topN
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range)
(Range r, size_t nth)
if (isRandomAccessRange!Range && hasLength!Range)
{
    static assert(ss == SwapStrategy.unstable,
            "Stable topN not yet implemented");
    while (r.length > nth)
    {
        import std.random : uniform;

        auto pivot = uniform(0, r.length);
        swap(r[pivot], r.back);
        assert(!binaryFun!less(r.back, r.back));
        auto right = partition!(a => binaryFun!less(a, r.back), ss)(r);
        assert(right.length >= 1);
        swap(right.front, r.back);
        pivot = r.length - right.length;
        if (pivot == nth)
            return;
        if (pivot < nth)
        {
            ++pivot;
            r = r[pivot .. $];
            nth -= pivot;
        }
        else
        {
            assert(pivot < r.length);
            r = r[0 .. pivot];
        }
    }
}

///
unittest
{
    int[] v = [ 25, 7, 9, 2, 0, 5, 21 ];
    auto n = 4;
    topN(v, n);
    assert(v[n] == 9);
    // Equivalent form:
    topN!("a < b")(v, n);
    assert(v[n] == 9);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    //scope(failure) writeln(stderr, "Failure testing algorithm");
    //auto v = ([ 25, 7, 9, 2, 0, 5, 21 ]).dup;
    int[] v = [ 7, 6, 5, 4, 3, 2, 1, 0 ];
    ptrdiff_t n = 3;
    topN!("a < b")(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 3;
    topN(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 1;
    topN(v, n);
    assert(reduce!max(v[0 .. n]) <= v[n]);
    assert(reduce!min(v[n + 1 .. $]) >= v[n]);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = v.length - 1;
    topN(v, n);
    assert(v[n] == 7);
    //
    v = ([3, 4, 5, 6, 7, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5]).dup;
    n = 0;
    topN(v, n);
    assert(v[n] == 1);

    double[][] v1 = [[-10, -5], [-10, -3], [-10, -5], [-10, -4],
            [-10, -5], [-9, -5], [-9, -3], [-9, -5],];

    // double[][] v1 = [ [-10, -5], [-10, -4], [-9, -5], [-9, -5],
    //         [-10, -5], [-10, -3], [-10, -5], [-9, -3],];
    double[]*[] idx = [ &v1[0], &v1[1], &v1[2], &v1[3], &v1[4], &v1[5], &v1[6], &v1[7], ];

    auto mid = v1.length / 2;
    topN!((a, b) => (*a)[1] < (*b)[1])(idx, mid);
    foreach (e; idx[0 .. mid]) assert((*e)[1] <= (*idx[mid])[1]);
    foreach (e; idx[mid .. $]) assert((*e)[1] >= (*idx[mid])[1]);
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");

    import std.random : uniform;

    int[] a = new int[uniform(1, 10000)];
    foreach (ref e; a)
        e = uniform(-1000, 1000);
    auto k = uniform(0, a.length);
    topN(a, k);
    if (k > 0)
    {
        auto left = reduce!max(a[0 .. k]);
        assert(left <= a[k]);
    }
    if (k + 1 < a.length)
    {
        auto right = reduce!min(a[k + 1 .. $]);
        assert(right >= a[k]);
    }
}

/**
Stores the smallest elements of the two ranges in the left-hand range.
 */
void topN
(alias less = "a < b", SwapStrategy ss = SwapStrategy.unstable, Range1, Range2)
(Range1 r1, Range2 r2)
if (isRandomAccessRange!Range1 && hasLength!Range1 &&
    isInputRange!Range2 &&
    is(ElementType!Range1 == ElementType!Range2))
{
    import std.container : BinaryHeap;

    static assert(ss == SwapStrategy.unstable,
            "Stable topN not yet implemented");

    auto heap = BinaryHeap!Range1(r1);
    for (; !r2.empty; r2.popFront())
    {
        heap.conditionalInsert(r2.front);
    }
}

/// Ditto
unittest
{
    int[] a = [ 5, 7, 2, 6, 7 ];
    int[] b = [ 2, 1, 5, 6, 7, 3, 0 ];
    topN(a, b);
    sort(a);
    assert(a == [0, 1, 2, 2, 3]);
}
