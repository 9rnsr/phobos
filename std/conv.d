module std.conv;

template to(T)
{
    T to(A...)(A args)
    {
        return toImpl!T(args);
    }
}

T toImpl(T, S)(S value)
    if (is(S : T))
{
    return value;
}

T toImpl(T, S)(S value)
    if (is(T : string))
{
    pragma(msg, "L", __LINE__);

    // other non-string values runs formatting

    import std.format;

    FormatSpec!(char) f;
    enforceValidFormatSpec!(S, char)(f);
    return "";
}

T toImpl(T, S)(S value)
    if (!is(S : T)
        &&
        is(T : long)
       )
{
    return T.init;
}

// parse

Target parse(Target, Source)(ref Source s)
{
    assert(0);
}

// text

string text(T...)(T args) { return null; }

// emplace

package ref UT emplaceRef(UT, Args...)(ref UT chunk, auto ref Args args)
{
    return chunk;
}

package ref UT emplaceRef(T, UT, Args...)(ref UT chunk, auto ref Args args)
{
    return chunk;
}

