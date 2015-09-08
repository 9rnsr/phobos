module std.format;

template enforceEx(E : Throwable)
{
    T enforceEx(T)(T value, lazy string msg = "", string file = __FILE__, size_t line = __LINE__)
    {
        if (!value) throw new E(msg, file, line);
        return value;
    }
}

private alias enforceFmt = enforceEx!Exception;

struct FormatSpec(Char)
{
    char spec = 's';
}

void enforceValidFormatSpec(T, Char)(ref FormatSpec!Char f)
{
    enforceFmt(f.spec == 's');
}

