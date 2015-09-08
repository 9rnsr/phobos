module std.format;

import std.exception;

private alias enforceFmt = enforceEx!Exception;

struct FormatSpec(Char)
{
    char spec = 's';
}

void enforceValidFormatSpec(T, Char)(ref FormatSpec!Char f)
{
    enforceFmt(f.spec == 's');
}

string format(Char, Args...)(in Char[] fmt, Args args)
{
    return "";
}
