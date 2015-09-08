module std.exception;

template enforceEx(E : Throwable)
{
    T enforceEx(T)(T value, lazy string msg = "", string file = __FILE__, size_t line = __LINE__)
    {
        if (!value) throw new E(msg, file, line);
        return value;
    }
}
