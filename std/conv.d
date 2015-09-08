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
