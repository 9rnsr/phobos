//Written in the D programming language

/++
    Module containing Date/Time functionality.

    Copyright: Copyright 2010 - 2015
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis, Kato Shoichi, and Kenji Hara
    Source:    $(PHOBOSSRC std/datetime/_timepoint.d)
    Macros:
        LREF2=<a href="#$1">$(D $2)</a>
+/
module std.datetime.timepoint;

public import core.time;
import std.datetime.conv;
import std.datetime.timezone;

import core.stdc.time;

version(Windows)
{
    import core.sys.windows.windows;
    import core.sys.windows.winsock2;
    import std.windows.registry;
}
else version(Posix)
{
    import core.sys.posix.stdlib;
    import core.sys.posix.sys.time;
}

import std.range.primitives;
import std.traits;

version(unittest)
{
    import std.exception : assertThrown, assertNotThrown;
}
unittest
{
    initializeTests();
}


/++
    $(D SysTime) is the type used to get the current time from the
    system or doing anything that involves time zones. Unlike
    $(LREF DateTime), the time zone is an integral part of $(D SysTime) (though for
    local time applications, time zones can be ignored and
    it will work, since it defaults to using the local time zone). It holds its
    internal time in std time (hnsecs since midnight, January 1st, 1 A.D. UTC),
    so it interfaces well with the system time. However, that means that, unlike
    $(LREF DateTime), it is not optimized for calendar-based operations, and
    getting individual units from it such as years or days is going to involve
    conversions and be less efficient.

    For calendar-based operations that don't
    care about time zones, then $(LREF DateTime) would be the type to
    use. For system time, use $(D SysTime).

    $(LREF2 .Clock.currTime, Clock.currTime) will return the current time as a $(D SysTime).
    To convert a $(D SysTime) to a $(LREF Date) or $(LREF DateTime), simply cast
    it. To convert a $(LREF Date) or $(LREF DateTime) to a
    $(D SysTime), use $(D SysTime)'s constructor, and pass in the
    intended time zone with it (or don't pass in a $(LREF2 .TimeZone, TimeZone), and the local
    time zone will be used). Be aware, however, that converting from a
    $(LREF DateTime) to a $(D SysTime) will not necessarily be 100% accurate due to
    DST (one hour of the year doesn't exist and another occurs twice).
    To not risk any conversion errors, keep times as
    $(D SysTime)s. Aside from DST though, there shouldn't be any conversion
    problems.

    For using time zones other than local time or UTC, use
    $(LREF PosixTimeZone) on Posix systems (or on Windows, if providing the TZ
    Database files), and use $(LREF WindowsTimeZone) on Windows systems.
    The time in $(D SysTime) is kept internally in hnsecs from midnight,
    January 1st, 1 A.D. UTC. Conversion error cannot happen when changing
    the time zone of a $(D SysTime). $(LREF LocalTime) is the $(LREF2 .TimeZone, TimeZone) class
    which represents the local time, and $(D UTC) is the $(LREF2 .TimeZone, TimeZone) class
    which represents UTC. $(D SysTime) uses $(LREF LocalTime) if no $(LREF2 .TimeZone, TimeZone)
    is provided. For more details on time zones, see the documentation for
    $(LREF2 .TimeZone, TimeZone), $(LREF PosixTimeZone), and $(LREF WindowsTimeZone).

    $(D SysTime)'s range is from approximately 29,000 B.C. to approximately
    29,000 A.D.
  +/
struct SysTime
{
    import std.typecons : Rebindable;
    import std.exception : enforce;

public:

    /++
        Params:
            dateTime = The $(LREF DateTime) to use to set this $(LREF SysTime)'s
                       internal std time. As $(LREF DateTime) has no concept of
                       time zone, tz is used as its time zone.
            tz       = The $(LREF2 .TimeZone, TimeZone) to use for this $(LREF SysTime). If null,
                       $(LREF LocalTime) will be used. The given $(LREF DateTime) is
                       assumed to be in the given time zone.
      +/
    this(in DateTime dateTime, immutable TimeZone tz = null) @safe nothrow
    {
        scope(failure) assert(0, "SysTime's constructor threw when it shouldn't have.");

        this(dateTime, Duration.zero, tz);
    }

    unittest
    {
        import std.format : format;
        static void test(DateTime dt, immutable TimeZone tz, long expected)
        {
            auto sysTime = SysTime(dt, tz);
            assert(sysTime._stdTime == expected);
            assert(sysTime._timezone is (tz is null ? LocalTime() : tz),
                   format("Given DateTime: %s", dt));
        }

        test(DateTime.init, UTC(), 0);
        test(DateTime(1,  1,  1, 12, 30, 33), UTC(),  450_330_000_000L);
        test(DateTime(0, 12, 31, 12, 30, 33), UTC(), -413_670_000_000L);
        test(DateTime(1,  1,  1,  0,  0,  0), UTC(),  0);
        test(DateTime(1,  1,  1,  0,  0,  1), UTC(),  10_000_000L);
        test(DateTime(0, 12, 31, 23, 59, 59), UTC(), -10_000_000L);

        test(DateTime(1, 1, 1, 0, 0, 0), new immutable SimpleTimeZone(dur!"minutes"(-60)), 36_000_000_000L);
        test(DateTime(1, 1, 1, 0, 0, 0), new immutable SimpleTimeZone(Duration.zero), 0);
        test(DateTime(1, 1, 1, 0, 0, 0), new immutable SimpleTimeZone(dur!"minutes"(60)), -36_000_000_000L);
    }

    /++
        Params:
            dateTime = The $(LREF DateTime) to use to set this $(LREF SysTime)'s
                       internal std time. As $(LREF DateTime) has no concept of
                       time zone, tz is used as its time zone.
            fracSecs = The fractional seconds portion of the time.
            tz       = The $(LREF2 .TimeZone, TimeZone) to use for this $(LREF SysTime). If null,
                       $(LREF LocalTime) will be used. The given $(LREF DateTime) is
                       assumed to be in the given time zone.

        Throws:
            $(LREF DateTimeException) if $(D fracSecs) is negative or if it's
            greater than or equal to one second.
      +/
    this(in DateTime dateTime, in Duration fracSecs, immutable TimeZone tz = null) @safe
    {
        enforce(fracSecs >= Duration.zero, new DateTimeException("A SysTime cannot have negative fractional seconds."));
        enforce(fracSecs < seconds(1), new DateTimeException("Fractional seconds must be less than one second."));
        auto nonNullTZ = tz is null ? LocalTime() : tz;

        immutable dateDiff = dateTime.date - Date.init;
        immutable todDiff = dateTime.timeOfDay - TimeOfDay.init;

        immutable adjustedTime = dateDiff + todDiff + fracSecs;
        immutable standardTime = nonNullTZ.tzToUTC(adjustedTime.total!"hnsecs");

        this(standardTime, nonNullTZ);
    }

    unittest
    {
        import std.format : format;
        static void test(DateTime dt, Duration fracSecs, immutable TimeZone tz, long expected)
        {
            auto sysTime = SysTime(dt, fracSecs, tz);
            assert(sysTime._stdTime == expected);
            assert(sysTime._timezone is (tz is null ? LocalTime() : tz),
                   format("Given DateTime: %s, Given Duration: %s", dt, fracSecs));
        }

        test(DateTime.init, Duration.zero, UTC(), 0);
        test(DateTime(1, 1, 1, 12, 30, 33), Duration.zero, UTC(), 450_330_000_000L);
        test(DateTime(0, 12, 31, 12, 30, 33), Duration.zero, UTC(), -413_670_000_000L);
        test(DateTime(1, 1, 1, 0, 0, 0), msecs(1), UTC(), 10_000L);
        test(DateTime(0, 12, 31, 23, 59, 59), msecs(999), UTC(), -10_000L);

        test(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC(), -1);
        test(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1), UTC(), -9_999_999);
        test(DateTime(0, 12, 31, 23, 59, 59), Duration.zero, UTC(), -10_000_000);

        assertThrown!DateTimeException(SysTime(DateTime.init, hnsecs(-1), UTC()));
        assertThrown!DateTimeException(SysTime(DateTime.init, seconds(1), UTC()));
    }

    /++
        $(RED Scheduled for deprecation. Please use the overload which takes a
              $(CXREF time, Duration) for the fractional seconds. This overload
              will be deprecated in 2.068).

        Params:
            dateTime = The $(LREF DateTime) to use to set this $(LREF SysTime)'s
                       internal std time. As $(LREF DateTime) has no concept of
                       time zone, tz is used as its time zone.
            fracSec  = The fractional seconds portion of the time.
            tz       = The $(LREF2 .TimeZone, TimeZone) to use for this $(LREF SysTime). If null,
                       $(LREF LocalTime) will be used. The given $(LREF DateTime) is
                       assumed to be in the given time zone.

        Throws:
            $(LREF DateTimeException) if $(D fracSec) is negative.
      +/
    //deprecated("Please use the overload which takes a Duration instead of a FracSec.")
    this(in DateTime dateTime, in FracSec fracSec, immutable TimeZone tz = null) @safe
    {
        immutable fracHNSecs = fracSec.hnsecs;
        enforce(fracHNSecs >= 0, new DateTimeException("A SysTime cannot have negative fractional seconds."));
        _timezone = tz is null ? LocalTime() : tz;

        scope(failure) assert(0, "Date, TimeOfDay, or DateTime's constructor threw when it shouldn't have.");

        immutable dateDiff = (dateTime.date - Date(1, 1, 1)).total!"hnsecs";
        immutable todDiff = (dateTime.timeOfDay - TimeOfDay(0, 0, 0)).total!"hnsecs";

        immutable adjustedTime = dateDiff + todDiff + fracHNSecs;
        immutable standardTime = _timezone.tzToUTC(adjustedTime);

        this(standardTime, _timezone);
    }

    /+deprecated+/ unittest
    {
        import std.format : format;

        static void test(DateTime dt,
                         FracSec fracSec,
                         immutable TimeZone tz,
                         long expected)
        {
            auto sysTime = SysTime(dt, fracSec, tz);
            assert(sysTime._stdTime == expected);
            assert(sysTime._timezone is (tz is null ? LocalTime() : tz),
                   format("Given DateTime: %s, Given FracSec: %s", dt, fracSec));
        }

        test(DateTime.init, FracSec.init, UTC(), 0);
        test(DateTime(1, 1, 1, 12, 30, 33), FracSec.init, UTC(), 450_330_000_000L);
        test(DateTime(0, 12, 31, 12, 30, 33), FracSec.init, UTC(), -413_670_000_000L);
        test(DateTime(1, 1, 1, 0, 0, 0), FracSec.from!"msecs"(1), UTC(), 10_000L);
        test(DateTime(0, 12, 31, 23, 59, 59), FracSec.from!"msecs"(999), UTC(), -10_000L);

        test(DateTime(0, 12, 31, 23, 59, 59), FracSec.from!"hnsecs"(9_999_999), UTC(), -1);
        test(DateTime(0, 12, 31, 23, 59, 59), FracSec.from!"hnsecs"(1), UTC(), -9_999_999);
        test(DateTime(0, 12, 31, 23, 59, 59), FracSec.from!"hnsecs"(0), UTC(), -10_000_000);

        assertThrown!DateTimeException(SysTime(DateTime.init, FracSec.from!"hnsecs"(-1), UTC()));
    }

    /++
        Params:
            date = The $(LREF Date) to use to set this $(LREF SysTime)'s internal std
                   time. As $(LREF Date) has no concept of time zone, tz is used as
                   its time zone.
            tz   = The $(LREF2 .TimeZone, TimeZone) to use for this $(LREF SysTime). If null,
                   $(LREF LocalTime) will be used. The given $(LREF Date) is assumed
                   to be in the given time zone.
      +/
    this(in Date date, immutable TimeZone tz = null) @safe nothrow
    {
        scope(failure) assert(0, "Date's constructor through when it shouldn't have.");

        _timezone = tz is null ? LocalTime() : tz;

        immutable adjustedTime = (date - Date(1, 1, 1)).total!"hnsecs";
        immutable standardTime = _timezone.tzToUTC(adjustedTime);

        this(standardTime, _timezone);
    }

    unittest
    {
        static void test(Date d, immutable TimeZone tz, long expected)
        {
            import std.format : format;
            auto sysTime = SysTime(d, tz);
            assert(sysTime._stdTime == expected);
            assert(sysTime._timezone is (tz is null ? LocalTime() : tz),
                   format("Given Date: %s", d));
        }

        test(Date.init, UTC(), 0);
        test(Date(1, 1, 1), UTC(), 0);
        test(Date(1, 1, 2), UTC(), 864000000000);
        test(Date(0, 12, 31), UTC(), -864000000000);
    }

    /++
        Note:
            Whereas the other constructors take in the given date/time, assume
            that it's in the given time zone, and convert it to hnsecs in UTC
            since midnight, January 1st, 1 A.D. UTC - i.e. std time - this
            constructor takes a std time, which is specifically already in UTC,
            so no conversion takes place. Of course, the various getter
            properties and functions will use the given time zone's conversion
            function to convert the results to that time zone, but no conversion
            of the arguments to this constructor takes place.

        Params:
            stdTime = The number of hnsecs since midnight, January 1st, 1 A.D. UTC.
            tz      = The $(LREF2 .TimeZone, TimeZone) to use for this $(LREF SysTime). If null,
                      $(LREF LocalTime) will be used.
      +/
    this(long stdTime, immutable TimeZone tz = null) @safe pure nothrow
    {
        _stdTime = stdTime;
        _timezone = tz is null ? LocalTime() : tz;
    }

    unittest
    {
        static void test(long stdTime, immutable TimeZone tz)
        {
            import std.format : format;
            auto sysTime = SysTime(stdTime, tz);
            assert(sysTime._stdTime == stdTime);
            assert(sysTime._timezone is (tz is null ? LocalTime() : tz),
                   format("Given stdTime: %s", stdTime));
        }

        foreach (stdTime; [-1234567890L, -250, 0, 250, 1235657390L])
        {
            foreach (tz; testTZs)
                test(stdTime, tz);
        }
    }

    /++
        Params:
            rhs = The $(LREF SysTime) to assign to this one.
      +/
    ref SysTime opAssign(const ref SysTime rhs) return @safe pure nothrow
    {
        _stdTime = rhs._stdTime;
        _timezone = rhs._timezone;

        return this;
    }

    /++
        Params:
            rhs = The $(LREF SysTime) to assign to this one.
      +/
    ref SysTime opAssign(SysTime rhs) return @safe pure nothrow
    {
        _stdTime = rhs._stdTime;
        _timezone = rhs._timezone;

        return this;
    }

    /++
        Checks for equality between this $(LREF SysTime) and the given
        $(LREF SysTime).

        Note that the time zone is ignored. Only the internal
        std times (which are in UTC) are compared.
     +/
    bool opEquals(const SysTime rhs) @safe const pure nothrow
    {
        return opEquals(rhs);
    }

    /// ditto
    bool opEquals(const ref SysTime rhs) @safe const pure nothrow
    {
        return _stdTime == rhs._stdTime;
    }

    unittest
    {
        import std.range;
        assert(SysTime(DateTime.init, UTC()) == SysTime(0, UTC()));
        assert(SysTime(DateTime.init, UTC()) == SysTime(0));
        assert(SysTime(Date.init, UTC()) == SysTime(0));
        assert(SysTime(0) == SysTime(0));

        static void test(DateTime dt,
                         immutable TimeZone tz1,
                         immutable TimeZone tz2)
        {
            auto st1 = SysTime(dt);
            st1.timezone = tz1;

            auto st2 = SysTime(dt);
            st2.timezone = tz2;

            assert(st1 == st2);
        }

        foreach (tz1; testTZs)
        {
            foreach (tz2; testTZs)
            {
                foreach (dt; chain(testDateTimesBC, testDateTimesAD))
                        test(dt, tz1, tz2);
            }
        }

        auto st = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        static assert(__traits(compiles, st == st));
        static assert(__traits(compiles, st == cst));
        //static assert(__traits(compiles, st == ist));
        static assert(__traits(compiles, cst == st));
        static assert(__traits(compiles, cst == cst));
        //static assert(__traits(compiles, cst == ist));
        //static assert(__traits(compiles, ist == st));
        //static assert(__traits(compiles, ist == cst));
        //static assert(__traits(compiles, ist == ist));
    }

    /++
        Compares this $(LREF SysTime) with the given $(LREF SysTime).

        Time zone is irrelevant when comparing $(LREF SysTime)s.

        Returns:
            $(BOOKTABLE,
            $(TR $(TD this &lt; rhs) $(TD &lt; 0))
            $(TR $(TD this == rhs) $(TD 0))
            $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(in SysTime rhs) @safe const pure nothrow
    {
        if (_stdTime < rhs._stdTime)
            return -1;
        if (_stdTime > rhs._stdTime)
            return 1;

        return 0;
    }

    unittest
    {
        import std.range;
        assert(SysTime(DateTime.init, UTC()).opCmp(SysTime(0, UTC())) == 0);
        assert(SysTime(DateTime.init, UTC()).opCmp(SysTime(0)) == 0);
        assert(SysTime(Date.init, UTC()).opCmp(SysTime(0)) == 0);
        assert(SysTime(0).opCmp(SysTime(0)) == 0);

        static void testEqual(SysTime st,
                              immutable TimeZone tz1,
                              immutable TimeZone tz2)
        {
            auto st1 = st;
            st1.timezone = tz1;

            auto st2 = st;
            st2.timezone = tz2;

            assert(st1.opCmp(st2) == 0);
        }

        auto sts = array(map!SysTime(chain(testDateTimesBC, testDateTimesAD)));

        foreach (st; sts)
            foreach (tz1; testTZs)
                foreach (tz2; testTZs)
                    testEqual(st, tz1, tz2);

        static void testCmp(SysTime st1,
                            immutable TimeZone tz1,
                            SysTime st2,
                            immutable TimeZone tz2)
        {
            st1.timezone = tz1;
            st2.timezone = tz2;
            assert(st1.opCmp(st2) < 0);
            assert(st2.opCmp(st1) > 0);
        }

        foreach (si, st1; sts)
            foreach (st2; sts[si+1 .. $])
                foreach (tz1; testTZs)
                    foreach (tz2; testTZs)
                        testCmp(st1, tz1, st2, tz2);

        auto st = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 33, 30));
        static assert(__traits(compiles, st.opCmp(st)));
        static assert(__traits(compiles, st.opCmp(cst)));
        //static assert(__traits(compiles, st.opCmp(ist)));
        static assert(__traits(compiles, cst.opCmp(st)));
        static assert(__traits(compiles, cst.opCmp(cst)));
        //static assert(__traits(compiles, cst.opCmp(ist)));
        //static assert(__traits(compiles, ist.opCmp(st)));
        //static assert(__traits(compiles, ist.opCmp(cst)));
        //static assert(__traits(compiles, ist.opCmp(ist)));
    }

    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.
     +/
    @property short year() @safe const nothrow
    {
        return (cast(Date)this).year;
    }

    unittest
    {
        import std.range;
        static void test(SysTime sysTime, long expected)
        {
            import std.format : format;
            assert(sysTime.year == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), 1);
        test(SysTime(1, UTC()), 1);
        test(SysTime(-1, UTC()), 0);

        foreach (year; chain(testYearsBC, testYearsAD))
        {
            foreach (md; testMonthDays)
            {
                foreach (tod; testTODs)
                {
                    auto dt = DateTime(Date(year, md.month, md.day), tod);

                    foreach (tz; testTZs)
                    {
                        foreach (fs; testFracSecs)
                            test(SysTime(dt, fs, tz), year);
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.year));
        //static assert(__traits(compiles, ist.year));
    }

    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.

        Params:
            year = The year to set this $(LREF SysTime)'s year to.

        Throws:
            $(LREF DateTimeException) if the new year is not a leap year and the
            resulting date would be on February 29th.
     +/
    @property void year(int year) @safe
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.year = year;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(date.dayOfGregorianCal - 1);
        adjTime = newDaysHNSecs + hnsecs;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 7, 6, 9, 7, 5)).year == 1999);
        assert(SysTime(DateTime(2010, 10, 4, 0, 0, 30)).year == 2010);
        assert(SysTime(DateTime(-7, 4, 5, 7, 45, 2)).year == -7);
    }

    unittest
    {
        import std.range;
        static void test(SysTime st, int year, in SysTime expected)
        {
            st.year = year;
            assert(st == expected);
        }

        foreach (st; chain(testSysTimesBC, testSysTimesAD))
        {
            auto dt = cast(DateTime)st;

            foreach (year; chain(testYearsBC, testYearsAD))
            {
                auto e = SysTime(DateTime(year, dt.month, dt.day, dt.hour, dt.minute, dt.second),
                                 st.fracSecs,
                                 st.timezone);
                test(st, year, e);
            }
        }

        foreach (fs; testFracSecs)
        {
            foreach (tz; testTZs)
            {
                foreach (tod; testTODs)
                {
                    test(SysTime(DateTime(Date(1999, 2, 28), tod), fs, tz), 2000,
                         SysTime(DateTime(Date(2000, 2, 28), tod), fs, tz));
                    test(SysTime(DateTime(Date(2000, 2, 28), tod), fs, tz), 1999,
                         SysTime(DateTime(Date(1999, 2, 28), tod), fs, tz));
                }

                foreach (tod; testTODsThrown)
                {
                    auto st = SysTime(DateTime(Date(2000, 2, 29), tod), fs, tz);
                    assertThrown!DateTimeException(st.year = 1999);
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.year = 7));
        //static assert(!__traits(compiles, ist.year = 7));
    }

    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Throws:
            $(LREF DateTimeException) if $(D isAD) is true.
     +/
    @property ushort yearBC() @safe const
    {
        return (cast(Date)this).yearBC;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(0, 1, 1, 12, 30, 33)).yearBC == 1);
        assert(SysTime(DateTime(-1, 1, 1, 10, 7, 2)).yearBC == 2);
        assert(SysTime(DateTime(-100, 1, 1, 4, 59, 0)).yearBC == 101);
    }

    unittest
    {
        import std.format : format;
        foreach (st; testSysTimesBC)
        {
            auto msg = format("SysTime: %s", st);
            assertNotThrown!DateTimeException(st.yearBC, msg);
            assert(st.yearBC == (st.year * -1) + 1, msg);
        }

        foreach (st; [testSysTimesAD[0], testSysTimesAD[$/2], testSysTimesAD[$-1]])
            assertThrown!DateTimeException(st.yearBC, format("SysTime: %s", st));

        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.year = 12));
        static assert(!__traits(compiles, cst.year = 12));
        //static assert(!__traits(compiles, ist.year = 12));
    }


    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Params:
            year = The year B.C. to set this $(LREF SysTime)'s year to.

        Throws:
            $(LREF DateTimeException) if a non-positive value is given.
     +/
    @property void yearBC(int year) @safe
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.yearBC = year;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(date.dayOfGregorianCal - 1);
        adjTime = newDaysHNSecs + hnsecs;
    }

    unittest
    {
        auto st = SysTime(DateTime(2010, 1, 1, 7, 30, 0));
        st.yearBC = 1;
        assert(st == SysTime(DateTime(0, 1, 1, 7, 30, 0)));

        st.yearBC = 10;
        assert(st == SysTime(DateTime(-9, 1, 1, 7, 30, 0)));
    }

    unittest
    {
        import std.range;
        static void test(SysTime st, int year, in SysTime expected)
        {
            import std.format : format;
            st.yearBC = year;
            assert(st == expected, format("SysTime: %s", st));
        }

        foreach (st; chain(testSysTimesBC, testSysTimesAD))
        {
            auto dt = cast(DateTime)st;

            foreach (year; testYearsBC)
            {
                auto e = SysTime(DateTime(year, dt.month, dt.day, dt.hour, dt.minute, dt.second),
                                 st.fracSecs,
                                 st.timezone);
                test(st, (year * -1) + 1, e);
            }
        }

        foreach (st; [testSysTimesBC[0], testSysTimesBC[$ - 1],
                     testSysTimesAD[0], testSysTimesAD[$ - 1]])
        {
            foreach (year; testYearsBC)
                assertThrown!DateTimeException(st.yearBC = year);
        }

        foreach (fs; testFracSecs)
        {
            foreach (tz; testTZs)
            {
                foreach (tod; testTODs)
                {
                    test(SysTime(DateTime(Date(-1999, 2, 28), tod), fs, tz), 2001,
                         SysTime(DateTime(Date(-2000, 2, 28), tod), fs, tz));
                    test(SysTime(DateTime(Date(-2000, 2, 28), tod), fs, tz), 2000,
                         SysTime(DateTime(Date(-1999, 2, 28), tod), fs, tz));
                }

                foreach (tod; testTODsThrown)
                {
                    auto st = SysTime(DateTime(Date(-2000, 2, 29), tod), fs, tz);
                    assertThrown!DateTimeException(st.year = -1999);
                }
            }
        }

        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.yearBC = 12));
        static assert(!__traits(compiles, cst.yearBC = 12));
        //static assert(!__traits(compiles, ist.yearBC = 12));
    }

    /++
        Month of a Gregorian Year.
     +/
    @property Month month() @safe const nothrow
    {
        return (cast(Date)this).month;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 7, 6, 9, 7, 5)).month == 7);
        assert(SysTime(DateTime(2010, 10, 4, 0, 0, 30)).month == 10);
        assert(SysTime(DateTime(-7, 4, 5, 7, 45, 2)).month == 4);
    }

    unittest
    {
        import std.range;
        static void test(SysTime sysTime, Month expected)
        {
            import std.format : format;
            assert(sysTime.month == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), Month.jan);
        test(SysTime(1, UTC()), Month.jan);
        test(SysTime(-1, UTC()), Month.dec);

        foreach (year; chain(testYearsBC, testYearsAD))
        {
            foreach (md; testMonthDays)
            {
                foreach (tod; testTODs)
                {
                    auto dt = DateTime(Date(year, md.month, md.day), tod);

                    foreach (fs; testFracSecs)
                    {
                        foreach (tz; testTZs)
                            test(SysTime(dt, fs, tz), md.month);
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.month));
        //static assert(__traits(compiles, ist.month));
    }


    /++
        Month of a Gregorian Year.

        Params:
            month = The month to set this $(LREF SysTime)'s month to.

        Throws:
            $(LREF DateTimeException) if the given month is not a valid month.
     +/
    @property void month(Month month) @safe
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.month = month;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(date.dayOfGregorianCal - 1);
        adjTime = newDaysHNSecs + hnsecs;
    }

    unittest
    {
        import std.range;

        static void test(SysTime st, Month month, in SysTime expected)
        {
            st.month = cast(Month)month;
            assert(st == expected);
        }

        foreach (st; chain(testSysTimesBC, testSysTimesAD))
        {
            auto dt = cast(DateTime)st;

            foreach (md; testMonthDays)
            {
                if (st.day > maxDay(dt.year, md.month))
                    continue;
                auto e = SysTime(DateTime(dt.year, md.month, dt.day, dt.hour, dt.minute, dt.second),
                                 st.fracSecs,
                                 st.timezone);
                test(st, md.month, e);
            }
        }

        foreach (fs; testFracSecs)
        {
            foreach (tz; testTZs)
            {
                foreach (tod; testTODs)
                {
                    foreach (year; filter!((a){return yearIsLeapYear(a);})
                                         (chain(testYearsBC, testYearsAD)))
                    {
                        test(SysTime(DateTime(Date(year, 1, 29), tod), fs, tz),
                             Month.feb,
                             SysTime(DateTime(Date(year, 2, 29), tod), fs, tz));
                    }

                    foreach (year; chain(testYearsBC, testYearsAD))
                    {
                        test(SysTime(DateTime(Date(year, 1, 28), tod), fs, tz),
                             Month.feb,
                             SysTime(DateTime(Date(year, 2, 28), tod), fs, tz));
                        test(SysTime(DateTime(Date(year, 7, 30), tod), fs, tz),
                             Month.jun,
                             SysTime(DateTime(Date(year, 6, 30), tod), fs, tz));
                    }
                }
            }
        }

        foreach (fs; [testFracSecs[0], testFracSecs[$-1]])
        {
            foreach (tz; testTZs)
            {
                foreach (tod; testTODsThrown)
                {
                    foreach (year; [testYearsBC[$-3], testYearsBC[$-2],
                                   testYearsBC[$-2], testYearsAD[0],
                                   testYearsAD[$-2], testYearsAD[$-1]])
                    {
                        auto day = yearIsLeapYear(year) ? 30 : 29;
                        auto st1 = SysTime(DateTime(Date(year, 1, day), tod), fs, tz);
                        assertThrown!DateTimeException(st1.month = Month.feb);

                        auto st2 = SysTime(DateTime(Date(year, 7, 31), tod), fs, tz);
                        assertThrown!DateTimeException(st2.month = Month.jun);
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.month = 12));
        //static assert(!__traits(compiles, ist.month = 12));
    }

    /++
        Day of a Gregorian Month.
     +/
    @property ubyte day() @safe const nothrow
    {
        return (cast(Date)this).day;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 7, 6, 9, 7, 5)).day == 6);
        assert(SysTime(DateTime(2010, 10, 4, 0, 0, 30)).day == 4);
        assert(SysTime(DateTime(-7, 4, 5, 7, 45, 2)).day == 5);
    }

    unittest
    {
        import std.range;

        static void test(SysTime sysTime, int expected)
        {
            import std.format : format;
            assert(sysTime.day == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), 1);
        test(SysTime(1, UTC()), 1);
        test(SysTime(-1, UTC()), 31);

        foreach (year; chain(testYearsBC, testYearsAD))
        {
            foreach (md; testMonthDays)
            {
                foreach (tod; testTODs)
                {
                    auto dt = DateTime(Date(year, md.month, md.day), tod);

                    foreach (tz; testTZs)
                    {
                        foreach (fs; testFracSecs)
                            test(SysTime(dt, fs, tz), md.day);
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.day));
        //static assert(__traits(compiles, ist.day));
    }


    /++
        Day of a Gregorian Month.

        Params:
            day = The day of the month to set this $(LREF SysTime)'s day to.

        Throws:
            $(LREF DateTimeException) if the given day is not a valid day of the
            current month.
     +/
    @property void day(int day) @safe
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.day = day;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(date.dayOfGregorianCal - 1);
        adjTime = newDaysHNSecs + hnsecs;
    }

    unittest
    {
        import std.format : format;
        import std.range;

        foreach (day; chain(testDays))
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;

                if (day > maxDay(dt.year, dt.month))
                    continue;
                auto expected = SysTime(DateTime(dt.year, dt.month, day, dt.hour, dt.minute, dt.second),
                                        st.fracSecs,
                                        st.timezone);
                st.day = day;
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        foreach (tz; testTZs)
        {
            foreach (tod; testTODs)
            {
                foreach (fs; testFracSecs)
                {
                    foreach (year; chain(testYearsBC, testYearsAD))
                    {
                        foreach (month; EnumMembers!Month)
                        {
                            auto st = SysTime(DateTime(Date(year, month, 1), tod), fs, tz);
                            immutable max = maxDay(year, month);
                            auto expected = SysTime(DateTime(Date(year, month, max), tod), fs, tz);

                            st.day = max;
                            assert(st == expected, format("[%s] [%s]", st, expected));
                        }
                    }
                }
            }
        }

        foreach (tz; testTZs)
        {
            foreach (tod; testTODsThrown)
            {
                foreach (fs; [testFracSecs[0], testFracSecs[$-1]])
                {
                    foreach (year; [testYearsBC[$-3], testYearsBC[$-2],
                                   testYearsBC[$-2], testYearsAD[0],
                                   testYearsAD[$-2], testYearsAD[$-1]])
                    {
                        foreach (month; EnumMembers!Month)
                        {
                            auto st = SysTime(DateTime(Date(year, month, 1), tod), fs, tz);
                            immutable max = maxDay(year, month);

                            assertThrown!DateTimeException(st.day = max + 1);
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.day = 27));
        //static assert(!__traits(compiles, ist.day = 27));
    }


    /++
        Hours past midnight.
     +/
    @property ubyte hour() @safe const nothrow
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        return cast(ubyte)getUnitsFromHNSecs!"hours"(hnsecs);
    }

    unittest
    {
        import std.range;
        import std.format : format;

        static void test(SysTime sysTime, int expected)
        {
            assert(sysTime.hour == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), 0);
        test(SysTime(1, UTC()), 0);
        test(SysTime(-1, UTC()), 23);

        foreach (tz; testTZs)
        {
            foreach (year; chain(testYearsBC, testYearsAD))
            {
                foreach (md; testMonthDays)
                {
                    foreach (hour; testHours)
                    {
                        foreach (minute; testMinSecs)
                        {
                            foreach (second; testMinSecs)
                            {
                                auto dt = DateTime(Date(year, md.month, md.day),
                                                   TimeOfDay(hour, minute, second));

                                foreach (fs; testFracSecs)
                                    test(SysTime(dt, fs, tz), hour);
                            }
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.hour));
        //static assert(__traits(compiles, ist.hour));
    }


    /++
        Hours past midnight.

        Params:
            hour = The hours to set this $(LREF SysTime)'s hour to.

        Throws:
            $(LREF DateTimeException) if the given hour are not a valid hour of
            the day.
     +/
    @property void hour(int hour) @safe
    {
        enforceValid!"hours"(hour);

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs);
        immutable daysHNSecs = convert!("days", "hnsecs")(days);
        immutable negative = hnsecs < 0;

        if (negative)
            hnsecs += convert!("hours", "hnsecs")(24);

        hnsecs = removeUnitsFromHNSecs!"hours"(hnsecs);
        hnsecs += convert!("hours", "hnsecs")(hour);

        if (negative)
            hnsecs -= convert!("hours", "hnsecs")(24);

        adjTime = daysHNSecs + hnsecs;
    }

    unittest
    {
        import std.range;
        import std.format : format;

        foreach (hour; chain(testHours))
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;
                auto expected = SysTime(DateTime(dt.year, dt.month, dt.day, hour, dt.minute, dt.second),
                                        st.fracSecs,
                                        st.timezone);
                st.hour = hour;
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        auto st = testSysTimesAD[0];
        assertThrown!DateTimeException(st.hour = -1);
        assertThrown!DateTimeException(st.hour = 60);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.hour = 27));
        //static assert(!__traits(compiles, ist.hour = 27));
    }


    /++
        Minutes past the current hour.
     +/
    @property ubyte minute() @safe const nothrow
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        hnsecs = removeUnitsFromHNSecs!"hours"(hnsecs);

        return cast(ubyte)getUnitsFromHNSecs!"minutes"(hnsecs);
    }

    unittest
    {
        import std.range;
        import std.format : format;

        static void test(SysTime sysTime, int expected)
        {
            assert(sysTime.minute == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), 0);
        test(SysTime(1, UTC()), 0);
        test(SysTime(-1, UTC()), 59);

        foreach (tz; testTZs)
        {
            foreach (year; chain(testYearsBC, testYearsAD))
            {
                foreach (md; testMonthDays)
                {
                    foreach (hour; testHours)
                    {
                        foreach (minute; testMinSecs)
                        {
                            foreach (second; testMinSecs)
                            {
                                auto dt = DateTime(Date(year, md.month, md.day),
                                                   TimeOfDay(hour, minute, second));

                                foreach (fs; testFracSecs)
                                    test(SysTime(dt, fs, tz), minute);
                            }
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.minute));
        //static assert(__traits(compiles, ist.minute));
    }


    /++
        Minutes past the current hour.

        Params:
            minute = The minute to set this $(LREF SysTime)'s minute to.

        Throws:
            $(LREF DateTimeException) if the given minute are not a valid minute
            of an hour.
     +/
    @property void minute(int minute) @safe
    {
        enforceValid!"minutes"(minute);

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs);
        immutable daysHNSecs = convert!("days", "hnsecs")(days);
        immutable negative = hnsecs < 0;

        if (negative)
            hnsecs += convert!("hours", "hnsecs")(24);

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        hnsecs = removeUnitsFromHNSecs!"minutes"(hnsecs);

        hnsecs += convert!("hours", "hnsecs")(hour);
        hnsecs += convert!("minutes", "hnsecs")(minute);

        if (negative)
            hnsecs -= convert!("hours", "hnsecs")(24);

        adjTime = daysHNSecs + hnsecs;
    }

    unittest
    {
        import std.range;
        import std.format : format;

        foreach (minute; testMinSecs)
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;
                auto expected = SysTime(DateTime(dt.year, dt.month, dt.day, dt.hour, minute, dt.second),
                                        st.fracSecs,
                                        st.timezone);
                st.minute = minute;
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        auto st = testSysTimesAD[0];
        assertThrown!DateTimeException(st.minute = -1);
        assertThrown!DateTimeException(st.minute = 60);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.minute = 27));
        //static assert(!__traits(compiles, ist.minute = 27));
    }


    /++
        Seconds past the current minute.
     +/
    @property ubyte second() @safe const nothrow
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        hnsecs = removeUnitsFromHNSecs!"hours"(hnsecs);
        hnsecs = removeUnitsFromHNSecs!"minutes"(hnsecs);

        return cast(ubyte)getUnitsFromHNSecs!"seconds"(hnsecs);
    }

    unittest
    {
        import std.range;
        import std.format : format;

        static void test(SysTime sysTime, int expected)
        {
            assert(sysTime.second == expected,
                             format("Value given: %s", sysTime));
        }

        test(SysTime(0, UTC()), 0);
        test(SysTime(1, UTC()), 0);
        test(SysTime(-1, UTC()), 59);

        foreach (tz; testTZs)
        {
            foreach (year; chain(testYearsBC, testYearsAD))
            {
                foreach (md; testMonthDays)
                {
                    foreach (hour; testHours)
                    {
                        foreach (minute; testMinSecs)
                        {
                            foreach (second; testMinSecs)
                            {
                                auto dt = DateTime(Date(year, md.month, md.day),
                                                   TimeOfDay(hour, minute, second));

                                foreach (fs; testFracSecs)
                                    test(SysTime(dt, fs, tz), second);
                            }
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.second));
        //static assert(__traits(compiles, ist.second));
    }


    /++
        Seconds past the current minute.

        Params:
            second = The second to set this $(LREF SysTime)'s second to.

        Throws:
            $(LREF DateTimeException) if the given second are not a valid second
            of a minute.
     +/
    @property void second(int second) @safe
    {
        enforceValid!"seconds"(second);

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs);
        immutable daysHNSecs = convert!("days", "hnsecs")(days);
        immutable negative = hnsecs < 0;

        if (negative)
            hnsecs += convert!("hours", "hnsecs")(24);

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        hnsecs = removeUnitsFromHNSecs!"seconds"(hnsecs);

        hnsecs += convert!("hours", "hnsecs")(hour);
        hnsecs += convert!("minutes", "hnsecs")(minute);
        hnsecs += convert!("seconds", "hnsecs")(second);

        if (negative)
            hnsecs -= convert!("hours", "hnsecs")(24);

        adjTime = daysHNSecs + hnsecs;
    }

    unittest
    {
        import std.range;
        import std.format : format;

        foreach (second; testMinSecs)
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;
                auto expected = SysTime(DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, second),
                                        st.fracSecs,
                                        st.timezone);
                st.second = second;
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        auto st = testSysTimesAD[0];
        assertThrown!DateTimeException(st.second = -1);
        assertThrown!DateTimeException(st.second = 60);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.seconds = 27));
        //static assert(!__traits(compiles, ist.seconds = 27));
    }


    /++
        Fractional seconds past the second (i.e. the portion of a
        $(LREF SysTime) which is less than a second).
     +/
    @property Duration fracSecs() @safe const nothrow
    {
        auto hnsecs = removeUnitsFromHNSecs!"days"(adjTime);

        if (hnsecs < 0)
            hnsecs += convert!("hours", "hnsecs")(24);

        return dur!"hnsecs"(removeUnitsFromHNSecs!"seconds"(hnsecs));
    }

    ///
    unittest
    {
        auto dt = DateTime(1982, 4, 1, 20, 59, 22);
        assert(SysTime(dt, msecs(213)).fracSecs == msecs(213));
        assert(SysTime(dt, usecs(5202)).fracSecs == usecs(5202));
        assert(SysTime(dt, hnsecs(1234567)).fracSecs == hnsecs(1234567));

        // SysTime and Duration both have a precision of hnsecs (100 ns),
        // so nsecs are going to be truncated.
        assert(SysTime(dt, nsecs(123456789)).fracSecs == nsecs(123456700));
    }

    unittest
    {
        import std.range;

        assert(SysTime(0, UTC()).fracSecs == Duration.zero);
        assert(SysTime(1, UTC()).fracSecs == hnsecs(1));
        assert(SysTime(-1, UTC()).fracSecs == hnsecs(9_999_999));

        foreach (tz; testTZs)
        {
            foreach (year; chain(testYearsBC, testYearsAD))
            {
                foreach (md; testMonthDays)
                {
                    foreach (hour; testHours)
                    {
                        foreach (minute; testMinSecs)
                        {
                            foreach (second; testMinSecs)
                            {
                                auto dt = DateTime(Date(year, md.month, md.day), TimeOfDay(hour, minute, second));
                                foreach (fs; testFracSecs)
                                    assert(SysTime(dt, fs, tz).fracSecs == fs);
                            }
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.fracSecs));
        //static assert(__traits(compiles, ist.fracSecs));
    }


    /++
        Fractional seconds past the second (i.e. the portion of a
        $(LREF SysTime) which is less than a second).

        Params:
            fracSecs = The duration to set this $(LREF SysTime)'s fractional
                       seconds to.

        Throws:
            $(LREF DateTimeException) if the given duration is negative or if
            it's greater than or equal to one second.
     +/
    @property void fracSecs(Duration fracSecs) @safe
    {
        enforce(fracSecs >= Duration.zero, new DateTimeException("A SysTime cannot have negative fractional seconds."));
        enforce(fracSecs < seconds(1), new DateTimeException("Fractional seconds must be less than one second."));

        auto oldHNSecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(oldHNSecs);
        immutable daysHNSecs = convert!("days", "hnsecs")(days);
        immutable negative = oldHNSecs < 0;

        if (negative)
            oldHNSecs += convert!("hours", "hnsecs")(24);

        immutable seconds = splitUnitsFromHNSecs!"seconds"(oldHNSecs);
        immutable secondsHNSecs = convert!("seconds", "hnsecs")(seconds);
        auto newHNSecs = fracSecs.total!"hnsecs" + secondsHNSecs;

        if (negative)
            newHNSecs -= convert!("hours", "hnsecs")(24);

        adjTime = daysHNSecs + newHNSecs;
    }

    ///
    unittest
    {
        auto st = SysTime(DateTime(1982, 4, 1, 20, 59, 22));
        assert(st.fracSecs == Duration.zero);

        st.fracSecs = msecs(213);
        assert(st.fracSecs == msecs(213));

        st.fracSecs = hnsecs(1234567);
        assert(st.fracSecs == hnsecs(1234567));

        // SysTime has a precision of hnsecs (100 ns), so nsecs are
        // going to be truncated.
        st.fracSecs = nsecs(123456789);
        assert(st.fracSecs == hnsecs(1234567));
    }

    unittest
    {
        import std.range;
        import std.format : format;

        foreach (fracSec; testFracSecs)
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;
                auto expected = SysTime(dt, fracSec, st.timezone);
                st.fracSecs = fracSec;
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        auto st = testSysTimesAD[0];
        assertThrown!DateTimeException(st.fracSecs = hnsecs(-1));
        assertThrown!DateTimeException(st.fracSecs = seconds(1));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.fracSecs = msecs(7)));
        //static assert(!__traits(compiles, ist.fracSecs = msecs(7)));
    }


    /++
        $(RED Scheduled for deprecation. Please use $(LREF fracSecs) instead of
              fracSec. It uses a $(CXREF time, Duration) to represent the
              fractional seconds instead of a $(CXREF time, FracSec). This
              overload will be deprecated in 2.068).

        Fractional seconds past the second.
     +/
    //deprecated("Please use fracSecs (with an s) rather than fracSec (without an s). It returns a Duration instead of a FracSec, as FracSec is being deprecated.")
    @property FracSec fracSec() @safe const nothrow
    {
        scope(failure) assert(0, "FracSec.from!\"hnsecs\"() threw.");

        auto hnsecs = removeUnitsFromHNSecs!"days"(adjTime);

        if (hnsecs < 0)
            hnsecs += convert!("hours", "hnsecs")(24);

        hnsecs = removeUnitsFromHNSecs!"seconds"(hnsecs);

        return FracSec.from!"hnsecs"(cast(int)hnsecs);
    }

    /+deprecated+/ unittest
    {
        import std.range;
        import std.format : format;
        import core.exception : AssertError;

        static void test(SysTime sysTime, FracSec expected, size_t line = __LINE__)
        {
            if (sysTime.fracSec != expected)
                throw new AssertError(format("Value given: %s", sysTime.fracSec), __FILE__, line);
        }

        test(SysTime(0, UTC()), FracSec.from!"hnsecs"(0));
        test(SysTime(1, UTC()), FracSec.from!"hnsecs"(1));
        test(SysTime(-1, UTC()), FracSec.from!"hnsecs"(9_999_999));

        foreach (tz; testTZs)
        {
            foreach (year; chain(testYearsBC, testYearsAD))
            {
                foreach (md; testMonthDays)
                {
                    foreach (hour; testHours)
                    {
                        foreach (minute; testMinSecs)
                        {
                            foreach (second; testMinSecs)
                            {
                                auto dt = DateTime(Date(year, md.month, md.day),
                                                   TimeOfDay(hour, minute, second));

                                foreach (fs; testFracSecs)
                                    test(SysTime(dt, fs, tz), FracSec.from!"hnsecs"(fs.total!"hnsecs"));
                            }
                        }
                    }
                }
            }
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.fracSec));
        //static assert(__traits(compiles, ist.fracSec));
    }


    /++
        $(RED Scheduled for deprecation. Please use $(LREF fracSecs) instead of
              fracSec. It uses a $(CXREF time, Duration) to represent the
              fractional seconds instead of a $(CXREF time, FracSec). This
              overload will be deprecated in 2.068).

        Fractional seconds past the second.

        Params:
            fracSec = The fractional seconds to set this $(LREF SysTime)'s
                      fractional seconds to.

        Throws:
            $(LREF DateTimeException) if $(D fracSec) is negative.
     +/
    //deprecated("Please use fracSecs (with an s) rather than fracSec (without an s). It takes a Duration instead of a FracSec, as FracSec is being deprecated.")
    @property void fracSec(FracSec fracSec) @safe
    {
        immutable fracHNSecs = fracSec.hnsecs;
        enforce(fracHNSecs >= 0, new DateTimeException("A SysTime cannot have negative fractional seconds."));

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs);
        immutable daysHNSecs = convert!("days", "hnsecs")(days);
        immutable negative = hnsecs < 0;

        if (negative)
            hnsecs += convert!("hours", "hnsecs")(24);

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable second = getUnitsFromHNSecs!"seconds"(hnsecs);

        hnsecs = fracHNSecs;
        hnsecs += convert!("hours", "hnsecs")(hour);
        hnsecs += convert!("minutes", "hnsecs")(minute);
        hnsecs += convert!("seconds", "hnsecs")(second);

        if (negative)
            hnsecs -= convert!("hours", "hnsecs")(24);

        adjTime = daysHNSecs + hnsecs;
    }

    /+deprecated+/ unittest
    {
        import std.range;
        import std.format : format;

        foreach (fracSec; testFracSecs)
        {
            foreach (st; chain(testSysTimesBC, testSysTimesAD))
            {
                auto dt = cast(DateTime)st;
                auto expected = SysTime(dt, fracSec, st.timezone);
                st.fracSec = FracSec.from!"hnsecs"(fracSec.total!"hnsecs");
                assert(st == expected, format("[%s] [%s]", st, expected));
            }
        }

        auto st = testSysTimesAD[0];
        assertThrown!DateTimeException(st.fracSec = FracSec.from!"hnsecs"(-1));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.fracSec = FracSec.from!"msecs"(7)));
        //static assert(!__traits(compiles, ist.fracSec = FracSec.from!"msecs"(7)));
    }


    /++
        The total hnsecs from midnight, January 1st, 1 A.D. UTC. This is the
        internal representation of $(LREF SysTime).
     +/
    @property long stdTime() @safe const pure nothrow
    {
        return _stdTime;
    }

    unittest
    {
        assert(SysTime(0).stdTime == 0);
        assert(SysTime(1).stdTime == 1);
        assert(SysTime(-1).stdTime == -1);
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 33), hnsecs(502), UTC()).stdTime == 330000502L);
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC()).stdTime == 621355968000000000L);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.stdTime));
        //static assert(__traits(compiles, ist.stdTime));
    }


    /++
        The total hnsecs from midnight, January 1st, 1 A.D. UTC. This is the
        internal representation of $(LREF SysTime).

        Params:
            stdTime = The number of hnsecs since January 1st, 1 A.D. UTC.
     +/
    @property void stdTime(long stdTime) @safe pure nothrow
    {
        _stdTime = stdTime;
    }

    unittest
    {
        static void test(long stdTime, in SysTime expected, size_t line = __LINE__)
        {
            auto st = SysTime(0, UTC());
            st.stdTime = stdTime;
            assert(st == expected);
        }

        test(0, SysTime(Date(1, 1, 1), UTC()));
        test(1, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1), UTC()));
        test(-1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()));
        test(330_000_502L, SysTime(DateTime(1, 1, 1, 0, 0, 33), hnsecs(502), UTC()));
        test(621_355_968_000_000_000L, SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC()));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.stdTime = 27));
        //static assert(!__traits(compiles, ist.stdTime = 27));
    }


    /++
        The current time zone of this $(LREF SysTime). Its internal time is always
        kept in UTC, so there are no conversion issues between time zones due to
        DST. Functions which return all or part of the time - such as hours -
        adjust the time to this $(LREF SysTime)'s time zone before returning.
      +/
    @property immutable(TimeZone) timezone() @safe const pure nothrow
    {
        return _timezone;
    }


    /++
        The current time zone of this $(LREF SysTime). It's internal time is always
        kept in UTC, so there are no conversion issues between time zones due to
        DST. Functions which return all or part of the time - such as hours -
        adjust the time to this $(LREF SysTime)'s time zone before returning.

        Params:
            timezone = The $(LREF2 .TimeZone, TimeZone) to set this $(LREF SysTime)'s time zone to.
      +/
    @property void timezone(immutable TimeZone timezone) @safe pure nothrow
    {
        if (timezone is null)
            _timezone = LocalTime();
        else
            _timezone = timezone;
    }


    /++
        Returns whether DST is in effect for this $(LREF SysTime).
      +/
    @property bool dstInEffect() @safe const nothrow
    {
        return _timezone.dstInEffect(_stdTime);
        //This function's unit testing is done in the time zone classes.
    }


    /++
        Returns what the offset from UTC is for this $(LREF SysTime).
        It includes the DST offset in effect at that time (if any).
      +/
    @property Duration utcOffset() @safe const nothrow
    {
        return _timezone.utcOffsetAt(_stdTime);
    }


    /++
        Returns a $(LREF SysTime) with the same std time as this one, but with
        $(LREF LocalTime) as its time zone.
      +/
    SysTime toLocalTime() @safe const pure nothrow
    {
        return SysTime(_stdTime, LocalTime());
    }

    unittest
    {
        {
            auto sysTime = SysTime(DateTime(1982, 1, 4, 8, 59, 7), hnsecs(27));
            assert(sysTime == sysTime.toLocalTime());
            assert(sysTime._stdTime == sysTime.toLocalTime()._stdTime);
            assert(sysTime.toLocalTime().timezone is LocalTime());
            assert(sysTime.toLocalTime().timezone is sysTime.timezone);
            assert(sysTime.toLocalTime().timezone !is UTC());
        }

        {
            auto stz = new immutable SimpleTimeZone(dur!"minutes"(-3 * 60));
            auto sysTime = SysTime(DateTime(1982, 1, 4, 8, 59, 7), hnsecs(27), stz);
            assert(sysTime == sysTime.toLocalTime());
            assert(sysTime._stdTime == sysTime.toLocalTime()._stdTime);
            assert(sysTime.toLocalTime().timezone is LocalTime());
            assert(sysTime.toLocalTime().timezone !is UTC());
            assert(sysTime.toLocalTime().timezone !is stz);
        }
    }


    /++
        Returns a $(LREF SysTime) with the same std time as this one, but with
        $(D UTC) as its time zone.
      +/
    SysTime toUTC() @safe const pure nothrow
    {
        return SysTime(_stdTime, UTC());
    }

    unittest
    {
        auto sysTime = SysTime(DateTime(1982, 1, 4, 8, 59, 7), hnsecs(27));
        assert(sysTime == sysTime.toUTC());
        assert(sysTime._stdTime == sysTime.toUTC()._stdTime);
        assert(sysTime.toUTC().timezone is UTC());
        assert(sysTime.toUTC().timezone !is LocalTime());
        assert(sysTime.toUTC().timezone !is sysTime.timezone);
    }


    /++
        Returns a $(LREF SysTime) with the same std time as this one, but with
        given time zone as its time zone.
      +/
    SysTime toOtherTZ(immutable TimeZone tz) @safe const pure nothrow
    {
        if (tz is null)
            return SysTime(_stdTime, LocalTime());
        else
            return SysTime(_stdTime, tz);
    }

    unittest
    {
        auto stz = new immutable SimpleTimeZone(dur!"minutes"(11 * 60));
        auto sysTime = SysTime(DateTime(1982, 1, 4, 8, 59, 7), hnsecs(27));
        assert(sysTime == sysTime.toOtherTZ(stz));
        assert(sysTime._stdTime == sysTime.toOtherTZ(stz)._stdTime);
        assert(sysTime.toOtherTZ(stz).timezone is stz);
        assert(sysTime.toOtherTZ(stz).timezone !is LocalTime());
        assert(sysTime.toOtherTZ(stz).timezone !is UTC());
    }


    /++
        Returns a $(D time_t) which represents the same time as this
        $(LREF SysTime).

        Note that like all conversions in std.datetime, this is a truncating
        conversion.

        If $(D time_t) is 32 bits, rather than 64, and the result can't fit in a
        32-bit value, then the closest value that can be held in 32 bits will be
        used (so $(D time_t.max) if it goes over and $(D time_t.min) if it goes
        under).
      +/
    time_t toUnixTime() @safe const pure nothrow
    {
        return stdTimeToUnixTime(_stdTime);
    }

    unittest
    {
        assert(SysTime(DateTime(1970, 1, 1), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 0), hnsecs(1), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 0), usecs(1), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 0), msecs(1), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 1), UTC()).toUnixTime() == 1);
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), usecs(999_999), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), msecs(999), UTC()).toUnixTime() == 0);
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), UTC()).toUnixTime() == -1);
    }


    /++
        Returns a $(D timeval) which represents this $(LREF SysTime).

        Note that like all conversions in std.datetime, this is a truncating
        conversion.

        If $(D time_t) is 32 bits, rather than 64, and the result can't fit in a
        32-bit value, then the closest value that can be held in 32 bits will be
        used for $(D tv_sec). (so $(D time_t.max) if it goes over and
        $(D time_t.min) if it goes under).
      +/
    timeval toTimeVal() @safe const pure nothrow
    {
        immutable tv_sec = toUnixTime();

        immutable fracHNSecs = removeUnitsFromHNSecs!"seconds"(_stdTime - 621355968000000000L);
        immutable tv_usec = cast(int)convert!("hnsecs", "usecs")(fracHNSecs);

        return timeval(tv_sec, tv_usec);
    }

    unittest
    {
        assert(SysTime(DateTime(1970, 1, 1), UTC()).toTimeVal() == timeval(0, 0));
        assert(SysTime(DateTime(1970, 1, 1), hnsecs(9), UTC()).toTimeVal() == timeval(0, 0));
        assert(SysTime(DateTime(1970, 1, 1), hnsecs(10), UTC()).toTimeVal() == timeval(0, 1));
        assert(SysTime(DateTime(1970, 1, 1), usecs(7), UTC()).toTimeVal() == timeval(0, 7));

        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 1), UTC()).toTimeVal() == timeval(1, 0));
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 1), hnsecs(9), UTC()).toTimeVal() == timeval(1, 0));
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 1), hnsecs(10), UTC()).toTimeVal() == timeval(1, 1));
        assert(SysTime(DateTime(1970, 1, 1, 0, 0, 1), usecs(7), UTC()).toTimeVal() == timeval(1, 7));

        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()).toTimeVal() == timeval(0, 0));
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), hnsecs(9_999_990), UTC()).toTimeVal() == timeval(0, -1));

        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), usecs(999_999), UTC()).toTimeVal() == timeval(0, -1));
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), usecs(999), UTC()).toTimeVal() == timeval(0, -999_001));
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), msecs(999), UTC()).toTimeVal() == timeval(0, -1000));
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 59), UTC()).toTimeVal() == timeval(-1, 0));
        assert(SysTime(DateTime(1969, 12, 31, 23, 59, 58), usecs(17), UTC()).toTimeVal() == timeval(-1, -999_983));
    }


    /++
        Returns a $(D tm) which represents this $(LREF SysTime).
      +/
    tm toTM() @safe const nothrow
    {
        auto dateTime = cast(DateTime)this;
        tm timeInfo;

        timeInfo.tm_sec = dateTime.second;
        timeInfo.tm_min = dateTime.minute;
        timeInfo.tm_hour = dateTime.hour;
        timeInfo.tm_mday = dateTime.day;
        timeInfo.tm_mon = dateTime.month - 1;
        timeInfo.tm_year = dateTime.year - 1900;
        timeInfo.tm_wday = dateTime.dayOfWeek;
        timeInfo.tm_yday = dateTime.dayOfYear - 1;
        timeInfo.tm_isdst = _timezone.dstInEffect(_stdTime);

        version(Posix)
        {
            import std.utf : toUTFz;
            timeInfo.tm_gmtoff = cast(int)convert!("hnsecs", "seconds")(adjTime - _stdTime);
            auto zone = (timeInfo.tm_isdst ? _timezone.dstName : _timezone.stdName);
            timeInfo.tm_zone = zone.toUTFz!(char*)();
        }

        return timeInfo;
    }

    unittest
    {
        import std.conv : to;
        version(Posix)
        {
            scope(exit) clearTZEnvVar();
            setTZEnvVar("America/Los_Angeles");
        }

        {
            auto timeInfo = SysTime(DateTime(1970, 1, 1)).toTM();

            assert(timeInfo.tm_sec == 0);
            assert(timeInfo.tm_min == 0);
            assert(timeInfo.tm_hour == 0);
            assert(timeInfo.tm_mday == 1);
            assert(timeInfo.tm_mon == 0);
            assert(timeInfo.tm_year == 70);
            assert(timeInfo.tm_wday == 4);
            assert(timeInfo.tm_yday == 0);

            version(Posix)
                assert(timeInfo.tm_isdst == 0);
            else version(Windows)
                assert(timeInfo.tm_isdst == 0 || timeInfo.tm_isdst == 1);

            version(Posix)
            {
                assert(timeInfo.tm_gmtoff == -8 * 60 * 60);
                assert(to!string(timeInfo.tm_zone) == "PST");
            }
        }

        {
            auto timeInfo = SysTime(DateTime(2010, 7, 4, 12, 15, 7), hnsecs(15)).toTM();

            assert(timeInfo.tm_sec == 7);
            assert(timeInfo.tm_min == 15);
            assert(timeInfo.tm_hour == 12);
            assert(timeInfo.tm_mday == 4);
            assert(timeInfo.tm_mon == 6);
            assert(timeInfo.tm_year == 110);
            assert(timeInfo.tm_wday == 0);
            assert(timeInfo.tm_yday == 184);

            version(Posix)
                assert(timeInfo.tm_isdst == 1);
            else version(Windows)
                assert(timeInfo.tm_isdst == 0 || timeInfo.tm_isdst == 1);

            version(Posix)
            {
                assert(timeInfo.tm_gmtoff == -7 * 60 * 60);
                assert(to!string(timeInfo.tm_zone) == "PDT");
            }
        }
    }


    /++
        Adds the given number of years or months to this $(LREF SysTime). A
        negative number will subtract.

        Note that if day overflow is allowed, and the date with the adjusted
        year/month overflows the number of days in the new month, then the month
        will be incremented by one, and the day set to the number of days
        overflowed. (e.g. if the day were 31 and the new month were June, then
        the month would be incremented to July, and the new day would be 1). If
        day overflow is not allowed, then the day will be set to the last valid
        day in the month (e.g. June 31st would become June 30th).

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF SysTime).
            allowOverflow = Whether the days should be allowed to overflow,
                            causing the month to increment.
      +/
    ref SysTime add(string units)(long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe nothrow
        if (units == "years" ||
           units == "months")
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.add!units(value, allowOverflow);
        days = date.dayOfGregorianCal - 1;

        if (days < 0)
        {
            hnsecs -= convert!("hours", "hnsecs")(24);
            ++days;
        }

        immutable newDaysHNSecs = convert!("days", "hnsecs")(days);

        adjTime = newDaysHNSecs + hnsecs;

        return this;
    }

    unittest
    {
        auto st1 = SysTime(DateTime(2010, 1, 1, 12, 30, 33));
        st1.add!"months"(11);
        assert(st1 == SysTime(DateTime(2010, 12, 1, 12, 30, 33)));

        auto st2 = SysTime(DateTime(2010, 1, 1, 12, 30, 33));
        st2.add!"months"(-11);
        assert(st2 == SysTime(DateTime(2009, 2, 1, 12, 30, 33)));

        auto st3 = SysTime(DateTime(2000, 2, 29, 12, 30, 33));
        st3.add!"years"(1);
        assert(st3 == SysTime(DateTime(2001, 3, 1, 12, 30, 33)));

        auto st4 = SysTime(DateTime(2000, 2, 29, 12, 30, 33));
        st4.add!"years"(1, AllowDayOverflow.no);
        assert(st4 == SysTime(DateTime(2001, 2, 28, 12, 30, 33)));
    }

    //Test add!"years"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"years"(7);
            assert(sysTime == SysTime(Date(2006, 7, 6)));
            sysTime.add!"years"(-9);
            assert(sysTime == SysTime(Date(1997, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(Date(2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(Date(1999, 3, 1)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 7, 3), msecs(234));
            sysTime.add!"years"(7);
            assert(sysTime == SysTime(DateTime(2006, 7, 6, 12, 7, 3), msecs(234)));
            sysTime.add!"years"(-9);
            assert(sysTime == SysTime(DateTime(1997, 7, 6, 12, 7, 3), msecs(234)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 2, 28, 0, 7, 2), usecs(1207));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(2000, 2, 28, 0, 7, 2), usecs(1207)));
        }

        {
            auto sysTime = SysTime(DateTime(2000, 2, 29, 0, 7, 2), usecs(1207));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(1999, 3, 1, 0, 7, 2), usecs(1207)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"years"(-7);
            assert(sysTime == SysTime(Date(-2006, 7, 6)));
            sysTime.add!"years"(9);
            assert(sysTime == SysTime(Date(-1997, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(Date(-2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(Date(-1999, 3, 1)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 7, 3), msecs(234));
            sysTime.add!"years"(-7);
            assert(sysTime == SysTime(DateTime(-2006, 7, 6, 12, 7, 3), msecs(234)));
            sysTime.add!"years"(9);
            assert(sysTime == SysTime(DateTime(-1997, 7, 6, 12, 7, 3), msecs(234)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 2, 28, 3, 3, 3), hnsecs(3));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(-2000, 2, 28, 3, 3, 3), hnsecs(3)));
        }

        {
            auto sysTime = SysTime(DateTime(-2000, 2, 29, 3, 3, 3), hnsecs(3));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(-1999, 3, 1, 3, 3, 3), hnsecs(3)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(4, 7, 6));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(Date(-1, 7, 6)));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(Date(4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 7, 6));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(Date(1, 7, 6)));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(4, 7, 6));
            sysTime.add!"years"(-8);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
            sysTime.add!"years"(8);
            assert(sysTime == SysTime(Date(4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 7, 6));
            sysTime.add!"years"(8);
            assert(sysTime == SysTime(Date(4, 7, 6)));
            sysTime.add!"years"(-8);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 2, 29));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(Date(1, 3, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 2, 29));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(Date(-1, 3, 1)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 1, 1, 0, 0, 0));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"years"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"years"(-1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(DateTime(-1, 7, 6, 14, 7, 1), usecs(54329)));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329)));
        }

        {
            auto sysTime = SysTime(DateTime(-4, 7, 6, 14, 7, 1), usecs(54329));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(DateTime(1, 7, 6, 14, 7, 1), usecs(54329)));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(DateTime(-4, 7, 6, 14, 7, 1), usecs(54329)));
        }

        {
            auto sysTime = SysTime(DateTime(-4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(DateTime(1, 3, 1, 5, 5, 5), msecs(555)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(DateTime(-1, 3, 1, 5, 5, 5), msecs(555)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(-5).add!"years"(7);
            assert(sysTime == SysTime(DateTime(6, 3, 1, 5, 5, 5), msecs(555)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.add!"years"(4)));
        //static assert(!__traits(compiles, ist.add!"years"(4)));
    }

    //Test add!"years"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"years"(7, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2006, 7, 6)));
            sysTime.add!"years"(-9, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 7, 3), msecs(234));
            sysTime.add!"years"(7, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(2006, 7, 6, 12, 7, 3), msecs(234)));
            sysTime.add!"years"(-9, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1997, 7, 6, 12, 7, 3), msecs(234)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 2, 28, 0, 7, 2), usecs(1207));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(2000, 2, 28, 0, 7, 2), usecs(1207)));
        }

        {
            auto sysTime = SysTime(DateTime(2000, 2, 29, 0, 7, 2), usecs(1207));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 2, 28, 0, 7, 2), usecs(1207)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"years"(-7, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2006, 7, 6)));
            sysTime.add!"years"(9, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 7, 3), msecs(234));
            sysTime.add!"years"(-7, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2006, 7, 6, 12, 7, 3), msecs(234)));
            sysTime.add!"years"(9, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1997, 7, 6, 12, 7, 3), msecs(234)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 2, 28, 3, 3, 3), hnsecs(3));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2000, 2, 28, 3, 3, 3), hnsecs(3)));
        }

        {
            auto sysTime = SysTime(DateTime(-2000, 2, 29, 3, 3, 3), hnsecs(3));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 2, 28, 3, 3, 3), hnsecs(3)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(4, 7, 6));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1, 7, 6)));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 7, 6));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1, 7, 6)));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(4, 7, 6));
            sysTime.add!"years"(-8, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
            sysTime.add!"years"(8, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 7, 6));
            sysTime.add!"years"(8, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 7, 6)));
            sysTime.add!"years"(-8, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-4, 2, 29));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(4, 2, 29));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1, 2, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 1, 1, 0, 0, 0));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"years"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"years"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329));
            sysTime.add!"years"(-5);
            assert(sysTime == SysTime(DateTime(-1, 7, 6, 14, 7, 1), usecs(54329)));
            sysTime.add!"years"(5);
            assert(sysTime == SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1, 7, 6, 14, 7, 1), usecs(54329)));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(4, 7, 6, 14, 7, 1), usecs(54329)));
        }

        {
            auto sysTime = SysTime(DateTime(-4, 7, 6, 14, 7, 1), usecs(54329));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 7, 6, 14, 7, 1), usecs(54329)));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-4, 7, 6, 14, 7, 1), usecs(54329)));
        }

        {
            auto sysTime = SysTime(DateTime(-4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 2, 28, 5, 5, 5), msecs(555)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(-5, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1, 2, 28, 5, 5, 5), msecs(555)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 2, 29, 5, 5, 5), msecs(555));
            sysTime.add!"years"(-5, AllowDayOverflow.no).add!"years"(7, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(6, 2, 28, 5, 5, 5), msecs(555)));
        }
    }

    //Test add!"months"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(3);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.add!"months"(-4);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(6);
            assert(sysTime == SysTime(Date(2000, 1, 6)));
            sysTime.add!"months"(-6);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(27);
            assert(sysTime == SysTime(Date(2001, 10, 6)));
            sysTime.add!"months"(-28);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(1999, 7, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(Date(1999, 5, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.add!"months"(12);
            assert(sysTime == SysTime(Date(2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.add!"months"(12);
            assert(sysTime == SysTime(Date(2001, 3, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 31));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(1999, 8, 31)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(1999, 10, 1)));
        }

        {
            auto sysTime = SysTime(Date(1998, 8, 31));
            sysTime.add!"months"(13);
            assert(sysTime == SysTime(Date(1999, 10, 1)));
            sysTime.add!"months"(-13);
            assert(sysTime == SysTime(Date(1998, 9, 1)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.add!"months"(13);
            assert(sysTime == SysTime(Date(1999, 1, 31)));
            sysTime.add!"months"(-13);
            assert(sysTime == SysTime(Date(1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(1999, 3, 3)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(1998, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(1998, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(2000, 3, 2)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(1999, 1, 2)));
        }

        {
            auto sysTime = SysTime(Date(1999, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(2001, 3, 3)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(2000, 1, 3)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.add!"months"(3);
            assert(sysTime == SysTime(DateTime(1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.add!"months"(-4);
            assert(sysTime == SysTime(DateTime(1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(1998, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(DateTime(2000, 3, 2, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(DateTime(1999, 1, 2, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(DateTime(2001, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(DateTime(2000, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(3);
            assert(sysTime == SysTime(Date(-1999, 10, 6)));
            sysTime.add!"months"(-4);
            assert(sysTime == SysTime(Date(-1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(6);
            assert(sysTime == SysTime(Date(-1998, 1, 6)));
            sysTime.add!"months"(-6);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(-27);
            assert(sysTime == SysTime(Date(-2001, 4, 6)));
            sysTime.add!"months"(28);
            assert(sysTime == SysTime(Date(-1999, 8, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 7, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(Date(-1999, 5, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.add!"months"(-12);
            assert(sysTime == SysTime(Date(-2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.add!"months"(-12);
            assert(sysTime == SysTime(Date(-2001, 3, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 31));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 8, 31)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 10, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1998, 8, 31));
            sysTime.add!"months"(13);
            assert(sysTime == SysTime(Date(-1997, 10, 1)));
            sysTime.add!"months"(-13);
            assert(sysTime == SysTime(Date(-1998, 9, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.add!"months"(13);
            assert(sysTime == SysTime(Date(-1995, 1, 31)));
            sysTime.add!"months"(-13);
            assert(sysTime == SysTime(Date(-1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(-1995, 3, 3)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(-1996, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(-2002, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(-2000, 3, 2)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(-2001, 1, 2)));
        }

        {
            auto sysTime = SysTime(Date(-2001, 12, 31));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(Date(-1999, 3, 3)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(Date(-2000, 1, 3)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.add!"months"(3);
            assert(sysTime == SysTime(DateTime(-1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.add!"months"(-4);
            assert(sysTime == SysTime(DateTime(-1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(-2002, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(DateTime(-2000, 3, 2, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(DateTime(-2001, 1, 2, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(-2001, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14);
            assert(sysTime == SysTime(DateTime(-1999, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14);
            assert(sysTime == SysTime(DateTime(-2000, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(1, 1, 1));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(Date(0, 12, 1)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(Date(1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 1, 1));
            sysTime.add!"months"(-48);
            assert(sysTime == SysTime(Date(0, 1, 1)));
            sysTime.add!"months"(48);
            assert(sysTime == SysTime(Date(4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.add!"months"(-49);
            assert(sysTime == SysTime(Date(0, 3, 2)));
            sysTime.add!"months"(49);
            assert(sysTime == SysTime(Date(4, 4, 2)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.add!"months"(-85);
            assert(sysTime == SysTime(Date(-3, 3, 3)));
            sysTime.add!"months"(85);
            assert(sysTime == SysTime(Date(4, 4, 3)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 0, 0, 0));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17));
            sysTime.add!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 7, 9), hnsecs(17)));
            sysTime.add!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(-85);
            assert(sysTime == SysTime(DateTime(-3, 3, 3, 12, 11, 10), msecs(9)));
            sysTime.add!"months"(85);
            assert(sysTime == SysTime(DateTime(4, 4, 3, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(85);
            assert(sysTime == SysTime(DateTime(4, 5, 1, 12, 11, 10), msecs(9)));
            sysTime.add!"months"(-85);
            assert(sysTime == SysTime(DateTime(-3, 4, 1, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(85).add!"months"(-83);
            assert(sysTime == SysTime(DateTime(-3, 6, 1, 12, 11, 10), msecs(9)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.add!"months"(4)));
        //static assert(!__traits(compiles, ist.add!"months"(4)));
    }

    //Test add!"months"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.add!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2000, 1, 6)));
            sysTime.add!"months"(-6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.add!"months"(27, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2001, 10, 6)));
            sysTime.add!"months"(-28, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 4, 30)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.add!"months"(12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.add!"months"(12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2001, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 31));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 8, 31)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 9, 30)));
        }

        {
            auto sysTime = SysTime(Date(1998, 8, 31));
            sysTime.add!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 9, 30)));
            sysTime.add!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 8, 30)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.add!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 1, 31)));
            sysTime.add!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(1998, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2000, 2, 29)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 12, 29)));
        }

        {
            auto sysTime = SysTime(Date(1999, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2001, 2, 28)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 12, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.add!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.add!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(1998, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(2000, 2, 29, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1998, 12, 29, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(2001, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 10, 6)));
            sysTime.add!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1998, 1, 6)));
            sysTime.add!"months"(-6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.add!"months"(-27, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2001, 4, 6)));
            sysTime.add!"months"(28, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 8, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 4, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.add!"months"(-12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2000, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.add!"months"(-12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2001, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 31));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 8, 31)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 9, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1998, 8, 31));
            sysTime.add!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 9, 30)));
            sysTime.add!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1998, 8, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.add!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1995, 1, 31)));
            sysTime.add!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1995, 2, 28)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2002, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2000, 2, 29)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2002, 12, 29)));
        }

        {
            auto sysTime = SysTime(Date(-2001, 12, 31));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 2, 28)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2001, 12, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.add!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.add!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(-2002, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2000, 2, 29, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2002, 12, 29, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(-2001, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.add!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.add!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2001, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(1, 1, 1));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(0, 12, 1)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 1, 1));
            sysTime.add!"months"(-48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(0, 1, 1)));
            sysTime.add!"months"(48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.add!"months"(-49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(0, 2, 29)));
            sysTime.add!"months"(49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 3, 29)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.add!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-3, 2, 28)));
            sysTime.add!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 3, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 0, 0, 0));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17));
            sysTime.add!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 7, 9), hnsecs(17)));
            sysTime.add!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 2, 28, 12, 11, 10), msecs(9)));
            sysTime.add!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(4, 3, 28, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(4, 4, 30, 12, 11, 10), msecs(9)));
            sysTime.add!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 3, 30, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.add!"months"(85, AllowDayOverflow.no).add!"months"(-83, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 5, 30, 12, 11, 10), msecs(9)));
        }
    }


    /++
        Adds the given number of years or months to this $(LREF SysTime). A
        negative number will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. Rolling a $(LREF SysTime) 12 months
        gets the exact same $(LREF SysTime). However, the days can still be affected
        due to the differing number of days in each month.

        Because there are no units larger than years, there is no difference
        between adding and rolling years.

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF SysTime).
            allowOverflow = Whether the days should be allowed to overflow,
                            causing the month to increment.
      +/
    ref SysTime roll(string units)(long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe nothrow
        if (units == "years")
    {
        return add!"years"(value, allowOverflow);
    }

    ///
    unittest
    {
        auto st1 = SysTime(DateTime(2010, 1, 1, 12, 33, 33));
        st1.roll!"months"(1);
        assert(st1 == SysTime(DateTime(2010, 2, 1, 12, 33, 33)));

        auto st2 = SysTime(DateTime(2010, 1, 1, 12, 33, 33));
        st2.roll!"months"(-1);
        assert(st2 == SysTime(DateTime(2010, 12, 1, 12, 33, 33)));

        auto st3 = SysTime(DateTime(1999, 1, 29, 12, 33, 33));
        st3.roll!"months"(1);
        assert(st3 == SysTime(DateTime(1999, 3, 1, 12, 33, 33)));

        auto st4 = SysTime(DateTime(1999, 1, 29, 12, 33, 33));
        st4.roll!"months"(1, AllowDayOverflow.no);
        assert(st4 == SysTime(DateTime(1999, 2, 28, 12, 33, 33)));

        auto st5 = SysTime(DateTime(2000, 2, 29, 12, 30, 33));
        st5.roll!"years"(1);
        assert(st5 == SysTime(DateTime(2001, 3, 1, 12, 30, 33)));

        auto st6 = SysTime(DateTime(2000, 2, 29, 12, 30, 33));
        st6.roll!"years"(1, AllowDayOverflow.no);
        assert(st6 == SysTime(DateTime(2001, 2, 28, 12, 30, 33)));
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.roll!"years"(4)));
        static assert(!__traits(compiles, cst.roll!"years"(4)));
        //static assert(!__traits(compiles, ist.roll!"years"(4)));
    }


    //Shares documentation with "years" overload.
    ref SysTime roll(string units)(long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe nothrow
        if (units == "months")
    {
        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto date = Date(cast(int)days);
        date.roll!"months"(value, allowOverflow);
        days = date.dayOfGregorianCal - 1;

        if (days < 0)
        {
            hnsecs -= convert!("hours", "hnsecs")(24);
            ++days;
        }

        immutable newDaysHNSecs = convert!("days", "hnsecs")(days);
        adjTime = newDaysHNSecs + hnsecs;
        return this;
    }

    //Test roll!"months"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(3);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.roll!"months"(-4);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(6);
            assert(sysTime == SysTime(Date(1999, 1, 6)));
            sysTime.roll!"months"(-6);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(27);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.roll!"months"(-28);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(1999, 7, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(Date(1999, 5, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.roll!"months"(12);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.roll!"months"(12);
            assert(sysTime == SysTime(Date(2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 31));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(1999, 8, 31)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(1999, 10, 1)));
        }

        {
            auto sysTime = SysTime(Date(1998, 8, 31));
            sysTime.roll!"months"(13);
            assert(sysTime == SysTime(Date(1998, 10, 1)));
            sysTime.roll!"months"(-13);
            assert(sysTime == SysTime(Date(1998, 9, 1)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.roll!"months"(13);
            assert(sysTime == SysTime(Date(1997, 1, 31)));
            sysTime.roll!"months"(-13);
            assert(sysTime == SysTime(Date(1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(1997, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(1997, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(1998, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(1998, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(1998, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(1999, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(1999, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(1999, 1, 3)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.roll!"months"(3);
            assert(sysTime == SysTime(DateTime(1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.roll!"months"(-4);
            assert(sysTime == SysTime(DateTime(1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(1998, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(DateTime(1998, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(DateTime(1998, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(DateTime(1999, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(DateTime(1999, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(3);
            assert(sysTime == SysTime(Date(-1999, 10, 6)));
            sysTime.roll!"months"(-4);
            assert(sysTime == SysTime(Date(-1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(6);
            assert(sysTime == SysTime(Date(-1999, 1, 6)));
            sysTime.roll!"months"(-6);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(-27);
            assert(sysTime == SysTime(Date(-1999, 4, 6)));
            sysTime.roll!"months"(28);
            assert(sysTime == SysTime(Date(-1999, 8, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 7, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(Date(-1999, 5, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.roll!"months"(-12);
            assert(sysTime == SysTime(Date(-1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.roll!"months"(-12);
            assert(sysTime == SysTime(Date(-2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 31));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 8, 31)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(-1999, 10, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1998, 8, 31));
            sysTime.roll!"months"(13);
            assert(sysTime == SysTime(Date(-1998, 10, 1)));
            sysTime.roll!"months"(-13);
            assert(sysTime == SysTime(Date(-1998, 9, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.roll!"months"(13);
            assert(sysTime == SysTime(Date(-1997, 1, 31)));
            sysTime.roll!"months"(-13);
            assert(sysTime == SysTime(Date(-1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(-1997, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(-1997, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(-2002, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(-2002, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(-2002, 1, 3)));
        }

        {
            auto sysTime = SysTime(Date(-2001, 12, 31));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(Date(-2001, 3, 3)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(Date(-2001, 1, 3)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 0, 0, 0)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 0, 0, 0));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 2, 7), hnsecs(5007));
            sysTime.roll!"months"(3);
            assert(sysTime == SysTime(DateTime(-1999, 10, 6, 12, 2, 7), hnsecs(5007)));
            sysTime.roll!"months"(-4);
            assert(sysTime == SysTime(DateTime(-1999, 6, 6, 12, 2, 7), hnsecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(-2002, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(DateTime(-2002, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(DateTime(-2002, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(-2001, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14);
            assert(sysTime == SysTime(DateTime(-2001, 3, 3, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14);
            assert(sysTime == SysTime(DateTime(-2001, 1, 3, 7, 7, 7), hnsecs(422202)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(1, 1, 1));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(Date(1, 12, 1)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 1, 1));
            sysTime.roll!"months"(-48);
            assert(sysTime == SysTime(Date(4, 1, 1)));
            sysTime.roll!"months"(48);
            assert(sysTime == SysTime(Date(4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.roll!"months"(-49);
            assert(sysTime == SysTime(Date(4, 3, 2)));
            sysTime.roll!"months"(49);
            assert(sysTime == SysTime(Date(4, 4, 2)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.roll!"months"(-85);
            assert(sysTime == SysTime(Date(4, 3, 2)));
            sysTime.roll!"months"(85);
            assert(sysTime == SysTime(Date(4, 4, 2)));
        }

        {
            auto sysTime = SysTime(Date(-1, 1, 1));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(Date(-1, 12, 1)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(Date(-1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(-4, 1, 1));
            sysTime.roll!"months"(-48);
            assert(sysTime == SysTime(Date(-4, 1, 1)));
            sysTime.roll!"months"(48);
            assert(sysTime == SysTime(Date(-4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(-4, 3, 31));
            sysTime.roll!"months"(-49);
            assert(sysTime == SysTime(Date(-4, 3, 2)));
            sysTime.roll!"months"(49);
            assert(sysTime == SysTime(Date(-4, 4, 2)));
        }

        {
            auto sysTime = SysTime(Date(-4, 3, 31));
            sysTime.roll!"months"(-85);
            assert(sysTime == SysTime(Date(-4, 3, 2)));
            sysTime.roll!"months"(85);
            assert(sysTime == SysTime(Date(-4, 4, 2)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17));
            sysTime.roll!"months"(-1);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 0, 7, 9), hnsecs(17)));
            sysTime.roll!"months"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(-85);
            assert(sysTime == SysTime(DateTime(4, 3, 2, 12, 11, 10), msecs(9)));
            sysTime.roll!"months"(85);
            assert(sysTime == SysTime(DateTime(4, 4, 2, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(85);
            assert(sysTime == SysTime(DateTime(-3, 5, 1, 12, 11, 10), msecs(9)));
            sysTime.roll!"months"(-85);
            assert(sysTime == SysTime(DateTime(-3, 4, 1, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(85).roll!"months"(-83);
            assert(sysTime == SysTime(DateTime(-3, 6, 1, 12, 11, 10), msecs(9)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"months"(4)));
        //static assert(!__traits(compiles, ist.roll!"months"(4)));
    }

    //Test roll!"months"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.roll!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 1, 6)));
            sysTime.roll!"months"(-6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"months"(27, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 10, 6)));
            sysTime.roll!"months"(-28, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(1999, 5, 31));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 4, 30)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.roll!"months"(12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 29));
            sysTime.roll!"months"(12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 31));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 8, 31)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 9, 30)));
        }

        {
            auto sysTime = SysTime(Date(1998, 8, 31));
            sysTime.roll!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 9, 30)));
            sysTime.roll!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 8, 30)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.roll!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 1, 31)));
            sysTime.roll!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(1997, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1997, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(1998, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1998, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(1999, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1999, 12, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.roll!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.roll!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(1998, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1998, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1998, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1999, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 10, 6)));
            sysTime.roll!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 6, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 1, 6)));
            sysTime.roll!"months"(-6, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"months"(-27, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 4, 6)));
            sysTime.roll!"months"(28, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 8, 6)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 5, 31));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 4, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.roll!"months"(-12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 29));
            sysTime.roll!"months"(-12, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 31));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 8, 31)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1999, 9, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1998, 8, 31));
            sysTime.roll!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1998, 9, 30)));
            sysTime.roll!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1998, 8, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.roll!"months"(13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 1, 31)));
            sysTime.roll!"months"(-13, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 12, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1997, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1997, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2002, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2002, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2002, 12, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2001, 12, 31));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2001, 2, 28)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-2001, 12, 28)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 12, 2, 7), usecs(5007));
            sysTime.roll!"months"(3, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 10, 6, 12, 2, 7), usecs(5007)));
            sysTime.roll!"months"(-4, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-1999, 6, 6, 12, 2, 7), usecs(5007)));
        }

        {
            auto sysTime = SysTime(DateTime(-2002, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2002, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2002, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        {
            auto sysTime = SysTime(DateTime(-2001, 12, 31, 7, 7, 7), hnsecs(422202));
            sysTime.roll!"months"(14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2001, 2, 28, 7, 7, 7), hnsecs(422202)));
            sysTime.roll!"months"(-14, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-2001, 12, 28, 7, 7, 7), hnsecs(422202)));
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(1, 1, 1));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1, 12, 1)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 1, 1));
            sysTime.roll!"months"(-48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 1, 1)));
            sysTime.roll!"months"(48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.roll!"months"(-49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 2, 29)));
            sysTime.roll!"months"(49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 3, 29)));
        }

        {
            auto sysTime = SysTime(Date(4, 3, 31));
            sysTime.roll!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 2, 29)));
            sysTime.roll!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(4, 3, 29)));
        }

        {
            auto sysTime = SysTime(Date(-1, 1, 1));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1, 12, 1)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-1, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(-4, 1, 1));
            sysTime.roll!"months"(-48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 1, 1)));
            sysTime.roll!"months"(48, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(-4, 3, 31));
            sysTime.roll!"months"(-49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 2, 29)));
            sysTime.roll!"months"(49, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 3, 29)));
        }

        {
            auto sysTime = SysTime(Date(-4, 3, 31));
            sysTime.roll!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 2, 29)));
            sysTime.roll!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(Date(-4, 3, 29)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 0, 0, 0)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 0, 0, 0));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 0, 0, 0)));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17));
            sysTime.roll!"months"(-1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 12, 1, 0, 7, 9), hnsecs(17)));
            sysTime.roll!"months"(1, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 7, 9), hnsecs(17)));
        }

        {
            auto sysTime = SysTime(DateTime(4, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(4, 2, 29, 12, 11, 10), msecs(9)));
            sysTime.roll!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(4, 3, 29, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 4, 30, 12, 11, 10), msecs(9)));
            sysTime.roll!"months"(-85, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 3, 30, 12, 11, 10), msecs(9)));
        }

        {
            auto sysTime = SysTime(DateTime(-3, 3, 31, 12, 11, 10), msecs(9));
            sysTime.roll!"months"(85, AllowDayOverflow.no).roll!"months"(-83, AllowDayOverflow.no);
            assert(sysTime == SysTime(DateTime(-3, 5, 30, 12, 11, 10), msecs(9)));
        }
    }


    /++
        Adds the given number of units to this $(LREF SysTime). A negative number
        will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. For instance, rolling a $(LREF SysTime) one
        year's worth of days gets the exact same $(LREF SysTime).

        Accepted units are $(D "days"), $(D "minutes"), $(D "hours"),
        $(D "minutes"), $(D "seconds"), $(D "msecs"), $(D "usecs"), and
        $(D "hnsecs").

        Note that when rolling msecs, usecs or hnsecs, they all add up to a
        second. So, for example, rolling 1000 msecs is exactly the same as
        rolling 100,000 usecs.

        Params:
            units = The units to add.
            value = The number of $(D_PARAM units) to add to this $(LREF SysTime).
      +/
    ref SysTime roll(string units)(long value) @safe nothrow
        if (units == "days")
    {
        auto hnsecs = adjTime;
        auto gdays = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --gdays;
        }

        auto date = Date(cast(int)gdays);
        date.roll!"days"(value);
        gdays = date.dayOfGregorianCal - 1;

        if (gdays < 0)
        {
            hnsecs -= convert!("hours", "hnsecs")(24);
            ++gdays;
        }

        immutable newDaysHNSecs = convert!("days", "hnsecs")(gdays);
        adjTime = newDaysHNSecs + hnsecs;
        return  this;
    }

    ///
    unittest
    {
        auto st1 = SysTime(DateTime(2010, 1, 1, 11, 23, 12));
        st1.roll!"days"(1);
        assert(st1 == SysTime(DateTime(2010, 1, 2, 11, 23, 12)));
        st1.roll!"days"(365);
        assert(st1 == SysTime(DateTime(2010, 1, 26, 11, 23, 12)));
        st1.roll!"days"(-32);
        assert(st1 == SysTime(DateTime(2010, 1, 25, 11, 23, 12)));

        auto st2 = SysTime(DateTime(2010, 7, 4, 12, 0, 0));
        st2.roll!"hours"(1);
        assert(st2 == SysTime(DateTime(2010, 7, 4, 13, 0, 0)));

        auto st3 = SysTime(DateTime(2010, 2, 12, 12, 0, 0));
        st3.roll!"hours"(-1);
        assert(st3 == SysTime(DateTime(2010, 2, 12, 11, 0, 0)));

        auto st4 = SysTime(DateTime(2009, 12, 31, 0, 0, 0));
        st4.roll!"minutes"(1);
        assert(st4 == SysTime(DateTime(2009, 12, 31, 0, 1, 0)));

        auto st5 = SysTime(DateTime(2010, 1, 1, 0, 0, 0));
        st5.roll!"minutes"(-1);
        assert(st5 == SysTime(DateTime(2010, 1, 1, 0, 59, 0)));

        auto st6 = SysTime(DateTime(2009, 12, 31, 0, 0, 0));
        st6.roll!"seconds"(1);
        assert(st6 == SysTime(DateTime(2009, 12, 31, 0, 0, 1)));

        auto st7 = SysTime(DateTime(2010, 1, 1, 0, 0, 0));
        st7.roll!"seconds"(-1);
        assert(st7 == SysTime(DateTime(2010, 1, 1, 0, 0, 59)));

        auto dt = DateTime(2010, 1, 1, 0, 0, 0);
        auto st8 = SysTime(dt);
        st8.roll!"msecs"(1);
        assert(st8 == SysTime(dt, msecs(1)));

        auto st9 = SysTime(dt);
        st9.roll!"msecs"(-1);
        assert(st9 == SysTime(dt, msecs(999)));

        auto st10 = SysTime(dt);
        st10.roll!"hnsecs"(1);
        assert(st10 == SysTime(dt, hnsecs(1)));

        auto st11 = SysTime(dt);
        st11.roll!"hnsecs"(-1);
        assert(st11 == SysTime(dt, hnsecs(9_999_999)));
    }

    unittest
    {
        //Test A.D.
        {
            auto sysTime = SysTime(Date(1999, 2, 28));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(1999, 2, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(2000, 2, 28));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(2000, 2, 29)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(2000, 2, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(1999, 6, 30));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(1999, 6, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 31));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(1999, 7, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(1999, 7, 31)));
        }

        {
            auto sysTime = SysTime(Date(1999, 1, 1));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(1999, 1, 31)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(1999, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"days"(9);
            assert(sysTime == SysTime(Date(1999, 7, 15)));
            sysTime.roll!"days"(-11);
            assert(sysTime == SysTime(Date(1999, 7, 4)));
            sysTime.roll!"days"(30);
            assert(sysTime == SysTime(Date(1999, 7, 3)));
            sysTime.roll!"days"(-3);
            assert(sysTime == SysTime(Date(1999, 7, 31)));
        }

        {
            auto sysTime = SysTime(Date(1999, 7, 6));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(Date(1999, 7, 30)));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
            sysTime.roll!"days"(366);
            assert(sysTime == SysTime(Date(1999, 7, 31)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(Date(1999, 7, 17)));
            sysTime.roll!"days"(-1096);
            assert(sysTime == SysTime(Date(1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(Date(1999, 2, 6));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(Date(1999, 2, 7)));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(Date(1999, 2, 6)));
            sysTime.roll!"days"(366);
            assert(sysTime == SysTime(Date(1999, 2, 8)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(Date(1999, 2, 10)));
            sysTime.roll!"days"(-1096);
            assert(sysTime == SysTime(Date(1999, 2, 6)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 2, 28, 7, 9, 2), usecs(234578));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(1999, 2, 1, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(1999, 2, 28, 7, 9, 2), usecs(234578)));
        }

        {
            auto sysTime = SysTime(DateTime(1999, 7, 6, 7, 9, 2), usecs(234578));
            sysTime.roll!"days"(9);
            assert(sysTime == SysTime(DateTime(1999, 7, 15, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-11);
            assert(sysTime == SysTime(DateTime(1999, 7, 4, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(30);
            assert(sysTime == SysTime(DateTime(1999, 7, 3, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-3);
            assert(sysTime == SysTime(DateTime(1999, 7, 31, 7, 9, 2), usecs(234578)));
        }

        //Test B.C.
        {
            auto sysTime = SysTime(Date(-1999, 2, 28));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-1999, 2, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(-1999, 2, 28)));
        }

        {
            auto sysTime = SysTime(Date(-2000, 2, 28));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-2000, 2, 29)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-2000, 2, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(-2000, 2, 29)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 6, 30));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-1999, 6, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(-1999, 6, 30)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 31));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-1999, 7, 1)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(-1999, 7, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 1, 1));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(Date(-1999, 1, 31)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(Date(-1999, 1, 1)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"days"(9);
            assert(sysTime == SysTime(Date(-1999, 7, 15)));
            sysTime.roll!"days"(-11);
            assert(sysTime == SysTime(Date(-1999, 7, 4)));
            sysTime.roll!"days"(30);
            assert(sysTime == SysTime(Date(-1999, 7, 3)));
            sysTime.roll!"days"(-3);
            assert(sysTime == SysTime(Date(-1999, 7, 31)));
        }

        {
            auto sysTime = SysTime(Date(-1999, 7, 6));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(Date(-1999, 7, 30)));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
            sysTime.roll!"days"(366);
            assert(sysTime == SysTime(Date(-1999, 7, 31)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(Date(-1999, 7, 17)));
            sysTime.roll!"days"(-1096);
            assert(sysTime == SysTime(Date(-1999, 7, 6)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 2, 28, 7, 9, 2), usecs(234578));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(-1999, 2, 1, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(-1999, 2, 28, 7, 9, 2), usecs(234578)));
        }

        {
            auto sysTime = SysTime(DateTime(-1999, 7, 6, 7, 9, 2), usecs(234578));
            sysTime.roll!"days"(9);
            assert(sysTime == SysTime(DateTime(-1999, 7, 15, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-11);
            assert(sysTime == SysTime(DateTime(-1999, 7, 4, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(30);
            assert(sysTime == SysTime(DateTime(-1999, 7, 3, 7, 9, 2), usecs(234578)));
            sysTime.roll!"days"(-3);
        }

        //Test Both
        {
            auto sysTime = SysTime(Date(1, 7, 6));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(Date(1, 7, 13)));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(Date(1, 7, 6)));
            sysTime.roll!"days"(-731);
            assert(sysTime == SysTime(Date(1, 7, 19)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(Date(1, 7, 5)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 31, 0, 0, 0)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 31, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 0, 0, 0));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 0, 0, 0)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"days"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"days"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 7, 6, 13, 13, 9), msecs(22));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(DateTime(1, 7, 13, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(DateTime(1, 7, 6, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(-731);
            assert(sysTime == SysTime(DateTime(1, 7, 19, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(DateTime(1, 7, 5, 13, 13, 9), msecs(22)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 7, 6, 13, 13, 9), msecs(22));
            sysTime.roll!"days"(-365);
            assert(sysTime == SysTime(DateTime(0, 7, 13, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(365);
            assert(sysTime == SysTime(DateTime(0, 7, 6, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(-731);
            assert(sysTime == SysTime(DateTime(0, 7, 19, 13, 13, 9), msecs(22)));
            sysTime.roll!"days"(730);
            assert(sysTime == SysTime(DateTime(0, 7, 5, 13, 13, 9), msecs(22)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 7, 6, 13, 13, 9), msecs(22));
            sysTime.roll!"days"(-365).roll!"days"(362).roll!"days"(-12).roll!"days"(730);
            assert(sysTime == SysTime(DateTime(0, 7, 8, 13, 13, 9), msecs(22)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"days"(4)));
        //static assert(!__traits(compiles, ist.roll!"days"(4)));
    }


    //Shares documentation with "days" version.
    ref SysTime roll(string units)(long value) @safe nothrow
        if (units == "hours" ||
           units == "minutes" ||
           units == "seconds")
    {
        scope(failure) assert(0, "Either DateTime's constructor or TimeOfDay's constructor threw.");

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable second = splitUnitsFromHNSecs!"seconds"(hnsecs);

        auto dateTime = DateTime(Date(cast(int)days), TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second));
        dateTime.roll!units(value);
        --days;

        hnsecs += convert!("hours", "hnsecs")(dateTime.hour);
        hnsecs += convert!("minutes", "hnsecs")(dateTime.minute);
        hnsecs += convert!("seconds", "hnsecs")(dateTime.second);

        if (days < 0)
        {
            hnsecs -= convert!("hours", "hnsecs")(24);
            ++days;
        }

        immutable newDaysHNSecs = convert!("days", "hnsecs")(days);
        adjTime = newDaysHNSecs + hnsecs;
        return this;
    }

    //Test roll!"hours"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, int hours, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"hours"(hours);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        immutable d = msecs(45);
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), d);
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 13, 30, 33), d));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 14, 30, 33), d));
        testST(beforeAD, 3, SysTime(DateTime(1999, 7, 6, 15, 30, 33), d));
        testST(beforeAD, 4, SysTime(DateTime(1999, 7, 6, 16, 30, 33), d));
        testST(beforeAD, 5, SysTime(DateTime(1999, 7, 6, 17, 30, 33), d));
        testST(beforeAD, 6, SysTime(DateTime(1999, 7, 6, 18, 30, 33), d));
        testST(beforeAD, 7, SysTime(DateTime(1999, 7, 6, 19, 30, 33), d));
        testST(beforeAD, 8, SysTime(DateTime(1999, 7, 6, 20, 30, 33), d));
        testST(beforeAD, 9, SysTime(DateTime(1999, 7, 6, 21, 30, 33), d));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 22, 30, 33), d));
        testST(beforeAD, 11, SysTime(DateTime(1999, 7, 6, 23, 30, 33), d));
        testST(beforeAD, 12, SysTime(DateTime(1999, 7, 6, 0, 30, 33), d));
        testST(beforeAD, 13, SysTime(DateTime(1999, 7, 6, 1, 30, 33), d));
        testST(beforeAD, 14, SysTime(DateTime(1999, 7, 6, 2, 30, 33), d));
        testST(beforeAD, 15, SysTime(DateTime(1999, 7, 6, 3, 30, 33), d));
        testST(beforeAD, 16, SysTime(DateTime(1999, 7, 6, 4, 30, 33), d));
        testST(beforeAD, 17, SysTime(DateTime(1999, 7, 6, 5, 30, 33), d));
        testST(beforeAD, 18, SysTime(DateTime(1999, 7, 6, 6, 30, 33), d));
        testST(beforeAD, 19, SysTime(DateTime(1999, 7, 6, 7, 30, 33), d));
        testST(beforeAD, 20, SysTime(DateTime(1999, 7, 6, 8, 30, 33), d));
        testST(beforeAD, 21, SysTime(DateTime(1999, 7, 6, 9, 30, 33), d));
        testST(beforeAD, 22, SysTime(DateTime(1999, 7, 6, 10, 30, 33), d));
        testST(beforeAD, 23, SysTime(DateTime(1999, 7, 6, 11, 30, 33), d));
        testST(beforeAD, 24, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 25, SysTime(DateTime(1999, 7, 6, 13, 30, 33), d));
        testST(beforeAD, 50, SysTime(DateTime(1999, 7, 6, 14, 30, 33), d));
        testST(beforeAD, 10_000, SysTime(DateTime(1999, 7, 6, 4, 30, 33), d));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 11, 30, 33), d));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 10, 30, 33), d));
        testST(beforeAD, -3, SysTime(DateTime(1999, 7, 6, 9, 30, 33), d));
        testST(beforeAD, -4, SysTime(DateTime(1999, 7, 6, 8, 30, 33), d));
        testST(beforeAD, -5, SysTime(DateTime(1999, 7, 6, 7, 30, 33), d));
        testST(beforeAD, -6, SysTime(DateTime(1999, 7, 6, 6, 30, 33), d));
        testST(beforeAD, -7, SysTime(DateTime(1999, 7, 6, 5, 30, 33), d));
        testST(beforeAD, -8, SysTime(DateTime(1999, 7, 6, 4, 30, 33), d));
        testST(beforeAD, -9, SysTime(DateTime(1999, 7, 6, 3, 30, 33), d));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 2, 30, 33), d));
        testST(beforeAD, -11, SysTime(DateTime(1999, 7, 6, 1, 30, 33), d));
        testST(beforeAD, -12, SysTime(DateTime(1999, 7, 6, 0, 30, 33), d));
        testST(beforeAD, -13, SysTime(DateTime(1999, 7, 6, 23, 30, 33), d));
        testST(beforeAD, -14, SysTime(DateTime(1999, 7, 6, 22, 30, 33), d));
        testST(beforeAD, -15, SysTime(DateTime(1999, 7, 6, 21, 30, 33), d));
        testST(beforeAD, -16, SysTime(DateTime(1999, 7, 6, 20, 30, 33), d));
        testST(beforeAD, -17, SysTime(DateTime(1999, 7, 6, 19, 30, 33), d));
        testST(beforeAD, -18, SysTime(DateTime(1999, 7, 6, 18, 30, 33), d));
        testST(beforeAD, -19, SysTime(DateTime(1999, 7, 6, 17, 30, 33), d));
        testST(beforeAD, -20, SysTime(DateTime(1999, 7, 6, 16, 30, 33), d));
        testST(beforeAD, -21, SysTime(DateTime(1999, 7, 6, 15, 30, 33), d));
        testST(beforeAD, -22, SysTime(DateTime(1999, 7, 6, 14, 30, 33), d));
        testST(beforeAD, -23, SysTime(DateTime(1999, 7, 6, 13, 30, 33), d));
        testST(beforeAD, -24, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, -25, SysTime(DateTime(1999, 7, 6, 11, 30, 33), d));
        testST(beforeAD, -50, SysTime(DateTime(1999, 7, 6, 10, 30, 33), d));
        testST(beforeAD, -10_000, SysTime(DateTime(1999, 7, 6, 20, 30, 33), d));

        testST(SysTime(DateTime(1999, 7, 6, 0, 30, 33), d), 1, SysTime(DateTime(1999, 7, 6, 1, 30, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 30, 33), d), 0, SysTime(DateTime(1999, 7, 6, 0, 30, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 30, 33), d), -1, SysTime(DateTime(1999, 7, 6, 23, 30, 33), d));

        testST(SysTime(DateTime(1999, 7, 6, 23, 30, 33), d), 1, SysTime(DateTime(1999, 7, 6, 0, 30, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 23, 30, 33), d), 0, SysTime(DateTime(1999, 7, 6, 23, 30, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 23, 30, 33), d), -1, SysTime(DateTime(1999, 7, 6, 22, 30, 33), d));

        testST(SysTime(DateTime(1999, 7, 31, 23, 30, 33), d), 1, SysTime(DateTime(1999, 7, 31, 0, 30, 33), d));
        testST(SysTime(DateTime(1999, 8, 1, 0, 30, 33), d), -1, SysTime(DateTime(1999, 8, 1, 23, 30, 33), d));

        testST(SysTime(DateTime(1999, 12, 31, 23, 30, 33), d), 1, SysTime(DateTime(1999, 12, 31, 0, 30, 33), d));
        testST(SysTime(DateTime(2000, 1, 1, 0, 30, 33), d), -1, SysTime(DateTime(2000, 1, 1, 23, 30, 33), d));

        testST(SysTime(DateTime(1999, 2, 28, 23, 30, 33), d), 25, SysTime(DateTime(1999, 2, 28, 0, 30, 33), d));
        testST(SysTime(DateTime(1999, 3, 2, 0, 30, 33), d), -25, SysTime(DateTime(1999, 3, 2, 23, 30, 33), d));

        testST(SysTime(DateTime(2000, 2, 28, 23, 30, 33), d), 25, SysTime(DateTime(2000, 2, 28, 0, 30, 33), d));
        testST(SysTime(DateTime(2000, 3, 1, 0, 30, 33), d), -25, SysTime(DateTime(2000, 3, 1, 23, 30, 33), d));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d);
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 13, 30, 33), d));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 14, 30, 33), d));
        testST(beforeBC, 3, SysTime(DateTime(-1999, 7, 6, 15, 30, 33), d));
        testST(beforeBC, 4, SysTime(DateTime(-1999, 7, 6, 16, 30, 33), d));
        testST(beforeBC, 5, SysTime(DateTime(-1999, 7, 6, 17, 30, 33), d));
        testST(beforeBC, 6, SysTime(DateTime(-1999, 7, 6, 18, 30, 33), d));
        testST(beforeBC, 7, SysTime(DateTime(-1999, 7, 6, 19, 30, 33), d));
        testST(beforeBC, 8, SysTime(DateTime(-1999, 7, 6, 20, 30, 33), d));
        testST(beforeBC, 9, SysTime(DateTime(-1999, 7, 6, 21, 30, 33), d));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 22, 30, 33), d));
        testST(beforeBC, 11, SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d));
        testST(beforeBC, 12, SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d));
        testST(beforeBC, 13, SysTime(DateTime(-1999, 7, 6, 1, 30, 33), d));
        testST(beforeBC, 14, SysTime(DateTime(-1999, 7, 6, 2, 30, 33), d));
        testST(beforeBC, 15, SysTime(DateTime(-1999, 7, 6, 3, 30, 33), d));
        testST(beforeBC, 16, SysTime(DateTime(-1999, 7, 6, 4, 30, 33), d));
        testST(beforeBC, 17, SysTime(DateTime(-1999, 7, 6, 5, 30, 33), d));
        testST(beforeBC, 18, SysTime(DateTime(-1999, 7, 6, 6, 30, 33), d));
        testST(beforeBC, 19, SysTime(DateTime(-1999, 7, 6, 7, 30, 33), d));
        testST(beforeBC, 20, SysTime(DateTime(-1999, 7, 6, 8, 30, 33), d));
        testST(beforeBC, 21, SysTime(DateTime(-1999, 7, 6, 9, 30, 33), d));
        testST(beforeBC, 22, SysTime(DateTime(-1999, 7, 6, 10, 30, 33), d));
        testST(beforeBC, 23, SysTime(DateTime(-1999, 7, 6, 11, 30, 33), d));
        testST(beforeBC, 24, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 25, SysTime(DateTime(-1999, 7, 6, 13, 30, 33), d));
        testST(beforeBC, 50, SysTime(DateTime(-1999, 7, 6, 14, 30, 33), d));
        testST(beforeBC, 10_000, SysTime(DateTime(-1999, 7, 6, 4, 30, 33), d));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 11, 30, 33), d));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 10, 30, 33), d));
        testST(beforeBC, -3, SysTime(DateTime(-1999, 7, 6, 9, 30, 33), d));
        testST(beforeBC, -4, SysTime(DateTime(-1999, 7, 6, 8, 30, 33), d));
        testST(beforeBC, -5, SysTime(DateTime(-1999, 7, 6, 7, 30, 33), d));
        testST(beforeBC, -6, SysTime(DateTime(-1999, 7, 6, 6, 30, 33), d));
        testST(beforeBC, -7, SysTime(DateTime(-1999, 7, 6, 5, 30, 33), d));
        testST(beforeBC, -8, SysTime(DateTime(-1999, 7, 6, 4, 30, 33), d));
        testST(beforeBC, -9, SysTime(DateTime(-1999, 7, 6, 3, 30, 33), d));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 2, 30, 33), d));
        testST(beforeBC, -11, SysTime(DateTime(-1999, 7, 6, 1, 30, 33), d));
        testST(beforeBC, -12, SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d));
        testST(beforeBC, -13, SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d));
        testST(beforeBC, -14, SysTime(DateTime(-1999, 7, 6, 22, 30, 33), d));
        testST(beforeBC, -15, SysTime(DateTime(-1999, 7, 6, 21, 30, 33), d));
        testST(beforeBC, -16, SysTime(DateTime(-1999, 7, 6, 20, 30, 33), d));
        testST(beforeBC, -17, SysTime(DateTime(-1999, 7, 6, 19, 30, 33), d));
        testST(beforeBC, -18, SysTime(DateTime(-1999, 7, 6, 18, 30, 33), d));
        testST(beforeBC, -19, SysTime(DateTime(-1999, 7, 6, 17, 30, 33), d));
        testST(beforeBC, -20, SysTime(DateTime(-1999, 7, 6, 16, 30, 33), d));
        testST(beforeBC, -21, SysTime(DateTime(-1999, 7, 6, 15, 30, 33), d));
        testST(beforeBC, -22, SysTime(DateTime(-1999, 7, 6, 14, 30, 33), d));
        testST(beforeBC, -23, SysTime(DateTime(-1999, 7, 6, 13, 30, 33), d));
        testST(beforeBC, -24, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, -25, SysTime(DateTime(-1999, 7, 6, 11, 30, 33), d));
        testST(beforeBC, -50, SysTime(DateTime(-1999, 7, 6, 10, 30, 33), d));
        testST(beforeBC, -10_000, SysTime(DateTime(-1999, 7, 6, 20, 30, 33), d));

        testST(SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d), 1, SysTime(DateTime(-1999, 7, 6, 1, 30, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d), 0, SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d), -1, SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d));

        testST(SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d), 1, SysTime(DateTime(-1999, 7, 6, 0, 30, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d), 0, SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 23, 30, 33), d), -1, SysTime(DateTime(-1999, 7, 6, 22, 30, 33), d));

        testST(SysTime(DateTime(-1999, 7, 31, 23, 30, 33), d), 1, SysTime(DateTime(-1999, 7, 31, 0, 30, 33), d));
        testST(SysTime(DateTime(-1999, 8, 1, 0, 30, 33), d), -1, SysTime(DateTime(-1999, 8, 1, 23, 30, 33), d));

        testST(SysTime(DateTime(-2001, 12, 31, 23, 30, 33), d), 1, SysTime(DateTime(-2001, 12, 31, 0, 30, 33), d));
        testST(SysTime(DateTime(-2000, 1, 1, 0, 30, 33), d), -1, SysTime(DateTime(-2000, 1, 1, 23, 30, 33), d));

        testST(SysTime(DateTime(-2001, 2, 28, 23, 30, 33), d), 25, SysTime(DateTime(-2001, 2, 28, 0, 30, 33), d));
        testST(SysTime(DateTime(-2001, 3, 2, 0, 30, 33), d), -25, SysTime(DateTime(-2001, 3, 2, 23, 30, 33), d));

        testST(SysTime(DateTime(-2000, 2, 28, 23, 30, 33), d), 25, SysTime(DateTime(-2000, 2, 28, 0, 30, 33), d));
        testST(SysTime(DateTime(-2000, 3, 1, 0, 30, 33), d), -25, SysTime(DateTime(-2000, 3, 1, 23, 30, 33), d));

        //Test Both
        testST(SysTime(DateTime(-1, 1, 1, 11, 30, 33), d), 17_546, SysTime(DateTime(-1, 1, 1, 13, 30, 33), d));
        testST(SysTime(DateTime(1, 1, 1, 13, 30, 33), d), -17_546, SysTime(DateTime(1, 1, 1, 11, 30, 33), d));

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"hours"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 0, 0)));
            sysTime.roll!"hours"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"hours"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"hours"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 0, 0));
            sysTime.roll!"hours"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 0, 0, 0)));
            sysTime.roll!"hours"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"hours"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 0, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"hours"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"hours"(1).roll!"hours"(-67);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 5, 59, 59), hnsecs(9_999_999)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"hours"(4)));
        //static assert(!__traits(compiles, ist.roll!"hours"(4)));
    }

    //Test roll!"minutes"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, int minutes, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"minutes"(minutes);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        immutable d = usecs(7203);
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), d);
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 31, 33), d));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 32, 33), d));
        testST(beforeAD, 3, SysTime(DateTime(1999, 7, 6, 12, 33, 33), d));
        testST(beforeAD, 4, SysTime(DateTime(1999, 7, 6, 12, 34, 33), d));
        testST(beforeAD, 5, SysTime(DateTime(1999, 7, 6, 12, 35, 33), d));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 40, 33), d));
        testST(beforeAD, 15, SysTime(DateTime(1999, 7, 6, 12, 45, 33), d));
        testST(beforeAD, 29, SysTime(DateTime(1999, 7, 6, 12, 59, 33), d));
        testST(beforeAD, 30, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, 45, SysTime(DateTime(1999, 7, 6, 12, 15, 33), d));
        testST(beforeAD, 60, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 75, SysTime(DateTime(1999, 7, 6, 12, 45, 33), d));
        testST(beforeAD, 90, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, 100, SysTime(DateTime(1999, 7, 6, 12, 10, 33), d));

        testST(beforeAD, 689, SysTime(DateTime(1999, 7, 6, 12, 59, 33), d));
        testST(beforeAD, 690, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, 691, SysTime(DateTime(1999, 7, 6, 12, 1, 33), d));
        testST(beforeAD, 960, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 1439, SysTime(DateTime(1999, 7, 6, 12, 29, 33), d));
        testST(beforeAD, 1440, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 1441, SysTime(DateTime(1999, 7, 6, 12, 31, 33), d));
        testST(beforeAD, 2880, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 29, 33), d));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 28, 33), d));
        testST(beforeAD, -3, SysTime(DateTime(1999, 7, 6, 12, 27, 33), d));
        testST(beforeAD, -4, SysTime(DateTime(1999, 7, 6, 12, 26, 33), d));
        testST(beforeAD, -5, SysTime(DateTime(1999, 7, 6, 12, 25, 33), d));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 20, 33), d));
        testST(beforeAD, -15, SysTime(DateTime(1999, 7, 6, 12, 15, 33), d));
        testST(beforeAD, -29, SysTime(DateTime(1999, 7, 6, 12, 1, 33), d));
        testST(beforeAD, -30, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, -45, SysTime(DateTime(1999, 7, 6, 12, 45, 33), d));
        testST(beforeAD, -60, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, -75, SysTime(DateTime(1999, 7, 6, 12, 15, 33), d));
        testST(beforeAD, -90, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, -100, SysTime(DateTime(1999, 7, 6, 12, 50, 33), d));

        testST(beforeAD, -749, SysTime(DateTime(1999, 7, 6, 12, 1, 33), d));
        testST(beforeAD, -750, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(beforeAD, -751, SysTime(DateTime(1999, 7, 6, 12, 59, 33), d));
        testST(beforeAD, -960, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, -1439, SysTime(DateTime(1999, 7, 6, 12, 31, 33), d));
        testST(beforeAD, -1440, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, -1441, SysTime(DateTime(1999, 7, 6, 12, 29, 33), d));
        testST(beforeAD, -2880, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));

        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 33), d), 1, SysTime(DateTime(1999, 7, 6, 12, 1, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 33), d), 0, SysTime(DateTime(1999, 7, 6, 12, 0, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 33), d), -1, SysTime(DateTime(1999, 7, 6, 12, 59, 33), d));

        testST(SysTime(DateTime(1999, 7, 6, 11, 59, 33), d), 1, SysTime(DateTime(1999, 7, 6, 11, 0, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 11, 59, 33), d), 0, SysTime(DateTime(1999, 7, 6, 11, 59, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 11, 59, 33), d), -1, SysTime(DateTime(1999, 7, 6, 11, 58, 33), d));

        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 33), d), 1, SysTime(DateTime(1999, 7, 6, 0, 1, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 33), d), 0, SysTime(DateTime(1999, 7, 6, 0, 0, 33), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 33), d), -1, SysTime(DateTime(1999, 7, 6, 0, 59, 33), d));

        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 33), d), 1, SysTime(DateTime(1999, 7, 5, 23, 0, 33), d));
        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 33), d), 0, SysTime(DateTime(1999, 7, 5, 23, 59, 33), d));
        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 33), d), -1, SysTime(DateTime(1999, 7, 5, 23, 58, 33), d));

        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 33), d), 1, SysTime(DateTime(1998, 12, 31, 23, 0, 33), d));
        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 33), d), 0, SysTime(DateTime(1998, 12, 31, 23, 59, 33), d));
        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 33), d), -1, SysTime(DateTime(1998, 12, 31, 23, 58, 33), d));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d);
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 31, 33), d));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 32, 33), d));
        testST(beforeBC, 3, SysTime(DateTime(-1999, 7, 6, 12, 33, 33), d));
        testST(beforeBC, 4, SysTime(DateTime(-1999, 7, 6, 12, 34, 33), d));
        testST(beforeBC, 5, SysTime(DateTime(-1999, 7, 6, 12, 35, 33), d));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 40, 33), d));
        testST(beforeBC, 15, SysTime(DateTime(-1999, 7, 6, 12, 45, 33), d));
        testST(beforeBC, 29, SysTime(DateTime(-1999, 7, 6, 12, 59, 33), d));
        testST(beforeBC, 30, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, 45, SysTime(DateTime(-1999, 7, 6, 12, 15, 33), d));
        testST(beforeBC, 60, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 75, SysTime(DateTime(-1999, 7, 6, 12, 45, 33), d));
        testST(beforeBC, 90, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, 100, SysTime(DateTime(-1999, 7, 6, 12, 10, 33), d));

        testST(beforeBC, 689, SysTime(DateTime(-1999, 7, 6, 12, 59, 33), d));
        testST(beforeBC, 690, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, 691, SysTime(DateTime(-1999, 7, 6, 12, 1, 33), d));
        testST(beforeBC, 960, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 1439, SysTime(DateTime(-1999, 7, 6, 12, 29, 33), d));
        testST(beforeBC, 1440, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 1441, SysTime(DateTime(-1999, 7, 6, 12, 31, 33), d));
        testST(beforeBC, 2880, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 29, 33), d));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 28, 33), d));
        testST(beforeBC, -3, SysTime(DateTime(-1999, 7, 6, 12, 27, 33), d));
        testST(beforeBC, -4, SysTime(DateTime(-1999, 7, 6, 12, 26, 33), d));
        testST(beforeBC, -5, SysTime(DateTime(-1999, 7, 6, 12, 25, 33), d));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 20, 33), d));
        testST(beforeBC, -15, SysTime(DateTime(-1999, 7, 6, 12, 15, 33), d));
        testST(beforeBC, -29, SysTime(DateTime(-1999, 7, 6, 12, 1, 33), d));
        testST(beforeBC, -30, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, -45, SysTime(DateTime(-1999, 7, 6, 12, 45, 33), d));
        testST(beforeBC, -60, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, -75, SysTime(DateTime(-1999, 7, 6, 12, 15, 33), d));
        testST(beforeBC, -90, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, -100, SysTime(DateTime(-1999, 7, 6, 12, 50, 33), d));

        testST(beforeBC, -749, SysTime(DateTime(-1999, 7, 6, 12, 1, 33), d));
        testST(beforeBC, -750, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(beforeBC, -751, SysTime(DateTime(-1999, 7, 6, 12, 59, 33), d));
        testST(beforeBC, -960, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, -1439, SysTime(DateTime(-1999, 7, 6, 12, 31, 33), d));
        testST(beforeBC, -1440, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, -1441, SysTime(DateTime(-1999, 7, 6, 12, 29, 33), d));
        testST(beforeBC, -2880, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));

        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d), 1, SysTime(DateTime(-1999, 7, 6, 12, 1, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d), 0, SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 33), d), -1, SysTime(DateTime(-1999, 7, 6, 12, 59, 33), d));

        testST(SysTime(DateTime(-1999, 7, 6, 11, 59, 33), d), 1, SysTime(DateTime(-1999, 7, 6, 11, 0, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 11, 59, 33), d), 0, SysTime(DateTime(-1999, 7, 6, 11, 59, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 11, 59, 33), d), -1, SysTime(DateTime(-1999, 7, 6, 11, 58, 33), d));

        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 33), d), 1, SysTime(DateTime(-1999, 7, 6, 0, 1, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 33), d), 0, SysTime(DateTime(-1999, 7, 6, 0, 0, 33), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 33), d), -1, SysTime(DateTime(-1999, 7, 6, 0, 59, 33), d));

        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 33), d), 1, SysTime(DateTime(-1999, 7, 5, 23, 0, 33), d));
        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 33), d), 0, SysTime(DateTime(-1999, 7, 5, 23, 59, 33), d));
        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 33), d), -1, SysTime(DateTime(-1999, 7, 5, 23, 58, 33), d));

        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 33), d), 1, SysTime(DateTime(-2000, 12, 31, 23, 0, 33), d));
        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 33), d), 0, SysTime(DateTime(-2000, 12, 31, 23, 59, 33), d));
        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 33), d), -1, SysTime(DateTime(-2000, 12, 31, 23, 58, 33), d));

        //Test Both
        testST(SysTime(DateTime(1, 1, 1, 0, 0, 0)), -1, SysTime(DateTime(1, 1, 1, 0, 59, 0)));
        testST(SysTime(DateTime(0, 12, 31, 23, 59, 0)), 1, SysTime(DateTime(0, 12, 31, 23, 0, 0)));

        testST(SysTime(DateTime(0, 1, 1, 0, 0, 0)), -1, SysTime(DateTime(0, 1, 1, 0, 59, 0)));
        testST(SysTime(DateTime(-1, 12, 31, 23, 59, 0)), 1, SysTime(DateTime(-1, 12, 31, 23, 0, 0)));

        testST(SysTime(DateTime(-1, 1, 1, 11, 30, 33), d), 1_052_760, SysTime(DateTime(-1, 1, 1, 11, 30, 33), d));
        testST(SysTime(DateTime(1, 1, 1, 13, 30, 33), d), -1_052_760, SysTime(DateTime(1, 1, 1, 13, 30, 33), d));

        testST(SysTime(DateTime(-1, 1, 1, 11, 30, 33), d), 1_052_782, SysTime(DateTime(-1, 1, 1, 11, 52, 33), d));
        testST(SysTime(DateTime(1, 1, 1, 13, 52, 33), d), -1_052_782, SysTime(DateTime(1, 1, 1, 13, 30, 33), d));

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"minutes"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 59, 0)));
            sysTime.roll!"minutes"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 59), hnsecs(9_999_999));
            sysTime.roll!"minutes"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 59, 59), hnsecs(9_999_999)));
            sysTime.roll!"minutes"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 0));
            sysTime.roll!"minutes"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 0, 0)));
            sysTime.roll!"minutes"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"minutes"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 0, 59), hnsecs(9_999_999)));
            sysTime.roll!"minutes"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"minutes"(1).roll!"minutes"(-79);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 41, 59), hnsecs(9_999_999)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"minutes"(4)));
        //static assert(!__traits(compiles, ist.roll!"minutes"(4)));
    }

    //Test roll!"seconds"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, int seconds, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"seconds"(seconds);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        immutable d = msecs(274);
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), d);
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 30, 34), d));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 30, 35), d));
        testST(beforeAD, 3, SysTime(DateTime(1999, 7, 6, 12, 30, 36), d));
        testST(beforeAD, 4, SysTime(DateTime(1999, 7, 6, 12, 30, 37), d));
        testST(beforeAD, 5, SysTime(DateTime(1999, 7, 6, 12, 30, 38), d));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 30, 43), d));
        testST(beforeAD, 15, SysTime(DateTime(1999, 7, 6, 12, 30, 48), d));
        testST(beforeAD, 26, SysTime(DateTime(1999, 7, 6, 12, 30, 59), d));
        testST(beforeAD, 27, SysTime(DateTime(1999, 7, 6, 12, 30, 0), d));
        testST(beforeAD, 30, SysTime(DateTime(1999, 7, 6, 12, 30, 3), d));
        testST(beforeAD, 59, SysTime(DateTime(1999, 7, 6, 12, 30, 32), d));
        testST(beforeAD, 60, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 61, SysTime(DateTime(1999, 7, 6, 12, 30, 34), d));

        testST(beforeAD, 1766, SysTime(DateTime(1999, 7, 6, 12, 30, 59), d));
        testST(beforeAD, 1767, SysTime(DateTime(1999, 7, 6, 12, 30, 0), d));
        testST(beforeAD, 1768, SysTime(DateTime(1999, 7, 6, 12, 30, 1), d));
        testST(beforeAD, 2007, SysTime(DateTime(1999, 7, 6, 12, 30, 0), d));
        testST(beforeAD, 3599, SysTime(DateTime(1999, 7, 6, 12, 30, 32), d));
        testST(beforeAD, 3600, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, 3601, SysTime(DateTime(1999, 7, 6, 12, 30, 34), d));
        testST(beforeAD, 7200, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 30, 32), d));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 30, 31), d));
        testST(beforeAD, -3, SysTime(DateTime(1999, 7, 6, 12, 30, 30), d));
        testST(beforeAD, -4, SysTime(DateTime(1999, 7, 6, 12, 30, 29), d));
        testST(beforeAD, -5, SysTime(DateTime(1999, 7, 6, 12, 30, 28), d));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 30, 23), d));
        testST(beforeAD, -15, SysTime(DateTime(1999, 7, 6, 12, 30, 18), d));
        testST(beforeAD, -33, SysTime(DateTime(1999, 7, 6, 12, 30, 0), d));
        testST(beforeAD, -34, SysTime(DateTime(1999, 7, 6, 12, 30, 59), d));
        testST(beforeAD, -35, SysTime(DateTime(1999, 7, 6, 12, 30, 58), d));
        testST(beforeAD, -59, SysTime(DateTime(1999, 7, 6, 12, 30, 34), d));
        testST(beforeAD, -60, SysTime(DateTime(1999, 7, 6, 12, 30, 33), d));
        testST(beforeAD, -61, SysTime(DateTime(1999, 7, 6, 12, 30, 32), d));

        testST(SysTime(DateTime(1999, 7, 6, 12, 30, 0), d), 1, SysTime(DateTime(1999, 7, 6, 12, 30, 1), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 30, 0), d), 0, SysTime(DateTime(1999, 7, 6, 12, 30, 0), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 30, 0), d), -1, SysTime(DateTime(1999, 7, 6, 12, 30, 59), d));

        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 0), d), 1, SysTime(DateTime(1999, 7, 6, 12, 0, 1), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 0), d), 0, SysTime(DateTime(1999, 7, 6, 12, 0, 0), d));
        testST(SysTime(DateTime(1999, 7, 6, 12, 0, 0), d), -1, SysTime(DateTime(1999, 7, 6, 12, 0, 59), d));

        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 0), d), 1, SysTime(DateTime(1999, 7, 6, 0, 0, 1), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 0), d), 0, SysTime(DateTime(1999, 7, 6, 0, 0, 0), d));
        testST(SysTime(DateTime(1999, 7, 6, 0, 0, 0), d), -1, SysTime(DateTime(1999, 7, 6, 0, 0, 59), d));

        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 59), d), 1, SysTime(DateTime(1999, 7, 5, 23, 59, 0), d));
        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 59), d), 0, SysTime(DateTime(1999, 7, 5, 23, 59, 59), d));
        testST(SysTime(DateTime(1999, 7, 5, 23, 59, 59), d), -1, SysTime(DateTime(1999, 7, 5, 23, 59, 58), d));

        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 59), d), 1, SysTime(DateTime(1998, 12, 31, 23, 59, 0), d));
        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 59), d), 0, SysTime(DateTime(1998, 12, 31, 23, 59, 59), d));
        testST(SysTime(DateTime(1998, 12, 31, 23, 59, 59), d), -1, SysTime(DateTime(1998, 12, 31, 23, 59, 58), d));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d);
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 34), d));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 30, 35), d));
        testST(beforeBC, 3, SysTime(DateTime(-1999, 7, 6, 12, 30, 36), d));
        testST(beforeBC, 4, SysTime(DateTime(-1999, 7, 6, 12, 30, 37), d));
        testST(beforeBC, 5, SysTime(DateTime(-1999, 7, 6, 12, 30, 38), d));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 30, 43), d));
        testST(beforeBC, 15, SysTime(DateTime(-1999, 7, 6, 12, 30, 48), d));
        testST(beforeBC, 26, SysTime(DateTime(-1999, 7, 6, 12, 30, 59), d));
        testST(beforeBC, 27, SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d));
        testST(beforeBC, 30, SysTime(DateTime(-1999, 7, 6, 12, 30, 3), d));
        testST(beforeBC, 59, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), d));
        testST(beforeBC, 60, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 61, SysTime(DateTime(-1999, 7, 6, 12, 30, 34), d));

        testST(beforeBC, 1766, SysTime(DateTime(-1999, 7, 6, 12, 30, 59), d));
        testST(beforeBC, 1767, SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d));
        testST(beforeBC, 1768, SysTime(DateTime(-1999, 7, 6, 12, 30, 1), d));
        testST(beforeBC, 2007, SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d));
        testST(beforeBC, 3599, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), d));
        testST(beforeBC, 3600, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, 3601, SysTime(DateTime(-1999, 7, 6, 12, 30, 34), d));
        testST(beforeBC, 7200, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), d));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 30, 31), d));
        testST(beforeBC, -3, SysTime(DateTime(-1999, 7, 6, 12, 30, 30), d));
        testST(beforeBC, -4, SysTime(DateTime(-1999, 7, 6, 12, 30, 29), d));
        testST(beforeBC, -5, SysTime(DateTime(-1999, 7, 6, 12, 30, 28), d));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 30, 23), d));
        testST(beforeBC, -15, SysTime(DateTime(-1999, 7, 6, 12, 30, 18), d));
        testST(beforeBC, -33, SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d));
        testST(beforeBC, -34, SysTime(DateTime(-1999, 7, 6, 12, 30, 59), d));
        testST(beforeBC, -35, SysTime(DateTime(-1999, 7, 6, 12, 30, 58), d));
        testST(beforeBC, -59, SysTime(DateTime(-1999, 7, 6, 12, 30, 34), d));
        testST(beforeBC, -60, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), d));
        testST(beforeBC, -61, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), d));

        testST(SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d), 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 1), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d), 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 30, 0), d), -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 59), d));

        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 0), d), 1, SysTime(DateTime(-1999, 7, 6, 12, 0, 1), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 0), d), 0, SysTime(DateTime(-1999, 7, 6, 12, 0, 0), d));
        testST(SysTime(DateTime(-1999, 7, 6, 12, 0, 0), d), -1, SysTime(DateTime(-1999, 7, 6, 12, 0, 59), d));

        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 0), d), 1, SysTime(DateTime(-1999, 7, 6, 0, 0, 1), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 0), d), 0, SysTime(DateTime(-1999, 7, 6, 0, 0, 0), d));
        testST(SysTime(DateTime(-1999, 7, 6, 0, 0, 0), d), -1, SysTime(DateTime(-1999, 7, 6, 0, 0, 59), d));

        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 59), d), 1, SysTime(DateTime(-1999, 7, 5, 23, 59, 0), d));
        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 59), d), 0, SysTime(DateTime(-1999, 7, 5, 23, 59, 59), d));
        testST(SysTime(DateTime(-1999, 7, 5, 23, 59, 59), d), -1, SysTime(DateTime(-1999, 7, 5, 23, 59, 58), d));

        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 59), d), 1, SysTime(DateTime(-2000, 12, 31, 23, 59, 0), d));
        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 59), d), 0, SysTime(DateTime(-2000, 12, 31, 23, 59, 59), d));
        testST(SysTime(DateTime(-2000, 12, 31, 23, 59, 59), d), -1, SysTime(DateTime(-2000, 12, 31, 23, 59, 58), d));

        //Test Both
        testST(SysTime(DateTime(1, 1, 1, 0, 0, 0), d), -1, SysTime(DateTime(1, 1, 1, 0, 0, 59), d));
        testST(SysTime(DateTime(0, 12, 31, 23, 59, 59), d), 1, SysTime(DateTime(0, 12, 31, 23, 59, 0), d));

        testST(SysTime(DateTime(0, 1, 1, 0, 0, 0), d), -1, SysTime(DateTime(0, 1, 1, 0, 0, 59), d));
        testST(SysTime(DateTime(-1, 12, 31, 23, 59, 59), d), 1, SysTime(DateTime(-1, 12, 31, 23, 59, 0), d));

        testST(SysTime(DateTime(-1, 1, 1, 11, 30, 33), d), 63_165_600L, SysTime(DateTime(-1, 1, 1, 11, 30, 33), d));
        testST(SysTime(DateTime(1, 1, 1, 13, 30, 33), d), -63_165_600L, SysTime(DateTime(1, 1, 1, 13, 30, 33), d));

        testST(SysTime(DateTime(-1, 1, 1, 11, 30, 33), d), 63_165_617L, SysTime(DateTime(-1, 1, 1, 11, 30, 50), d));
        testST(SysTime(DateTime(1, 1, 1, 13, 30, 50), d), -63_165_617L, SysTime(DateTime(1, 1, 1, 13, 30, 33), d));

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0));
            sysTime.roll!"seconds"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 59)));
            sysTime.roll!"seconds"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        }

        {
            auto sysTime = SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(9_999_999));
            sysTime.roll!"seconds"(-1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 59), hnsecs(9_999_999)));
            sysTime.roll!"seconds"(1);
            assert(sysTime == SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59));
            sysTime.roll!"seconds"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 0)));
            sysTime.roll!"seconds"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 59)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"seconds"(1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 0), hnsecs(9_999_999)));
            sysTime.roll!"seconds"(-1);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        }

        {
            auto sysTime = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            sysTime.roll!"seconds"(1).roll!"seconds"(-102);
            assert(sysTime == SysTime(DateTime(0, 12, 31, 23, 59, 18), hnsecs(9_999_999)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"seconds"(4)));
        //static assert(!__traits(compiles, ist.roll!"seconds"(4)));
    }


    //Shares documentation with "days" version.
    ref SysTime roll(string units)(long value) @safe nothrow
        if (units == "msecs" ||
           units == "usecs" ||
           units == "hnsecs")
    {
        auto hnsecs = adjTime;
        immutable days = splitUnitsFromHNSecs!"days"(hnsecs);
        immutable negative = hnsecs < 0;

        if (negative)
            hnsecs += convert!("hours", "hnsecs")(24);

        immutable seconds = splitUnitsFromHNSecs!"seconds"(hnsecs);
        hnsecs += convert!(units, "hnsecs")(value);
        hnsecs %= convert!("seconds", "hnsecs")(1);

        if (hnsecs < 0)
            hnsecs += convert!("seconds", "hnsecs")(1);
        hnsecs += convert!("seconds", "hnsecs")(seconds);

        if (negative)
            hnsecs -= convert!("hours", "hnsecs")(24);

        immutable newDaysHNSecs = convert!("days", "hnsecs")(days);
        adjTime = newDaysHNSecs + hnsecs;
        return this;
    }


    //Test roll!"msecs"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, int milliseconds, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"msecs"(milliseconds);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274));
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(275)));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(276)));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(284)));
        testST(beforeAD, 100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(374)));
        testST(beforeAD, 725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeAD, 726, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, 1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeAD, 1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(275)));
        testST(beforeAD, 2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeAD, 26_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeAD, 26_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, 26_727, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(1)));
        testST(beforeAD, 1_766_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeAD, 1_766_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(273)));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(272)));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(264)));
        testST(beforeAD, -100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(174)));
        testST(beforeAD, -274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeAD, -1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeAD, -1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(273)));
        testST(beforeAD, -2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeAD, -33_274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -33_275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeAD, -1_833_274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -1_833_275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(999)));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274));
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(275)));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(276)));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(284)));
        testST(beforeBC, 100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(374)));
        testST(beforeBC, 725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeBC, 726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, 1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeBC, 1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(275)));
        testST(beforeBC, 2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeBC, 26_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeBC, 26_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, 26_727, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(1)));
        testST(beforeBC, 1_766_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeBC, 1_766_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(273)));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(272)));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(264)));
        testST(beforeBC, -100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(174)));
        testST(beforeBC, -274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeBC, -1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeBC, -1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(273)));
        testST(beforeBC, -2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(274)));
        testST(beforeBC, -33_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -33_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));
        testST(beforeBC, -1_833_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -1_833_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), msecs(999)));

        //Test Both
        auto beforeBoth1 = SysTime(DateTime(1, 1, 1, 0, 0, 0));
        testST(beforeBoth1, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), msecs(1)));
        testST(beforeBoth1, 0, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -1, SysTime(DateTime(1, 1, 1, 0, 0, 0), msecs(999)));
        testST(beforeBoth1, -2, SysTime(DateTime(1, 1, 1, 0, 0, 0), msecs(998)));
        testST(beforeBoth1, -1000, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -2000, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -2555, SysTime(DateTime(1, 1, 1, 0, 0, 0), msecs(445)));

        auto beforeBoth2 = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
        testST(beforeBoth2, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_989_999)));
        testST(beforeBoth2, 0, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9999)));
        testST(beforeBoth2, 2, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(19_999)));
        testST(beforeBoth2, 1000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 2000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 2555, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(5_549_999)));

        {
            auto st = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            st.roll!"msecs"(1202).roll!"msecs"(-703);
            assert(st == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(4_989_999)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.addMSecs(4)));
        //static assert(!__traits(compiles, ist.addMSecs(4)));
    }

    //Test roll!"usecs"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, long microseconds, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"usecs"(microseconds);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274));
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(275)));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(276)));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(284)));
        testST(beforeAD, 100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(374)));
        testST(beforeAD, 725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(999)));
        testST(beforeAD, 726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(1000)));
        testST(beforeAD, 1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(1274)));
        testST(beforeAD, 1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(1275)));
        testST(beforeAD, 2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(2274)));
        testST(beforeAD, 26_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(26_999)));
        testST(beforeAD, 26_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(27_000)));
        testST(beforeAD, 26_727, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(27_001)));
        testST(beforeAD, 1_766_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(766_999)));
        testST(beforeAD, 1_766_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(767_000)));
        testST(beforeAD, 1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeAD, 60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeAD, 3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(273)));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(272)));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(264)));
        testST(beforeAD, -100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(174)));
        testST(beforeAD, -274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(999_999)));
        testST(beforeAD, -1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(999_274)));
        testST(beforeAD, -1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(999_273)));
        testST(beforeAD, -2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(998_274)));
        testST(beforeAD, -33_274, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(967_000)));
        testST(beforeAD, -33_275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(966_999)));
        testST(beforeAD, -1_833_274, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(167_000)));
        testST(beforeAD, -1_833_275, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(166_999)));
        testST(beforeAD, -1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeAD, -60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeAD, -3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(274)));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274));
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(275)));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(276)));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(284)));
        testST(beforeBC, 100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(374)));
        testST(beforeBC, 725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(999)));
        testST(beforeBC, 726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(1000)));
        testST(beforeBC, 1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(1274)));
        testST(beforeBC, 1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(1275)));
        testST(beforeBC, 2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(2274)));
        testST(beforeBC, 26_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(26_999)));
        testST(beforeBC, 26_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(27_000)));
        testST(beforeBC, 26_727, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(27_001)));
        testST(beforeBC, 1_766_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(766_999)));
        testST(beforeBC, 1_766_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(767_000)));
        testST(beforeBC, 1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeBC, 60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeBC, 3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(273)));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(272)));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(264)));
        testST(beforeBC, -100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(174)));
        testST(beforeBC, -274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(999_999)));
        testST(beforeBC, -1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(999_274)));
        testST(beforeBC, -1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(999_273)));
        testST(beforeBC, -2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(998_274)));
        testST(beforeBC, -33_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(967_000)));
        testST(beforeBC, -33_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(966_999)));
        testST(beforeBC, -1_833_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(167_000)));
        testST(beforeBC, -1_833_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(166_999)));
        testST(beforeBC, -1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeBC, -60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));
        testST(beforeBC, -3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), usecs(274)));

        //Test Both
        auto beforeBoth1 = SysTime(DateTime(1, 1, 1, 0, 0, 0));
        testST(beforeBoth1, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(1)));
        testST(beforeBoth1, 0, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -1, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(999_999)));
        testST(beforeBoth1, -2, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(999_998)));
        testST(beforeBoth1, -1000, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(999_000)));
        testST(beforeBoth1, -2000, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(998_000)));
        testST(beforeBoth1, -2555, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(997_445)));
        testST(beforeBoth1, -1_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -2_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -2_333_333, SysTime(DateTime(1, 1, 1, 0, 0, 0), usecs(666_667)));

        auto beforeBoth2 = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
        testST(beforeBoth2, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_989)));
        testST(beforeBoth2, 0, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9)));
        testST(beforeBoth2, 2, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(19)));
        testST(beforeBoth2, 1000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9999)));
        testST(beforeBoth2, 2000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(19_999)));
        testST(beforeBoth2, 2555, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(25_549)));
        testST(beforeBoth2, 1_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 2_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 2_333_333, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(3_333_329)));

        {
            auto st = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            st.roll!"usecs"(9_020_027);
            assert(st == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(200_269)));
        }

        {
            auto st = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            st.roll!"usecs"(9_020_027).roll!"usecs"(-70_034);
            assert(st == SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_499_929)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"usecs"(4)));
        //static assert(!__traits(compiles, ist.roll!"usecs"(4)));
    }

    //Test roll!"hnsecs"().
    unittest
    {
        import core.exception : AssertError;

        static void testST(SysTime orig, long hnsecs, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            orig.roll!"hnsecs"(hnsecs);
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        auto dtAD = DateTime(1999, 7, 6, 12, 30, 33);
        auto beforeAD = SysTime(dtAD, hnsecs(274));
        testST(beforeAD, 0, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, 1, SysTime(dtAD, hnsecs(275)));
        testST(beforeAD, 2, SysTime(dtAD, hnsecs(276)));
        testST(beforeAD, 10, SysTime(dtAD, hnsecs(284)));
        testST(beforeAD, 100, SysTime(dtAD, hnsecs(374)));
        testST(beforeAD, 725, SysTime(dtAD, hnsecs(999)));
        testST(beforeAD, 726, SysTime(dtAD, hnsecs(1000)));
        testST(beforeAD, 1000, SysTime(dtAD, hnsecs(1274)));
        testST(beforeAD, 1001, SysTime(dtAD, hnsecs(1275)));
        testST(beforeAD, 2000, SysTime(dtAD, hnsecs(2274)));
        testST(beforeAD, 26_725, SysTime(dtAD, hnsecs(26_999)));
        testST(beforeAD, 26_726, SysTime(dtAD, hnsecs(27_000)));
        testST(beforeAD, 26_727, SysTime(dtAD, hnsecs(27_001)));
        testST(beforeAD, 1_766_725, SysTime(dtAD, hnsecs(1_766_999)));
        testST(beforeAD, 1_766_726, SysTime(dtAD, hnsecs(1_767_000)));
        testST(beforeAD, 1_000_000, SysTime(dtAD, hnsecs(1_000_274)));
        testST(beforeAD, 60_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, 3_600_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, 600_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, 36_000_000_000L, SysTime(dtAD, hnsecs(274)));

        testST(beforeAD, -1, SysTime(dtAD, hnsecs(273)));
        testST(beforeAD, -2, SysTime(dtAD, hnsecs(272)));
        testST(beforeAD, -10, SysTime(dtAD, hnsecs(264)));
        testST(beforeAD, -100, SysTime(dtAD, hnsecs(174)));
        testST(beforeAD, -274, SysTime(dtAD));
        testST(beforeAD, -275, SysTime(dtAD, hnsecs(9_999_999)));
        testST(beforeAD, -1000, SysTime(dtAD, hnsecs(9_999_274)));
        testST(beforeAD, -1001, SysTime(dtAD, hnsecs(9_999_273)));
        testST(beforeAD, -2000, SysTime(dtAD, hnsecs(9_998_274)));
        testST(beforeAD, -33_274, SysTime(dtAD, hnsecs(9_967_000)));
        testST(beforeAD, -33_275, SysTime(dtAD, hnsecs(9_966_999)));
        testST(beforeAD, -1_833_274, SysTime(dtAD, hnsecs(8_167_000)));
        testST(beforeAD, -1_833_275, SysTime(dtAD, hnsecs(8_166_999)));
        testST(beforeAD, -1_000_000, SysTime(dtAD, hnsecs(9_000_274)));
        testST(beforeAD, -60_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, -3_600_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, -600_000_000L, SysTime(dtAD, hnsecs(274)));
        testST(beforeAD, -36_000_000_000L, SysTime(dtAD, hnsecs(274)));

        //Test B.C.
        auto dtBC = DateTime(-1999, 7, 6, 12, 30, 33);
        auto beforeBC = SysTime(dtBC, hnsecs(274));
        testST(beforeBC, 0, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, 1, SysTime(dtBC, hnsecs(275)));
        testST(beforeBC, 2, SysTime(dtBC, hnsecs(276)));
        testST(beforeBC, 10, SysTime(dtBC, hnsecs(284)));
        testST(beforeBC, 100, SysTime(dtBC, hnsecs(374)));
        testST(beforeBC, 725, SysTime(dtBC, hnsecs(999)));
        testST(beforeBC, 726, SysTime(dtBC, hnsecs(1000)));
        testST(beforeBC, 1000, SysTime(dtBC, hnsecs(1274)));
        testST(beforeBC, 1001, SysTime(dtBC, hnsecs(1275)));
        testST(beforeBC, 2000, SysTime(dtBC, hnsecs(2274)));
        testST(beforeBC, 26_725, SysTime(dtBC, hnsecs(26_999)));
        testST(beforeBC, 26_726, SysTime(dtBC, hnsecs(27_000)));
        testST(beforeBC, 26_727, SysTime(dtBC, hnsecs(27_001)));
        testST(beforeBC, 1_766_725, SysTime(dtBC, hnsecs(1_766_999)));
        testST(beforeBC, 1_766_726, SysTime(dtBC, hnsecs(1_767_000)));
        testST(beforeBC, 1_000_000, SysTime(dtBC, hnsecs(1_000_274)));
        testST(beforeBC, 60_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, 3_600_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, 600_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, 36_000_000_000L, SysTime(dtBC, hnsecs(274)));

        testST(beforeBC, -1, SysTime(dtBC, hnsecs(273)));
        testST(beforeBC, -2, SysTime(dtBC, hnsecs(272)));
        testST(beforeBC, -10, SysTime(dtBC, hnsecs(264)));
        testST(beforeBC, -100, SysTime(dtBC, hnsecs(174)));
        testST(beforeBC, -274, SysTime(dtBC));
        testST(beforeBC, -275, SysTime(dtBC, hnsecs(9_999_999)));
        testST(beforeBC, -1000, SysTime(dtBC, hnsecs(9_999_274)));
        testST(beforeBC, -1001, SysTime(dtBC, hnsecs(9_999_273)));
        testST(beforeBC, -2000, SysTime(dtBC, hnsecs(9_998_274)));
        testST(beforeBC, -33_274, SysTime(dtBC, hnsecs(9_967_000)));
        testST(beforeBC, -33_275, SysTime(dtBC, hnsecs(9_966_999)));
        testST(beforeBC, -1_833_274, SysTime(dtBC, hnsecs(8_167_000)));
        testST(beforeBC, -1_833_275, SysTime(dtBC, hnsecs(8_166_999)));
        testST(beforeBC, -1_000_000, SysTime(dtBC, hnsecs(9_000_274)));
        testST(beforeBC, -60_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, -3_600_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, -600_000_000L, SysTime(dtBC, hnsecs(274)));
        testST(beforeBC, -36_000_000_000L, SysTime(dtBC, hnsecs(274)));

        //Test Both
        auto dtBoth1 = DateTime(1, 1, 1, 0, 0, 0);
        auto beforeBoth1 = SysTime(dtBoth1);
        testST(beforeBoth1, 1, SysTime(dtBoth1, hnsecs(1)));
        testST(beforeBoth1, 0, SysTime(dtBoth1));
        testST(beforeBoth1, -1, SysTime(dtBoth1, hnsecs(9_999_999)));
        testST(beforeBoth1, -2, SysTime(dtBoth1, hnsecs(9_999_998)));
        testST(beforeBoth1, -1000, SysTime(dtBoth1, hnsecs(9_999_000)));
        testST(beforeBoth1, -2000, SysTime(dtBoth1, hnsecs(9_998_000)));
        testST(beforeBoth1, -2555, SysTime(dtBoth1, hnsecs(9_997_445)));
        testST(beforeBoth1, -1_000_000, SysTime(dtBoth1, hnsecs(9_000_000)));
        testST(beforeBoth1, -2_000_000, SysTime(dtBoth1, hnsecs(8_000_000)));
        testST(beforeBoth1, -2_333_333, SysTime(dtBoth1, hnsecs(7_666_667)));
        testST(beforeBoth1, -10_000_000, SysTime(dtBoth1));
        testST(beforeBoth1, -20_000_000, SysTime(dtBoth1));
        testST(beforeBoth1, -20_888_888, SysTime(dtBoth1, hnsecs(9_111_112)));

        auto dtBoth2 = DateTime(0, 12, 31, 23, 59, 59);
        auto beforeBoth2 = SysTime(dtBoth2, hnsecs(9_999_999));
        testST(beforeBoth2, -1, SysTime(dtBoth2, hnsecs(9_999_998)));
        testST(beforeBoth2, 0, SysTime(dtBoth2, hnsecs(9_999_999)));
        testST(beforeBoth2, 1, SysTime(dtBoth2));
        testST(beforeBoth2, 2, SysTime(dtBoth2, hnsecs(1)));
        testST(beforeBoth2, 1000, SysTime(dtBoth2, hnsecs(999)));
        testST(beforeBoth2, 2000, SysTime(dtBoth2, hnsecs(1999)));
        testST(beforeBoth2, 2555, SysTime(dtBoth2, hnsecs(2554)));
        testST(beforeBoth2, 1_000_000, SysTime(dtBoth2, hnsecs(999_999)));
        testST(beforeBoth2, 2_000_000, SysTime(dtBoth2, hnsecs(1_999_999)));
        testST(beforeBoth2, 2_333_333, SysTime(dtBoth2, hnsecs(2_333_332)));
        testST(beforeBoth2, 10_000_000, SysTime(dtBoth2, hnsecs(9_999_999)));
        testST(beforeBoth2, 20_000_000, SysTime(dtBoth2, hnsecs(9_999_999)));
        testST(beforeBoth2, 20_888_888, SysTime(dtBoth2, hnsecs(888_887)));

        {
            auto st = SysTime(dtBoth2, hnsecs(9_999_999));
            st.roll!"hnsecs"(70_777_222).roll!"hnsecs"(-222_555_292);
            assert(st == SysTime(dtBoth2, hnsecs(8_221_929)));
        }

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.roll!"hnsecs"(4)));
        //static assert(!__traits(compiles, ist.roll!"hnsecs"(4)));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF SysTime).

        The legal types of arithmetic for $(LREF SysTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD SysTime) $(TD +) $(TD duration) $(TD -->) $(TD SysTime))
        $(TR $(TD SysTime) $(TD -) $(TD duration) $(TD -->) $(TD SysTime))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF SysTime).
      +/
    SysTime opBinary(string op, D)(in D duration) @safe const pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        import std.format : format;

        SysTime retval = SysTime(this._stdTime, this._timezone);

        static if (is(Unqual!D == Duration))
            immutable hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            immutable hnsecs = duration.hnsecs;

        mixin(format("retval._stdTime %s= hnsecs;", op));
        return retval;
    }

    unittest
    {
        import core.exception : AssertError;

        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_678));

        assert(st + dur!"weeks"(7) == SysTime(DateTime(1999, 8, 24, 12, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"weeks"(-7) == SysTime(DateTime(1999, 5, 18, 12, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"days"(7) == SysTime(DateTime(1999, 7, 13, 12, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"days"(-7) == SysTime(DateTime(1999, 6, 29, 12, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"hours"(7) == SysTime(DateTime(1999, 7, 6, 19, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"hours"(-7) == SysTime(DateTime(1999, 7, 6, 5, 30, 33), hnsecs(2_345_678)));
        assert(st + dur!"minutes"(7) == SysTime(DateTime(1999, 7, 6, 12, 37, 33), hnsecs(2_345_678)));
        assert(st + dur!"minutes"(-7) == SysTime(DateTime(1999, 7, 6, 12, 23, 33), hnsecs(2_345_678)));
        assert(st + dur!"seconds"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 40), hnsecs(2_345_678)));
        assert(st + dur!"seconds"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 26), hnsecs(2_345_678)));
        assert(st + dur!"msecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_415_678)));
        assert(st + dur!"msecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_275_678)));
        assert(st + dur!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_748)));
        assert(st + dur!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_608)));
        assert(st + dur!"hnsecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_685)));
        assert(st + dur!"hnsecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_671)));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(st + TickDuration.from!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_748)));
            assert(st + TickDuration.from!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_608)));
        }

        assert(st - dur!"weeks"(-7) == SysTime(DateTime(1999, 8, 24, 12, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"weeks"(7) == SysTime(DateTime(1999, 5, 18, 12, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"days"(-7) == SysTime(DateTime(1999, 7, 13, 12, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"days"(7) == SysTime(DateTime(1999, 6, 29, 12, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"hours"(-7) == SysTime(DateTime(1999, 7, 6, 19, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"hours"(7) == SysTime(DateTime(1999, 7, 6, 5, 30, 33), hnsecs(2_345_678)));
        assert(st - dur!"minutes"(-7) == SysTime(DateTime(1999, 7, 6, 12, 37, 33), hnsecs(2_345_678)));
        assert(st - dur!"minutes"(7) == SysTime(DateTime(1999, 7, 6, 12, 23, 33), hnsecs(2_345_678)));
        assert(st - dur!"seconds"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 40), hnsecs(2_345_678)));
        assert(st - dur!"seconds"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 26), hnsecs(2_345_678)));
        assert(st - dur!"msecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_415_678)));
        assert(st - dur!"msecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_275_678)));
        assert(st - dur!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_748)));
        assert(st - dur!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_608)));
        assert(st - dur!"hnsecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_685)));
        assert(st - dur!"hnsecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_671)));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(st - TickDuration.from!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_748)));
            assert(st - TickDuration.from!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2_345_608)));
        }

        static void testST(in SysTime orig, long hnsecs, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;
            auto result = orig + dur!"hnsecs"(hnsecs);
            if (result != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", result, expected), __FILE__, line);
        }

        //Test A.D.
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(274));
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(274)));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(275)));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(276)));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(284)));
        testST(beforeAD, 100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(374)));
        testST(beforeAD, 725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(999)));
        testST(beforeAD, 726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1000)));
        testST(beforeAD, 1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1274)));
        testST(beforeAD, 1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1275)));
        testST(beforeAD, 2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2274)));
        testST(beforeAD, 26_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(26_999)));
        testST(beforeAD, 26_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(27_000)));
        testST(beforeAD, 26_727, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(27_001)));
        testST(beforeAD, 1_766_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_766_999)));
        testST(beforeAD, 1_766_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_767_000)));
        testST(beforeAD, 1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_000_274)));
        testST(beforeAD, 60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 39), hnsecs(274)));
        testST(beforeAD, 3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 36, 33), hnsecs(274)));
        testST(beforeAD, 600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 31, 33), hnsecs(274)));
        testST(beforeAD, 36_000_000_000L, SysTime(DateTime(1999, 7, 6, 13, 30, 33), hnsecs(274)));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(273)));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(272)));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(264)));
        testST(beforeAD, -100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(174)));
        testST(beforeAD, -274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_999)));
        testST(beforeAD, -1000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_274)));
        testST(beforeAD, -1001, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_273)));
        testST(beforeAD, -2000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_998_274)));
        testST(beforeAD, -33_274, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_967_000)));
        testST(beforeAD, -33_275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_966_999)));
        testST(beforeAD, -1_833_274, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(8_167_000)));
        testST(beforeAD, -1_833_275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(8_166_999)));
        testST(beforeAD, -1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_000_274)));
        testST(beforeAD, -60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 27), hnsecs(274)));
        testST(beforeAD, -3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 24, 33), hnsecs(274)));
        testST(beforeAD, -600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 29, 33), hnsecs(274)));
        testST(beforeAD, -36_000_000_000L, SysTime(DateTime(1999, 7, 6, 11, 30, 33), hnsecs(274)));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(274));
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(274)));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(275)));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(276)));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(284)));
        testST(beforeBC, 100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(374)));
        testST(beforeBC, 725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(999)));
        testST(beforeBC, 726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1000)));
        testST(beforeBC, 1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1274)));
        testST(beforeBC, 1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1275)));
        testST(beforeBC, 2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(2274)));
        testST(beforeBC, 26_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(26_999)));
        testST(beforeBC, 26_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(27_000)));
        testST(beforeBC, 26_727, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(27_001)));
        testST(beforeBC, 1_766_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_766_999)));
        testST(beforeBC, 1_766_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_767_000)));
        testST(beforeBC, 1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_000_274)));
        testST(beforeBC, 60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 39), hnsecs(274)));
        testST(beforeBC, 3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 36, 33), hnsecs(274)));
        testST(beforeBC, 600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 31, 33), hnsecs(274)));
        testST(beforeBC, 36_000_000_000L, SysTime(DateTime(-1999, 7, 6, 13, 30, 33), hnsecs(274)));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(273)));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(272)));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(264)));
        testST(beforeBC, -100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(174)));
        testST(beforeBC, -274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_999)));
        testST(beforeBC, -1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_274)));
        testST(beforeBC, -1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_273)));
        testST(beforeBC, -2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_998_274)));
        testST(beforeBC, -33_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_967_000)));
        testST(beforeBC, -33_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_966_999)));
        testST(beforeBC, -1_833_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(8_167_000)));
        testST(beforeBC, -1_833_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(8_166_999)));
        testST(beforeBC, -1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_000_274)));
        testST(beforeBC, -60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 27), hnsecs(274)));
        testST(beforeBC, -3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 24, 33), hnsecs(274)));
        testST(beforeBC, -600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 29, 33), hnsecs(274)));
        testST(beforeBC, -36_000_000_000L, SysTime(DateTime(-1999, 7, 6, 11, 30, 33), hnsecs(274)));

        //Test Both
        auto beforeBoth1 = SysTime(DateTime(1, 1, 1, 0, 0, 0));
        testST(beforeBoth1, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(beforeBoth1, 0, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth1, -2, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_998)));
        testST(beforeBoth1, -1000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_000)));
        testST(beforeBoth1, -2000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_998_000)));
        testST(beforeBoth1, -2555, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_997_445)));
        testST(beforeBoth1, -1_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_000_000)));
        testST(beforeBoth1, -2_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(8_000_000)));
        testST(beforeBoth1, -2_333_333, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(7_666_667)));
        testST(beforeBoth1, -10_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59)));
        testST(beforeBoth1, -20_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 58)));
        testST(beforeBoth1, -20_888_888, SysTime(DateTime(0, 12, 31, 23, 59, 57), hnsecs(9_111_112)));

        auto beforeBoth2 = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
        testST(beforeBoth2, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_998)));
        testST(beforeBoth2, 0, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth2, 2, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(beforeBoth2, 1000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(999)));
        testST(beforeBoth2, 2000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1999)));
        testST(beforeBoth2, 2555, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(2554)));
        testST(beforeBoth2, 1_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(999_999)));
        testST(beforeBoth2, 2_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1_999_999)));
        testST(beforeBoth2, 2_333_333, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(2_333_332)));
        testST(beforeBoth2, 10_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        testST(beforeBoth2, 20_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 1), hnsecs(9_999_999)));
        testST(beforeBoth2, 20_888_888, SysTime(DateTime(1, 1, 1, 0, 0, 2), hnsecs(888_887)));

        auto duration = dur!"seconds"(12);
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst + duration));
        //static assert(__traits(compiles, ist + duration));
        static assert(__traits(compiles, cst - duration));
        //static assert(__traits(compiles, ist - duration));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF SysTime), as well as assigning the result to this $(LREF SysTime).

        The legal types of arithmetic for $(LREF SysTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD SysTime) $(TD +) $(TD duration) $(TD -->) $(TD SysTime))
        $(TR $(TD SysTime) $(TD -) $(TD duration) $(TD -->) $(TD SysTime))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF SysTime).
      +/
    ref SysTime opOpAssign(string op, D)(in D duration) @safe pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        import std.format : format;

        static if (is(Unqual!D == Duration))
            auto hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            auto hnsecs = duration.hnsecs;

        mixin(format("_stdTime %s= hnsecs;", op));
        return this;
    }

    unittest
    {
        import core.exception : AssertError;

        auto before = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        assert(before + dur!"weeks"(7) == SysTime(DateTime(1999, 8, 24, 12, 30, 33)));
        assert(before + dur!"weeks"(-7) == SysTime(DateTime(1999, 5, 18, 12, 30, 33)));
        assert(before + dur!"days"(7) == SysTime(DateTime(1999, 7, 13, 12, 30, 33)));
        assert(before + dur!"days"(-7) == SysTime(DateTime(1999, 6, 29, 12, 30, 33)));

        assert(before + dur!"hours"(7) == SysTime(DateTime(1999, 7, 6, 19, 30, 33)));
        assert(before + dur!"hours"(-7) == SysTime(DateTime(1999, 7, 6, 5, 30, 33)));
        assert(before + dur!"minutes"(7) == SysTime(DateTime(1999, 7, 6, 12, 37, 33)));
        assert(before + dur!"minutes"(-7) == SysTime(DateTime(1999, 7, 6, 12, 23, 33)));
        assert(before + dur!"seconds"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 40)));
        assert(before + dur!"seconds"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 26)));
        assert(before + dur!"msecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(7)));
        assert(before + dur!"msecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), msecs(993)));
        assert(before + dur!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(7)));
        assert(before + dur!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), usecs(999_993)));
        assert(before + dur!"hnsecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(7)));
        assert(before + dur!"hnsecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_993)));

        assert(before - dur!"weeks"(-7) == SysTime(DateTime(1999, 8, 24, 12, 30, 33)));
        assert(before - dur!"weeks"(7) == SysTime(DateTime(1999, 5, 18, 12, 30, 33)));
        assert(before - dur!"days"(-7) == SysTime(DateTime(1999, 7, 13, 12, 30, 33)));
        assert(before - dur!"days"(7) == SysTime(DateTime(1999, 6, 29, 12, 30, 33)));

        assert(before - dur!"hours"(-7) == SysTime(DateTime(1999, 7, 6, 19, 30, 33)));
        assert(before - dur!"hours"(7) == SysTime(DateTime(1999, 7, 6, 5, 30, 33)));
        assert(before - dur!"minutes"(-7) == SysTime(DateTime(1999, 7, 6, 12, 37, 33)));
        assert(before - dur!"minutes"(7) == SysTime(DateTime(1999, 7, 6, 12, 23, 33)));
        assert(before - dur!"seconds"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 40)));
        assert(before - dur!"seconds"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 26)));
        assert(before - dur!"msecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), msecs(7)));
        assert(before - dur!"msecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), msecs(993)));
        assert(before - dur!"usecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), usecs(7)));
        assert(before - dur!"usecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), usecs(999_993)));
        assert(before - dur!"hnsecs"(-7) == SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(7)));
        assert(before - dur!"hnsecs"(7) == SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_993)));

        static void testST(SysTime orig, long hnsecs, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;

            auto r = orig += dur!"hnsecs"(hnsecs);
            if (orig != expected)
                throw new AssertError(format("Failed 1. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
            if (r != expected)
                throw new AssertError(format("Failed 2. actual [%s] != expected [%s]", r, expected), __FILE__, line);
        }

        //Test A.D.
        auto beforeAD = SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(274));
        testST(beforeAD, 0, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(274)));
        testST(beforeAD, 1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(275)));
        testST(beforeAD, 2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(276)));
        testST(beforeAD, 10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(284)));
        testST(beforeAD, 100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(374)));
        testST(beforeAD, 725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(999)));
        testST(beforeAD, 726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1000)));
        testST(beforeAD, 1000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1274)));
        testST(beforeAD, 1001, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1275)));
        testST(beforeAD, 2000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(2274)));
        testST(beforeAD, 26_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(26_999)));
        testST(beforeAD, 26_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(27_000)));
        testST(beforeAD, 26_727, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(27_001)));
        testST(beforeAD, 1_766_725, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_766_999)));
        testST(beforeAD, 1_766_726, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_767_000)));
        testST(beforeAD, 1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(1_000_274)));
        testST(beforeAD, 60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 39), hnsecs(274)));
        testST(beforeAD, 3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 36, 33), hnsecs(274)));
        testST(beforeAD, 600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 31, 33), hnsecs(274)));
        testST(beforeAD, 36_000_000_000L, SysTime(DateTime(1999, 7, 6, 13, 30, 33), hnsecs(274)));

        testST(beforeAD, -1, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(273)));
        testST(beforeAD, -2, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(272)));
        testST(beforeAD, -10, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(264)));
        testST(beforeAD, -100, SysTime(DateTime(1999, 7, 6, 12, 30, 33), hnsecs(174)));
        testST(beforeAD, -274, SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        testST(beforeAD, -275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_999)));
        testST(beforeAD, -1000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_274)));
        testST(beforeAD, -1001, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_999_273)));
        testST(beforeAD, -2000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_998_274)));
        testST(beforeAD, -33_274, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_967_000)));
        testST(beforeAD, -33_275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_966_999)));
        testST(beforeAD, -1_833_274, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(8_167_000)));
        testST(beforeAD, -1_833_275, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(8_166_999)));
        testST(beforeAD, -1_000_000, SysTime(DateTime(1999, 7, 6, 12, 30, 32), hnsecs(9_000_274)));
        testST(beforeAD, -60_000_000L, SysTime(DateTime(1999, 7, 6, 12, 30, 27), hnsecs(274)));
        testST(beforeAD, -3_600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 24, 33), hnsecs(274)));
        testST(beforeAD, -600_000_000L, SysTime(DateTime(1999, 7, 6, 12, 29, 33), hnsecs(274)));
        testST(beforeAD, -36_000_000_000L, SysTime(DateTime(1999, 7, 6, 11, 30, 33), hnsecs(274)));

        //Test B.C.
        auto beforeBC = SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(274));
        testST(beforeBC, 0, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(274)));
        testST(beforeBC, 1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(275)));
        testST(beforeBC, 2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(276)));
        testST(beforeBC, 10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(284)));
        testST(beforeBC, 100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(374)));
        testST(beforeBC, 725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(999)));
        testST(beforeBC, 726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1000)));
        testST(beforeBC, 1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1274)));
        testST(beforeBC, 1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1275)));
        testST(beforeBC, 2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(2274)));
        testST(beforeBC, 26_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(26_999)));
        testST(beforeBC, 26_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(27_000)));
        testST(beforeBC, 26_727, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(27_001)));
        testST(beforeBC, 1_766_725, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_766_999)));
        testST(beforeBC, 1_766_726, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_767_000)));
        testST(beforeBC, 1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(1_000_274)));
        testST(beforeBC, 60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 39), hnsecs(274)));
        testST(beforeBC, 3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 36, 33), hnsecs(274)));
        testST(beforeBC, 600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 31, 33), hnsecs(274)));
        testST(beforeBC, 36_000_000_000L, SysTime(DateTime(-1999, 7, 6, 13, 30, 33), hnsecs(274)));

        testST(beforeBC, -1, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(273)));
        testST(beforeBC, -2, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(272)));
        testST(beforeBC, -10, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(264)));
        testST(beforeBC, -100, SysTime(DateTime(-1999, 7, 6, 12, 30, 33), hnsecs(174)));
        testST(beforeBC, -274, SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        testST(beforeBC, -275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_999)));
        testST(beforeBC, -1000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_274)));
        testST(beforeBC, -1001, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_999_273)));
        testST(beforeBC, -2000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_998_274)));
        testST(beforeBC, -33_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_967_000)));
        testST(beforeBC, -33_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_966_999)));
        testST(beforeBC, -1_833_274, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(8_167_000)));
        testST(beforeBC, -1_833_275, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(8_166_999)));
        testST(beforeBC, -1_000_000, SysTime(DateTime(-1999, 7, 6, 12, 30, 32), hnsecs(9_000_274)));
        testST(beforeBC, -60_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 30, 27), hnsecs(274)));
        testST(beforeBC, -3_600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 24, 33), hnsecs(274)));
        testST(beforeBC, -600_000_000L, SysTime(DateTime(-1999, 7, 6, 12, 29, 33), hnsecs(274)));
        testST(beforeBC, -36_000_000_000L, SysTime(DateTime(-1999, 7, 6, 11, 30, 33), hnsecs(274)));

        //Test Both
        auto beforeBoth1 = SysTime(DateTime(1, 1, 1, 0, 0, 0));
        testST(beforeBoth1, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(beforeBoth1, 0, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth1, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth1, -2, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_998)));
        testST(beforeBoth1, -1000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_000)));
        testST(beforeBoth1, -2000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_998_000)));
        testST(beforeBoth1, -2555, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_997_445)));
        testST(beforeBoth1, -1_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_000_000)));
        testST(beforeBoth1, -2_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(8_000_000)));
        testST(beforeBoth1, -2_333_333, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(7_666_667)));
        testST(beforeBoth1, -10_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 59)));
        testST(beforeBoth1, -20_000_000, SysTime(DateTime(0, 12, 31, 23, 59, 58)));
        testST(beforeBoth1, -20_888_888, SysTime(DateTime(0, 12, 31, 23, 59, 57), hnsecs(9_111_112)));

        auto beforeBoth2 = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
        testST(beforeBoth2, -1, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_998)));
        testST(beforeBoth2, 0, SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(beforeBoth2, 1, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(beforeBoth2, 2, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(beforeBoth2, 1000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(999)));
        testST(beforeBoth2, 2000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1999)));
        testST(beforeBoth2, 2555, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(2554)));
        testST(beforeBoth2, 1_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(999_999)));
        testST(beforeBoth2, 2_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1_999_999)));
        testST(beforeBoth2, 2_333_333, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(2_333_332)));
        testST(beforeBoth2, 10_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        testST(beforeBoth2, 20_000_000, SysTime(DateTime(1, 1, 1, 0, 0, 1), hnsecs(9_999_999)));
        testST(beforeBoth2, 20_888_888, SysTime(DateTime(1, 1, 1, 0, 0, 2), hnsecs(888_887)));

        {
            auto st = SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999));
            (st += dur!"hnsecs"(52)) += dur!"seconds"(-907);
            assert(st == SysTime(DateTime(0, 12, 31, 23, 44, 53), hnsecs(51)));
        }

        auto duration = dur!"seconds"(12);
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst += duration));
        //static assert(!__traits(compiles, ist += duration));
        static assert(!__traits(compiles, cst -= duration));
        //static assert(!__traits(compiles, ist -= duration));
    }


    /++
        Gives the difference between two $(LREF SysTime)s.

        The legal types of arithmetic for $(LREF SysTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD SysTime) $(TD -) $(TD SysTime) $(TD -->) $(TD duration))
        )
      +/
    Duration opBinary(string op)(in SysTime rhs) @safe const pure nothrow
        if (op == "-")
    {
        return dur!"hnsecs"(_stdTime - rhs._stdTime);
    }

    unittest
    {
        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1998, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(31_536_000));
        assert(SysTime(DateTime(1998, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(-31_536_000));

        assert(SysTime(DateTime(1999, 8, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(26_78_400));
        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 8, 6, 12, 30, 33)) ==
                    dur!"seconds"(-26_78_400));

        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 5, 12, 30, 33)) ==
                    dur!"seconds"(86_400));
        assert(SysTime(DateTime(1999, 7, 5, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(-86_400));

        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 11, 30, 33)) ==
                    dur!"seconds"(3600));
        assert(SysTime(DateTime(1999, 7, 6, 11, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(-3600));

        assert(SysTime(DateTime(1999, 7, 6, 12, 31, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(60));
        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 31, 33)) ==
                    dur!"seconds"(-60));

        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 34)) - SysTime(DateTime(1999, 7, 6, 12, 30, 33)) ==
                    dur!"seconds"(1));
        assert(SysTime(DateTime(1999, 7, 6, 12, 30, 33)) - SysTime(DateTime(1999, 7, 6, 12, 30, 34)) ==
                    dur!"seconds"(-1));

        {
            auto dt = DateTime(1999, 7, 6, 12, 30, 33);
            assert(SysTime(dt, msecs(532)) - SysTime(dt) == msecs(532));
            assert(SysTime(dt) - SysTime(dt, msecs(532)) == msecs(-532));

            assert(SysTime(dt, usecs(333_347)) - SysTime(dt) == usecs(333_347));
            assert(SysTime(dt) - SysTime(dt, usecs(333_347)) == usecs(-333_347));

            assert(SysTime(dt, hnsecs(1_234_567)) - SysTime(dt) == hnsecs(1_234_567));
            assert(SysTime(dt) - SysTime(dt, hnsecs(1_234_567)) == hnsecs(-1_234_567));
        }

        assert(SysTime(DateTime(1, 1, 1, 12, 30, 33)) - SysTime(DateTime(1, 1, 1, 0, 0, 0)) == dur!"seconds"(45033));
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)) - SysTime(DateTime(1, 1, 1, 12, 30, 33)) == dur!"seconds"(-45033));
        assert(SysTime(DateTime(0, 12, 31, 12, 30, 33)) - SysTime(DateTime(1, 1, 1, 0, 0, 0)) == dur!"seconds"(-41367));
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)) - SysTime(DateTime(0, 12, 31, 12, 30, 33)) == dur!"seconds"(41367));

        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)) - SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)) ==
                        dur!"hnsecs"(1));
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)) - SysTime(DateTime(1, 1, 1, 0, 0, 0)) ==
                        dur!"hnsecs"(-1));

        auto tz = TimeZone.getTimeZone("America/Los_Angeles");

        {
            auto dt = DateTime(2011, 1, 13, 8, 17, 2);
            auto d = msecs(296);
            assert(SysTime(dt, d, tz) - SysTime(dt, d, tz) == Duration.zero);
            assert(SysTime(dt, d, tz) - SysTime(dt, d, UTC()) == hours(8));
            assert(SysTime(dt, d, UTC()) - SysTime(dt, d, tz) == hours(-8));
        }

        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st - st));
        static assert(__traits(compiles, cst - st));
        //static assert(__traits(compiles, ist - st));

        static assert(__traits(compiles, st - cst));
        static assert(__traits(compiles, cst - cst));
        //static assert(__traits(compiles, ist - cst));

        //static assert(__traits(compiles, st - ist));
        //static assert(__traits(compiles, cst - ist));
        //static assert(__traits(compiles, ist - ist));
    }


    /++
        Returns the difference between the two $(LREF SysTime)s in months.

        To get the difference in years, subtract the year property
        of two $(LREF SysTime)s. To get the difference in days or weeks,
        subtract the $(LREF SysTime)s themselves and use the $(CXREF time, Duration)
        that results. Because converting between months and smaller
        units requires a specific date (which $(CXREF time, Duration)s don't have),
        getting the difference in months requires some math using both
        the year and month properties, so this is a convenience function for
        getting the difference in months.

        Note that the number of days in the months or how far into the month
        either date is is irrelevant. It is the difference in the month property
        combined with the difference in years * 12. So, for instance,
        December 31st and January 1st are one month apart just as December 1st
        and January 31st are one month apart.

        Params:
            rhs = The $(LREF SysTime) to subtract from this one.
      +/
    int diffMonths(in SysTime rhs) @safe const nothrow
    {
        return (cast(Date)this).diffMonths(cast(Date)rhs);
    }

    ///
    unittest
    {
        assert(SysTime(Date(1999, 2, 1)).diffMonths(
                    SysTime(Date(1999, 1, 31))) == 1);

        assert(SysTime(Date(1999, 1, 31)).diffMonths(
                    SysTime(Date(1999, 2, 1))) == -1);

        assert(SysTime(Date(1999, 3, 1)).diffMonths(
                    SysTime(Date(1999, 1, 1))) == 2);

        assert(SysTime(Date(1999, 1, 1)).diffMonths(
                    SysTime(Date(1999, 3, 31))) == -2);
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.diffMonths(st)));
        static assert(__traits(compiles, cst.diffMonths(st)));
        //static assert(__traits(compiles, ist.diffMonths(st)));

        static assert(__traits(compiles, st.diffMonths(cst)));
        static assert(__traits(compiles, cst.diffMonths(cst)));
        //static assert(__traits(compiles, ist.diffMonths(cst)));

        //static assert(__traits(compiles, st.diffMonths(ist)));
        //static assert(__traits(compiles, cst.diffMonths(ist)));
        //static assert(__traits(compiles, ist.diffMonths(ist)));
    }


    /++
        Whether this $(LREF SysTime) is in a leap year.
     +/
    @property bool isLeapYear() @safe const nothrow
    {
        return (cast(Date)this).isLeapYear;
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.isLeapYear));
        static assert(__traits(compiles, cst.isLeapYear));
        //static assert(__traits(compiles, ist.isLeapYear));
    }


    /++
        Day of the week this $(LREF SysTime) is on.
      +/
    @property DayOfWeek dayOfWeek() @safe const nothrow
    {
        return getDayOfWeek(dayOfGregorianCal);
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.dayOfWeek));
        static assert(__traits(compiles, cst.dayOfWeek));
        //static assert(__traits(compiles, ist.dayOfWeek));
    }


    /++
        Day of the year this $(LREF SysTime) is on.
      +/
    @property ushort dayOfYear() @safe const nothrow
    {
        return (cast(Date)this).dayOfYear;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 1, 1, 12, 22, 7)).dayOfYear == 1);
        assert(SysTime(DateTime(1999, 12, 31, 7, 2, 59)).dayOfYear == 365);
        assert(SysTime(DateTime(2000, 12, 31, 21, 20, 0)).dayOfYear == 366);
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.dayOfYear));
        static assert(__traits(compiles, cst.dayOfYear));
        //static assert(__traits(compiles, ist.dayOfYear));
    }


    /++
        Day of the year.

        Params:
            day = The day of the year to set which day of the year this
                  $(LREF SysTime) is on.
      +/
    @property void dayOfYear(int day) @safe
    {
        immutable hnsecs = adjTime;
        immutable days = convert!("hnsecs", "days")(hnsecs);
        immutable theRest = hnsecs - convert!("days", "hnsecs")(days);

        auto date = Date(cast(int)days);
        date.dayOfYear = day;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(date.dayOfGregorianCal - 1);

        adjTime = newDaysHNSecs + theRest;
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.dayOfYear = 12));
        static assert(!__traits(compiles, cst.dayOfYear = 12));
        //static assert(!__traits(compiles, ist.dayOfYear = 12));
    }


    /++
        The Xth day of the Gregorian Calendar that this $(LREF SysTime) is on.
     +/
    @property int dayOfGregorianCal() @safe const nothrow
    {
        immutable adjustedTime = adjTime;

        //We have to add one because 0 would be midnight, January 1st, 1 A.D.,
        //which would be the 1st day of the Gregorian Calendar, not the 0th. So,
        //simply casting to days is one day off.
        if (adjustedTime > 0)
            return cast(int)getUnitsFromHNSecs!"days"(adjustedTime) + 1;

        long hnsecs = adjustedTime;
        immutable days = cast(int)splitUnitsFromHNSecs!"days"(hnsecs);

        return hnsecs == 0 ? days + 1 : days;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)).dayOfGregorianCal == 1);
        assert(SysTime(DateTime(1, 12, 31, 23, 59, 59)).dayOfGregorianCal == 365);
        assert(SysTime(DateTime(2, 1, 1, 2, 2, 2)).dayOfGregorianCal == 366);

        assert(SysTime(DateTime(0, 12, 31, 7, 7, 7)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 1, 1, 19, 30, 0)).dayOfGregorianCal == -365);
        assert(SysTime(DateTime(-1, 12, 31, 4, 7, 0)).dayOfGregorianCal == -366);

        assert(SysTime(DateTime(2000, 1, 1, 9, 30, 20)).dayOfGregorianCal == 730_120);
        assert(SysTime(DateTime(2010, 12, 31, 15, 45, 50)).dayOfGregorianCal == 734_137);
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)).dayOfGregorianCal == 1);
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)).dayOfGregorianCal == 1);
        assert(SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)).dayOfGregorianCal == 1);

        assert(SysTime(DateTime(1, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 1);
        assert(SysTime(DateTime(1, 1, 2, 12, 2, 9), msecs(212)).dayOfGregorianCal == 2);
        assert(SysTime(DateTime(1, 2, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 32);
        assert(SysTime(DateTime(2, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 366);
        assert(SysTime(DateTime(3, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 731);
        assert(SysTime(DateTime(4, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 1096);
        assert(SysTime(DateTime(5, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 1462);
        assert(SysTime(DateTime(50, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 17_898);
        assert(SysTime(DateTime(97, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 35_065);
        assert(SysTime(DateTime(100, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 36_160);
        assert(SysTime(DateTime(101, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 36_525);
        assert(SysTime(DateTime(105, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 37_986);
        assert(SysTime(DateTime(200, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 72_684);
        assert(SysTime(DateTime(201, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 73_049);
        assert(SysTime(DateTime(300, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 109_208);
        assert(SysTime(DateTime(301, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 109_573);
        assert(SysTime(DateTime(400, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 145_732);
        assert(SysTime(DateTime(401, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 146_098);
        assert(SysTime(DateTime(500, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 182_257);
        assert(SysTime(DateTime(501, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 182_622);
        assert(SysTime(DateTime(1000, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 364_878);
        assert(SysTime(DateTime(1001, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 365_243);
        assert(SysTime(DateTime(1600, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 584_023);
        assert(SysTime(DateTime(1601, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 584_389);
        assert(SysTime(DateTime(1900, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 693_596);
        assert(SysTime(DateTime(1901, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 693_961);
        assert(SysTime(DateTime(1945, 11, 12, 12, 2, 9), msecs(212)).dayOfGregorianCal == 710_347);
        assert(SysTime(DateTime(1999, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 729_755);
        assert(SysTime(DateTime(2000, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 730_120);
        assert(SysTime(DateTime(2001, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == 730_486);

        assert(SysTime(DateTime(2010, 1, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_773);
        assert(SysTime(DateTime(2010, 1, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_803);
        assert(SysTime(DateTime(2010, 2, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_804);
        assert(SysTime(DateTime(2010, 2, 28, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_831);
        assert(SysTime(DateTime(2010, 3, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_832);
        assert(SysTime(DateTime(2010, 3, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_862);
        assert(SysTime(DateTime(2010, 4, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_863);
        assert(SysTime(DateTime(2010, 4, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_892);
        assert(SysTime(DateTime(2010, 5, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_893);
        assert(SysTime(DateTime(2010, 5, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_923);
        assert(SysTime(DateTime(2010, 6, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_924);
        assert(SysTime(DateTime(2010, 6, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_953);
        assert(SysTime(DateTime(2010, 7, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_954);
        assert(SysTime(DateTime(2010, 7, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_984);
        assert(SysTime(DateTime(2010, 8, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 733_985);
        assert(SysTime(DateTime(2010, 8, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_015);
        assert(SysTime(DateTime(2010, 9, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_016);
        assert(SysTime(DateTime(2010, 9, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_045);
        assert(SysTime(DateTime(2010, 10, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_046);
        assert(SysTime(DateTime(2010, 10, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_076);
        assert(SysTime(DateTime(2010, 11, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_077);
        assert(SysTime(DateTime(2010, 11, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_106);
        assert(SysTime(DateTime(2010, 12, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_107);
        assert(SysTime(DateTime(2010, 12, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == 734_137);

        assert(SysTime(DateTime(2012, 2, 1, 0, 0, 0)).dayOfGregorianCal == 734_534);
        assert(SysTime(DateTime(2012, 2, 28, 0, 0, 0)).dayOfGregorianCal == 734_561);
        assert(SysTime(DateTime(2012, 2, 29, 0, 0, 0)).dayOfGregorianCal == 734_562);
        assert(SysTime(DateTime(2012, 3, 1, 0, 0, 0)).dayOfGregorianCal == 734_563);

        //Test B.C.
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_998)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 12, 31, 0, 0, 0), hnsecs(1)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 12, 31, 0, 0, 0)).dayOfGregorianCal == 0);

        assert(SysTime(DateTime(-1, 12, 31, 23, 59, 59), hnsecs(9_999_999)).dayOfGregorianCal == -366);
        assert(SysTime(DateTime(-1, 12, 31, 23, 59, 59), hnsecs(9_999_998)).dayOfGregorianCal == -366);
        assert(SysTime(DateTime(-1, 12, 31, 23, 59, 59)).dayOfGregorianCal == -366);
        assert(SysTime(DateTime(-1, 12, 31, 0, 0, 0)).dayOfGregorianCal == -366);

        assert(SysTime(DateTime(0, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == 0);
        assert(SysTime(DateTime(0, 12, 30, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1);
        assert(SysTime(DateTime(0, 12, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -30);
        assert(SysTime(DateTime(0, 11, 30, 12, 2, 9), msecs(212)).dayOfGregorianCal == -31);

        assert(SysTime(DateTime(-1, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -366);
        assert(SysTime(DateTime(-1, 12, 30, 12, 2, 9), msecs(212)).dayOfGregorianCal == -367);
        assert(SysTime(DateTime(-1, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -730);
        assert(SysTime(DateTime(-2, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -731);
        assert(SysTime(DateTime(-2, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1095);
        assert(SysTime(DateTime(-3, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1096);
        assert(SysTime(DateTime(-3, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1460);
        assert(SysTime(DateTime(-4, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1461);
        assert(SysTime(DateTime(-4, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1826);
        assert(SysTime(DateTime(-5, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -1827);
        assert(SysTime(DateTime(-5, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -2191);
        assert(SysTime(DateTime(-9, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -3652);

        assert(SysTime(DateTime(-49, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -18_262);
        assert(SysTime(DateTime(-50, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -18_627);
        assert(SysTime(DateTime(-97, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -35_794);
        assert(SysTime(DateTime(-99, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -36_160);
        assert(SysTime(DateTime(-99, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -36_524);
        assert(SysTime(DateTime(-100, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -36_889);
        assert(SysTime(DateTime(-101, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -37_254);
        assert(SysTime(DateTime(-105, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -38_715);
        assert(SysTime(DateTime(-200, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -73_413);
        assert(SysTime(DateTime(-201, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -73_778);
        assert(SysTime(DateTime(-300, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -109_937);
        assert(SysTime(DateTime(-301, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -110_302);
        assert(SysTime(DateTime(-400, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -146_097);
        assert(SysTime(DateTime(-400, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -146_462);
        assert(SysTime(DateTime(-401, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -146_827);
        assert(SysTime(DateTime(-499, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -182_621);
        assert(SysTime(DateTime(-500, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -182_986);
        assert(SysTime(DateTime(-501, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -183_351);
        assert(SysTime(DateTime(-1000, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -365_607);
        assert(SysTime(DateTime(-1001, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -365_972);
        assert(SysTime(DateTime(-1599, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -584_387);
        assert(SysTime(DateTime(-1600, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -584_388);
        assert(SysTime(DateTime(-1600, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -584_753);
        assert(SysTime(DateTime(-1601, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -585_118);
        assert(SysTime(DateTime(-1900, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -694_325);
        assert(SysTime(DateTime(-1901, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -694_690);
        assert(SysTime(DateTime(-1999, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -730_484);
        assert(SysTime(DateTime(-2000, 12, 31, 12, 2, 9), msecs(212)).dayOfGregorianCal == -730_485);
        assert(SysTime(DateTime(-2000, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -730_850);
        assert(SysTime(DateTime(-2001, 1, 1, 12, 2, 9), msecs(212)).dayOfGregorianCal == -731_215);

        assert(SysTime(DateTime(-2010, 1, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_502);
        assert(SysTime(DateTime(-2010, 1, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_472);
        assert(SysTime(DateTime(-2010, 2, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_471);
        assert(SysTime(DateTime(-2010, 2, 28, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_444);
        assert(SysTime(DateTime(-2010, 3, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_443);
        assert(SysTime(DateTime(-2010, 3, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_413);
        assert(SysTime(DateTime(-2010, 4, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_412);
        assert(SysTime(DateTime(-2010, 4, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_383);
        assert(SysTime(DateTime(-2010, 5, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_382);
        assert(SysTime(DateTime(-2010, 5, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_352);
        assert(SysTime(DateTime(-2010, 6, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_351);
        assert(SysTime(DateTime(-2010, 6, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_322);
        assert(SysTime(DateTime(-2010, 7, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_321);
        assert(SysTime(DateTime(-2010, 7, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_291);
        assert(SysTime(DateTime(-2010, 8, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_290);
        assert(SysTime(DateTime(-2010, 8, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_260);
        assert(SysTime(DateTime(-2010, 9, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_259);
        assert(SysTime(DateTime(-2010, 9, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_230);
        assert(SysTime(DateTime(-2010, 10, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_229);
        assert(SysTime(DateTime(-2010, 10, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_199);
        assert(SysTime(DateTime(-2010, 11, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_198);
        assert(SysTime(DateTime(-2010, 11, 30, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_169);
        assert(SysTime(DateTime(-2010, 12, 1, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_168);
        assert(SysTime(DateTime(-2010, 12, 31, 23, 59, 59), msecs(999)).dayOfGregorianCal == -734_138);

        assert(SysTime(DateTime(-2012, 2, 1, 0, 0, 0)).dayOfGregorianCal == -735_202);
        assert(SysTime(DateTime(-2012, 2, 28, 0, 0, 0)).dayOfGregorianCal == -735_175);
        assert(SysTime(DateTime(-2012, 2, 29, 0, 0, 0)).dayOfGregorianCal == -735_174);
        assert(SysTime(DateTime(-2012, 3, 1, 0, 0, 0)).dayOfGregorianCal == -735_173);

        // Start of Hebrew Calendar
        assert(SysTime(DateTime(-3760, 9, 7, 0, 0, 0)).dayOfGregorianCal == -1_373_427);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.dayOfGregorianCal));
        //static assert(__traits(compiles, ist.dayOfGregorianCal));
    }


    //Test that the logic for the day of the Gregorian Calendar is consistent
    //between Date and SysTime.
    unittest
    {
        import core.exception : AssertError;

        void test(Date date, SysTime st, size_t line = __LINE__)
        {
            import std.format : format;

            if (date.dayOfGregorianCal != st.dayOfGregorianCal)
            {
                throw new AssertError(format("Date [%s] SysTime [%s]", date.dayOfGregorianCal, st.dayOfGregorianCal),
                                      __FILE__, line);
            }
        }

        //Test A.D.
        test(Date(1, 1, 1), SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        test(Date(1, 1, 2), SysTime(DateTime(1, 1, 2, 0, 0, 0), hnsecs(500)));
        test(Date(1, 2, 1), SysTime(DateTime(1, 2, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(2, 1, 1), SysTime(DateTime(2, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(3, 1, 1), SysTime(DateTime(3, 1, 1, 12, 13, 14)));
        test(Date(4, 1, 1), SysTime(DateTime(4, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(5, 1, 1), SysTime(DateTime(5, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(50, 1, 1), SysTime(DateTime(50, 1, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(97, 1, 1), SysTime(DateTime(97, 1, 1, 23, 59, 59)));
        test(Date(100, 1, 1), SysTime(DateTime(100, 1, 1, 23, 59, 59), hnsecs(500)));
        test(Date(101, 1, 1), SysTime(DateTime(101, 1, 1, 23, 59, 59), hnsecs(50_000)));
        test(Date(105, 1, 1), SysTime(DateTime(105, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(200, 1, 1), SysTime(DateTime(200, 1, 1, 0, 0, 0)));
        test(Date(201, 1, 1), SysTime(DateTime(201, 1, 1, 0, 0, 0), hnsecs(500)));
        test(Date(300, 1, 1), SysTime(DateTime(300, 1, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(301, 1, 1), SysTime(DateTime(301, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(400, 1, 1), SysTime(DateTime(400, 1, 1, 12, 13, 14)));
        test(Date(401, 1, 1), SysTime(DateTime(401, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(500, 1, 1), SysTime(DateTime(500, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(501, 1, 1), SysTime(DateTime(501, 1, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(1000, 1, 1), SysTime(DateTime(1000, 1, 1, 23, 59, 59)));
        test(Date(1001, 1, 1), SysTime(DateTime(1001, 1, 1, 23, 59, 59), hnsecs(500)));
        test(Date(1600, 1, 1), SysTime(DateTime(1600, 1, 1, 23, 59, 59), hnsecs(50_000)));
        test(Date(1601, 1, 1), SysTime(DateTime(1601, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(1900, 1, 1), SysTime(DateTime(1900, 1, 1, 0, 0, 0)));
        test(Date(1901, 1, 1), SysTime(DateTime(1901, 1, 1, 0, 0, 0), hnsecs(500)));
        test(Date(1945, 11, 12), SysTime(DateTime(1945, 11, 12, 0, 0, 0), hnsecs(50_000)));
        test(Date(1999, 1, 1), SysTime(DateTime(1999, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(1999, 7, 6), SysTime(DateTime(1999, 7, 6, 12, 13, 14)));
        test(Date(2000, 1, 1), SysTime(DateTime(2000, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(2001, 1, 1), SysTime(DateTime(2001, 1, 1, 12, 13, 14), hnsecs(50_000)));

        test(Date(2010, 1, 1), SysTime(DateTime(2010, 1, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(2010, 1, 31), SysTime(DateTime(2010, 1, 31, 23, 0, 0)));
        test(Date(2010, 2, 1), SysTime(DateTime(2010, 2, 1, 23, 59, 59), hnsecs(500)));
        test(Date(2010, 2, 28), SysTime(DateTime(2010, 2, 28, 23, 59, 59), hnsecs(50_000)));
        test(Date(2010, 3, 1), SysTime(DateTime(2010, 3, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(2010, 3, 31), SysTime(DateTime(2010, 3, 31, 0, 0, 0)));
        test(Date(2010, 4, 1), SysTime(DateTime(2010, 4, 1, 0, 0, 0), hnsecs(500)));
        test(Date(2010, 4, 30), SysTime(DateTime(2010, 4, 30, 0, 0, 0), hnsecs(50_000)));
        test(Date(2010, 5, 1), SysTime(DateTime(2010, 5, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(2010, 5, 31), SysTime(DateTime(2010, 5, 31, 12, 13, 14)));
        test(Date(2010, 6, 1), SysTime(DateTime(2010, 6, 1, 12, 13, 14), hnsecs(500)));
        test(Date(2010, 6, 30), SysTime(DateTime(2010, 6, 30, 12, 13, 14), hnsecs(50_000)));
        test(Date(2010, 7, 1), SysTime(DateTime(2010, 7, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(2010, 7, 31), SysTime(DateTime(2010, 7, 31, 23, 59, 59)));
        test(Date(2010, 8, 1), SysTime(DateTime(2010, 8, 1, 23, 59, 59), hnsecs(500)));
        test(Date(2010, 8, 31), SysTime(DateTime(2010, 8, 31, 23, 59, 59), hnsecs(50_000)));
        test(Date(2010, 9, 1), SysTime(DateTime(2010, 9, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(2010, 9, 30), SysTime(DateTime(2010, 9, 30, 12, 0, 0)));
        test(Date(2010, 10, 1), SysTime(DateTime(2010, 10, 1, 0, 12, 0), hnsecs(500)));
        test(Date(2010, 10, 31), SysTime(DateTime(2010, 10, 31, 0, 0, 12), hnsecs(50_000)));
        test(Date(2010, 11, 1), SysTime(DateTime(2010, 11, 1, 23, 0, 0), hnsecs(9_999_999)));
        test(Date(2010, 11, 30), SysTime(DateTime(2010, 11, 30, 0, 59, 0)));
        test(Date(2010, 12, 1), SysTime(DateTime(2010, 12, 1, 0, 0, 59), hnsecs(500)));
        test(Date(2010, 12, 31), SysTime(DateTime(2010, 12, 31, 0, 59, 59), hnsecs(50_000)));

        test(Date(2012, 2, 1), SysTime(DateTime(2012, 2, 1, 23, 0, 59), hnsecs(9_999_999)));
        test(Date(2012, 2, 28), SysTime(DateTime(2012, 2, 28, 23, 59, 0)));
        test(Date(2012, 2, 29), SysTime(DateTime(2012, 2, 29, 7, 7, 7), hnsecs(7)));
        test(Date(2012, 3, 1), SysTime(DateTime(2012, 3, 1, 7, 7, 7), hnsecs(7)));

        //Test B.C.
        test(Date(0, 12, 31), SysTime(DateTime(0, 12, 31, 0, 0, 0)));
        test(Date(0, 12, 30), SysTime(DateTime(0, 12, 30, 0, 0, 0), hnsecs(500)));
        test(Date(0, 12, 1), SysTime(DateTime(0, 12, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(0, 11, 30), SysTime(DateTime(0, 11, 30, 0, 0, 0), hnsecs(9_999_999)));

        test(Date(-1, 12, 31), SysTime(DateTime(-1, 12, 31, 12, 13, 14)));
        test(Date(-1, 12, 30), SysTime(DateTime(-1, 12, 30, 12, 13, 14), hnsecs(500)));
        test(Date(-1, 1, 1), SysTime(DateTime(-1, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(-2, 12, 31), SysTime(DateTime(-2, 12, 31, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(-2, 1, 1), SysTime(DateTime(-2, 1, 1, 23, 59, 59)));
        test(Date(-3, 12, 31), SysTime(DateTime(-3, 12, 31, 23, 59, 59), hnsecs(500)));
        test(Date(-3, 1, 1), SysTime(DateTime(-3, 1, 1, 23, 59, 59), hnsecs(50_000)));
        test(Date(-4, 12, 31), SysTime(DateTime(-4, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(-4, 1, 1), SysTime(DateTime(-4, 1, 1, 0, 0, 0)));
        test(Date(-5, 12, 31), SysTime(DateTime(-5, 12, 31, 0, 0, 0), hnsecs(500)));
        test(Date(-5, 1, 1), SysTime(DateTime(-5, 1, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(-9, 1, 1), SysTime(DateTime(-9, 1, 1, 0, 0, 0), hnsecs(9_999_999)));

        test(Date(-49, 1, 1), SysTime(DateTime(-49, 1, 1, 12, 13, 14)));
        test(Date(-50, 1, 1), SysTime(DateTime(-50, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(-97, 1, 1), SysTime(DateTime(-97, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(-99, 12, 31), SysTime(DateTime(-99, 12, 31, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(-99, 1, 1), SysTime(DateTime(-99, 1, 1, 23, 59, 59)));
        test(Date(-100, 1, 1), SysTime(DateTime(-100, 1, 1, 23, 59, 59), hnsecs(500)));
        test(Date(-101, 1, 1), SysTime(DateTime(-101, 1, 1, 23, 59, 59), hnsecs(50_000)));
        test(Date(-105, 1, 1), SysTime(DateTime(-105, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(-200, 1, 1), SysTime(DateTime(-200, 1, 1, 0, 0, 0)));
        test(Date(-201, 1, 1), SysTime(DateTime(-201, 1, 1, 0, 0, 0), hnsecs(500)));
        test(Date(-300, 1, 1), SysTime(DateTime(-300, 1, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(-301, 1, 1), SysTime(DateTime(-301, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(-400, 12, 31), SysTime(DateTime(-400, 12, 31, 12, 13, 14)));
        test(Date(-400, 1, 1), SysTime(DateTime(-400, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(-401, 1, 1), SysTime(DateTime(-401, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(-499, 1, 1), SysTime(DateTime(-499, 1, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(-500, 1, 1), SysTime(DateTime(-500, 1, 1, 23, 59, 59)));
        test(Date(-501, 1, 1), SysTime(DateTime(-501, 1, 1, 23, 59, 59), hnsecs(500)));
        test(Date(-1000, 1, 1), SysTime(DateTime(-1000, 1, 1, 23, 59, 59), hnsecs(50_000)));
        test(Date(-1001, 1, 1), SysTime(DateTime(-1001, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(-1599, 1, 1), SysTime(DateTime(-1599, 1, 1, 0, 0, 0)));
        test(Date(-1600, 12, 31), SysTime(DateTime(-1600, 12, 31, 0, 0, 0), hnsecs(500)));
        test(Date(-1600, 1, 1), SysTime(DateTime(-1600, 1, 1, 0, 0, 0), hnsecs(50_000)));
        test(Date(-1601, 1, 1), SysTime(DateTime(-1601, 1, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(-1900, 1, 1), SysTime(DateTime(-1900, 1, 1, 12, 13, 14)));
        test(Date(-1901, 1, 1), SysTime(DateTime(-1901, 1, 1, 12, 13, 14), hnsecs(500)));
        test(Date(-1999, 1, 1), SysTime(DateTime(-1999, 1, 1, 12, 13, 14), hnsecs(50_000)));
        test(Date(-1999, 7, 6), SysTime(DateTime(-1999, 7, 6, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(-2000, 12, 31), SysTime(DateTime(-2000, 12, 31, 23, 59, 59)));
        test(Date(-2000, 1, 1), SysTime(DateTime(-2000, 1, 1, 23, 59, 59), hnsecs(500)));
        test(Date(-2001, 1, 1), SysTime(DateTime(-2001, 1, 1, 23, 59, 59), hnsecs(50_000)));

        test(Date(-2010, 1, 1), SysTime(DateTime(-2010, 1, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(-2010, 1, 31), SysTime(DateTime(-2010, 1, 31, 0, 0, 0)));
        test(Date(-2010, 2, 1), SysTime(DateTime(-2010, 2, 1, 0, 0, 0), hnsecs(500)));
        test(Date(-2010, 2, 28), SysTime(DateTime(-2010, 2, 28, 0, 0, 0), hnsecs(50_000)));
        test(Date(-2010, 3, 1), SysTime(DateTime(-2010, 3, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(-2010, 3, 31), SysTime(DateTime(-2010, 3, 31, 12, 13, 14)));
        test(Date(-2010, 4, 1), SysTime(DateTime(-2010, 4, 1, 12, 13, 14), hnsecs(500)));
        test(Date(-2010, 4, 30), SysTime(DateTime(-2010, 4, 30, 12, 13, 14), hnsecs(50_000)));
        test(Date(-2010, 5, 1), SysTime(DateTime(-2010, 5, 1, 12, 13, 14), hnsecs(9_999_999)));
        test(Date(-2010, 5, 31), SysTime(DateTime(-2010, 5, 31, 23, 59, 59)));
        test(Date(-2010, 6, 1), SysTime(DateTime(-2010, 6, 1, 23, 59, 59), hnsecs(500)));
        test(Date(-2010, 6, 30), SysTime(DateTime(-2010, 6, 30, 23, 59, 59), hnsecs(50_000)));
        test(Date(-2010, 7, 1), SysTime(DateTime(-2010, 7, 1, 23, 59, 59), hnsecs(9_999_999)));
        test(Date(-2010, 7, 31), SysTime(DateTime(-2010, 7, 31, 0, 0, 0)));
        test(Date(-2010, 8, 1), SysTime(DateTime(-2010, 8, 1, 0, 0, 0), hnsecs(500)));
        test(Date(-2010, 8, 31), SysTime(DateTime(-2010, 8, 31, 0, 0, 0), hnsecs(50_000)));
        test(Date(-2010, 9, 1), SysTime(DateTime(-2010, 9, 1, 0, 0, 0), hnsecs(9_999_999)));
        test(Date(-2010, 9, 30), SysTime(DateTime(-2010, 9, 30, 12, 0, 0)));
        test(Date(-2010, 10, 1), SysTime(DateTime(-2010, 10, 1, 0, 12, 0), hnsecs(500)));
        test(Date(-2010, 10, 31), SysTime(DateTime(-2010, 10, 31, 0, 0, 12), hnsecs(50_000)));
        test(Date(-2010, 11, 1), SysTime(DateTime(-2010, 11, 1, 23, 0, 0), hnsecs(9_999_999)));
        test(Date(-2010, 11, 30), SysTime(DateTime(-2010, 11, 30, 0, 59, 0)));
        test(Date(-2010, 12, 1), SysTime(DateTime(-2010, 12, 1, 0, 0, 59), hnsecs(500)));
        test(Date(-2010, 12, 31), SysTime(DateTime(-2010, 12, 31, 0, 59, 59), hnsecs(50_000)));

        test(Date(-2012, 2, 1), SysTime(DateTime(-2012, 2, 1, 23, 0, 59), hnsecs(9_999_999)));
        test(Date(-2012, 2, 28), SysTime(DateTime(-2012, 2, 28, 23, 59, 0)));
        test(Date(-2012, 2, 29), SysTime(DateTime(-2012, 2, 29, 7, 7, 7), hnsecs(7)));
        test(Date(-2012, 3, 1), SysTime(DateTime(-2012, 3, 1, 7, 7, 7), hnsecs(7)));

        test(Date(-3760, 9, 7), SysTime(DateTime(-3760, 9, 7, 0, 0, 0)));
    }


    /++
        The Xth day of the Gregorian Calendar that this $(LREF SysTime) is on.
        Setting this property does not affect the time portion of $(LREF SysTime).

        Params:
            days = The day of the Gregorian Calendar to set this $(LREF SysTime)
                   to.
     +/
    @property void dayOfGregorianCal(int days) @safe nothrow
    {
        auto hnsecs = adjTime;
        hnsecs = removeUnitsFromHNSecs!"days"(hnsecs);

        if (hnsecs < 0)
            hnsecs += convert!("hours", "hnsecs")(24);

        if (--days < 0)
        {
            hnsecs -= convert!("hours", "hnsecs")(24);
            ++days;
        }

        immutable newDaysHNSecs = convert!("days", "hnsecs")(days);

        adjTime = newDaysHNSecs + hnsecs;
    }

    ///
    unittest
    {
        auto st = SysTime(DateTime(0, 1, 1, 12, 0, 0));
        st.dayOfGregorianCal = 1;
        assert(st == SysTime(DateTime(1, 1, 1, 12, 0, 0)));

        st.dayOfGregorianCal = 365;
        assert(st == SysTime(DateTime(1, 12, 31, 12, 0, 0)));

        st.dayOfGregorianCal = 366;
        assert(st == SysTime(DateTime(2, 1, 1, 12, 0, 0)));

        st.dayOfGregorianCal = 0;
        assert(st == SysTime(DateTime(0, 12, 31, 12, 0, 0)));

        st.dayOfGregorianCal = -365;
        assert(st == SysTime(DateTime(-0, 1, 1, 12, 0, 0)));

        st.dayOfGregorianCal = -366;
        assert(st == SysTime(DateTime(-1, 12, 31, 12, 0, 0)));

        st.dayOfGregorianCal = 730_120;
        assert(st == SysTime(DateTime(2000, 1, 1, 12, 0, 0)));

        st.dayOfGregorianCal = 734_137;
        assert(st == SysTime(DateTime(2010, 12, 31, 12, 0, 0)));
    }

    unittest
    {
        import core.exception : AssertError;

        void testST(SysTime orig, int day, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;

            orig.dayOfGregorianCal = day;
            if (orig != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", orig, expected), __FILE__, line);
        }

        //Test A.D.
        testST(SysTime(DateTime(1, 1, 1, 0, 0, 0)), 1, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)), 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)), 1,
               SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));

        //Test B.C.
        testST(SysTime(DateTime(0, 1, 1, 0, 0, 0)), 0, SysTime(DateTime(0, 12, 31, 0, 0, 0)));
        testST(SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(9_999_999)), 0,
               SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(SysTime(DateTime(0, 1, 1, 23, 59, 59), hnsecs(1)), 0,
               SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1)));
        testST(SysTime(DateTime(0, 1, 1, 23, 59, 59)), 0, SysTime(DateTime(0, 12, 31, 23, 59, 59)));

        //Test Both.
        testST(SysTime(DateTime(-512, 7, 20, 0, 0, 0)), 1, SysTime(DateTime(1, 1, 1, 0, 0, 0)));
        testST(SysTime(DateTime(-513, 6, 6, 0, 0, 0), hnsecs(1)), 1, SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1)));
        testST(SysTime(DateTime(-511, 5, 7, 23, 59, 59), hnsecs(9_999_999)), 1,
               SysTime(DateTime(1, 1, 1, 23, 59, 59), hnsecs(9_999_999)));

        testST(SysTime(DateTime(1607, 4, 8, 0, 0, 0)), 0, SysTime(DateTime(0, 12, 31, 0, 0, 0)));
        testST(SysTime(DateTime(1500, 3, 9, 23, 59, 59), hnsecs(9_999_999)), 0,
               SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999)));
        testST(SysTime(DateTime(999, 2, 10, 23, 59, 59), hnsecs(1)), 0,
               SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1)));
        testST(SysTime(DateTime(2007, 12, 11, 23, 59, 59)), 0, SysTime(DateTime(0, 12, 31, 23, 59, 59)));


        auto st = SysTime(DateTime(1, 1, 1, 12, 2, 9), msecs(212));

        void testST2(int day, in SysTime expected, size_t line = __LINE__)
        {
            import std.format : format;

            st.dayOfGregorianCal = day;
            if (st != expected)
                throw new AssertError(format("Failed. actual [%s] != expected [%s]", st, expected), __FILE__, line);
        }

        //Test A.D.
        testST2(1, SysTime(DateTime(1, 1, 1, 12, 2, 9), msecs(212)));
        testST2(2, SysTime(DateTime(1, 1, 2, 12, 2, 9), msecs(212)));
        testST2(32, SysTime(DateTime(1, 2, 1, 12, 2, 9), msecs(212)));
        testST2(366, SysTime(DateTime(2, 1, 1, 12, 2, 9), msecs(212)));
        testST2(731, SysTime(DateTime(3, 1, 1, 12, 2, 9), msecs(212)));
        testST2(1096, SysTime(DateTime(4, 1, 1, 12, 2, 9), msecs(212)));
        testST2(1462, SysTime(DateTime(5, 1, 1, 12, 2, 9), msecs(212)));
        testST2(17_898, SysTime(DateTime(50, 1, 1, 12, 2, 9), msecs(212)));
        testST2(35_065, SysTime(DateTime(97, 1, 1, 12, 2, 9), msecs(212)));
        testST2(36_160, SysTime(DateTime(100, 1, 1, 12, 2, 9), msecs(212)));
        testST2(36_525, SysTime(DateTime(101, 1, 1, 12, 2, 9), msecs(212)));
        testST2(37_986, SysTime(DateTime(105, 1, 1, 12, 2, 9), msecs(212)));
        testST2(72_684, SysTime(DateTime(200, 1, 1, 12, 2, 9), msecs(212)));
        testST2(73_049, SysTime(DateTime(201, 1, 1, 12, 2, 9), msecs(212)));
        testST2(109_208, SysTime(DateTime(300, 1, 1, 12, 2, 9), msecs(212)));
        testST2(109_573, SysTime(DateTime(301, 1, 1, 12, 2, 9), msecs(212)));
        testST2(145_732, SysTime(DateTime(400, 1, 1, 12, 2, 9), msecs(212)));
        testST2(146_098, SysTime(DateTime(401, 1, 1, 12, 2, 9), msecs(212)));
        testST2(182_257, SysTime(DateTime(500, 1, 1, 12, 2, 9), msecs(212)));
        testST2(182_622, SysTime(DateTime(501, 1, 1, 12, 2, 9), msecs(212)));
        testST2(364_878, SysTime(DateTime(1000, 1, 1, 12, 2, 9), msecs(212)));
        testST2(365_243, SysTime(DateTime(1001, 1, 1, 12, 2, 9), msecs(212)));
        testST2(584_023, SysTime(DateTime(1600, 1, 1, 12, 2, 9), msecs(212)));
        testST2(584_389, SysTime(DateTime(1601, 1, 1, 12, 2, 9), msecs(212)));
        testST2(693_596, SysTime(DateTime(1900, 1, 1, 12, 2, 9), msecs(212)));
        testST2(693_961, SysTime(DateTime(1901, 1, 1, 12, 2, 9), msecs(212)));
        testST2(729_755, SysTime(DateTime(1999, 1, 1, 12, 2, 9), msecs(212)));
        testST2(730_120, SysTime(DateTime(2000, 1, 1, 12, 2, 9), msecs(212)));
        testST2(730_486, SysTime(DateTime(2001, 1, 1, 12, 2, 9), msecs(212)));

        testST2(733_773, SysTime(DateTime(2010, 1, 1, 12, 2, 9), msecs(212)));
        testST2(733_803, SysTime(DateTime(2010, 1, 31, 12, 2, 9), msecs(212)));
        testST2(733_804, SysTime(DateTime(2010, 2, 1, 12, 2, 9), msecs(212)));
        testST2(733_831, SysTime(DateTime(2010, 2, 28, 12, 2, 9), msecs(212)));
        testST2(733_832, SysTime(DateTime(2010, 3, 1, 12, 2, 9), msecs(212)));
        testST2(733_862, SysTime(DateTime(2010, 3, 31, 12, 2, 9), msecs(212)));
        testST2(733_863, SysTime(DateTime(2010, 4, 1, 12, 2, 9), msecs(212)));
        testST2(733_892, SysTime(DateTime(2010, 4, 30, 12, 2, 9), msecs(212)));
        testST2(733_893, SysTime(DateTime(2010, 5, 1, 12, 2, 9), msecs(212)));
        testST2(733_923, SysTime(DateTime(2010, 5, 31, 12, 2, 9), msecs(212)));
        testST2(733_924, SysTime(DateTime(2010, 6, 1, 12, 2, 9), msecs(212)));
        testST2(733_953, SysTime(DateTime(2010, 6, 30, 12, 2, 9), msecs(212)));
        testST2(733_954, SysTime(DateTime(2010, 7, 1, 12, 2, 9), msecs(212)));
        testST2(733_984, SysTime(DateTime(2010, 7, 31, 12, 2, 9), msecs(212)));
        testST2(733_985, SysTime(DateTime(2010, 8, 1, 12, 2, 9), msecs(212)));
        testST2(734_015, SysTime(DateTime(2010, 8, 31, 12, 2, 9), msecs(212)));
        testST2(734_016, SysTime(DateTime(2010, 9, 1, 12, 2, 9), msecs(212)));
        testST2(734_045, SysTime(DateTime(2010, 9, 30, 12, 2, 9), msecs(212)));
        testST2(734_046, SysTime(DateTime(2010, 10, 1, 12, 2, 9), msecs(212)));
        testST2(734_076, SysTime(DateTime(2010, 10, 31, 12, 2, 9), msecs(212)));
        testST2(734_077, SysTime(DateTime(2010, 11, 1, 12, 2, 9), msecs(212)));
        testST2(734_106, SysTime(DateTime(2010, 11, 30, 12, 2, 9), msecs(212)));
        testST2(734_107, SysTime(DateTime(2010, 12, 1, 12, 2, 9), msecs(212)));
        testST2(734_137, SysTime(DateTime(2010, 12, 31, 12, 2, 9), msecs(212)));

        testST2(734_534, SysTime(DateTime(2012, 2, 1, 12, 2, 9), msecs(212)));
        testST2(734_561, SysTime(DateTime(2012, 2, 28, 12, 2, 9), msecs(212)));
        testST2(734_562, SysTime(DateTime(2012, 2, 29, 12, 2, 9), msecs(212)));
        testST2(734_563, SysTime(DateTime(2012, 3, 1, 12, 2, 9), msecs(212)));

        testST2(734_534,  SysTime(DateTime(2012, 2, 1, 12, 2, 9), msecs(212)));

        testST2(734_561, SysTime(DateTime(2012, 2, 28, 12, 2, 9), msecs(212)));
        testST2(734_562, SysTime(DateTime(2012, 2, 29, 12, 2, 9), msecs(212)));
        testST2(734_563, SysTime(DateTime(2012, 3, 1, 12, 2, 9), msecs(212)));

        //Test B.C.
        testST2(0, SysTime(DateTime(0, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-1, SysTime(DateTime(0, 12, 30, 12, 2, 9), msecs(212)));
        testST2(-30, SysTime(DateTime(0, 12, 1, 12, 2, 9), msecs(212)));
        testST2(-31, SysTime(DateTime(0, 11, 30, 12, 2, 9), msecs(212)));

        testST2(-366, SysTime(DateTime(-1, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-367, SysTime(DateTime(-1, 12, 30, 12, 2, 9), msecs(212)));
        testST2(-730, SysTime(DateTime(-1, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-731, SysTime(DateTime(-2, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-1095, SysTime(DateTime(-2, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-1096, SysTime(DateTime(-3, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-1460, SysTime(DateTime(-3, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-1461, SysTime(DateTime(-4, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-1826, SysTime(DateTime(-4, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-1827, SysTime(DateTime(-5, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-2191, SysTime(DateTime(-5, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-3652, SysTime(DateTime(-9, 1, 1, 12, 2, 9), msecs(212)));

        testST2(-18_262, SysTime(DateTime(-49, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-18_627, SysTime(DateTime(-50, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-35_794, SysTime(DateTime(-97, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-36_160, SysTime(DateTime(-99, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-36_524, SysTime(DateTime(-99, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-36_889, SysTime(DateTime(-100, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-37_254, SysTime(DateTime(-101, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-38_715, SysTime(DateTime(-105, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-73_413, SysTime(DateTime(-200, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-73_778, SysTime(DateTime(-201, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-109_937, SysTime(DateTime(-300, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-110_302, SysTime(DateTime(-301, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-146_097, SysTime(DateTime(-400, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-146_462, SysTime(DateTime(-400, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-146_827, SysTime(DateTime(-401, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-182_621, SysTime(DateTime(-499, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-182_986, SysTime(DateTime(-500, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-183_351, SysTime(DateTime(-501, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-365_607, SysTime(DateTime(-1000, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-365_972, SysTime(DateTime(-1001, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-584_387, SysTime(DateTime(-1599, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-584_388, SysTime(DateTime(-1600, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-584_753, SysTime(DateTime(-1600, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-585_118, SysTime(DateTime(-1601, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-694_325, SysTime(DateTime(-1900, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-694_690, SysTime(DateTime(-1901, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-730_484, SysTime(DateTime(-1999, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-730_485, SysTime(DateTime(-2000, 12, 31, 12, 2, 9), msecs(212)));
        testST2(-730_850, SysTime(DateTime(-2000, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-731_215, SysTime(DateTime(-2001, 1, 1, 12, 2, 9), msecs(212)));

        testST2(-734_502, SysTime(DateTime(-2010, 1, 1, 12, 2, 9), msecs(212)));
        testST2(-734_472, SysTime(DateTime(-2010, 1, 31, 12, 2, 9), msecs(212)));
        testST2(-734_471, SysTime(DateTime(-2010, 2, 1, 12, 2, 9), msecs(212)));
        testST2(-734_444, SysTime(DateTime(-2010, 2, 28, 12, 2, 9), msecs(212)));
        testST2(-734_443, SysTime(DateTime(-2010, 3, 1, 12, 2, 9), msecs(212)));
        testST2(-734_413, SysTime(DateTime(-2010, 3, 31, 12, 2, 9), msecs(212)));
        testST2(-734_412, SysTime(DateTime(-2010, 4, 1, 12, 2, 9), msecs(212)));
        testST2(-734_383, SysTime(DateTime(-2010, 4, 30, 12, 2, 9), msecs(212)));
        testST2(-734_382, SysTime(DateTime(-2010, 5, 1, 12, 2, 9), msecs(212)));
        testST2(-734_352, SysTime(DateTime(-2010, 5, 31, 12, 2, 9), msecs(212)));
        testST2(-734_351, SysTime(DateTime(-2010, 6, 1, 12, 2, 9), msecs(212)));
        testST2(-734_322, SysTime(DateTime(-2010, 6, 30, 12, 2, 9), msecs(212)));
        testST2(-734_321, SysTime(DateTime(-2010, 7, 1, 12, 2, 9), msecs(212)));
        testST2(-734_291, SysTime(DateTime(-2010, 7, 31, 12, 2, 9), msecs(212)));
        testST2(-734_290, SysTime(DateTime(-2010, 8, 1, 12, 2, 9), msecs(212)));
        testST2(-734_260, SysTime(DateTime(-2010, 8, 31, 12, 2, 9), msecs(212)));
        testST2(-734_259, SysTime(DateTime(-2010, 9, 1, 12, 2, 9), msecs(212)));
        testST2(-734_230, SysTime(DateTime(-2010, 9, 30, 12, 2, 9), msecs(212)));
        testST2(-734_229, SysTime(DateTime(-2010, 10, 1, 12, 2, 9), msecs(212)));
        testST2(-734_199, SysTime(DateTime(-2010, 10, 31, 12, 2, 9), msecs(212)));
        testST2(-734_198, SysTime(DateTime(-2010, 11, 1, 12, 2, 9), msecs(212)));
        testST2(-734_169, SysTime(DateTime(-2010, 11, 30, 12, 2, 9), msecs(212)));
        testST2(-734_168, SysTime(DateTime(-2010, 12, 1, 12, 2, 9), msecs(212)));
        testST2(-734_138, SysTime(DateTime(-2010, 12, 31, 12, 2, 9), msecs(212)));

        testST2(-735_202, SysTime(DateTime(-2012, 2, 1, 12, 2, 9), msecs(212)));
        testST2(-735_175, SysTime(DateTime(-2012, 2, 28, 12, 2, 9), msecs(212)));
        testST2(-735_174, SysTime(DateTime(-2012, 2, 29, 12, 2, 9), msecs(212)));
        testST2(-735_173, SysTime(DateTime(-2012, 3, 1, 12, 2, 9), msecs(212)));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(!__traits(compiles, cst.dayOfGregorianCal = 7));
        //static assert(!__traits(compiles, ist.dayOfGregorianCal = 7));
    }


    /++
        The ISO 8601 week of the year that this $(LREF SysTime) is in.

        See_Also:
            $(WEB en.wikipedia.org/wiki/ISO_week_date, ISO Week Date).
      +/
    @property ubyte isoWeek() @safe const nothrow
    {
        return (cast(Date)this).isoWeek;
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.isoWeek));
        static assert(__traits(compiles, cst.isoWeek));
        //static assert(__traits(compiles, ist.isoWeek));
    }


    /++
        $(LREF SysTime) for the last day in the month that this Date is in.
        The time portion of endOfMonth is always 23:59:59.9999999.
      +/
    @property SysTime endOfMonth() @safe const nothrow
    {
        immutable hnsecs = adjTime;
        immutable days = getUnitsFromHNSecs!"days"(hnsecs);

        auto date = Date(cast(int)days + 1).endOfMonth;
        auto newDays = date.dayOfGregorianCal - 1;
        long theTimeHNSecs;

        if (newDays < 0)
        {
            theTimeHNSecs = -1;
            ++newDays;
        }
        else
            theTimeHNSecs = convert!("days", "hnsecs")(1) - 1;

        immutable newDaysHNSecs = convert!("days", "hnsecs")(newDays);

        auto retval = SysTime(this._stdTime, this._timezone);
        retval.adjTime = newDaysHNSecs + theTimeHNSecs;

        return retval;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 1, 6, 0, 0, 0)).endOfMonth ==
               SysTime(DateTime(1999, 1, 31, 23, 59, 59),
                       hnsecs(9_999_999)));

        assert(SysTime(DateTime(1999, 2, 7, 19, 30, 0),
                       msecs(24)).endOfMonth ==
               SysTime(DateTime(1999, 2, 28, 23, 59, 59),
                       hnsecs(9_999_999)));

        assert(SysTime(DateTime(2000, 2, 7, 5, 12, 27),
                       usecs(5203)).endOfMonth ==
               SysTime(DateTime(2000, 2, 29, 23, 59, 59),
                       hnsecs(9_999_999)));

        assert(SysTime(DateTime(2000, 6, 4, 12, 22, 9),
                       hnsecs(12345)).endOfMonth ==
               SysTime(DateTime(2000, 6, 30, 23, 59, 59),
                       hnsecs(9_999_999)));
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(Date(1999, 1, 1)).endOfMonth == SysTime(DateTime(1999, 1, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 2, 1)).endOfMonth == SysTime(DateTime(1999, 2, 28, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(2000, 2, 1)).endOfMonth == SysTime(DateTime(2000, 2, 29, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 3, 1)).endOfMonth == SysTime(DateTime(1999, 3, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 4, 1)).endOfMonth == SysTime(DateTime(1999, 4, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 5, 1)).endOfMonth == SysTime(DateTime(1999, 5, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 6, 1)).endOfMonth == SysTime(DateTime(1999, 6, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 7, 1)).endOfMonth == SysTime(DateTime(1999, 7, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 8, 1)).endOfMonth == SysTime(DateTime(1999, 8, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 9, 1)).endOfMonth == SysTime(DateTime(1999, 9, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 10, 1)).endOfMonth == SysTime(DateTime(1999, 10, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 11, 1)).endOfMonth == SysTime(DateTime(1999, 11, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(1999, 12, 1)).endOfMonth == SysTime(DateTime(1999, 12, 31, 23, 59, 59), hnsecs(9_999_999)));

        //Test B.C.
        assert(SysTime(Date(-1999, 1, 1)).endOfMonth == SysTime(DateTime(-1999, 1, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 2, 1)).endOfMonth == SysTime(DateTime(-1999, 2, 28, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-2000, 2, 1)).endOfMonth == SysTime(DateTime(-2000, 2, 29, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 3, 1)).endOfMonth == SysTime(DateTime(-1999, 3, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 4, 1)).endOfMonth == SysTime(DateTime(-1999, 4, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 5, 1)).endOfMonth == SysTime(DateTime(-1999, 5, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 6, 1)).endOfMonth == SysTime(DateTime(-1999, 6, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 7, 1)).endOfMonth == SysTime(DateTime(-1999, 7, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 8, 1)).endOfMonth == SysTime(DateTime(-1999, 8, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 9, 1)).endOfMonth == SysTime(DateTime(-1999, 9, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 10, 1)).endOfMonth ==
               SysTime(DateTime(-1999, 10, 31, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 11, 1)).endOfMonth ==
               SysTime(DateTime(-1999, 11, 30, 23, 59, 59), hnsecs(9_999_999)));
        assert(SysTime(Date(-1999, 12, 1)).endOfMonth ==
               SysTime(DateTime(-1999, 12, 31, 23, 59, 59), hnsecs(9_999_999)));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.endOfMonth));
        //static assert(__traits(compiles, ist.endOfMonth));
    }


    /++
        The last day in the month that this $(LREF SysTime) is in.
      +/
    @property ubyte daysInMonth() @safe const nothrow
    {
        return Date(dayOfGregorianCal).daysInMonth;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1999, 1, 6, 0, 0, 0)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 2, 7, 19, 30, 0)).daysInMonth == 28);
        assert(SysTime(DateTime(2000, 2, 7, 5, 12, 27)).daysInMonth == 29);
        assert(SysTime(DateTime(2000, 6, 4, 12, 22, 9)).daysInMonth == 30);
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(DateTime(1999, 1, 1, 12, 1, 13)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 2, 1, 17, 13, 12)).daysInMonth == 28);
        assert(SysTime(DateTime(2000, 2, 1, 13, 2, 12)).daysInMonth == 29);
        assert(SysTime(DateTime(1999, 3, 1, 12, 13, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 4, 1, 12, 6, 13)).daysInMonth == 30);
        assert(SysTime(DateTime(1999, 5, 1, 15, 13, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 6, 1, 13, 7, 12)).daysInMonth == 30);
        assert(SysTime(DateTime(1999, 7, 1, 12, 13, 17)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 8, 1, 12, 3, 13)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 9, 1, 12, 13, 12)).daysInMonth == 30);
        assert(SysTime(DateTime(1999, 10, 1, 13, 19, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(1999, 11, 1, 12, 13, 17)).daysInMonth == 30);
        assert(SysTime(DateTime(1999, 12, 1, 12, 52, 13)).daysInMonth == 31);

        //Test B.C.
        assert(SysTime(DateTime(-1999, 1, 1, 12, 1, 13)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 2, 1, 7, 13, 12)).daysInMonth == 28);
        assert(SysTime(DateTime(-2000, 2, 1, 13, 2, 12)).daysInMonth == 29);
        assert(SysTime(DateTime(-1999, 3, 1, 12, 13, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 4, 1, 12, 6, 13)).daysInMonth == 30);
        assert(SysTime(DateTime(-1999, 5, 1, 5, 13, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 6, 1, 13, 7, 12)).daysInMonth == 30);
        assert(SysTime(DateTime(-1999, 7, 1, 12, 13, 17)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 8, 1, 12, 3, 13)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 9, 1, 12, 13, 12)).daysInMonth == 30);
        assert(SysTime(DateTime(-1999, 10, 1, 13, 19, 12)).daysInMonth == 31);
        assert(SysTime(DateTime(-1999, 11, 1, 12, 13, 17)).daysInMonth == 30);
        assert(SysTime(DateTime(-1999, 12, 1, 12, 52, 13)).daysInMonth == 31);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.daysInMonth));
        //static assert(__traits(compiles, ist.daysInMonth));
    }


    /++
        Whether the current year is a date in A.D.
      +/
    @property bool isAD() @safe const nothrow
    {
        return adjTime >= 0;
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(1, 1, 1, 12, 7, 0)).isAD);
        assert(SysTime(DateTime(2010, 12, 31, 0, 0, 0)).isAD);
        assert(!SysTime(DateTime(0, 12, 31, 23, 59, 59)).isAD);
        assert(!SysTime(DateTime(-2010, 1, 1, 2, 2, 2)).isAD);
    }

    unittest
    {
        assert(SysTime(DateTime(2010, 7, 4, 12, 0, 9)).isAD);
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)).isAD);
        assert(!SysTime(DateTime(0, 12, 31, 23, 59, 59)).isAD);
        assert(!SysTime(DateTime(0, 1, 1, 23, 59, 59)).isAD);
        assert(!SysTime(DateTime(-1, 1, 1, 23 ,59 ,59)).isAD);
        assert(!SysTime(DateTime(-2010, 7, 4, 12, 2, 2)).isAD);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.isAD));
        //static assert(__traits(compiles, ist.isAD));
    }


    /++
        The $(WEB en.wikipedia.org/wiki/Julian_day, Julian day)
        for this $(LREF SysTime) at the given time. For example,
        prior to noon, 1996-03-31 would be the Julian day number 2_450_173, so
        this function returns 2_450_173, while from noon onward, the Julian
        day number would be 2_450_174, so this function returns 2_450_174.
      +/
    @property long julianDay() @safe const nothrow
    {
        immutable jd = dayOfGregorianCal + 1_721_425;

        return hour < 12 ? jd - 1 : jd;
    }

    unittest
    {
        assert(SysTime(DateTime(-4713, 11, 24, 0, 0, 0)).julianDay == -1);
        assert(SysTime(DateTime(-4713, 11, 24, 12, 0, 0)).julianDay == 0);

        assert(SysTime(DateTime(0, 12, 31, 0, 0, 0)).julianDay == 1_721_424);
        assert(SysTime(DateTime(0, 12, 31, 12, 0, 0)).julianDay == 1_721_425);

        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0)).julianDay == 1_721_425);
        assert(SysTime(DateTime(1, 1, 1, 12, 0, 0)).julianDay == 1_721_426);

        assert(SysTime(DateTime(1582, 10, 15, 0, 0, 0)).julianDay == 2_299_160);
        assert(SysTime(DateTime(1582, 10, 15, 12, 0, 0)).julianDay == 2_299_161);

        assert(SysTime(DateTime(1858, 11, 17, 0, 0, 0)).julianDay == 2_400_000);
        assert(SysTime(DateTime(1858, 11, 17, 12, 0, 0)).julianDay == 2_400_001);

        assert(SysTime(DateTime(1982, 1, 4, 0, 0, 0)).julianDay == 2_444_973);
        assert(SysTime(DateTime(1982, 1, 4, 12, 0, 0)).julianDay == 2_444_974);

        assert(SysTime(DateTime(1996, 3, 31, 0, 0, 0)).julianDay == 2_450_173);
        assert(SysTime(DateTime(1996, 3, 31, 12, 0, 0)).julianDay == 2_450_174);

        assert(SysTime(DateTime(2010, 8, 24, 0, 0, 0)).julianDay == 2_455_432);
        assert(SysTime(DateTime(2010, 8, 24, 12, 0, 0)).julianDay == 2_455_433);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.julianDay));
        //static assert(__traits(compiles, ist.julianDay));
    }


    /++
        The modified $(WEB en.wikipedia.org/wiki/Julian_day, Julian day) for any time on this date (since, the modified
        Julian day changes at midnight).
      +/
    @property long modJulianDay() @safe const nothrow
    {
        return (dayOfGregorianCal + 1_721_425) - 2_400_001;
    }

    unittest
    {
        assert(SysTime(DateTime(1858, 11, 17, 0, 0, 0)).modJulianDay == 0);
        assert(SysTime(DateTime(1858, 11, 17, 12, 0, 0)).modJulianDay == 0);

        assert(SysTime(DateTime(2010, 8, 24, 0, 0, 0)).modJulianDay == 55_432);
        assert(SysTime(DateTime(2010, 8, 24, 12, 0, 0)).modJulianDay == 55_432);

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cst.modJulianDay));
        //static assert(__traits(compiles, ist.modJulianDay));
    }


    /++
        Returns a $(LREF Date) equivalent to this $(LREF SysTime).
      +/
    Date opCast(T)() @safe const nothrow
        if (is(Unqual!T == Date))
    {
        return Date(dayOfGregorianCal);
    }

    unittest
    {
        assert(cast(Date)SysTime(Date(1999, 7, 6)) == Date(1999, 7, 6));
        assert(cast(Date)SysTime(Date(2000, 12, 31)) == Date(2000, 12, 31));
        assert(cast(Date)SysTime(Date(2001, 1, 1)) == Date(2001, 1, 1));

        assert(cast(Date)SysTime(DateTime(1999, 7, 6, 12, 10, 9)) == Date(1999, 7, 6));
        assert(cast(Date)SysTime(DateTime(2000, 12, 31, 13, 11, 10)) == Date(2000, 12, 31));
        assert(cast(Date)SysTime(DateTime(2001, 1, 1, 14, 12, 11)) == Date(2001, 1, 1));

        assert(cast(Date)SysTime(Date(-1999, 7, 6)) == Date(-1999, 7, 6));
        assert(cast(Date)SysTime(Date(-2000, 12, 31)) == Date(-2000, 12, 31));
        assert(cast(Date)SysTime(Date(-2001, 1, 1)) == Date(-2001, 1, 1));

        assert(cast(Date)SysTime(DateTime(-1999, 7, 6, 12, 10, 9)) == Date(-1999, 7, 6));
        assert(cast(Date)SysTime(DateTime(-2000, 12, 31, 13, 11, 10)) == Date(-2000, 12, 31));
        assert(cast(Date)SysTime(DateTime(-2001, 1, 1, 14, 12, 11)) == Date(-2001, 1, 1));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(Date)cst));
        //static assert(__traits(compiles, cast(Date)ist));
    }


    /++
        Returns a $(LREF DateTime) equivalent to this $(LREF SysTime).
      +/
    DateTime opCast(T)() @safe const nothrow
        if (is(Unqual!T == DateTime))
    {
        scope(failure) assert(0, "Either DateTime's constructor or TimeOfDay's constructor threw.");

        auto hnsecs = adjTime;
        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable second = getUnitsFromHNSecs!"seconds"(hnsecs);

        return DateTime(Date(cast(int)days), TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second));
    }

    unittest
    {
        assert(cast(DateTime)SysTime(DateTime(1, 1, 6, 7, 12, 22)) == DateTime(1, 1, 6, 7, 12, 22));
        assert(cast(DateTime)SysTime(DateTime(1, 1, 6, 7, 12, 22), msecs(22)) == DateTime(1, 1, 6, 7, 12, 22));
        assert(cast(DateTime)SysTime(Date(1999, 7, 6)) == DateTime(1999, 7, 6, 0, 0, 0));
        assert(cast(DateTime)SysTime(Date(2000, 12, 31)) == DateTime(2000, 12, 31, 0, 0, 0));
        assert(cast(DateTime)SysTime(Date(2001, 1, 1)) == DateTime(2001, 1, 1, 0, 0, 0));

        assert(cast(DateTime)SysTime(DateTime(1999, 7, 6, 12, 10, 9)) == DateTime(1999, 7, 6, 12, 10, 9));
        assert(cast(DateTime)SysTime(DateTime(2000, 12, 31, 13, 11, 10)) == DateTime(2000, 12, 31, 13, 11, 10));
        assert(cast(DateTime)SysTime(DateTime(2001, 1, 1, 14, 12, 11)) == DateTime(2001, 1, 1, 14, 12, 11));

        assert(cast(DateTime)SysTime(DateTime(-1, 1, 6, 7, 12, 22)) == DateTime(-1, 1, 6, 7, 12, 22));
        assert(cast(DateTime)SysTime(DateTime(-1, 1, 6, 7, 12, 22), msecs(22)) == DateTime(-1, 1, 6, 7, 12, 22));
        assert(cast(DateTime)SysTime(Date(-1999, 7, 6)) == DateTime(-1999, 7, 6, 0, 0, 0));
        assert(cast(DateTime)SysTime(Date(-2000, 12, 31)) == DateTime(-2000, 12, 31, 0, 0, 0));
        assert(cast(DateTime)SysTime(Date(-2001, 1, 1)) == DateTime(-2001, 1, 1, 0, 0, 0));

        assert(cast(DateTime)SysTime(DateTime(-1999, 7, 6, 12, 10, 9)) == DateTime(-1999, 7, 6, 12, 10, 9));
        assert(cast(DateTime)SysTime(DateTime(-2000, 12, 31, 13, 11, 10)) == DateTime(-2000, 12, 31, 13, 11, 10));
        assert(cast(DateTime)SysTime(DateTime(-2001, 1, 1, 14, 12, 11)) == DateTime(-2001, 1, 1, 14, 12, 11));

        assert(cast(DateTime)SysTime(DateTime(2011, 1, 13, 8, 17, 2), msecs(296), LocalTime()) ==
               DateTime(2011, 1, 13, 8, 17, 2));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(DateTime)cst));
        //static assert(__traits(compiles, cast(DateTime)ist));
    }


    /++
        Returns a $(LREF TimeOfDay) equivalent to this $(LREF SysTime).
      +/
    TimeOfDay opCast(T)() @safe const nothrow
        if (is(Unqual!T == TimeOfDay))
    {
        scope(failure) assert(0, "TimeOfDay's constructor threw.");

        auto hnsecs = adjTime;
        hnsecs = removeUnitsFromHNSecs!"days"(hnsecs);

        if (hnsecs < 0)
            hnsecs += convert!("hours", "hnsecs")(24);

        immutable hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable second = getUnitsFromHNSecs!"seconds"(hnsecs);

        return TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second);
    }

    unittest
    {
        assert(cast(TimeOfDay)SysTime(Date(1999, 7, 6)) == TimeOfDay(0, 0, 0));
        assert(cast(TimeOfDay)SysTime(Date(2000, 12, 31)) == TimeOfDay(0, 0, 0));
        assert(cast(TimeOfDay)SysTime(Date(2001, 1, 1)) == TimeOfDay(0, 0, 0));

        assert(cast(TimeOfDay)SysTime(DateTime(1999, 7, 6, 12, 10, 9)) == TimeOfDay(12, 10, 9));
        assert(cast(TimeOfDay)SysTime(DateTime(2000, 12, 31, 13, 11, 10)) == TimeOfDay(13, 11, 10));
        assert(cast(TimeOfDay)SysTime(DateTime(2001, 1, 1, 14, 12, 11)) == TimeOfDay(14, 12, 11));

        assert(cast(TimeOfDay)SysTime(Date(-1999, 7, 6)) == TimeOfDay(0, 0, 0));
        assert(cast(TimeOfDay)SysTime(Date(-2000, 12, 31)) == TimeOfDay(0, 0, 0));
        assert(cast(TimeOfDay)SysTime(Date(-2001, 1, 1)) == TimeOfDay(0, 0, 0));

        assert(cast(TimeOfDay)SysTime(DateTime(-1999, 7, 6, 12, 10, 9)) == TimeOfDay(12, 10, 9));
        assert(cast(TimeOfDay)SysTime(DateTime(-2000, 12, 31, 13, 11, 10)) == TimeOfDay(13, 11, 10));
        assert(cast(TimeOfDay)SysTime(DateTime(-2001, 1, 1, 14, 12, 11)) == TimeOfDay(14, 12, 11));

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(TimeOfDay)cst));
        //static assert(__traits(compiles, cast(TimeOfDay)ist));
    }


    //Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=4867 is fixed.
    //This allows assignment from const(SysTime) to SysTime.
    //It may be a good idea to keep it though, since casting from a type to itself
    //should be allowed, and it doesn't work without this opCast() since opCast()
    //has already been defined for other types.
    SysTime opCast(T)() @safe const pure nothrow
        if (is(Unqual!T == SysTime))
    {
        return SysTime(_stdTime, _timezone);
    }


    /++
        Converts this $(LREF SysTime) to a string with the format
        YYYYMMDDTHHMMSS.FFFFFFFTZ (where F is fractional seconds and TZ is time
        zone).

        Note that the number of digits in the fractional seconds varies with the
        number of fractional seconds. It's a maximum of 7 (which would be
        hnsecs), but only has as many as are necessary to hold the correct value
        (so no trailing zeroes), and if there are no fractional seconds, then
        there is no decimal point.

        If this $(LREF SysTime)'s time zone is $(LREF LocalTime), then TZ is empty.
        If its time zone is $(D UTC), then it is "Z". Otherwise, it is the
        offset from UTC (e.g. +1:00 or -7:00). Note that the offset from UTC
        is $(I not) enough to uniquely identify the time zone.

        Time zone offsets will be in the form +HH:MM or -HH:MM.
      +/
    string toISOString() @safe const nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");

        immutable adjustedTime = adjTime;
        long hnsecs = adjustedTime;

        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        auto minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        auto second = splitUnitsFromHNSecs!"seconds"(hnsecs);

        auto dateTime = DateTime(Date(cast(int)days), TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second));
        auto fracSecStr = fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is LocalTime())
            return dateTime.toISOString() ~ fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is UTC())
            return dateTime.toISOString() ~ fracSecsToISOString(cast(int)hnsecs) ~ "Z";

        immutable utcOffset = dur!"hnsecs"(adjustedTime - stdTime);

        return format("%s%s%s",
                      dateTime.toISOString(),
                      fracSecsToISOString(cast(int)hnsecs),
                      SimpleTimeZone.toISOString(utcOffset));
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(2010, 7, 4, 7, 6, 12)).toISOString() ==
               "20100704T070612");

        assert(SysTime(DateTime(1998, 12, 25, 2, 15, 0),
                       msecs(24)).toISOString() ==
               "19981225T021500.024");

        assert(SysTime(DateTime(0, 1, 5, 23, 9, 59)).toISOString() ==
               "00000105T230959");

        assert(SysTime(DateTime(-4, 1, 5, 0, 0, 2),
                       hnsecs(520_920)).toISOString() ==
               "-00040105T000002.052092");
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(DateTime.init, UTC()).toISOString() == "00010101T000000Z");
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1), UTC()).toISOString() == "00010101T000000.0000001Z");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0)).toISOString() == "00091204T000000");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12)).toISOString() == "00991204T050612");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59)).toISOString() == "09991204T134459");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59)).toISOString() == "99990704T235959");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1)).toISOString() == "+100001020T010101");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0), msecs(42)).toISOString() == "00091204T000000.042");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12), msecs(100)).toISOString() == "00991204T050612.1");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59), usecs(45020)).toISOString() == "09991204T134459.04502");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59), hnsecs(12)).toISOString() == "99990704T235959.0000012");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1), hnsecs(507890)).toISOString() == "+100001020T010101.050789");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                                 new immutable SimpleTimeZone(dur!"minutes"(-360))).toISOString() ==
                        "20121221T121212-06:00");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                                 new immutable SimpleTimeZone(dur!"minutes"(420))).toISOString() ==
                        "20121221T121212+07:00");

        //Test B.C.
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()).toISOString() ==
               "00001231T235959.9999999Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1), UTC()).toISOString() == "00001231T235959.0000001Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), UTC()).toISOString() == "00001231T235959Z");

        assert(SysTime(DateTime(0, 12, 4, 0, 12, 4)).toISOString() == "00001204T001204");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0)).toISOString() == "-00091204T000000");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12)).toISOString() == "-00991204T050612");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59)).toISOString() == "-09991204T134459");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59)).toISOString() == "-99990704T235959");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1)).toISOString() == "-100001020T010101");

        assert(SysTime(DateTime(0, 12, 4, 0, 0, 0), msecs(7)).toISOString() == "00001204T000000.007");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0), msecs(42)).toISOString() == "-00091204T000000.042");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12), msecs(100)).toISOString() == "-00991204T050612.1");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59), usecs(45020)).toISOString() == "-09991204T134459.04502");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59), hnsecs(12)).toISOString() == "-99990704T235959.0000012");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1), hnsecs(507890)).toISOString() == "-100001020T010101.050789");

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(TimeOfDay)cst));
        //static assert(__traits(compiles, cast(TimeOfDay)ist));
    }



    /++
        Converts this $(LREF SysTime) to a string with the format
        YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ (where F is fractional seconds and TZ
        is the time zone).

        Note that the number of digits in the fractional seconds varies with the
        number of fractional seconds. It's a maximum of 7 (which would be
        hnsecs), but only has as many as are necessary to hold the correct value
        (so no trailing zeroes), and if there are no fractional seconds, then
        there is no decimal point.

        If this $(LREF SysTime)'s time zone is $(LREF LocalTime), then TZ is empty. If
        its time zone is $(D UTC), then it is "Z". Otherwise, it is the offset
        from UTC (e.g. +1:00 or -7:00). Note that the offset from UTC is
        $(I not) enough to uniquely identify the time zone.

        Time zone offsets will be in the form +HH:MM or -HH:MM.
      +/
    string toISOExtString() @safe const nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");

        immutable adjustedTime = adjTime;
        long hnsecs = adjustedTime;

        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        auto minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        auto second = splitUnitsFromHNSecs!"seconds"(hnsecs);

        auto dateTime = DateTime(Date(cast(int)days), TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second));
        auto fracSecStr = fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is LocalTime())
            return dateTime.toISOExtString() ~ fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is UTC())
            return dateTime.toISOExtString() ~ fracSecsToISOString(cast(int)hnsecs) ~ "Z";

        immutable utcOffset = dur!"hnsecs"(adjustedTime - stdTime);

        return format("%s%s%s",
                      dateTime.toISOExtString(),
                      fracSecsToISOString(cast(int)hnsecs),
                      SimpleTimeZone.toISOString(utcOffset));
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(2010, 7, 4, 7, 6, 12)).toISOExtString() ==
               "2010-07-04T07:06:12");

        assert(SysTime(DateTime(1998, 12, 25, 2, 15, 0),
                       msecs(24)).toISOExtString() ==
               "1998-12-25T02:15:00.024");

        assert(SysTime(DateTime(0, 1, 5, 23, 9, 59)).toISOExtString() ==
               "0000-01-05T23:09:59");

        assert(SysTime(DateTime(-4, 1, 5, 0, 0, 2),
                       hnsecs(520_920)).toISOExtString() ==
               "-0004-01-05T00:00:02.052092");
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(DateTime.init, UTC()).toISOExtString() == "0001-01-01T00:00:00Z");
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1), UTC()).toISOExtString() ==
               "0001-01-01T00:00:00.0000001Z");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0)).toISOExtString() == "0009-12-04T00:00:00");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12)).toISOExtString() == "0099-12-04T05:06:12");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59)).toISOExtString() == "0999-12-04T13:44:59");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59)).toISOExtString() == "9999-07-04T23:59:59");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1)).toISOExtString() == "+10000-10-20T01:01:01");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0), msecs(42)).toISOExtString() == "0009-12-04T00:00:00.042");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12), msecs(100)).toISOExtString() == "0099-12-04T05:06:12.1");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59), usecs(45020)).toISOExtString() == "0999-12-04T13:44:59.04502");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59), hnsecs(12)).toISOExtString() == "9999-07-04T23:59:59.0000012");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1), hnsecs(507890)).toISOExtString() ==
               "+10000-10-20T01:01:01.050789");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                                new immutable SimpleTimeZone(dur!"minutes"(-360))).toISOExtString() ==
               "2012-12-21T12:12:12-06:00");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                       new immutable SimpleTimeZone(dur!"minutes"(420))).toISOExtString() ==
               "2012-12-21T12:12:12+07:00");

        //Test B.C.
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()).toISOExtString() ==
               "0000-12-31T23:59:59.9999999Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1), UTC()).toISOExtString() ==
               "0000-12-31T23:59:59.0000001Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), UTC()).toISOExtString() == "0000-12-31T23:59:59Z");

        assert(SysTime(DateTime(0, 12, 4, 0, 12, 4)).toISOExtString() == "0000-12-04T00:12:04");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0)).toISOExtString() == "-0009-12-04T00:00:00");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12)).toISOExtString() == "-0099-12-04T05:06:12");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59)).toISOExtString() == "-0999-12-04T13:44:59");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59)).toISOExtString() == "-9999-07-04T23:59:59");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1)).toISOExtString() == "-10000-10-20T01:01:01");

        assert(SysTime(DateTime(0, 12, 4, 0, 0, 0), msecs(7)).toISOExtString() == "0000-12-04T00:00:00.007");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0), msecs(42)).toISOExtString() == "-0009-12-04T00:00:00.042");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12), msecs(100)).toISOExtString() == "-0099-12-04T05:06:12.1");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59), usecs(45020)).toISOExtString() ==
               "-0999-12-04T13:44:59.04502");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59), hnsecs(12)).toISOExtString() ==
               "-9999-07-04T23:59:59.0000012");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1), hnsecs(507890)).toISOExtString() ==
               "-10000-10-20T01:01:01.050789");

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(TimeOfDay)cst));
        //static assert(__traits(compiles, cast(TimeOfDay)ist));
    }

    /++
        Converts this $(LREF SysTime) to a string with the format
        YYYY-Mon-DD HH:MM:SS.FFFFFFFTZ (where F is fractional seconds and TZ
        is the time zone).

        Note that the number of digits in the fractional seconds varies with the
        number of fractional seconds. It's a maximum of 7 (which would be
        hnsecs), but only has as many as are necessary to hold the correct value
        (so no trailing zeroes), and if there are no fractional seconds, then
        there is no decimal point.

        If this $(LREF SysTime)'s time zone is $(LREF LocalTime), then TZ is empty. If
        its time zone is $(D UTC), then it is "Z". Otherwise, it is the offset
        from UTC (e.g. +1:00 or -7:00). Note that the offset from UTC is
        $(I not) enough to uniquely identify the time zone.

        Time zone offsets will be in the form +HH:MM or -HH:MM.
      +/
    string toSimpleString() @safe const nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");

        immutable adjustedTime = adjTime;
        long hnsecs = adjustedTime;

        auto days = splitUnitsFromHNSecs!"days"(hnsecs) + 1;

        if (hnsecs < 0)
        {
            hnsecs += convert!("hours", "hnsecs")(24);
            --days;
        }

        auto hour = splitUnitsFromHNSecs!"hours"(hnsecs);
        auto minute = splitUnitsFromHNSecs!"minutes"(hnsecs);
        auto second = splitUnitsFromHNSecs!"seconds"(hnsecs);

        auto dateTime = DateTime(Date(cast(int)days), TimeOfDay(cast(int)hour, cast(int)minute, cast(int)second));
        auto fracSecStr = fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is LocalTime())
            return dateTime.toSimpleString() ~ fracSecsToISOString(cast(int)hnsecs);

        if (_timezone is UTC())
            return dateTime.toSimpleString() ~ fracSecsToISOString(cast(int)hnsecs) ~ "Z";

        immutable utcOffset = dur!"hnsecs"(adjustedTime - stdTime);

        return format("%s%s%s",
                      dateTime.toSimpleString(),
                      fracSecsToISOString(cast(int)hnsecs),
                      SimpleTimeZone.toISOString(utcOffset));
    }

    ///
    unittest
    {
        assert(SysTime(DateTime(2010, 7, 4, 7, 6, 12)).toSimpleString() ==
               "2010-Jul-04 07:06:12");

        assert(SysTime(DateTime(1998, 12, 25, 2, 15, 0),
                       msecs(24)).toSimpleString() ==
               "1998-Dec-25 02:15:00.024");

        assert(SysTime(DateTime(0, 1, 5, 23, 9, 59)).toSimpleString() ==
               "0000-Jan-05 23:09:59");

        assert(SysTime(DateTime(-4, 1, 5, 0, 0, 2),
                       hnsecs(520_920)).toSimpleString() ==
                "-0004-Jan-05 00:00:02.052092");
    }

    unittest
    {
        //Test A.D.
        assert(SysTime(DateTime.init, UTC()).toString() == "0001-Jan-01 00:00:00Z");
        assert(SysTime(DateTime(1, 1, 1, 0, 0, 0), hnsecs(1), UTC()).toString() == "0001-Jan-01 00:00:00.0000001Z");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0)).toSimpleString() == "0009-Dec-04 00:00:00");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12)).toSimpleString() == "0099-Dec-04 05:06:12");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59)).toSimpleString() == "0999-Dec-04 13:44:59");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59)).toSimpleString() == "9999-Jul-04 23:59:59");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1)).toSimpleString() == "+10000-Oct-20 01:01:01");

        assert(SysTime(DateTime(9, 12, 4, 0, 0, 0), msecs(42)).toSimpleString() == "0009-Dec-04 00:00:00.042");
        assert(SysTime(DateTime(99, 12, 4, 5, 6, 12), msecs(100)).toSimpleString() == "0099-Dec-04 05:06:12.1");
        assert(SysTime(DateTime(999, 12, 4, 13, 44, 59), usecs(45020)).toSimpleString() ==
               "0999-Dec-04 13:44:59.04502");
        assert(SysTime(DateTime(9999, 7, 4, 23, 59, 59), hnsecs(12)).toSimpleString() ==
               "9999-Jul-04 23:59:59.0000012");
        assert(SysTime(DateTime(10000, 10, 20, 1, 1, 1), hnsecs(507890)).toSimpleString() ==
               "+10000-Oct-20 01:01:01.050789");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                       new immutable SimpleTimeZone(dur!"minutes"(-360))).toSimpleString() ==
               "2012-Dec-21 12:12:12-06:00");

        assert(SysTime(DateTime(2012, 12, 21, 12, 12, 12),
                       new immutable SimpleTimeZone(dur!"minutes"(420))).toSimpleString() ==
               "2012-Dec-21 12:12:12+07:00");

        //Test B.C.
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(9_999_999), UTC()).toSimpleString() ==
               "0000-Dec-31 23:59:59.9999999Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), hnsecs(1), UTC()).toSimpleString() ==
               "0000-Dec-31 23:59:59.0000001Z");
        assert(SysTime(DateTime(0, 12, 31, 23, 59, 59), UTC()).toSimpleString() == "0000-Dec-31 23:59:59Z");

        assert(SysTime(DateTime(0, 12, 4, 0, 12, 4)).toSimpleString() == "0000-Dec-04 00:12:04");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0)).toSimpleString() == "-0009-Dec-04 00:00:00");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12)).toSimpleString() == "-0099-Dec-04 05:06:12");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59)).toSimpleString() == "-0999-Dec-04 13:44:59");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59)).toSimpleString() == "-9999-Jul-04 23:59:59");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1)).toSimpleString() == "-10000-Oct-20 01:01:01");

        assert(SysTime(DateTime(0, 12, 4, 0, 0, 0), msecs(7)).toSimpleString() == "0000-Dec-04 00:00:00.007");
        assert(SysTime(DateTime(-9, 12, 4, 0, 0, 0), msecs(42)).toSimpleString() == "-0009-Dec-04 00:00:00.042");
        assert(SysTime(DateTime(-99, 12, 4, 5, 6, 12), msecs(100)).toSimpleString() == "-0099-Dec-04 05:06:12.1");
        assert(SysTime(DateTime(-999, 12, 4, 13, 44, 59), usecs(45020)).toSimpleString() ==
               "-0999-Dec-04 13:44:59.04502");
        assert(SysTime(DateTime(-9999, 7, 4, 23, 59, 59), hnsecs(12)).toSimpleString() ==
               "-9999-Jul-04 23:59:59.0000012");
        assert(SysTime(DateTime(-10000, 10, 20, 1, 1, 1), hnsecs(507890)).toSimpleString() ==
               "-10000-Oct-20 01:01:01.050789");

        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, cast(TimeOfDay)cst));
        //static assert(__traits(compiles, cast(TimeOfDay)ist));
    }


    /++
        Converts this $(LREF SysTime) to a string.
      +/
    string toString() @safe const nothrow
    {
        return toSimpleString();
    }

    unittest
    {
        auto st = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        const cst = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        //immutable ist = SysTime(DateTime(1999, 7, 6, 12, 30, 33));
        static assert(__traits(compiles, st.toString()));
        static assert(__traits(compiles, cst.toString()));
        //static assert(__traits(compiles, ist.toString()));
    }


    /++
        Creates a $(LREF SysTime) from a string with the format
        YYYYMMDDTHHMMSS.FFFFFFFTZ (where F is fractional seconds is the time
        zone). Whitespace is stripped from the given string.

        The exact format is exactly as described in $(D toISOString) except that
        trailing zeroes are permitted - including having fractional seconds with
        all zeroes. However, a decimal point with nothing following it is
        invalid.

        If there is no time zone in the string, then $(LREF LocalTime) is used. If
        the time zone is "Z", then $(D UTC) is used. Otherwise, a
        $(LREF SimpleTimeZone) which corresponds to the given offset from UTC is
        used. To get the returned $(LREF SysTime) to be a particular time
        zone, pass in that time zone and the $(LREF SysTime) to be returned
        will be converted to that time zone (though it will still be read in as
        whatever time zone is in its string).

        The accepted formats for time zone offsets
        are +H, -H, +HH, -HH, +H:MM, -H:MM, +HH:MM, and -HH:MM.

        Params:
            isoString = A string formatted in the ISO format for dates and times.
            tz        = The time zone to convert the given time to (no
                        conversion occurs if null).

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF SysTime) would not be valid.
      +/
    static SysTime fromISOString(S)(in S isoString, immutable TimeZone tz = null) @safe
        if (isSomeString!S)
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : startsWith, find;
        import std.format : format;

        auto dstr = to!dstring(strip(isoString));
        immutable skipFirst = dstr.startsWith('+', '-') != 0;

        auto found = (skipFirst ? dstr[1..$] : dstr).find('.', 'Z', '+', '-');
        auto dateTimeStr = dstr[0 .. $ - found[0].length];

        dstring fracSecStr;
        dstring zoneStr;

        if (found[1] != 0)
        {
            if (found[1] == 1)
            {
                auto foundTZ = found[0].find('Z', '+', '-');

                if (foundTZ[1] != 0)
                {
                    fracSecStr = found[0][0 .. $ - foundTZ[0].length];
                    zoneStr = foundTZ[0];
                }
                else
                    fracSecStr = found[0];
            }
            else
                zoneStr = found[0];
        }

        try
        {
            auto dateTime = DateTime.fromISOString(dateTimeStr);
            auto fracSec = fracSecsFromISOString(fracSecStr);
            Rebindable!(immutable TimeZone) parsedZone;

            if (zoneStr.empty)
                parsedZone = LocalTime();
            else if (zoneStr == "Z")
                parsedZone = UTC();
            else
                parsedZone = SimpleTimeZone.fromISOString(zoneStr);

            auto retval = SysTime(dateTime, fracSec, parsedZone);

            if (tz !is null)
                retval.timezone = tz;

            return retval;
        }
        catch (DateTimeException dte)
            throw new DateTimeException(format("Invalid ISO String: %s", isoString));
    }

    ///
    unittest
    {
        assert(SysTime.fromISOString("20100704T070612") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));
        assert(SysTime.fromISOString("19981225T021500.007") ==
               SysTime(DateTime(1998, 12, 25, 2, 15, 0), msecs(7)));
        assert(SysTime.fromISOString("00000105T230959.00002") ==
               SysTime(DateTime(0, 1, 5, 23, 9, 59), usecs(20)));
        assert(SysTime.fromISOString("-00040105T000002") ==
               SysTime(DateTime(-4, 1, 5, 0, 0, 2)));
        assert(SysTime.fromISOString(" 20100704T070612 ") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));

        assert(SysTime.fromISOString("20100704T070612Z") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12), UTC()));
        assert(SysTime.fromISOString("20100704T070612-8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(-8))));
        assert(SysTime.fromISOString("20100704T070612+8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(8))));
    }

    unittest
    {
        assertThrown!DateTimeException(SysTime.fromISOString(""));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704000000"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704 000000"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704t000000"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000."));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000.A"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000.Z"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000.00000000"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000.00000000"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000+"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000-"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000:"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000-:"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000+:"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000-1:"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000+1:"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000+1:0"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000-24.00"));
        assertThrown!DateTimeException(SysTime.fromISOString("20100704T000000+24.00"));

        assertThrown!DateTimeException(SysTime.fromISOString("2010-07-0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-07-04T00:00:00."));

        assertThrown!DateTimeException(SysTime.fromISOString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-Jul-04 00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-Jul-04T00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-Jul-04 00:00:00."));

        assertThrown!DateTimeException(SysTime.fromISOString("2010-12-22T172201"));
        assertThrown!DateTimeException(SysTime.fromISOString("2010-Dec-22 17:22:01"));

        assert(SysTime.fromISOString("20101222T172201") == SysTime(DateTime(2010, 12, 22, 17, 22, 01)));
        assert(SysTime.fromISOString("19990706T123033") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOString("-19990706T123033") == SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOString("+019990706T123033") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOString("19990706T123033 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOString(" 19990706T123033") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOString(" 19990706T123033 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));

        assert(SysTime.fromISOString("19070707T121212.0") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromISOString("19070707T121212.0000000") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromISOString("19070707T121212.0000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), hnsecs(1)));
        assert(SysTime.fromISOString("19070707T121212.000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromISOString("19070707T121212.0000010") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromISOString("19070707T121212.001") == SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));
        assert(SysTime.fromISOString("19070707T121212.0010000") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));

        assert(SysTime.fromISOString("20101222T172201Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), UTC()));
        assert(SysTime.fromISOString("20101222T172201-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOString("20101222T172201-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOString("20101222T172201-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromISOString("20101222T172201-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromISOString("20101222T172201+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOString("20101222T172201+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOString("20101222T172201+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromISOString("20101222T172201+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(480))));

        assert(SysTime.fromISOString("20101103T065106.57159Z") ==
               SysTime(DateTime(2010, 11, 3, 6, 51, 6), hnsecs(5715900), UTC()));

        assert(SysTime.fromISOString("20101222T172201.23412Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_341_200), UTC()));
        assert(SysTime.fromISOString("20101222T172201.23112-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_311_200),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOString("20101222T172201.45-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOString("20101222T172201.1-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_000_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromISOString("20101222T172201.55-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(5_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromISOString("20101222T172201.1234567+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_234_567),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOString("20101222T172201.0+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOString("20101222T172201.0000000+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromISOString("20101222T172201.45+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(480))));
    }


    /++
        Creates a $(LREF SysTime) from a string with the format
        YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ (where F is fractional seconds is the
        time zone). Whitespace is stripped from the given string.

        The exact format is exactly as described in $(D toISOExtString)
        except that trailing zeroes are permitted - including having fractional
        seconds with all zeroes. However, a decimal point with nothing following
        it is invalid.

        If there is no time zone in the string, then $(LREF LocalTime) is used. If
        the time zone is "Z", then $(D UTC) is used. Otherwise, a
        $(LREF SimpleTimeZone) which corresponds to the given offset from UTC is
        used. To get the returned $(LREF SysTime) to be a particular time
        zone, pass in that time zone and the $(LREF SysTime) to be returned
        will be converted to that time zone (though it will still be read in as
        whatever time zone is in its string).

        The accepted formats for time zone offsets
        are +H, -H, +HH, -HH, +H:MM, -H:MM, +HH:MM, and -HH:MM.

        Params:
            isoExtString = A string formatted in the ISO Extended format for dates
                           and times.
            tz           = The time zone to convert the given time to (no
                           conversion occurs if null).

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF SysTime) would not be valid.
      +/
    static SysTime fromISOExtString(S)(in S isoExtString, immutable TimeZone tz = null) @safe
        if (isSomeString!(S))
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : countUntil, find;
        import std.format : format;

        auto dstr = to!dstring(strip(isoExtString));

        auto tIndex = dstr.countUntil('T');
        enforce(tIndex != -1, new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        auto found = dstr[tIndex + 1 .. $].find('.', 'Z', '+', '-');
        auto dateTimeStr = dstr[0 .. $ - found[0].length];

        dstring fracSecStr;
        dstring zoneStr;

        if (found[1] != 0)
        {
            if (found[1] == 1)
            {
                auto foundTZ = found[0].find('Z', '+', '-');

                if (foundTZ[1] != 0)
                {
                    fracSecStr = found[0][0 .. $ - foundTZ[0].length];
                    zoneStr = foundTZ[0];
                }
                else
                    fracSecStr = found[0];
            }
            else
                zoneStr = found[0];
        }

        try
        {
            auto dateTime = DateTime.fromISOExtString(dateTimeStr);
            auto fracSec = fracSecsFromISOString(fracSecStr);
            Rebindable!(immutable TimeZone) parsedZone;

            if (zoneStr.empty)
                parsedZone = LocalTime();
            else if (zoneStr == "Z")
                parsedZone = UTC();
            else
                parsedZone = SimpleTimeZone.fromISOString(zoneStr);

            auto retval = SysTime(dateTime, fracSec, parsedZone);

            if (tz !is null)
                retval.timezone = tz;

            return retval;
        }
        catch (DateTimeException dte)
            throw new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString));
    }

    ///
    unittest
    {
        assert(SysTime.fromISOExtString("2010-07-04T07:06:12") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));
        assert(SysTime.fromISOExtString("1998-12-25T02:15:00.007") ==
               SysTime(DateTime(1998, 12, 25, 2, 15, 0), msecs(7)));
        assert(SysTime.fromISOExtString("0000-01-05T23:09:59.00002") ==
               SysTime(DateTime(0, 1, 5, 23, 9, 59), usecs(20)));
        assert(SysTime.fromISOExtString("-0004-01-05T00:00:02") ==
               SysTime(DateTime(-4, 1, 5, 0, 0, 2)));
        assert(SysTime.fromISOExtString(" 2010-07-04T07:06:12 ") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));

        assert(SysTime.fromISOExtString("2010-07-04T07:06:12Z") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12), UTC()));
        assert(SysTime.fromISOExtString("2010-07-04T07:06:12-8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(-8))));
        assert(SysTime.fromISOExtString("2010-07-04T07:06:12+8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(8))));
    }

    unittest
    {
        assertThrown!DateTimeException(SysTime.fromISOExtString(""));
        assertThrown!DateTimeException(SysTime.fromISOExtString("20100704000000"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("20100704 000000"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("20100704t000000"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("20100704T000000."));
        assertThrown!DateTimeException(SysTime.fromISOExtString("20100704T000000.0"));

        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07:0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00."));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00.A"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00.Z"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00.00000000"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00.00000000"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00+"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00-"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00:"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00-:"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00+:"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00-1:"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00+1:"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00+1:0"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00-24.00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-07-04T00:00:00+24.00"));

        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-Jul-04 00:00:00."));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-Jul-04 00:00:00.0"));

        assertThrown!DateTimeException(SysTime.fromISOExtString("20101222T172201"));
        assertThrown!DateTimeException(SysTime.fromISOExtString("2010-Dec-22 17:22:01"));

        assert(SysTime.fromISOExtString("2010-12-22T17:22:01") == SysTime(DateTime(2010, 12, 22, 17, 22, 01)));
        assert(SysTime.fromISOExtString("1999-07-06T12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOExtString("-1999-07-06T12:30:33") == SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOExtString("+01999-07-06T12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOExtString("1999-07-06T12:30:33 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOExtString(" 1999-07-06T12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromISOExtString(" 1999-07-06T12:30:33 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));

        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.0") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.0000000") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.0000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), hnsecs(1)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.0000010") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));
        assert(SysTime.fromISOExtString("1907-07-07T12:12:12.0010000") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));

        assert(SysTime.fromISOExtString("2010-12-22T17:22:01Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), UTC()));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(480))));

        assert(SysTime.fromISOExtString("2010-11-03T06:51:06.57159Z") ==
               SysTime(DateTime(2010, 11, 3, 6, 51, 6), hnsecs(5715900), UTC()));

        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.23412Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_341_200), UTC()));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.23112-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_311_200),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.45-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.1-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_000_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.55-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(5_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.1234567+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_234_567),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.0+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.0000000+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromISOExtString("2010-12-22T17:22:01.45+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(480))));
    }


    /++
        Creates a $(LREF SysTime) from a string with the format
        YYYY-MM-DD HH:MM:SS.FFFFFFFTZ (where F is fractional seconds is the
        time zone). Whitespace is stripped from the given string.

        The exact format is exactly as described in $(D toSimpleString) except
        that trailing zeroes are permitted - including having fractional seconds
        with all zeroes. However, a decimal point with nothing following it is
        invalid.

        If there is no time zone in the string, then $(LREF LocalTime) is used. If
        the time zone is "Z", then $(D UTC) is used. Otherwise, a
        $(LREF SimpleTimeZone) which corresponds to the given offset from UTC is
        used. To get the returned $(LREF SysTime) to be a particular time
        zone, pass in that time zone and the $(LREF SysTime) to be returned
        will be converted to that time zone (though it will still be read in as
        whatever time zone is in its string).

        The accepted formats for time zone offsets
        are +H, -H, +HH, -HH, +H:MM, -H:MM, +HH:MM, and -HH:MM.


        Params:
            simpleString = A string formatted in the way that
                           $(D toSimpleString) formats dates and times.
            tz           = The time zone to convert the given time to (no
                           conversion occurs if null).

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF SysTime) would not be valid.
      +/
    static SysTime fromSimpleString(S)(in S simpleString, immutable TimeZone tz = null) @safe
        if (isSomeString!(S))
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : countUntil, find;
        import std.format : format;

        auto dstr = to!dstring(strip(simpleString));

        auto spaceIndex = dstr.countUntil(' ');
        enforce(spaceIndex != -1, new DateTimeException(format("Invalid Simple String: %s", simpleString)));

        auto found = dstr[spaceIndex + 1 .. $].find('.', 'Z', '+', '-');
        auto dateTimeStr = dstr[0 .. $ - found[0].length];

        dstring fracSecStr;
        dstring zoneStr;

        if (found[1] != 0)
        {
            if (found[1] == 1)
            {
                auto foundTZ = found[0].find('Z', '+', '-');

                if (foundTZ[1] != 0)
                {
                    fracSecStr = found[0][0 .. $ - foundTZ[0].length];
                    zoneStr = foundTZ[0];
                }
                else
                    fracSecStr = found[0];
            }
            else
                zoneStr = found[0];
        }

        try
        {
            auto dateTime = DateTime.fromSimpleString(dateTimeStr);
            auto fracSec = fracSecsFromISOString(fracSecStr);
            Rebindable!(immutable TimeZone) parsedZone;

            if (zoneStr.empty)
                parsedZone = LocalTime();
            else if (zoneStr == "Z")
                parsedZone = UTC();
            else
                parsedZone = SimpleTimeZone.fromISOString(zoneStr);

            auto retval = SysTime(dateTime, fracSec, parsedZone);

            if (tz !is null)
                retval.timezone = tz;

            return retval;
        }
        catch (DateTimeException dte)
            throw new DateTimeException(format("Invalid Simple String: %s", simpleString));
    }

    ///
    unittest
    {
        assert(SysTime.fromSimpleString("2010-Jul-04 07:06:12") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));
        assert(SysTime.fromSimpleString("1998-Dec-25 02:15:00.007") ==
               SysTime(DateTime(1998, 12, 25, 2, 15, 0), msecs(7)));
        assert(SysTime.fromSimpleString("0000-Jan-05 23:09:59.00002") ==
               SysTime(DateTime(0, 1, 5, 23, 9, 59), usecs(20)));
        assert(SysTime.fromSimpleString("-0004-Jan-05 00:00:02") ==
               SysTime(DateTime(-4, 1, 5, 0, 0, 2)));
        assert(SysTime.fromSimpleString(" 2010-Jul-04 07:06:12 ") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12)));

        assert(SysTime.fromSimpleString("2010-Jul-04 07:06:12Z") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12), UTC()));
        assert(SysTime.fromSimpleString("2010-Jul-04 07:06:12-8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(-8))));
        assert(SysTime.fromSimpleString("2010-Jul-04 07:06:12+8:00") ==
               SysTime(DateTime(2010, 7, 4, 7, 6, 12),
                       new immutable SimpleTimeZone(dur!"hours"(8))));
    }

    unittest
    {
        assertThrown!DateTimeException(SysTime.fromSimpleString(""));
        assertThrown!DateTimeException(SysTime.fromSimpleString("20100704000000"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("20100704 000000"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("20100704t000000"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("20100704T000000."));
        assertThrown!DateTimeException(SysTime.fromSimpleString("20100704T000000.0"));

        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-07-0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-07-04T00:00:00."));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-07-04T00:00:00.0"));

        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04T00:00:00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00."));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00.A"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00.Z"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00.00000000"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00.00000000"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00+"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00-"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00:"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00-:"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00+:"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00-1:"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00+1:"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00+1:0"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00-24.00"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-Jul-04 00:00:00+24.00"));

        assertThrown!DateTimeException(SysTime.fromSimpleString("20101222T172201"));
        assertThrown!DateTimeException(SysTime.fromSimpleString("2010-12-22T172201"));

        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01") == SysTime(DateTime(2010, 12, 22, 17, 22, 01)));
        assert(SysTime.fromSimpleString("1999-Jul-06 12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromSimpleString("-1999-Jul-06 12:30:33") == SysTime(DateTime(-1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromSimpleString("+01999-Jul-06 12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromSimpleString("1999-Jul-06 12:30:33 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromSimpleString(" 1999-Jul-06 12:30:33") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));
        assert(SysTime.fromSimpleString(" 1999-Jul-06 12:30:33 ") == SysTime(DateTime(1999, 7, 6, 12, 30, 33)));

        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.0") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.0000000") == SysTime(DateTime(1907, 07, 07, 12, 12, 12)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.0000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), hnsecs(1)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.000001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.0000010") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), usecs(1)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.001") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));
        assert(SysTime.fromSimpleString("1907-Jul-07 12:12:12.0010000") ==
               SysTime(DateTime(1907, 07, 07, 12, 12, 12), msecs(1)));

        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), UTC()));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), new immutable SimpleTimeZone(dur!"minutes"(480))));

        assert(SysTime.fromSimpleString("2010-Nov-03 06:51:06.57159Z") ==
               SysTime(DateTime(2010, 11, 3, 6, 51, 6), hnsecs(5715900), UTC()));

        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.23412Z") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_341_200), UTC()));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.23112-1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(2_311_200),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.45-1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.1-1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_000_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-90))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.55-8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(5_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(-480))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.1234567+1:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(1_234_567),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.0+1") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(60))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.0000000+1:30") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01),
                       new immutable SimpleTimeZone(dur!"minutes"(90))));
        assert(SysTime.fromSimpleString("2010-Dec-22 17:22:01.45+8:00") ==
               SysTime(DateTime(2010, 12, 22, 17, 22, 01), hnsecs(4_500_000),
                       new immutable SimpleTimeZone(dur!"minutes"(480))));
    }


    /++
        Returns the $(LREF SysTime) farthest in the past which is representable
        by $(LREF SysTime).

        The $(LREF SysTime) which is returned is in UTC.
      +/
    @property static SysTime min() @safe pure nothrow
    {
        return SysTime(long.min, UTC());
    }

    unittest
    {
        assert(SysTime.min.year < 0);
        assert(SysTime.min < SysTime.max);
    }


    /++
        Returns the $(LREF SysTime) farthest in the future which is representable
        by $(LREF SysTime).

        The $(LREF SysTime) which is returned is in UTC.
      +/
    @property static SysTime max() @safe pure nothrow
    {
        return SysTime(long.max, UTC());
    }

    unittest
    {
        assert(SysTime.max.year > 0);
        assert(SysTime.max > SysTime.min);
    }


private:

    /+
        Returns $(D stdTime) converted to $(LREF SysTime)'s time zone.
      +/
    @property long adjTime() @safe const nothrow
    {
        return _timezone.utcToTZ(_stdTime);
    }


    /+
        Converts the given hnsecs from $(LREF SysTime)'s time zone to std time.
      +/
    @property void adjTime(long adjTime) @safe nothrow
    {
        _stdTime = _timezone.tzToUTC(adjTime);
    }


    //Commented out due to bug http://d.puremagic.com/issues/show_bug.cgi?id=5058
    /+
    invariant()
    {
        assert(_timezone !is null, "Invariant Failure: timezone is null. Were you foolish enough to use SysTime.init? (since timezone for SysTime.init can't be set at compile time).");
    }
    +/


    long  _stdTime;
    Rebindable!(immutable TimeZone) _timezone;
}


/++
    Represents a date in the
    $(WEB en.wikipedia.org/wiki/Proleptic_Gregorian_calendar, Proleptic Gregorian Calendar)
    ranging from
    32,768 B.C. to 32,767 A.D. Positive years are A.D. Non-positive years are
    B.C.

    Year, month, and day are kept separately internally so that $(D Date) is
    optimized for calendar-based operations.

    $(D Date) uses the Proleptic Gregorian Calendar, so it assumes the Gregorian
    leap year calculations for its entire length. As per
    $(WEB en.wikipedia.org/wiki/ISO_8601, ISO 8601), it treats 1 B.C. as
    year 0, i.e. 1 B.C. is 0, 2 B.C. is -1, etc. Use $(LREF yearBC) to use B.C. as
    a positive integer with 1 B.C. being the year prior to 1 A.D.

    Year 0 is a leap year.
 +/
struct Date
{
    import std.exception : enforce;
    import std.format : format;

public:

    /++
        Throws:
            $(LREF DateTimeException) if the resulting $(LREF Date) would not be valid.

        Params:
            year  = Year of the Gregorian Calendar. Positive values are A.D.
                    Non-positive values are B.C. with year 0 being the year
                    prior to 1 A.D.
            month = Month of the year.
            day   = Day of the month.
     +/
    this(int year, int month, int day) @safe pure
    {
        enforceValid!"months"(cast(Month)month);
        enforceValid!"days"(year, cast(Month)month, day);

        _year  = cast(short)year;
        _month = cast(Month)month;
        _day   = cast(ubyte)day;
    }

    unittest
    {
        assert(Date(1, 1, 1) == Date.init);

        static void testDate(in Date date, int year, int month, int day)
        {
            assert(date._year == year);
            assert(date._month == month);
            assert(date._day == day);
        }

        testDate(Date(1999, 1 , 1), 1999, Month.jan, 1);
        testDate(Date(1999, 7 , 1), 1999, Month.jul, 1);
        testDate(Date(1999, 7 , 6), 1999, Month.jul, 6);

        //Test A.D.
        assertThrown!DateTimeException(Date(   1,  0,  1));
        assertThrown!DateTimeException(Date(   1,  1,  0));
        assertThrown!DateTimeException(Date(1999, 13,  1));
        assertThrown!DateTimeException(Date(1999,  1, 32));
        assertThrown!DateTimeException(Date(1999,  2, 29));
        assertThrown!DateTimeException(Date(2000,  2, 30));
        assertThrown!DateTimeException(Date(1999,  3, 32));
        assertThrown!DateTimeException(Date(1999,  4, 31));
        assertThrown!DateTimeException(Date(1999,  5, 32));
        assertThrown!DateTimeException(Date(1999,  6, 31));
        assertThrown!DateTimeException(Date(1999,  7, 32));
        assertThrown!DateTimeException(Date(1999,  8, 32));
        assertThrown!DateTimeException(Date(1999,  9, 31));
        assertThrown!DateTimeException(Date(1999, 10, 32));
        assertThrown!DateTimeException(Date(1999, 11, 31));
        assertThrown!DateTimeException(Date(1999, 12, 32));

        assertNotThrown!DateTimeException(Date(1999,  1, 31));
        assertNotThrown!DateTimeException(Date(1999,  2, 28));
        assertNotThrown!DateTimeException(Date(2000,  2, 29));
        assertNotThrown!DateTimeException(Date(1999,  3, 31));
        assertNotThrown!DateTimeException(Date(1999,  4, 30));
        assertNotThrown!DateTimeException(Date(1999,  5, 31));
        assertNotThrown!DateTimeException(Date(1999,  6, 30));
        assertNotThrown!DateTimeException(Date(1999,  7, 31));
        assertNotThrown!DateTimeException(Date(1999,  8, 31));
        assertNotThrown!DateTimeException(Date(1999,  9, 30));
        assertNotThrown!DateTimeException(Date(1999, 10, 31));
        assertNotThrown!DateTimeException(Date(1999, 11, 30));
        assertNotThrown!DateTimeException(Date(1999, 12, 31));

        //Test B.C.
        assertNotThrown!DateTimeException(Date( 0,  1,  1));
        assertNotThrown!DateTimeException(Date(-1,  1,  1));
        assertNotThrown!DateTimeException(Date(-1, 12, 31));
        assertNotThrown!DateTimeException(Date(-1,  2, 28));
        assertNotThrown!DateTimeException(Date(-4,  2, 29));

        assertThrown!DateTimeException(Date(-1, 2, 29));
        assertThrown!DateTimeException(Date(-2, 2, 29));
        assertThrown!DateTimeException(Date(-3, 2, 29));
    }


    /++
        Params:
            day = The Xth day of the Gregorian Calendar that the constructed
                  $(LREF Date) will be for.
     +/
    this(int day) @safe pure nothrow
    {
        if (day > 0)
        {
            int years = (day / daysIn400Years) * 400 + 1;
            day %= daysIn400Years;

            {
                immutable tempYears = day / daysIn100Years;

                if (tempYears == 4)
                {
                    years += 300;
                    day -= daysIn100Years * 3;
                }
                else
                {
                    years += tempYears * 100;
                    day %= daysIn100Years;
                }
            }

            years += (day / daysIn4Years) * 4;
            day %= daysIn4Years;

            {
                immutable tempYears = day / daysInYear;

                if (tempYears == 4)
                {
                    years += 3;
                    day -= daysInYear * 3;
                }
                else
                {
                    years += tempYears;
                    day %= daysInYear;
                }
            }

            if (day == 0)
            {
                _year = cast(short)(years - 1);
                _month = Month.dec;
                _day = 31;
            }
            else
            {
                _year = cast(short)years;

                scope(failure) assert(0, "dayOfYear assignment threw.");
                dayOfYear = day;
            }
        }
        else if (day <= 0 && -day < daysInLeapYear)
        {
            _year = 0;

            scope(failure) assert(0, "dayOfYear assignment threw.");
            dayOfYear = (daysInLeapYear + day);
        }
        else
        {
            day += daysInLeapYear - 1;
            int years = (day / daysIn400Years) * 400 - 1;
            day %= daysIn400Years;

            {
                immutable tempYears = day / daysIn100Years;

                if (tempYears == -4)
                {
                    years -= 300;
                    day += daysIn100Years * 3;
                }
                else
                {
                    years += tempYears * 100;
                    day %= daysIn100Years;
                }
            }

            years += (day / daysIn4Years) * 4;
            day %= daysIn4Years;

            {
                immutable tempYears = day / daysInYear;

                if (tempYears == -4)
                {
                    years -= 3;
                    day += daysInYear * 3;
                }
                else
                {
                    years += tempYears;
                    day %= daysInYear;
                }
            }

            if (day == 0)
            {
                _year = cast(short)(years + 1);
                _month = Month.jan;
                _day = 1;
            }
            else
            {
                _year = cast(short)years;
                immutable newDoY = (yearIsLeapYear(_year) ? daysInLeapYear : daysInYear) + day + 1;

                scope(failure) assert(0, "dayOfYear assignment threw.");
                dayOfYear = newDoY;
            }
        }
    }

    unittest
    {
        import std.range;

        //Test A.D.
        foreach (gd; chain(testGregDaysBC, testGregDaysAD))
            assert(Date(gd.day) == gd.date);
    }


    /++
        Compares this $(LREF Date) with the given $(LREF Date).

        Returns:
            $(BOOKTABLE,
            $(TR $(TD this &lt; rhs) $(TD &lt; 0))
            $(TR $(TD this == rhs) $(TD 0))
            $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(in Date rhs) @safe const pure nothrow
    {
        if (_year < rhs._year) return -1;
        if (_year > rhs._year) return +1;

        if (_month < rhs._month) return -1;
        if (_month > rhs._month) return +1;

        if (_day < rhs._day) return -1;
        if (_day > rhs._day) return +1;

        return 0;
    }

    unittest
    {
        //Test A.D.
        assert(Date(1, 1, 1).opCmp(Date.init) == 0);

        assert(Date(1999, 1, 1).opCmp(Date(1999, 1, 1)) == 0);
        assert(Date(1, 7, 1).opCmp(Date(1, 7, 1)) == 0);
        assert(Date(1, 1, 6).opCmp(Date(1, 1, 6)) == 0);

        assert(Date(1999, 7, 1).opCmp(Date(1999, 7, 1)) == 0);
        assert(Date(1999, 7, 6).opCmp(Date(1999, 7, 6)) == 0);

        assert(Date(1, 7, 6).opCmp(Date(1, 7, 6)) == 0);

        assert(Date(1999, 7, 6).opCmp(Date(2000, 7, 6)) < 0);
        assert(Date(2000, 7, 6).opCmp(Date(1999, 7, 6)) > 0);
        assert(Date(1999, 7, 6).opCmp(Date(1999, 8, 6)) < 0);
        assert(Date(1999, 8, 6).opCmp(Date(1999, 7, 6)) > 0);
        assert(Date(1999, 7, 6).opCmp(Date(1999, 7, 7)) < 0);
        assert(Date(1999, 7, 7).opCmp(Date(1999, 7, 6)) > 0);

        assert(Date(1999, 8, 7).opCmp(Date(2000, 7, 6)) < 0);
        assert(Date(2000, 8, 6).opCmp(Date(1999, 7, 7)) > 0);
        assert(Date(1999, 7, 7).opCmp(Date(2000, 7, 6)) < 0);
        assert(Date(2000, 7, 6).opCmp(Date(1999, 7, 7)) > 0);
        assert(Date(1999, 7, 7).opCmp(Date(1999, 8, 6)) < 0);
        assert(Date(1999, 8, 6).opCmp(Date(1999, 7, 7)) > 0);

        //Test B.C.
        assert(Date( 0, 1, 1).opCmp(Date( 0, 1, 1)) == 0);
        assert(Date(-1, 1, 1).opCmp(Date(-1, 1, 1)) == 0);
        assert(Date(-1, 7, 1).opCmp(Date(-1, 7, 1)) == 0);
        assert(Date(-1, 1, 6).opCmp(Date(-1, 1, 6)) == 0);

        assert(Date(-1999, 7, 1).opCmp(Date(-1999, 7, 1)) == 0);
        assert(Date(-1999, 7, 6).opCmp(Date(-1999, 7, 6)) == 0);

        assert(Date(-1, 7, 6).opCmp(Date(-1, 7, 6)) == 0);

        assert(Date(-2000, 7, 6).opCmp(Date(-1999, 7, 6)) < 0);
        assert(Date(-1999, 7, 6).opCmp(Date(-2000, 7, 6)) > 0);
        assert(Date(-1999, 7, 6).opCmp(Date(-1999, 8, 6)) < 0);
        assert(Date(-1999, 8, 6).opCmp(Date(-1999, 7, 6)) > 0);
        assert(Date(-1999, 7, 6).opCmp(Date(-1999, 7, 7)) < 0);
        assert(Date(-1999, 7, 7).opCmp(Date(-1999, 7, 6)) > 0);

        assert(Date(-2000, 8, 6).opCmp(Date(-1999, 7, 7)) < 0);
        assert(Date(-1999, 8, 7).opCmp(Date(-2000, 7, 6)) > 0);
        assert(Date(-2000, 7, 6).opCmp(Date(-1999, 7, 7)) < 0);
        assert(Date(-1999, 7, 7).opCmp(Date(-2000, 7, 6)) > 0);
        assert(Date(-1999, 7, 7).opCmp(Date(-1999, 8, 6)) < 0);
        assert(Date(-1999, 8, 6).opCmp(Date(-1999, 7, 7)) > 0);

        //Test Both
        assert(Date(-1999, 7, 6).opCmp(Date( 1999, 7, 6)) < 0);
        assert(Date( 1999, 7, 6).opCmp(Date(-1999, 7, 6)) > 0);

        assert(Date(-1999, 8, 6).opCmp(Date( 1999, 7, 6)) < 0);
        assert(Date( 1999, 7, 6).opCmp(Date(-1999, 8, 6)) > 0);

        assert(Date(-1999, 7, 7).opCmp(Date( 1999, 7, 6)) < 0);
        assert(Date( 1999, 7, 6).opCmp(Date(-1999, 7, 7)) > 0);

        assert(Date(-1999, 8, 7).opCmp(Date( 1999, 7, 6)) < 0);
        assert(Date( 1999, 7, 6).opCmp(Date(-1999, 8, 7)) > 0);

        assert(Date(-1999, 8, 6).opCmp(Date( 1999, 6, 6)) < 0);
        assert(Date( 1999, 6, 8).opCmp(Date(-1999, 7, 6)) > 0);

             auto mdate = Date(1999, 7, 6);
            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, mdate.opCmp(mdate)));
        static assert(__traits(compiles, mdate.opCmp(cdate)));
        static assert(__traits(compiles, mdate.opCmp(idate)));
        static assert(__traits(compiles, cdate.opCmp(mdate)));
        static assert(__traits(compiles, cdate.opCmp(cdate)));
        static assert(__traits(compiles, cdate.opCmp(idate)));
        static assert(__traits(compiles, idate.opCmp(mdate)));
        static assert(__traits(compiles, idate.opCmp(cdate)));
        static assert(__traits(compiles, idate.opCmp(idate)));
    }


    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.
     +/
    @property short year() @safe const pure nothrow
    {
        return _year;
    }

    ///
    unittest
    {
        assert(Date(1999,  7, 6).year == 1999);
        assert(Date(2010, 10, 4).year == 2010);
        assert(Date(  -7,  4, 5).year == -7);
    }

    unittest
    {
        assert(Date.init.year == 1);
        assert(Date( 1999, 7, 6).year ==  1999);
        assert(Date(-1999, 7, 6).year == -1999);

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.year == 1999));
        static assert(__traits(compiles, idate.year == 1999));
    }

    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.

        Params:
            year = The year to set this Date's year to.

        Throws:
            $(LREF DateTimeException) if the new year is not a leap year and the
            resulting date would be on February 29th.
     +/
    @property void year(int year) @safe pure
    {
        enforceValid!"days"(year, _month, _day);
        _year = cast(short)year;
    }

    ///
    unittest
    {
        assert(Date(1999,  7, 6).year == 1999);
        assert(Date(2010, 10, 4).year == 2010);
        assert(Date(  -7,  4, 5).year == -7);
    }

    unittest
    {
        static void testDateInvalid(Date date, int year)
        {
            date.year = year;
        }

        static void testDate(Date date, int year, in Date expected)
        {
            date.year = year;
            assert(date == expected);
        }

        assertThrown!DateTimeException(testDateInvalid(Date(4, 2, 29), 1));

        testDate(Date(1, 1, 1),  1999, Date( 1999, 1, 1));
        testDate(Date(1, 1, 1),     0, Date(    0, 1, 1));
        testDate(Date(1, 1, 1), -1999, Date(-1999, 1, 1));

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.year = 1999));
        static assert(!__traits(compiles, idate.year = 1999));
    }


    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Throws:
            $(LREF DateTimeException) if $(D isAD) is true.
     +/
    @property ushort yearBC() @safe const pure
    {
        if (isAD)
            throw new DateTimeException(format("Year %s is A.D.", _year));
        return cast(ushort)((_year * -1) + 1);
    }

    ///
    unittest
    {
        assert(Date(   0, 1, 1).yearBC == 1);
        assert(Date(  -1, 1, 1).yearBC == 2);
        assert(Date(-100, 1, 1).yearBC == 101);
    }

    unittest
    {
        assertThrown!DateTimeException((in Date date){ date.yearBC; }(Date(1, 1, 1)));

             auto mdate = Date(0, 7, 6);
            const cdate = Date(0, 7, 6);
        immutable idate = Date(0, 7, 6);
        static assert(__traits(compiles, mdate.yearBC));
        static assert(__traits(compiles, cdate.yearBC));
        static assert(__traits(compiles, idate.yearBC));
    }


    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Params:
            year = The year B.C. to set this $(LREF Date)'s year to.

        Throws:
            $(LREF DateTimeException) if a non-positive value is given.
     +/
    @property void yearBC(int year) @safe pure
    {
        enforce(0 < year,
                new DateTimeException("The given year is not a year B.C."));
        _year = cast(short)((year - 1) * -1);
    }

    ///
    unittest
    {
        auto date = Date(2010, 1, 1);
        date.yearBC = 1;
        assert(date == Date(0, 1, 1));

        date.yearBC = 10;
        assert(date == Date(-9, 1, 1));
    }

    unittest
    {
        assertThrown!DateTimeException((Date date){date.yearBC = -1;}(Date(1, 1, 1)));

             auto mdate = Date(0, 7, 6);
            const cdate = Date(0, 7, 6);
        immutable idate = Date(0, 7, 6);
        static assert( __traits(compiles, mdate.yearBC = 7));
        static assert(!__traits(compiles, cdate.yearBC = 7));
        static assert(!__traits(compiles, idate.yearBC = 7));
    }


    /++
        Month of a Gregorian Year.
     +/
    @property Month month() @safe const pure nothrow
    {
        return _month;
    }

    ///
    unittest
    {
        assert(Date(1999,  7, 6).month ==  7);
        assert(Date(2010, 10, 4).month == 10);
        assert(Date(  -7,  4, 5).month ==  4);
    }

    unittest
    {
        assert(Date.init.month == 1);
        assert(Date( 1999, 7, 6).month == 7);
        assert(Date(-1999, 7, 6).month == 7);

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.month == 7));
        static assert(__traits(compiles, idate.month == 7));
    }

    /++
        Month of a Gregorian Year.

        Params:
            month = The month to set this $(LREF Date)'s month to.

        Throws:
            $(LREF DateTimeException) if the given month is not a valid month or if
            the current day would not be valid in the given month.
     +/
    @property void month(Month month) @safe pure
    {
        enforceValid!"months"(month);
        enforceValid!"days"(_year, month, _day);
        _month = cast(Month)month;
    }

    unittest
    {
        static void testDate(Date date, Month month, in Date expected = Date.init)
        {
            date.month = month;
            assert(expected != Date.init);
            assert(date == expected);
        }

        assertThrown!DateTimeException(testDate(Date(1, 1,  1), cast(Month) 0));
        assertThrown!DateTimeException(testDate(Date(1, 1,  1), cast(Month)13));
        assertThrown!DateTimeException(testDate(Date(1, 1, 29), cast(Month) 2));
        assertThrown!DateTimeException(testDate(Date(0, 1, 30), cast(Month) 2));

        testDate(Date( 1, 1, 1), cast(Month)7, Date( 1, 7, 1));
        testDate(Date(-1, 1, 1), cast(Month)7, Date(-1, 7, 1));

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.month = 7));
        static assert(!__traits(compiles, idate.month = 7));
    }


    /++
        Day of a Gregorian Month.
     +/
    @property ubyte day() @safe const pure nothrow
    {
        return _day;
    }

    ///
    unittest
    {
        assert(Date(1999,  7, 6).day == 6);
        assert(Date(2010, 10, 4).day == 4);
        assert(Date(  -7,  4, 5).day == 5);
    }

    unittest
    {
        import std.range;

        static void test(Date date, int expected)
        {
            assert(date.day == expected, format("Value given: %s", date));
        }

        foreach (year; chain(testYearsBC, testYearsAD))
        {
            foreach (md; testMonthDays)
                test(Date(year, md.month, md.day), md.day);
        }

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.day == 6));
        static assert(__traits(compiles, idate.day == 6));
    }

    /++
        Day of a Gregorian Month.

        Params:
            day = The day of the month to set this $(LREF Date)'s day to.

        Throws:
            $(LREF DateTimeException) if the given day is not a valid day of the
            current month.
     +/
    @property void day(int day) @safe pure
    {
        enforceValid!"days"(_year, _month, day);
        _day = cast(ubyte)day;
    }

    unittest
    {
        static void testDate(Date date, int day)
        {
            date.day = day;
        }

        //Test A.D.
        assertThrown!DateTimeException(testDate(Date(1,  1, 1), 0));
        assertThrown!DateTimeException(testDate(Date(1,  1, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1,  2, 1), 29));
        assertThrown!DateTimeException(testDate(Date(4,  2, 1), 30));
        assertThrown!DateTimeException(testDate(Date(1,  3, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1,  4, 1), 31));
        assertThrown!DateTimeException(testDate(Date(1,  5, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1,  6, 1), 31));
        assertThrown!DateTimeException(testDate(Date(1,  7, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1,  8, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1,  9, 1), 31));
        assertThrown!DateTimeException(testDate(Date(1, 10, 1), 32));
        assertThrown!DateTimeException(testDate(Date(1, 11, 1), 31));
        assertThrown!DateTimeException(testDate(Date(1, 12, 1), 32));

        assertNotThrown!DateTimeException(testDate(Date(1,  1, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1,  2, 1), 28));
        assertNotThrown!DateTimeException(testDate(Date(4,  2, 1), 29));
        assertNotThrown!DateTimeException(testDate(Date(1,  3, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1,  4, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(1,  5, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1,  6, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(1,  7, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1,  8, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1,  9, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(1, 10, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(1, 11, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(1, 12, 1), 31));

        {
            auto date = Date(1, 1, 1);
            date.day = 6;
            assert(date == Date(1, 1, 6));
        }

        //Test B.C.
        assertThrown!DateTimeException(testDate(Date(-1,  1, 1),  0));
        assertThrown!DateTimeException(testDate(Date(-1,  1, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1,  2, 1), 29));
        assertThrown!DateTimeException(testDate(Date( 0,  2, 1), 30));
        assertThrown!DateTimeException(testDate(Date(-1,  3, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1,  4, 1), 31));
        assertThrown!DateTimeException(testDate(Date(-1,  5, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1,  6, 1), 31));
        assertThrown!DateTimeException(testDate(Date(-1,  7, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1,  8, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1,  9, 1), 31));
        assertThrown!DateTimeException(testDate(Date(-1, 10, 1), 32));
        assertThrown!DateTimeException(testDate(Date(-1, 11, 1), 31));
        assertThrown!DateTimeException(testDate(Date(-1, 12, 1), 32));

        assertNotThrown!DateTimeException(testDate(Date(-1,  1, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1,  2, 1), 28));
        assertNotThrown!DateTimeException(testDate(Date( 0,  2, 1), 29));
        assertNotThrown!DateTimeException(testDate(Date(-1,  3, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1,  4, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(-1,  5, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1,  6, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(-1,  7, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1,  8, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1,  9, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(-1, 10, 1), 31));
        assertNotThrown!DateTimeException(testDate(Date(-1, 11, 1), 30));
        assertNotThrown!DateTimeException(testDate(Date(-1, 12, 1), 31));

        {
            auto date = Date(-1, 1, 1);
            date.day = 6;
            assert(date == Date(-1, 1, 6));
        }

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.day = 6));
        static assert(!__traits(compiles, idate.day = 6));
    }


    /++
        Adds the given number of years or months to this $(LREF Date). A negative
        number will subtract.

        Note that if day overflow is allowed, and the date with the adjusted
        year/month overflows the number of days in the new month, then the month
        will be incremented by one, and the day set to the number of days
        overflowed. (e.g. if the day were 31 and the new month were June, then
        the month would be incremented to July, and the new day would be 1). If
        day overflow is not allowed, then the day will be set to the last valid
        day in the month (e.g. June 31st would become June 30th).

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF Date).
            allowOverflow = Whether the day should be allowed to overflow,
                            causing the month to increment.
      +/
    ref Date add(string units)(long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "years")
    {
        immutable newYear = _year + value;

        _year += value;

        if (_month == Month.feb && _day == 29 && !yearIsLeapYear(_year))
        {
            if (allowOverflow == AllowDayOverflow.yes)
            {
                _month = Month.mar;
                _day = 1;
            }
            else
                _day = 28;
        }

        return this;
    }

    ///
    unittest
    {
        auto d1 = Date(2010, 1, 1);
        d1.add!"months"(11);
        assert(d1 == Date(2010, 12, 1));

        auto d2 = Date(2010, 1, 1);
        d2.add!"months"(-11);
        assert(d2 == Date(2009, 2, 1));

        auto d3 = Date(2000, 2, 29);
        d3.add!"years"(1);
        assert(d3 == Date(2001, 3, 1));

        auto d4 = Date(2000, 2, 29);
        d4.add!"years"(1, AllowDayOverflow.no);
        assert(d4 == Date(2001, 2, 28));
    }

    //Test add!"years"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.add!"years"(7);
            assert(date == Date(2006, 7, 6));
            date.add!"years"(-9);
            assert(date == Date(1997, 7, 6));
        }

        {
            auto date = Date(1999, 2, 28);
            date.add!"years"(1);
            assert(date == Date(2000, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.add!"years"(-1);
            assert(date == Date(1999, 3, 1));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.add!"years"(-7);
            assert(date == Date(-2006, 7, 6));
            date.add!"years"(9);
            assert(date == Date(-1997, 7, 6));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.add!"years"(-1);
            assert(date == Date(-2000, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.add!"years"(1);
            assert(date == Date(-1999, 3, 1));
        }

        //Test Both
        {
            auto date = Date(4, 7, 6);
            date.add!"years"(-5);
            assert(date == Date(-1, 7, 6));
            date.add!"years"(5);
            assert(date == Date(4, 7, 6));
        }

        {
            auto date = Date(-4, 7, 6);
            date.add!"years"(5);
            assert(date == Date(1, 7, 6));
            date.add!"years"(-5);
            assert(date == Date(-4, 7, 6));
        }

        {
            auto date = Date(4, 7, 6);
            date.add!"years"(-8);
            assert(date == Date(-4, 7, 6));
            date.add!"years"(8);
            assert(date == Date(4, 7, 6));
        }

        {
            auto date = Date(-4, 7, 6);
            date.add!"years"(8);
            assert(date == Date(4, 7, 6));
            date.add!"years"(-8);
            assert(date == Date(-4, 7, 6));
        }

        {
            auto date = Date(-4, 2, 29);
            date.add!"years"(5);
            assert(date == Date(1, 3, 1));
        }

        {
            auto date = Date(4, 2, 29);
            date.add!"years"(-5);
            assert(date == Date(-1, 3, 1));
        }

        {
            auto date = Date(4, 2, 29);
            date.add!"years"(-5).add!"years"(7);
            assert(date == Date(6, 3, 1));
        }

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.add!"years"(7)));
        static assert(!__traits(compiles, idate.add!"years"(7)));
    }

    //Test add!"years"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.add!"years"(7, AllowDayOverflow.no);
            assert(date == Date(2006, 7, 6));
            date.add!"years"(-9, AllowDayOverflow.no);
            assert(date == Date(1997, 7, 6));
        }

        {
            auto date = Date(1999, 2, 28);
            date.add!"years"(1, AllowDayOverflow.no);
            assert(date == Date(2000, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.add!"years"(-1, AllowDayOverflow.no);
            assert(date == Date(1999, 2, 28));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.add!"years"(-7, AllowDayOverflow.no);
            assert(date == Date(-2006, 7, 6));
            date.add!"years"(9, AllowDayOverflow.no);
            assert(date == Date(-1997, 7, 6));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.add!"years"(-1, AllowDayOverflow.no);
            assert(date == Date(-2000, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.add!"years"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 2, 28));
        }

        //Test Both
        {
            auto date = Date(4, 7, 6);
            date.add!"years"(-5, AllowDayOverflow.no);
            assert(date == Date(-1, 7, 6));
            date.add!"years"(5, AllowDayOverflow.no);
            assert(date == Date(4, 7, 6));
        }

        {
            auto date = Date(-4, 7, 6);
            date.add!"years"(5, AllowDayOverflow.no);
            assert(date == Date(1, 7, 6));
            date.add!"years"(-5, AllowDayOverflow.no);
            assert(date == Date(-4, 7, 6));
        }

        {
            auto date = Date(4, 7, 6);
            date.add!"years"(-8, AllowDayOverflow.no);
            assert(date == Date(-4, 7, 6));
            date.add!"years"(8, AllowDayOverflow.no);
            assert(date == Date(4, 7, 6));
        }

        {
            auto date = Date(-4, 7, 6);
            date.add!"years"(8, AllowDayOverflow.no);
            assert(date == Date(4, 7, 6));
            date.add!"years"(-8, AllowDayOverflow.no);
            assert(date == Date(-4, 7, 6));
        }

        {
            auto date = Date(-4, 2, 29);
            date.add!"years"(5, AllowDayOverflow.no);
            assert(date == Date(1, 2, 28));
        }

        {
            auto date = Date(4, 2, 29);
            date.add!"years"(-5, AllowDayOverflow.no);
            assert(date == Date(-1, 2, 28));
        }

        {
            auto date = Date(4, 2, 29);
            date.add!"years"(-5, AllowDayOverflow.no).add!"years"(7, AllowDayOverflow.no);
            assert(date == Date(6, 2, 28));
        }
    }


    //Shares documentation with "years" version.
    ref Date add(string units)(long months, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "months")
    {
        auto years = months / 12;
        months %= 12;
        auto newMonth = _month + months;

        if (months < 0)
        {
            if (newMonth < 1)
            {
                newMonth += 12;
                --years;
            }
        }
        else if (newMonth > 12)
        {
            newMonth -= 12;
            ++years;
        }

        _year += years;
        _month = cast(Month)newMonth;

        immutable currMaxDay = maxDay(_year, _month);
        immutable overflow = _day - currMaxDay;

        if (overflow > 0)
        {
            if (allowOverflow == AllowDayOverflow.yes)
            {
                ++_month;
                _day = cast(ubyte)overflow;
            }
            else
                _day = cast(ubyte)currMaxDay;
        }

        return this;
    }

    //Test add!"months"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(3);
            assert(date == Date(1999, 10, 6));
            date.add!"months"(-4);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(6);
            assert(date == Date(2000, 1, 6));
            date.add!"months"(-6);
            assert(date == Date(1999, 7, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(27);
            assert(date == Date(2001, 10, 6));
            date.add!"months"(-28);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 5, 31);
            date.add!"months"(1);
            assert(date == Date(1999, 7, 1));
        }

        {
            auto date = Date(1999, 5, 31);
            date.add!"months"(-1);
            assert(date == Date(1999, 5, 1));
        }

        {
            auto date = Date(1999, 2, 28);
            date.add!"months"(12);
            assert(date == Date(2000, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.add!"months"(12);
            assert(date == Date(2001, 3, 1));
        }

        {
            auto date = Date(1999, 7, 31);
            date.add!"months"(1);
            assert(date == Date(1999, 8, 31));
            date.add!"months"(1);
            assert(date == Date(1999, 10, 1));
        }

        {
            auto date = Date(1998, 8, 31);
            date.add!"months"(13);
            assert(date == Date(1999, 10, 1));
            date.add!"months"(-13);
            assert(date == Date(1998, 9, 1));
        }

        {
            auto date = Date(1997, 12, 31);
            date.add!"months"(13);
            assert(date == Date(1999, 1, 31));
            date.add!"months"(-13);
            assert(date == Date(1997, 12, 31));
        }

        {
            auto date = Date(1997, 12, 31);
            date.add!"months"(14);
            assert(date == Date(1999, 3, 3));
            date.add!"months"(-14);
            assert(date == Date(1998, 1, 3));
        }

        {
            auto date = Date(1998, 12, 31);
            date.add!"months"(14);
            assert(date == Date(2000, 3, 2));
            date.add!"months"(-14);
            assert(date == Date(1999, 1, 2));
        }

        {
            auto date = Date(1999, 12, 31);
            date.add!"months"(14);
            assert(date == Date(2001, 3, 3));
            date.add!"months"(-14);
            assert(date == Date(2000, 1, 3));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(3);
            assert(date == Date(-1999, 10, 6));
            date.add!"months"(-4);
            assert(date == Date(-1999, 6, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(6);
            assert(date == Date(-1998, 1, 6));
            date.add!"months"(-6);
            assert(date == Date(-1999, 7, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(-27);
            assert(date == Date(-2001, 4, 6));
            date.add!"months"(28);
            assert(date == Date(-1999, 8, 6));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.add!"months"(1);
            assert(date == Date(-1999, 7, 1));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.add!"months"(-1);
            assert(date == Date(-1999, 5, 1));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.add!"months"(-12);
            assert(date == Date(-2000, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.add!"months"(-12);
            assert(date == Date(-2001, 3, 1));
        }

        {
            auto date = Date(-1999, 7, 31);
            date.add!"months"(1);
            assert(date == Date(-1999, 8, 31));
            date.add!"months"(1);
            assert(date == Date(-1999, 10, 1));
        }

        {
            auto date = Date(-1998, 8, 31);
            date.add!"months"(13);
            assert(date == Date(-1997, 10, 1));
            date.add!"months"(-13);
            assert(date == Date(-1998, 9, 1));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.add!"months"(13);
            assert(date == Date(-1995, 1, 31));
            date.add!"months"(-13);
            assert(date == Date(-1997, 12, 31));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.add!"months"(14);
            assert(date == Date(-1995, 3, 3));
            date.add!"months"(-14);
            assert(date == Date(-1996, 1, 3));
        }

        {
            auto date = Date(-2002, 12, 31);
            date.add!"months"(14);
            assert(date == Date(-2000, 3, 2));
            date.add!"months"(-14);
            assert(date == Date(-2001, 1, 2));
        }

        {
            auto date = Date(-2001, 12, 31);
            date.add!"months"(14);
            assert(date == Date(-1999, 3, 3));
            date.add!"months"(-14);
            assert(date == Date(-2000, 1, 3));
        }

        //Test Both
        {
            auto date = Date(1, 1, 1);
            date.add!"months"(-1);
            assert(date == Date(0, 12, 1));
            date.add!"months"(1);
            assert(date == Date(1, 1, 1));
        }

        {
            auto date = Date(4, 1, 1);
            date.add!"months"(-48);
            assert(date == Date(0, 1, 1));
            date.add!"months"(48);
            assert(date == Date(4, 1, 1));
        }

        {
            auto date = Date(4, 3, 31);
            date.add!"months"(-49);
            assert(date == Date(0, 3, 2));
            date.add!"months"(49);
            assert(date == Date(4, 4, 2));
        }

        {
            auto date = Date(4, 3, 31);
            date.add!"months"(-85);
            assert(date == Date(-3, 3, 3));
            date.add!"months"(85);
            assert(date == Date(4, 4, 3));
        }

        {
            auto date = Date(-3, 3, 31);
            date.add!"months"(85).add!"months"(-83);
            assert(date == Date(-3, 6, 1));
        }

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.add!"months"(3)));
        static assert(!__traits(compiles, idate.add!"months"(3)));
    }

    //Test add!"months"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(3, AllowDayOverflow.no);
            assert(date == Date(1999, 10, 6));
            date.add!"months"(-4, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(6, AllowDayOverflow.no);
            assert(date == Date(2000, 1, 6));
            date.add!"months"(-6, AllowDayOverflow.no);
            assert(date == Date(1999, 7, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.add!"months"(27, AllowDayOverflow.no);
            assert(date == Date(2001, 10, 6));
            date.add!"months"(-28, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 5, 31);
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 30));
        }

        {
            auto date = Date(1999, 5, 31);
            date.add!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(1999, 4, 30));
        }

        {
            auto date = Date(1999, 2, 28);
            date.add!"months"(12, AllowDayOverflow.no);
            assert(date == Date(2000, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.add!"months"(12, AllowDayOverflow.no);
            assert(date == Date(2001, 2, 28));
        }

        {
            auto date = Date(1999, 7, 31);
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 8, 31));
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 9, 30));
        }

        {
            auto date = Date(1998, 8, 31);
            date.add!"months"(13, AllowDayOverflow.no);
            assert(date == Date(1999, 9, 30));
            date.add!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(1998, 8, 30));
        }

        {
            auto date = Date(1997, 12, 31);
            date.add!"months"(13, AllowDayOverflow.no);
            assert(date == Date(1999, 1, 31));
            date.add!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(1997, 12, 31));
        }

        {
            auto date = Date(1997, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(1999, 2, 28));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1997, 12, 28));
        }

        {
            auto date = Date(1998, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(2000, 2, 29));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1998, 12, 29));
        }

        {
            auto date = Date(1999, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(2001, 2, 28));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1999, 12, 28));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(3, AllowDayOverflow.no);
            assert(date == Date(-1999, 10, 6));
            date.add!"months"(-4, AllowDayOverflow.no);
            assert(date == Date(-1999, 6, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(6, AllowDayOverflow.no);
            assert(date == Date(-1998, 1, 6));
            date.add!"months"(-6, AllowDayOverflow.no);
            assert(date == Date(-1999, 7, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.add!"months"(-27, AllowDayOverflow.no);
            assert(date == Date(-2001, 4, 6));
            date.add!"months"(28, AllowDayOverflow.no);
            assert(date == Date(-1999, 8, 6));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 6, 30));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.add!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(-1999, 4, 30));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.add!"months"(-12, AllowDayOverflow.no);
            assert(date == Date(-2000, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.add!"months"(-12, AllowDayOverflow.no);
            assert(date == Date(-2001, 2, 28));
        }

        {
            auto date = Date(-1999, 7, 31);
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 8, 31));
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 9, 30));
        }

        {
            auto date = Date(-1998, 8, 31);
            date.add!"months"(13, AllowDayOverflow.no);
            assert(date == Date(-1997, 9, 30));
            date.add!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(-1998, 8, 30));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.add!"months"(13, AllowDayOverflow.no);
            assert(date == Date(-1995, 1, 31));
            date.add!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(-1997, 12, 31));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-1995, 2, 28));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-1997, 12, 28));
        }

        {
            auto date = Date(-2002, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-2000, 2, 29));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-2002, 12, 29));
        }

        {
            auto date = Date(-2001, 12, 31);
            date.add!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-1999, 2, 28));
            date.add!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-2001, 12, 28));
        }

        //Test Both
        {
            auto date = Date(1, 1, 1);
            date.add!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(0, 12, 1));
            date.add!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1, 1, 1));
        }

        {
            auto date = Date(4, 1, 1);
            date.add!"months"(-48, AllowDayOverflow.no);
            assert(date == Date(0, 1, 1));
            date.add!"months"(48, AllowDayOverflow.no);
            assert(date == Date(4, 1, 1));
        }

        {
            auto date = Date(4, 3, 31);
            date.add!"months"(-49, AllowDayOverflow.no);
            assert(date == Date(0, 2, 29));
            date.add!"months"(49, AllowDayOverflow.no);
            assert(date == Date(4, 3, 29));
        }

        {
            auto date = Date(4, 3, 31);
            date.add!"months"(-85, AllowDayOverflow.no);
            assert(date == Date(-3, 2, 28));
            date.add!"months"(85, AllowDayOverflow.no);
            assert(date == Date(4, 3, 28));
        }

        {
            auto date = Date(-3, 3, 31);
            date.add!"months"(85, AllowDayOverflow.no).add!"months"(-83, AllowDayOverflow.no);
            assert(date == Date(-3, 5, 30));
        }
    }


    /++
        Adds the given number of years or months to this $(LREF Date). A negative
        number will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. Rolling a $(LREF Date) 12 months gets
        the exact same $(LREF Date). However, the days can still be affected due to
        the differing number of days in each month.

        Because there are no units larger than years, there is no difference
        between adding and rolling years.

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF Date).
            allowOverflow = Whether the day should be allowed to overflow,
                            causing the month to increment.
      +/
    ref Date roll(string units)(long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "years")
    {
        return add!"years"(value, allowOverflow);
    }

    ///
    unittest
    {
        auto d1 = Date(2010, 1, 1);
        d1.roll!"months"(1);
        assert(d1 == Date(2010, 2, 1));

        auto d2 = Date(2010, 1, 1);
        d2.roll!"months"(-1);
        assert(d2 == Date(2010, 12, 1));

        auto d3 = Date(1999, 1, 29);
        d3.roll!"months"(1);
        assert(d3 == Date(1999, 3, 1));

        auto d4 = Date(1999, 1, 29);
        d4.roll!"months"(1, AllowDayOverflow.no);
        assert(d4 == Date(1999, 2, 28));

        auto d5 = Date(2000, 2, 29);
        d5.roll!"years"(1);
        assert(d5 == Date(2001, 3, 1));

        auto d6 = Date(2000, 2, 29);
        d6.roll!"years"(1, AllowDayOverflow.no);
        assert(d6 == Date(2001, 2, 28));
    }

    unittest
    {
        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.roll!"years"(3)));
        static assert(!__traits(compiles, idate.rolYears(3)));
    }


    //Shares documentation with "years" version.
    ref Date roll(string units)(long months, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "months")
    {
        months %= 12;
        auto newMonth = _month + months;

        if (months < 0)
        {
            if (newMonth < 1)
                newMonth += 12;
        }
        else
        {
            if (newMonth > 12)
                newMonth -= 12;
        }

        _month = cast(Month)newMonth;

        immutable currMaxDay = maxDay(_year, _month);
        immutable overflow = _day - currMaxDay;

        if (overflow > 0)
        {
            if (allowOverflow == AllowDayOverflow.yes)
            {
                ++_month;
                _day = cast(ubyte)overflow;
            }
            else
                _day = cast(ubyte)currMaxDay;
        }

        return this;
    }

    //Test roll!"months"() with AllowDayOverlow.yes
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(3);
            assert(date == Date(1999, 10, 6));
            date.roll!"months"(-4);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(6);
            assert(date == Date(1999, 1, 6));
            date.roll!"months"(-6);
            assert(date == Date(1999, 7, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(27);
            assert(date == Date(1999, 10, 6));
            date.roll!"months"(-28);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 5, 31);
            date.roll!"months"(1);
            assert(date == Date(1999, 7, 1));
        }

        {
            auto date = Date(1999, 5, 31);
            date.roll!"months"(-1);
            assert(date == Date(1999, 5, 1));
        }

        {
            auto date = Date(1999, 2, 28);
            date.roll!"months"(12);
            assert(date == Date(1999, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.roll!"months"(12);
            assert(date == Date(2000, 2, 29));
        }

        {
            auto date = Date(1999, 7, 31);
            date.roll!"months"(1);
            assert(date == Date(1999, 8, 31));
            date.roll!"months"(1);
            assert(date == Date(1999, 10, 1));
        }

        {
            auto date = Date(1998, 8, 31);
            date.roll!"months"(13);
            assert(date == Date(1998, 10, 1));
            date.roll!"months"(-13);
            assert(date == Date(1998, 9, 1));
        }

        {
            auto date = Date(1997, 12, 31);
            date.roll!"months"(13);
            assert(date == Date(1997, 1, 31));
            date.roll!"months"(-13);
            assert(date == Date(1997, 12, 31));
        }

        {
            auto date = Date(1997, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(1997, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(1997, 1, 3));
        }

        {
            auto date = Date(1998, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(1998, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(1998, 1, 3));
        }

        {
            auto date = Date(1999, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(1999, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(1999, 1, 3));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(3);
            assert(date == Date(-1999, 10, 6));
            date.roll!"months"(-4);
            assert(date == Date(-1999, 6, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(6);
            assert(date == Date(-1999, 1, 6));
            date.roll!"months"(-6);
            assert(date == Date(-1999, 7, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(-27);
            assert(date == Date(-1999, 4, 6));
            date.roll!"months"(28);
            assert(date == Date(-1999, 8, 6));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.roll!"months"(1);
            assert(date == Date(-1999, 7, 1));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.roll!"months"(-1);
            assert(date == Date(-1999, 5, 1));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.roll!"months"(-12);
            assert(date == Date(-1999, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.roll!"months"(-12);
            assert(date == Date(-2000, 2, 29));
        }

        {
            auto date = Date(-1999, 7, 31);
            date.roll!"months"(1);
            assert(date == Date(-1999, 8, 31));
            date.roll!"months"(1);
            assert(date == Date(-1999, 10, 1));
        }

        {
            auto date = Date(-1998, 8, 31);
            date.roll!"months"(13);
            assert(date == Date(-1998, 10, 1));
            date.roll!"months"(-13);
            assert(date == Date(-1998, 9, 1));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.roll!"months"(13);
            assert(date == Date(-1997, 1, 31));
            date.roll!"months"(-13);
            assert(date == Date(-1997, 12, 31));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(-1997, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(-1997, 1, 3));
        }

        {
            auto date = Date(-2002, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(-2002, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(-2002, 1, 3));
        }

        {
            auto date = Date(-2001, 12, 31);
            date.roll!"months"(14);
            assert(date == Date(-2001, 3, 3));
            date.roll!"months"(-14);
            assert(date == Date(-2001, 1, 3));
        }

        //Test Both
        {
            auto date = Date(1, 1, 1);
            date.roll!"months"(-1);
            assert(date == Date(1, 12, 1));
            date.roll!"months"(1);
            assert(date == Date(1, 1, 1));
        }

        {
            auto date = Date(4, 1, 1);
            date.roll!"months"(-48);
            assert(date == Date(4, 1, 1));
            date.roll!"months"(48);
            assert(date == Date(4, 1, 1));
        }

        {
            auto date = Date(4, 3, 31);
            date.roll!"months"(-49);
            assert(date == Date(4, 3, 2));
            date.roll!"months"(49);
            assert(date == Date(4, 4, 2));
        }

        {
            auto date = Date(4, 3, 31);
            date.roll!"months"(-85);
            assert(date == Date(4, 3, 2));
            date.roll!"months"(85);
            assert(date == Date(4, 4, 2));
        }

        {
            auto date = Date(-1, 1, 1);
            date.roll!"months"(-1);
            assert(date == Date(-1, 12, 1));
            date.roll!"months"(1);
            assert(date == Date(-1, 1, 1));
        }

        {
            auto date = Date(-4, 1, 1);
            date.roll!"months"(-48);
            assert(date == Date(-4, 1, 1));
            date.roll!"months"(48);
            assert(date == Date(-4, 1, 1));
        }

        {
            auto date = Date(-4, 3, 31);
            date.roll!"months"(-49);
            assert(date == Date(-4, 3, 2));
            date.roll!"months"(49);
            assert(date == Date(-4, 4, 2));
        }

        {
            auto date = Date(-4, 3, 31);
            date.roll!"months"(-85);
            assert(date == Date(-4, 3, 2));
            date.roll!"months"(85);
            assert(date == Date(-4, 4, 2));
        }

        {
            auto date = Date(-3, 3, 31);
            date.roll!"months"(85).roll!"months"(-83);
            assert(date == Date(-3, 6, 1));
        }

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.roll!"months"(3)));
        static assert(!__traits(compiles, idate.roll!"months"(3)));
    }

    //Test roll!"months"() with AllowDayOverlow.no
    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(3, AllowDayOverflow.no);
            assert(date == Date(1999, 10, 6));
            date.roll!"months"(-4, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(6, AllowDayOverflow.no);
            assert(date == Date(1999, 1, 6));
            date.roll!"months"(-6, AllowDayOverflow.no);
            assert(date == Date(1999, 7, 6));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"months"(27, AllowDayOverflow.no);
            assert(date == Date(1999, 10, 6));
            date.roll!"months"(-28, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 6));
        }

        {
            auto date = Date(1999, 5, 31);
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 6, 30));
        }

        {
            auto date = Date(1999, 5, 31);
            date.roll!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(1999, 4, 30));
        }

        {
            auto date = Date(1999, 2, 28);
            date.roll!"months"(12, AllowDayOverflow.no);
            assert(date == Date(1999, 2, 28));
        }

        {
            auto date = Date(2000, 2, 29);
            date.roll!"months"(12, AllowDayOverflow.no);
            assert(date == Date(2000, 2, 29));
        }

        {
            auto date = Date(1999, 7, 31);
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 8, 31));
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1999, 9, 30));
        }

        {
            auto date = Date(1998, 8, 31);
            date.roll!"months"(13, AllowDayOverflow.no);
            assert(date == Date(1998, 9, 30));
            date.roll!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(1998, 8, 30));
        }

        {
            auto date = Date(1997, 12, 31);
            date.roll!"months"(13, AllowDayOverflow.no);
            assert(date == Date(1997, 1, 31));
            date.roll!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(1997, 12, 31));
        }

        {
            auto date = Date(1997, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(1997, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1997, 12, 28));
        }

        {
            auto date = Date(1998, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(1998, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1998, 12, 28));
        }

        {
            auto date = Date(1999, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(1999, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(1999, 12, 28));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(3, AllowDayOverflow.no);
            assert(date == Date(-1999, 10, 6));
            date.roll!"months"(-4, AllowDayOverflow.no);
            assert(date == Date(-1999, 6, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(6, AllowDayOverflow.no);
            assert(date == Date(-1999, 1, 6));
            date.roll!"months"(-6, AllowDayOverflow.no);
            assert(date == Date(-1999, 7, 6));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"months"(-27, AllowDayOverflow.no);
            assert(date == Date(-1999, 4, 6));
            date.roll!"months"(28, AllowDayOverflow.no);
            assert(date == Date(-1999, 8, 6));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 6, 30));
        }

        {
            auto date = Date(-1999, 5, 31);
            date.roll!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(-1999, 4, 30));
        }

        {
            auto date = Date(-1999, 2, 28);
            date.roll!"months"(-12, AllowDayOverflow.no);
            assert(date == Date(-1999, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 29);
            date.roll!"months"(-12, AllowDayOverflow.no);
            assert(date == Date(-2000, 2, 29));
        }

        {
            auto date = Date(-1999, 7, 31);
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 8, 31));
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1999, 9, 30));
        }

        {
            auto date = Date(-1998, 8, 31);
            date.roll!"months"(13, AllowDayOverflow.no);
            assert(date == Date(-1998, 9, 30));
            date.roll!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(-1998, 8, 30));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.roll!"months"(13, AllowDayOverflow.no);
            assert(date == Date(-1997, 1, 31));
            date.roll!"months"(-13, AllowDayOverflow.no);
            assert(date == Date(-1997, 12, 31));
        }

        {
            auto date = Date(-1997, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-1997, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-1997, 12, 28));
        }

        {
            auto date = Date(-2002, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-2002, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-2002, 12, 28));
        }

        {
            auto date = Date(-2001, 12, 31);
            date.roll!"months"(14, AllowDayOverflow.no);
            assert(date == Date(-2001, 2, 28));
            date.roll!"months"(-14, AllowDayOverflow.no);
            assert(date == Date(-2001, 12, 28));
        }

        //Test Both
        {
            auto date = Date(1, 1, 1);
            date.roll!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(1, 12, 1));
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(1, 1, 1));
        }

        {
            auto date = Date(4, 1, 1);
            date.roll!"months"(-48, AllowDayOverflow.no);
            assert(date == Date(4, 1, 1));
            date.roll!"months"(48, AllowDayOverflow.no);
            assert(date == Date(4, 1, 1));
        }

        {
            auto date = Date(4, 3, 31);
            date.roll!"months"(-49, AllowDayOverflow.no);
            assert(date == Date(4, 2, 29));
            date.roll!"months"(49, AllowDayOverflow.no);
            assert(date == Date(4, 3, 29));
        }

        {
            auto date = Date(4, 3, 31);
            date.roll!"months"(-85, AllowDayOverflow.no);
            assert(date == Date(4, 2, 29));
            date.roll!"months"(85, AllowDayOverflow.no);
            assert(date == Date(4, 3, 29));
        }

        {
            auto date = Date(-1, 1, 1);
            date.roll!"months"(-1, AllowDayOverflow.no);
            assert(date == Date(-1, 12, 1));
            date.roll!"months"(1, AllowDayOverflow.no);
            assert(date == Date(-1, 1, 1));
        }

        {
            auto date = Date(-4, 1, 1);
            date.roll!"months"(-48, AllowDayOverflow.no);
            assert(date == Date(-4, 1, 1));
            date.roll!"months"(48, AllowDayOverflow.no);
            assert(date == Date(-4, 1, 1));
        }

        {
            auto date = Date(-4, 3, 31);
            date.roll!"months"(-49, AllowDayOverflow.no);
            assert(date == Date(-4, 2, 29));
            date.roll!"months"(49, AllowDayOverflow.no);
            assert(date == Date(-4, 3, 29));
        }

        {
            auto date = Date(-4, 3, 31);
            date.roll!"months"(-85, AllowDayOverflow.no);
            assert(date == Date(-4, 2, 29));
            date.roll!"months"(85, AllowDayOverflow.no);
            assert(date == Date(-4, 3, 29));
        }

        {
            auto date = Date(-3, 3, 31);
            date.roll!"months"(85, AllowDayOverflow.no).roll!"months"(-83, AllowDayOverflow.no);
            assert(date == Date(-3, 5, 30));
        }
    }


    /++
        Adds the given number of units to this $(LREF Date). A negative number will
        subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. For instance, rolling a $(LREF Date) one
        year's worth of days gets the exact same $(LREF Date).

        The only accepted units are $(D "days").

        Params:
            units = The units to add. Must be $(D "days").
            days  = The number of days to add to this $(LREF Date).
      +/
    ref Date roll(string units)(long days) @safe pure nothrow
        if (units == "days")
    {
        immutable limit = maxDay(_year, _month);
        days %= limit;
        auto newDay = _day + days;

        if (days < 0)
        {
            if (newDay < 1)
                newDay += limit;
        }
        else if (newDay > limit)
            newDay -= limit;

        _day = cast(ubyte)newDay;
        return this;
    }

    ///
    unittest
    {
        auto d = Date(2010, 1, 1);
        d.roll!"days"(1);
        assert(d == Date(2010, 1, 2));
        d.roll!"days"(365);
        assert(d == Date(2010, 1, 26));
        d.roll!"days"(-32);
        assert(d == Date(2010, 1, 25));
    }

    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 2, 28);
            date.roll!"days"(1);
            assert(date == Date(1999, 2, 1));
            date.roll!"days"(-1);
            assert(date == Date(1999, 2, 28));
        }

        {
            auto date = Date(2000, 2, 28);
            date.roll!"days"(1);
            assert(date == Date(2000, 2, 29));
            date.roll!"days"(1);
            assert(date == Date(2000, 2, 1));
            date.roll!"days"(-1);
            assert(date == Date(2000, 2, 29));
        }

        {
            auto date = Date(1999, 6, 30);
            date.roll!"days"(1);
            assert(date == Date(1999, 6, 1));
            date.roll!"days"(-1);
            assert(date == Date(1999, 6, 30));
        }

        {
            auto date = Date(1999, 7, 31);
            date.roll!"days"(1);
            assert(date == Date(1999, 7, 1));
            date.roll!"days"(-1);
            assert(date == Date(1999, 7, 31));
        }

        {
            auto date = Date(1999, 1, 1);
            date.roll!"days"(-1);
            assert(date == Date(1999, 1, 31));
            date.roll!"days"(1);
            assert(date == Date(1999, 1, 1));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"days"(9);
            assert(date == Date(1999, 7, 15));
            date.roll!"days"(-11);
            assert(date == Date(1999, 7, 4));
            date.roll!"days"(30);
            assert(date == Date(1999, 7, 3));
            date.roll!"days"(-3);
            assert(date == Date(1999, 7, 31));
        }

        {
            auto date = Date(1999, 7, 6);
            date.roll!"days"(365);
            assert(date == Date(1999, 7, 30));
            date.roll!"days"(-365);
            assert(date == Date(1999, 7, 6));
            date.roll!"days"(366);
            assert(date == Date(1999, 7, 31));
            date.roll!"days"(730);
            assert(date == Date(1999, 7, 17));
            date.roll!"days"(-1096);
            assert(date == Date(1999, 7, 6));
        }

        {
            auto date = Date(1999, 2, 6);
            date.roll!"days"(365);
            assert(date == Date(1999, 2, 7));
            date.roll!"days"(-365);
            assert(date == Date(1999, 2, 6));
            date.roll!"days"(366);
            assert(date == Date(1999, 2, 8));
            date.roll!"days"(730);
            assert(date == Date(1999, 2, 10));
            date.roll!"days"(-1096);
            assert(date == Date(1999, 2, 6));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 2, 28);
            date.roll!"days"(1);
            assert(date == Date(-1999, 2, 1));
            date.roll!"days"(-1);
            assert(date == Date(-1999, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 28);
            date.roll!"days"(1);
            assert(date == Date(-2000, 2, 29));
            date.roll!"days"(1);
            assert(date == Date(-2000, 2, 1));
            date.roll!"days"(-1);
            assert(date == Date(-2000, 2, 29));
        }

        {
            auto date = Date(-1999, 6, 30);
            date.roll!"days"(1);
            assert(date == Date(-1999, 6, 1));
            date.roll!"days"(-1);
            assert(date == Date(-1999, 6, 30));
        }

        {
            auto date = Date(-1999, 7, 31);
            date.roll!"days"(1);
            assert(date == Date(-1999, 7, 1));
            date.roll!"days"(-1);
            assert(date == Date(-1999, 7, 31));
        }

        {
            auto date = Date(-1999, 1, 1);
            date.roll!"days"(-1);
            assert(date == Date(-1999, 1, 31));
            date.roll!"days"(1);
            assert(date == Date(-1999, 1, 1));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"days"(9);
            assert(date == Date(-1999, 7, 15));
            date.roll!"days"(-11);
            assert(date == Date(-1999, 7, 4));
            date.roll!"days"(30);
            assert(date == Date(-1999, 7, 3));
            date.roll!"days"(-3);
            assert(date == Date(-1999, 7, 31));
        }

        {
            auto date = Date(-1999, 7, 6);
            date.roll!"days"(365);
            assert(date == Date(-1999, 7, 30));
            date.roll!"days"(-365);
            assert(date == Date(-1999, 7, 6));
            date.roll!"days"(366);
            assert(date == Date(-1999, 7, 31));
            date.roll!"days"(730);
            assert(date == Date(-1999, 7, 17));
            date.roll!"days"(-1096);
            assert(date == Date(-1999, 7, 6));
        }

        //Test Both
        {
            auto date = Date(1, 7, 6);
            date.roll!"days"(-365);
            assert(date == Date(1, 7, 13));
            date.roll!"days"(365);
            assert(date == Date(1, 7, 6));
            date.roll!"days"(-731);
            assert(date == Date(1, 7, 19));
            date.roll!"days"(730);
            assert(date == Date(1, 7, 5));
        }

        {
            auto date = Date(0, 7, 6);
            date.roll!"days"(-365);
            assert(date == Date(0, 7, 13));
            date.roll!"days"(365);
            assert(date == Date(0, 7, 6));
            date.roll!"days"(-731);
            assert(date == Date(0, 7, 19));
            date.roll!"days"(730);
            assert(date == Date(0, 7, 5));
        }

        {
            auto date = Date(0, 7, 6);
            date.roll!"days"(-365).roll!"days"(362).roll!"days"(-12).roll!"days"(730);
            assert(date == Date(0, 7, 8));
        }

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.roll!"days"(12)));
        static assert(!__traits(compiles, idate.roll!"days"(12)));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF Date).

        The legal types of arithmetic for Date using this operator are

        $(BOOKTABLE,
        $(TR $(TD Date) $(TD +) $(TD duration) $(TD -->) $(TD Date))
        $(TR $(TD Date) $(TD -) $(TD duration) $(TD -->) $(TD Date))
        )

        Params:
            duration = The duration to add to or subtract from this $(LREF Date).
      +/
    Date opBinary(string op, D)(in D duration) @safe const pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        Date retval = this;

        static if (is(Unqual!D == Duration))
            immutable days = duration.total!"days";
        else static if (is(Unqual!D == TickDuration))
            immutable days = convert!("hnsecs", "days")(duration.hnsecs);

        mixin(format("return retval._addDays(%sdays);", op));
    }

    unittest
    {
        auto date = Date(1999, 7, 6);

        assert(date + dur!"weeks"(7) == Date(1999, 8, 24));
        assert(date + dur!"weeks"(-7) == Date(1999, 5, 18));
        assert(date + dur!"days"(7) == Date(1999, 7, 13));
        assert(date + dur!"days"(-7) == Date(1999, 6, 29));

        assert(date + dur!"hours"(24) == Date(1999, 7, 7));
        assert(date + dur!"hours"(-24) == Date(1999, 7, 5));
        assert(date + dur!"minutes"(1440) == Date(1999, 7, 7));
        assert(date + dur!"minutes"(-1440) == Date(1999, 7, 5));
        assert(date + dur!"seconds"(86_400) == Date(1999, 7, 7));
        assert(date + dur!"seconds"(-86_400) == Date(1999, 7, 5));
        assert(date + dur!"msecs"(86_400_000) == Date(1999, 7, 7));
        assert(date + dur!"msecs"(-86_400_000) == Date(1999, 7, 5));
        assert(date + dur!"usecs"(86_400_000_000) == Date(1999, 7, 7));
        assert(date + dur!"usecs"(-86_400_000_000) == Date(1999, 7, 5));
        assert(date + dur!"hnsecs"(864_000_000_000) == Date(1999, 7, 7));
        assert(date + dur!"hnsecs"(-864_000_000_000) == Date(1999, 7, 5));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(date + TickDuration.from!"usecs"(86_400_000_000) == Date(1999, 7, 7));
            assert(date + TickDuration.from!"usecs"(-86_400_000_000) == Date(1999, 7, 5));
        }

        assert(date - dur!"weeks"(-7) == Date(1999, 8, 24));
        assert(date - dur!"weeks"(7) == Date(1999, 5, 18));
        assert(date - dur!"days"(-7) == Date(1999, 7, 13));
        assert(date - dur!"days"(7) == Date(1999, 6, 29));

        assert(date - dur!"hours"(-24) == Date(1999, 7, 7));
        assert(date - dur!"hours"(24) == Date(1999, 7, 5));
        assert(date - dur!"minutes"(-1440) == Date(1999, 7, 7));
        assert(date - dur!"minutes"(1440) == Date(1999, 7, 5));
        assert(date - dur!"seconds"(-86_400) == Date(1999, 7, 7));
        assert(date - dur!"seconds"(86_400) == Date(1999, 7, 5));
        assert(date - dur!"msecs"(-86_400_000) == Date(1999, 7, 7));
        assert(date - dur!"msecs"(86_400_000) == Date(1999, 7, 5));
        assert(date - dur!"usecs"(-86_400_000_000) == Date(1999, 7, 7));
        assert(date - dur!"usecs"(86_400_000_000) == Date(1999, 7, 5));
        assert(date - dur!"hnsecs"(-864_000_000_000) == Date(1999, 7, 7));
        assert(date - dur!"hnsecs"(864_000_000_000) == Date(1999, 7, 5));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(date - TickDuration.from!"usecs"(-86_400_000_000) == Date(1999, 7, 7));
            assert(date - TickDuration.from!"usecs"(86_400_000_000) == Date(1999, 7, 5));
        }

        auto duration = dur!"days"(12);
        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, date + duration));
        static assert(__traits(compiles, cdate + duration));
        static assert(__traits(compiles, idate + duration));

        static assert(__traits(compiles, date - duration));
        static assert(__traits(compiles, cdate - duration));
        static assert(__traits(compiles, idate - duration));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF Date), as well as assigning the result to this $(LREF Date).

        The legal types of arithmetic for $(LREF Date) using this operator are

        $(BOOKTABLE,
        $(TR $(TD Date) $(TD +) $(TD duration) $(TD -->) $(TD Date))
        $(TR $(TD Date) $(TD -) $(TD duration) $(TD -->) $(TD Date))
        )

        Params:
            duration = The duration to add to or subtract from this $(LREF Date).
      +/
    ref Date opOpAssign(string op, D)(in D duration) @safe pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        static if (is(Unqual!D == Duration))
            immutable days = duration.total!"days";
        else static if (is(Unqual!D == TickDuration))
            immutable days = convert!("hnsecs", "days")(duration.hnsecs);

        mixin(format("return _addDays(%sdays);", op));
    }

    unittest
    {
        assert(Date(1999, 7, 6) + dur!"weeks"(7) == Date(1999, 8, 24));
        assert(Date(1999, 7, 6) + dur!"weeks"(-7) == Date(1999, 5, 18));
        assert(Date(1999, 7, 6) + dur!"days"(7) == Date(1999, 7, 13));
        assert(Date(1999, 7, 6) + dur!"days"(-7) == Date(1999, 6, 29));

        assert(Date(1999, 7, 6) + dur!"hours"(24) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"hours"(-24) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) + dur!"minutes"(1440) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"minutes"(-1440) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) + dur!"seconds"(86_400) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"seconds"(-86_400) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) + dur!"msecs"(86_400_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"msecs"(-86_400_000) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) + dur!"usecs"(86_400_000_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"usecs"(-86_400_000_000) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) + dur!"hnsecs"(864_000_000_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) + dur!"hnsecs"(-864_000_000_000) == Date(1999, 7, 5));

        assert(Date(1999, 7, 6) - dur!"weeks"(-7) == Date(1999, 8, 24));
        assert(Date(1999, 7, 6) - dur!"weeks"(7) == Date(1999, 5, 18));
        assert(Date(1999, 7, 6) - dur!"days"(-7) == Date(1999, 7, 13));
        assert(Date(1999, 7, 6) - dur!"days"(7) == Date(1999, 6, 29));

        assert(Date(1999, 7, 6) - dur!"hours"(-24) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"hours"(24) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) - dur!"minutes"(-1440) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"minutes"(1440) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) - dur!"seconds"(-86_400) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"seconds"(86_400) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) - dur!"msecs"(-86_400_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"msecs"(86_400_000) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) - dur!"usecs"(-86_400_000_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"usecs"(86_400_000_000) == Date(1999, 7, 5));
        assert(Date(1999, 7, 6) - dur!"hnsecs"(-864_000_000_000) == Date(1999, 7, 7));
        assert(Date(1999, 7, 6) - dur!"hnsecs"(864_000_000_000) == Date(1999, 7, 5));

        {
            auto date = Date(0, 1, 31);
            (date += dur!"days"(507)) += dur!"days"(-2);
            assert(date == Date(1, 6, 19));
        }

        auto duration = dur!"days"(12);
        auto date = Date(1999, 7, 6);
        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, date += duration));
        static assert(!__traits(compiles, cdate += duration));
        static assert(!__traits(compiles, idate += duration));

        static assert(__traits(compiles, date -= duration));
        static assert(!__traits(compiles, cdate -= duration));
        static assert(!__traits(compiles, idate -= duration));
    }


    /++
        Gives the difference between two $(LREF Date)s.

        The legal types of arithmetic for Date using this operator are

        $(BOOKTABLE,
        $(TR $(TD Date) $(TD -) $(TD Date) $(TD -->) $(TD duration))
        )
      +/
    Duration opBinary(string op)(in Date rhs) @safe const pure nothrow
        if (op == "-")
    {
        return dur!"days"(this.dayOfGregorianCal - rhs.dayOfGregorianCal);
    }

    unittest
    {
        auto date = Date(1999, 7, 6);

        assert(Date(1999,  7,  6) - Date(1998,  7,  6) == dur!"days"( 365));
        assert(Date(1998,  7,  6) - Date(1999,  7,  6) == dur!"days"(-365));
        assert(Date(1999,  6,  6) - Date(1999,  5,  6) == dur!"days"( 31));
        assert(Date(1999,  5,  6) - Date(1999,  6,  6) == dur!"days"(-31));
        assert(Date(1999,  1,  1) - Date(1998, 12, 31) == dur!"days"( 1));
        assert(Date(1998, 12, 31) - Date(1999,  1,  1) == dur!"days"(-1));

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, date - date));
        static assert(__traits(compiles, cdate - date));
        static assert(__traits(compiles, idate - date));

        static assert(__traits(compiles, date - cdate));
        static assert(__traits(compiles, cdate - cdate));
        static assert(__traits(compiles, idate - cdate));

        static assert(__traits(compiles, date - idate));
        static assert(__traits(compiles, cdate - idate));
        static assert(__traits(compiles, idate - idate));
    }


    /++
        Returns the difference between the two $(LREF Date)s in months.

        To get the difference in years, subtract the year property
        of two $(LREF SysTime)s. To get the difference in days or weeks,
        subtract the $(LREF SysTime)s themselves and use the $(CXREF time, Duration)
        that results. Because converting between months and smaller
        units requires a specific date (which $(CXREF time, Duration)s don't have),
        getting the difference in months requires some math using both
        the year and month properties, so this is a convenience function for
        getting the difference in months.

        Note that the number of days in the months or how far into the month
        either $(LREF Date) is is irrelevant. It is the difference in the month
        property combined with the difference in years * 12. So, for instance,
        December 31st and January 1st are one month apart just as December 1st
        and January 31st are one month apart.

        Params:
            rhs = The $(LREF Date) to subtract from this one.
      +/
    int diffMonths(in Date rhs) @safe const pure nothrow
    {
        immutable yearDiff = _year - rhs._year;
        immutable monthDiff = _month - rhs._month;

        return yearDiff * 12 + monthDiff;
    }

    ///
    unittest
    {
        assert(Date(1999, 2, 1).diffMonths(Date(1999, 1, 31)) == 1);
        assert(Date(1999, 1, 31).diffMonths(Date(1999, 2, 1)) == -1);
        assert(Date(1999, 3, 1).diffMonths(Date(1999, 1, 1)) == 2);
        assert(Date(1999, 1, 1).diffMonths(Date(1999, 3, 31)) == -2);
    }

    unittest
    {
        auto date = Date(1999, 7, 6);

        //Test A.D.
        assert(date.diffMonths(Date(1998,  6, 5)) == 13);
        assert(date.diffMonths(Date(1998,  7, 5)) == 12);
        assert(date.diffMonths(Date(1998,  8, 5)) == 11);
        assert(date.diffMonths(Date(1998,  9, 5)) == 10);
        assert(date.diffMonths(Date(1998, 10, 5)) ==  9);
        assert(date.diffMonths(Date(1998, 11, 5)) ==  8);
        assert(date.diffMonths(Date(1998, 12, 5)) ==  7);
        assert(date.diffMonths(Date(1999,  1, 5)) ==  6);
        assert(date.diffMonths(Date(1999,  2, 6)) ==  5);
        assert(date.diffMonths(Date(1999,  3, 6)) ==  4);
        assert(date.diffMonths(Date(1999,  4, 6)) ==  3);
        assert(date.diffMonths(Date(1999,  5, 6)) ==  2);
        assert(date.diffMonths(Date(1999,  6, 6)) ==  1);
        assert(date.diffMonths(date) == 0);
        assert(date.diffMonths(Date(1999,  8, 6)) ==  -1);
        assert(date.diffMonths(Date(1999,  9, 6)) ==  -2);
        assert(date.diffMonths(Date(1999, 10, 6)) ==  -3);
        assert(date.diffMonths(Date(1999, 11, 6)) ==  -4);
        assert(date.diffMonths(Date(1999, 12, 6)) ==  -5);
        assert(date.diffMonths(Date(2000,  1, 6)) ==  -6);
        assert(date.diffMonths(Date(2000,  2, 6)) ==  -7);
        assert(date.diffMonths(Date(2000,  3, 6)) ==  -8);
        assert(date.diffMonths(Date(2000,  4, 6)) ==  -9);
        assert(date.diffMonths(Date(2000,  5, 6)) == -10);
        assert(date.diffMonths(Date(2000,  6, 6)) == -11);
        assert(date.diffMonths(Date(2000,  7, 6)) == -12);
        assert(date.diffMonths(Date(2000,  8, 6)) == -13);

        assert(Date(1998,  6, 5).diffMonths(date) == -13);
        assert(Date(1998,  7, 5).diffMonths(date) == -12);
        assert(Date(1998,  8, 5).diffMonths(date) == -11);
        assert(Date(1998,  9, 5).diffMonths(date) == -10);
        assert(Date(1998, 10, 5).diffMonths(date) ==  -9);
        assert(Date(1998, 11, 5).diffMonths(date) ==  -8);
        assert(Date(1998, 12, 5).diffMonths(date) ==  -7);
        assert(Date(1999,  1, 5).diffMonths(date) ==  -6);
        assert(Date(1999,  2, 6).diffMonths(date) ==  -5);
        assert(Date(1999,  3, 6).diffMonths(date) ==  -4);
        assert(Date(1999,  4, 6).diffMonths(date) ==  -3);
        assert(Date(1999,  5, 6).diffMonths(date) ==  -2);
        assert(Date(1999,  6, 6).diffMonths(date) ==  -1);
        assert(Date(1999,  8, 6).diffMonths(date) ==   1);
        assert(Date(1999,  9, 6).diffMonths(date) ==   2);
        assert(Date(1999, 10, 6).diffMonths(date) ==   3);
        assert(Date(1999, 11, 6).diffMonths(date) ==   4);
        assert(Date(1999, 12, 6).diffMonths(date) ==   5);
        assert(Date(2000,  1, 6).diffMonths(date) ==   6);
        assert(Date(2000,  2, 6).diffMonths(date) ==   7);
        assert(Date(2000,  3, 6).diffMonths(date) ==   8);
        assert(Date(2000,  4, 6).diffMonths(date) ==   9);
        assert(Date(2000,  5, 6).diffMonths(date) ==  10);
        assert(Date(2000,  6, 6).diffMonths(date) ==  11);
        assert(Date(2000,  7, 6).diffMonths(date) ==  12);
        assert(Date(2000,  8, 6).diffMonths(date) ==  13);

        assert(date.diffMonths(Date(1999, 6, 30)) ==  1);
        assert(date.diffMonths(Date(1999, 7,  1)) ==  0);
        assert(date.diffMonths(Date(1999, 7,  6)) ==  0);
        assert(date.diffMonths(Date(1999, 7, 11)) ==  0);
        assert(date.diffMonths(Date(1999, 7, 16)) ==  0);
        assert(date.diffMonths(Date(1999, 7, 21)) ==  0);
        assert(date.diffMonths(Date(1999, 7, 26)) ==  0);
        assert(date.diffMonths(Date(1999, 7, 31)) ==  0);
        assert(date.diffMonths(Date(1999, 8,  1)) == -1);

        assert(date.diffMonths(Date(1990, 6, 30)) == 109);
        assert(date.diffMonths(Date(1990, 7,  1)) == 108);
        assert(date.diffMonths(Date(1990, 7,  6)) == 108);
        assert(date.diffMonths(Date(1990, 7, 11)) == 108);
        assert(date.diffMonths(Date(1990, 7, 16)) == 108);
        assert(date.diffMonths(Date(1990, 7, 21)) == 108);
        assert(date.diffMonths(Date(1990, 7, 26)) == 108);
        assert(date.diffMonths(Date(1990, 7, 31)) == 108);
        assert(date.diffMonths(Date(1990, 8,  1)) == 107);

        assert(Date(1999, 6, 30).diffMonths(date) == -1);
        assert(Date(1999, 7,  1).diffMonths(date) ==  0);
        assert(Date(1999, 7,  6).diffMonths(date) ==  0);
        assert(Date(1999, 7, 11).diffMonths(date) ==  0);
        assert(Date(1999, 7, 16).diffMonths(date) ==  0);
        assert(Date(1999, 7, 21).diffMonths(date) ==  0);
        assert(Date(1999, 7, 26).diffMonths(date) ==  0);
        assert(Date(1999, 7, 31).diffMonths(date) ==  0);
        assert(Date(1999, 8,  1).diffMonths(date) ==  1);

        assert(Date(1990, 6, 30).diffMonths(date) == -109);
        assert(Date(1990, 7,  1).diffMonths(date) == -108);
        assert(Date(1990, 7,  6).diffMonths(date) == -108);
        assert(Date(1990, 7, 11).diffMonths(date) == -108);
        assert(Date(1990, 7, 16).diffMonths(date) == -108);
        assert(Date(1990, 7, 21).diffMonths(date) == -108);
        assert(Date(1990, 7, 26).diffMonths(date) == -108);
        assert(Date(1990, 7, 31).diffMonths(date) == -108);
        assert(Date(1990, 8,  1).diffMonths(date) == -107);

        //Test B.C.
        auto dateBC = Date(-1999, 7, 6);

        assert(dateBC.diffMonths(Date(-2000,  6, 5)) ==  13);
        assert(dateBC.diffMonths(Date(-2000,  7, 5)) ==  12);
        assert(dateBC.diffMonths(Date(-2000,  8, 5)) ==  11);
        assert(dateBC.diffMonths(Date(-2000,  9, 5)) ==  10);
        assert(dateBC.diffMonths(Date(-2000, 10, 5)) ==   9);
        assert(dateBC.diffMonths(Date(-2000, 11, 5)) ==   8);
        assert(dateBC.diffMonths(Date(-2000, 12, 5)) ==   7);
        assert(dateBC.diffMonths(Date(-1999,  1, 5)) ==   6);
        assert(dateBC.diffMonths(Date(-1999,  2, 6)) ==   5);
        assert(dateBC.diffMonths(Date(-1999,  3, 6)) ==   4);
        assert(dateBC.diffMonths(Date(-1999,  4, 6)) ==   3);
        assert(dateBC.diffMonths(Date(-1999,  5, 6)) ==   2);
        assert(dateBC.diffMonths(Date(-1999,  6, 6)) ==   1);
        assert(dateBC.diffMonths(dateBC) == 0);
        assert(dateBC.diffMonths(Date(-1999,  8, 6)) ==  -1);
        assert(dateBC.diffMonths(Date(-1999,  9, 6)) ==  -2);
        assert(dateBC.diffMonths(Date(-1999, 10, 6)) ==  -3);
        assert(dateBC.diffMonths(Date(-1999, 11, 6)) ==  -4);
        assert(dateBC.diffMonths(Date(-1999, 12, 6)) ==  -5);
        assert(dateBC.diffMonths(Date(-1998,  1, 6)) ==  -6);
        assert(dateBC.diffMonths(Date(-1998,  2, 6)) ==  -7);
        assert(dateBC.diffMonths(Date(-1998,  3, 6)) ==  -8);
        assert(dateBC.diffMonths(Date(-1998,  4, 6)) ==  -9);
        assert(dateBC.diffMonths(Date(-1998,  5, 6)) == -10);
        assert(dateBC.diffMonths(Date(-1998,  6, 6)) == -11);
        assert(dateBC.diffMonths(Date(-1998,  7, 6)) == -12);
        assert(dateBC.diffMonths(Date(-1998,  8, 6)) == -13);

        assert(Date(-2000,  6, 5).diffMonths(dateBC) == -13);
        assert(Date(-2000,  7, 5).diffMonths(dateBC) == -12);
        assert(Date(-2000,  8, 5).diffMonths(dateBC) == -11);
        assert(Date(-2000,  9, 5).diffMonths(dateBC) == -10);
        assert(Date(-2000, 10, 5).diffMonths(dateBC) ==  -9);
        assert(Date(-2000, 11, 5).diffMonths(dateBC) ==  -8);
        assert(Date(-2000, 12, 5).diffMonths(dateBC) ==  -7);
        assert(Date(-1999,  1, 5).diffMonths(dateBC) ==  -6);
        assert(Date(-1999,  2, 6).diffMonths(dateBC) ==  -5);
        assert(Date(-1999,  3, 6).diffMonths(dateBC) ==  -4);
        assert(Date(-1999,  4, 6).diffMonths(dateBC) ==  -3);
        assert(Date(-1999,  5, 6).diffMonths(dateBC) ==  -2);
        assert(Date(-1999,  6, 6).diffMonths(dateBC) ==  -1);
        assert(Date(-1999,  8, 6).diffMonths(dateBC) ==   1);
        assert(Date(-1999,  9, 6).diffMonths(dateBC) ==   2);
        assert(Date(-1999, 10, 6).diffMonths(dateBC) ==   3);
        assert(Date(-1999, 11, 6).diffMonths(dateBC) ==   4);
        assert(Date(-1999, 12, 6).diffMonths(dateBC) ==   5);
        assert(Date(-1998,  1, 6).diffMonths(dateBC) ==   6);
        assert(Date(-1998,  2, 6).diffMonths(dateBC) ==   7);
        assert(Date(-1998,  3, 6).diffMonths(dateBC) ==   8);
        assert(Date(-1998,  4, 6).diffMonths(dateBC) ==   9);
        assert(Date(-1998,  5, 6).diffMonths(dateBC) ==  10);
        assert(Date(-1998,  6, 6).diffMonths(dateBC) ==  11);
        assert(Date(-1998,  7, 6).diffMonths(dateBC) ==  12);
        assert(Date(-1998,  8, 6).diffMonths(dateBC) ==  13);

        assert(dateBC.diffMonths(Date(-1999, 6, 30)) ==  1);
        assert(dateBC.diffMonths(Date(-1999, 7,  1)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7,  6)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7, 11)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7, 16)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7, 21)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7, 26)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 7, 31)) ==  0);
        assert(dateBC.diffMonths(Date(-1999, 8,  1)) == -1);

        assert(dateBC.diffMonths(Date(-2008, 6, 30)) == 109);
        assert(dateBC.diffMonths(Date(-2008, 7,  1)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7,  6)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7, 11)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7, 16)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7, 21)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7, 26)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 7, 31)) == 108);
        assert(dateBC.diffMonths(Date(-2008, 8,  1)) == 107);

        assert(Date(-1999, 6, 30).diffMonths(dateBC) == -1);
        assert(Date(-1999, 7,  1).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7,  6).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7, 11).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7, 16).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7, 21).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7, 26).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 7, 31).diffMonths(dateBC) ==  0);
        assert(Date(-1999, 8,  1).diffMonths(dateBC) ==  1);

        assert(Date(-2008, 6, 30).diffMonths(dateBC) == -109);
        assert(Date(-2008, 7,  1).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7,  6).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7, 11).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7, 16).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7, 21).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7, 26).diffMonths(dateBC) == -108);
        assert(Date(-2008, 7, 31).diffMonths(dateBC) == -108);
        assert(Date(-2008, 8,  1).diffMonths(dateBC) == -107);

        //Test Both
        assert(Date( 3, 3, 3).diffMonths(Date(-5, 5, 5)) ==  94);
        assert(Date(-5, 5, 5).diffMonths(Date( 3, 3, 3)) == -94);

            alias mdate = date;
            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, mdate.diffMonths(mdate)));
        static assert(__traits(compiles, cdate.diffMonths(mdate)));
        static assert(__traits(compiles, idate.diffMonths(mdate)));

        static assert(__traits(compiles, mdate.diffMonths(cdate)));
        static assert(__traits(compiles, cdate.diffMonths(cdate)));
        static assert(__traits(compiles, idate.diffMonths(cdate)));

        static assert(__traits(compiles, mdate.diffMonths(idate)));
        static assert(__traits(compiles, cdate.diffMonths(idate)));
        static assert(__traits(compiles, idate.diffMonths(idate)));
    }


    /++
        Whether this $(LREF Date) is in a leap year.
     +/
    @property bool isLeapYear() @safe const pure nothrow
    {
        return yearIsLeapYear(_year);
    }

    unittest
    {
             auto mdate = Date(1999, 7, 6);
            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, mdate.isLeapYear = true));
        static assert(!__traits(compiles, cdate.isLeapYear = true));
        static assert(!__traits(compiles, idate.isLeapYear = true));
    }


    /++
        Day of the week this $(LREF Date) is on.
      +/
    @property DayOfWeek dayOfWeek() @safe const pure nothrow
    {
        return getDayOfWeek(dayOfGregorianCal);
    }

    unittest
    {
            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert( __traits(compiles, cdate.dayOfWeek == DayOfWeek.sun));
        static assert( __traits(compiles, idate.dayOfWeek == DayOfWeek.sun));
        static assert(!__traits(compiles, cdate.dayOfWeek = DayOfWeek.sun));
        static assert(!__traits(compiles, idate.dayOfWeek = DayOfWeek.sun));
    }


    /++
        Day of the year this $(LREF Date) is on.
      +/
    @property ushort dayOfYear() @safe const pure nothrow
    {
        if (_month >= Month.jan && _month <= Month.dec)
        {
            immutable int[] lastDay = isLeapYear ? lastDayLeap : lastDayNonLeap;
            auto monthIndex = _month - Month.jan;

            return cast(ushort)(lastDay[monthIndex] + _day);
        }
        assert(0, "Invalid month.");
    }

    ///
    unittest
    {
        assert(Date(1999,  1,  1).dayOfYear ==   1);
        assert(Date(1999, 12, 31).dayOfYear == 365);
        assert(Date(2000, 12, 31).dayOfYear == 366);
    }

    unittest
    {
        import std.range;

        foreach (year; filter!(a => !yearIsLeapYear(a))(chain(testYearsBC, testYearsAD)))
        {
            foreach (doy; testDaysOfYear)
            {
                assert(Date(year, doy.md.month, doy.md.day).dayOfYear ==
                                 doy.day);
            }
        }

        foreach (year; filter!(a => yearIsLeapYear(a))(chain(testYearsBC, testYearsAD)))
        {
            foreach (doy; testDaysOfLeapYear)
            {
                assert(Date(year, doy.md.month, doy.md.day).dayOfYear ==
                                 doy.day);
            }
        }

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.dayOfYear == 187));
        static assert(__traits(compiles, idate.dayOfYear == 187));
    }

    /++
        Day of the year.

        Params:
            day = The day of the year to set which day of the year this
                  $(LREF Date) is on.

        Throws:
            $(LREF DateTimeException) if the given day is an invalid day of the
            year.
      +/
    @property void dayOfYear(int day) @safe pure
    {
        immutable int[] lastDay = isLeapYear ? lastDayLeap : lastDayNonLeap;

        enforce(0 < day && day <= (isLeapYear ? daysInLeapYear : daysInYear),
                new DateTimeException("Invalid day of the year.");

        foreach (i; 1..lastDay.length)
        {
            if (day <= lastDay[i])
            {
                _month = cast(Month)(cast(int)Month.jan + i - 1);
                _day = cast(ubyte)(day - lastDay[i - 1]);
                return;
            }
        }
        assert(0, "Invalid day of the year.");
    }

    unittest
    {
        static void test(Date date, int day, MonthDay expected, size_t line = __LINE__)
        {
            date.dayOfYear = day;
            assert(date.month == expected.month);
            assert(date.day   == expected.day);
        }

        foreach (doy; testDaysOfYear)
        {
            test(Date(1999, 1, 1), doy.day, doy.md);
            test(Date(  -1, 1, 1), doy.day, doy.md);
        }

        foreach (doy; testDaysOfLeapYear)
        {
            test(Date(2000, 1, 1), doy.day, doy.md);
            test(Date(  -4, 1, 1), doy.day, doy.md);
        }

            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.dayOfYear = 187));
        static assert(!__traits(compiles, idate.dayOfYear = 187));
    }


    /++
        The Xth day of the Gregorian Calendar that this $(LREF Date) is on.
     +/
    @property int dayOfGregorianCal() @safe const pure nothrow
    {
        if (isAD)
        {
            if (_year == 1)
                return dayOfYear;

            int years = _year - 1;
            auto days = (years / 400) * daysIn400Years;
            years %= 400;

            days += (years / 100) * daysIn100Years;
            years %= 100;

            days += (years / 4) * daysIn4Years;
            years %= 4;

            days += years * daysInYear;

            days += dayOfYear;

            return days;
        }
        else if (_year == 0)
        {
            return dayOfYear - daysInLeapYear;
        }
        else
        {
            int years = _year;
            auto days = (years / 400) * daysIn400Years;
            years %= 400;

            days += (years / 100) * daysIn100Years;
            years %= 100;

            days += (years / 4) * daysIn4Years;
            years %= 4;

            if (years < 0)
            {
                days -= daysInLeapYear;
                ++years;

                days += years * daysInYear;

                days -= daysInYear - dayOfYear;
            }
            else
                days -= daysInLeapYear - dayOfYear;

            return days;
        }
    }

    ///
    unittest
    {
        assert(Date(1,  1,  1).dayOfGregorianCal ==   1);
        assert(Date(1, 12, 31).dayOfGregorianCal == 365);
        assert(Date(2,  1,  1).dayOfGregorianCal == 366);

        assert(Date( 0, 12, 31).dayOfGregorianCal ==    0);
        assert(Date( 0,  1,  1).dayOfGregorianCal == -365);
        assert(Date(-1, 12, 31).dayOfGregorianCal == -366);

        assert(Date(2000,  1,  1).dayOfGregorianCal == 730_120);
        assert(Date(2010, 12, 31).dayOfGregorianCal == 734_137);
    }

    unittest
    {
        import std.range;

        foreach (gd; chain(testGregDaysBC, testGregDaysAD))
            assert(gd.date.dayOfGregorianCal == gd.day);

             auto mdate = Date(1999, 7, 6);
            const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, mdate.dayOfGregorianCal));
        static assert(__traits(compiles, cdate.dayOfGregorianCal));
        static assert(__traits(compiles, idate.dayOfGregorianCal));
    }

    /++
        The Xth day of the Gregorian Calendar that this $(LREF Date) is on.

        Params:
            day = The day of the Gregorian Calendar to set this $(LREF Date) to.
     +/
    @property void dayOfGregorianCal(int day) @safe pure nothrow
    {
        this = Date(day);
    }

    ///
    unittest
    {
        auto date = Date.init;
        date.dayOfGregorianCal = 1;
        assert(date == Date(1, 1, 1));

        date.dayOfGregorianCal = 365;
        assert(date == Date(1, 12, 31));

        date.dayOfGregorianCal = 366;
        assert(date == Date(2, 1, 1));

        date.dayOfGregorianCal = 0;
        assert(date == Date(0, 12, 31));

        date.dayOfGregorianCal = -365;
        assert(date == Date(-0, 1, 1));

        date.dayOfGregorianCal = -366;
        assert(date == Date(-1, 12, 31));

        date.dayOfGregorianCal = 730_120;
        assert(date == Date(2000, 1, 1));

        date.dayOfGregorianCal = 734_137;
        assert(date == Date(2010, 12, 31));
    }

    unittest
    {
        auto date = Date(1999, 7, 6);
        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, date.dayOfGregorianCal = 187));
        static assert(!__traits(compiles, cdate.dayOfGregorianCal = 187));
        static assert(!__traits(compiles, idate.dayOfGregorianCal = 187));
    }


    /++
        The ISO 8601 week of the year that this $(LREF Date) is in.

        See_Also:
            $(WEB en.wikipedia.org/wiki/ISO_week_date, ISO Week Date)
      +/
    @property ubyte isoWeek() @safe const pure nothrow
    {
        immutable weekday = dayOfWeek;
        immutable adjustedWeekday = weekday == DayOfWeek.sun ? 7 : weekday;
        immutable week = (dayOfYear - adjustedWeekday + 10) / 7;

        scope(failure) assert(0, "Date's constructor threw.");

        if (week == 53)
        {
            switch (Date(_year + 1, 1, 1).dayOfWeek)
            {
                case DayOfWeek.mon:
                case DayOfWeek.tue:
                case DayOfWeek.wed:
                case DayOfWeek.thu:
                    return 1;
                case DayOfWeek.fri:
                case DayOfWeek.sat:
                case DayOfWeek.sun:
                    return 53;
                default:
                    assert(0, "Invalid ISO Week");
            }
        }
        else if (week > 0)
            return cast(ubyte)week;
        else
            return Date(_year - 1, 12, 31).isoWeek;
    }

    unittest
    {
        //Test A.D.
        assert(Date(2009, 12, 28).isoWeek == 53);
        assert(Date(2009, 12, 29).isoWeek == 53);
        assert(Date(2009, 12, 30).isoWeek == 53);
        assert(Date(2009, 12, 31).isoWeek == 53);
        assert(Date(2010, 1, 1).isoWeek == 53);
        assert(Date(2010, 1, 2).isoWeek == 53);
        assert(Date(2010, 1, 3).isoWeek == 53);
        assert(Date(2010, 1, 4).isoWeek == 1);
        assert(Date(2010, 1, 5).isoWeek == 1);
        assert(Date(2010, 1, 6).isoWeek == 1);
        assert(Date(2010, 1, 7).isoWeek == 1);
        assert(Date(2010, 1, 8).isoWeek == 1);
        assert(Date(2010, 1, 9).isoWeek == 1);
        assert(Date(2010, 1, 10).isoWeek == 1);
        assert(Date(2010, 1, 11).isoWeek == 2);
        assert(Date(2010, 12, 31).isoWeek == 52);

        assert(Date(2004, 12, 26).isoWeek == 52);
        assert(Date(2004, 12, 27).isoWeek == 53);
        assert(Date(2004, 12, 28).isoWeek == 53);
        assert(Date(2004, 12, 29).isoWeek == 53);
        assert(Date(2004, 12, 30).isoWeek == 53);
        assert(Date(2004, 12, 31).isoWeek == 53);
        assert(Date(2005, 1, 1).isoWeek == 53);
        assert(Date(2005, 1, 2).isoWeek == 53);

        assert(Date(2005, 12, 31).isoWeek == 52);
        assert(Date(2007, 1, 1).isoWeek == 1);

        assert(Date(2007, 12, 30).isoWeek == 52);
        assert(Date(2007, 12, 31).isoWeek == 1);
        assert(Date(2008, 1, 1).isoWeek == 1);

        assert(Date(2008, 12, 28).isoWeek == 52);
        assert(Date(2008, 12, 29).isoWeek == 1);
        assert(Date(2008, 12, 30).isoWeek == 1);
        assert(Date(2008, 12, 31).isoWeek == 1);
        assert(Date(2009, 1, 1).isoWeek == 1);
        assert(Date(2009, 1, 2).isoWeek == 1);
        assert(Date(2009, 1, 3).isoWeek == 1);
        assert(Date(2009, 1, 4).isoWeek == 1);

        //Test B.C.
        //The algorithm should work identically for both A.D. and B.C. since
        //it doesn't really take the year into account, so B.C. testing
        //probably isn't really needed.
        assert(Date(0, 12, 31).isoWeek == 52);
        assert(Date(0, 1, 4).isoWeek == 1);
        assert(Date(0, 1, 1).isoWeek == 52);

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.isoWeek == 3));
        static assert(!__traits(compiles, cdate.isoWeek = 3));
        static assert(__traits(compiles, idate.isoWeek == 3));
        static assert(!__traits(compiles, idate.isoWeek = 3));
    }


    /++
        $(LREF Date) for the last day in the month that this $(LREF Date) is in.
      +/
    @property Date endOfMonth() @safe const pure nothrow
    {
        scope(failure) assert(0, "Date's constructor threw.");
        return Date(_year, _month, maxDay(_year, _month));
    }

    ///
    unittest
    {
        assert(Date(1999, 1, 6).endOfMonth == Date(1999, 1, 31));
        assert(Date(1999, 2, 7).endOfMonth == Date(1999, 2, 28));
        assert(Date(2000, 2, 7).endOfMonth == Date(2000, 2, 29));
        assert(Date(2000, 6, 4).endOfMonth == Date(2000, 6, 30));
    }

    unittest
    {
        //Test A.D.
        assert(Date(1999, 1, 1).endOfMonth == Date(1999, 1, 31));
        assert(Date(1999, 2, 1).endOfMonth == Date(1999, 2, 28));
        assert(Date(2000, 2, 1).endOfMonth == Date(2000, 2, 29));
        assert(Date(1999, 3, 1).endOfMonth == Date(1999, 3, 31));
        assert(Date(1999, 4, 1).endOfMonth == Date(1999, 4, 30));
        assert(Date(1999, 5, 1).endOfMonth == Date(1999, 5, 31));
        assert(Date(1999, 6, 1).endOfMonth == Date(1999, 6, 30));
        assert(Date(1999, 7, 1).endOfMonth == Date(1999, 7, 31));
        assert(Date(1999, 8, 1).endOfMonth == Date(1999, 8, 31));
        assert(Date(1999, 9, 1).endOfMonth == Date(1999, 9, 30));
        assert(Date(1999, 10, 1).endOfMonth == Date(1999, 10, 31));
        assert(Date(1999, 11, 1).endOfMonth == Date(1999, 11, 30));
        assert(Date(1999, 12, 1).endOfMonth == Date(1999, 12, 31));

        //Test B.C.
        assert(Date(-1999, 1, 1).endOfMonth == Date(-1999, 1, 31));
        assert(Date(-1999, 2, 1).endOfMonth == Date(-1999, 2, 28));
        assert(Date(-2000, 2, 1).endOfMonth == Date(-2000, 2, 29));
        assert(Date(-1999, 3, 1).endOfMonth == Date(-1999, 3, 31));
        assert(Date(-1999, 4, 1).endOfMonth == Date(-1999, 4, 30));
        assert(Date(-1999, 5, 1).endOfMonth == Date(-1999, 5, 31));
        assert(Date(-1999, 6, 1).endOfMonth == Date(-1999, 6, 30));
        assert(Date(-1999, 7, 1).endOfMonth == Date(-1999, 7, 31));
        assert(Date(-1999, 8, 1).endOfMonth == Date(-1999, 8, 31));
        assert(Date(-1999, 9, 1).endOfMonth == Date(-1999, 9, 30));
        assert(Date(-1999, 10, 1).endOfMonth == Date(-1999, 10, 31));
        assert(Date(-1999, 11, 1).endOfMonth == Date(-1999, 11, 30));
        assert(Date(-1999, 12, 1).endOfMonth == Date(-1999, 12, 31));

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.endOfMonth = Date(1999, 7, 30)));
        static assert(!__traits(compiles, idate.endOfMonth = Date(1999, 7, 30)));
    }


    /++
        The last day in the month that this $(LREF Date) is in.
      +/
    @property ubyte daysInMonth() @safe const pure nothrow
    {
        return maxDay(_year, _month);
    }

    ///
    unittest
    {
        assert(Date(1999, 1, 6).daysInMonth == 31);
        assert(Date(1999, 2, 7).daysInMonth == 28);
        assert(Date(2000, 2, 7).daysInMonth == 29);
        assert(Date(2000, 6, 4).daysInMonth == 30);
    }

    unittest
    {
        //Test A.D.
        assert(Date(1999, 1, 1).daysInMonth == 31);
        assert(Date(1999, 2, 1).daysInMonth == 28);
        assert(Date(2000, 2, 1).daysInMonth == 29);
        assert(Date(1999, 3, 1).daysInMonth == 31);
        assert(Date(1999, 4, 1).daysInMonth == 30);
        assert(Date(1999, 5, 1).daysInMonth == 31);
        assert(Date(1999, 6, 1).daysInMonth == 30);
        assert(Date(1999, 7, 1).daysInMonth == 31);
        assert(Date(1999, 8, 1).daysInMonth == 31);
        assert(Date(1999, 9, 1).daysInMonth == 30);
        assert(Date(1999, 10, 1).daysInMonth == 31);
        assert(Date(1999, 11, 1).daysInMonth == 30);
        assert(Date(1999, 12, 1).daysInMonth == 31);

        //Test B.C.
        assert(Date(-1999, 1, 1).daysInMonth == 31);
        assert(Date(-1999, 2, 1).daysInMonth == 28);
        assert(Date(-2000, 2, 1).daysInMonth == 29);
        assert(Date(-1999, 3, 1).daysInMonth == 31);
        assert(Date(-1999, 4, 1).daysInMonth == 30);
        assert(Date(-1999, 5, 1).daysInMonth == 31);
        assert(Date(-1999, 6, 1).daysInMonth == 30);
        assert(Date(-1999, 7, 1).daysInMonth == 31);
        assert(Date(-1999, 8, 1).daysInMonth == 31);
        assert(Date(-1999, 9, 1).daysInMonth == 30);
        assert(Date(-1999, 10, 1).daysInMonth == 31);
        assert(Date(-1999, 11, 1).daysInMonth == 30);
        assert(Date(-1999, 12, 1).daysInMonth == 31);

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate.daysInMonth = 30));
        static assert(!__traits(compiles, idate.daysInMonth = 30));
    }


    /++
        Whether the current year is a date in A.D.
      +/
    @property bool isAD() @safe const pure nothrow
    {
        return _year > 0;
    }

    ///
    unittest
    {
        assert(Date(1, 1, 1).isAD);
        assert(Date(2010, 12, 31).isAD);
        assert(!Date(0, 12, 31).isAD);
        assert(!Date(-2010, 1, 1).isAD);
    }

    unittest
    {
        assert(Date(2010, 7, 4).isAD);
        assert(Date(1, 1, 1).isAD);
        assert(!Date(0, 1, 1).isAD);
        assert(!Date(-1, 1, 1).isAD);
        assert(!Date(-2010, 7, 4).isAD);

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.isAD));
        static assert(__traits(compiles, idate.isAD));
    }


    /++
        The $(WEB en.wikipedia.org/wiki/Julian_day, Julian day) for this $(LREF Date) at noon (since the Julian day changes
        at noon).
      +/
    @property long julianDay() @safe const pure nothrow
    {
        return dayOfGregorianCal + 1_721_425;
    }

    unittest
    {
        assert(Date(-4713, 11, 24).julianDay == 0);
        assert(Date(0, 12, 31).julianDay == 1_721_425);
        assert(Date(1, 1, 1).julianDay == 1_721_426);
        assert(Date(1582, 10, 15).julianDay == 2_299_161);
        assert(Date(1858, 11, 17).julianDay == 2_400_001);
        assert(Date(1982, 1, 4).julianDay == 2_444_974);
        assert(Date(1996, 3, 31).julianDay == 2_450_174);
        assert(Date(2010, 8, 24).julianDay == 2_455_433);

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.julianDay));
        static assert(__traits(compiles, idate.julianDay));
    }


    /++
        The modified $(WEB en.wikipedia.org/wiki/Julian_day, Julian day) for any time on this date (since, the modified
        Julian day changes at midnight).
      +/
    @property long modJulianDay() @safe const pure nothrow
    {
        return julianDay - 2_400_001;
    }

    unittest
    {
        assert(Date(1858, 11, 17).modJulianDay == 0);
        assert(Date(2010, 8, 24).modJulianDay == 55_432);

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.modJulianDay));
        static assert(__traits(compiles, idate.modJulianDay));
    }


    /++
        Converts this $(LREF Date) to a string with the format YYYYMMDD.
      +/
    string toISOString() @safe const pure nothrow
    {
        scope(failure) assert(0, "format() threw.");

        if (_year >= 0)
        {
            if (_year < 10_000)
                return format("%04d%02d%02d", _year, _month, _day);
            else
                return format("+%05d%02d%02d", _year, _month, _day);
        }
        else if (_year > -10_000)
            return format("%05d%02d%02d", _year, _month, _day);
        else
            return format("%06d%02d%02d", _year, _month, _day);
    }

    ///
    unittest
    {
        assert(Date(2010, 7, 4).toISOString() == "20100704");
        assert(Date(1998, 12, 25).toISOString() == "19981225");
        assert(Date(0, 1, 5).toISOString() == "00000105");
        assert(Date(-4, 1, 5).toISOString() == "-00040105");
    }

    unittest
    {
        //Test A.D.
        assert(Date(9, 12, 4).toISOString() == "00091204");
        assert(Date(99, 12, 4).toISOString() == "00991204");
        assert(Date(999, 12, 4).toISOString() == "09991204");
        assert(Date(9999, 7, 4).toISOString() == "99990704");
        assert(Date(10000, 10, 20).toISOString() == "+100001020");

        //Test B.C.
        assert(Date(0, 12, 4).toISOString() == "00001204");
        assert(Date(-9, 12, 4).toISOString() == "-00091204");
        assert(Date(-99, 12, 4).toISOString() == "-00991204");
        assert(Date(-999, 12, 4).toISOString() == "-09991204");
        assert(Date(-9999, 7, 4).toISOString() == "-99990704");
        assert(Date(-10000, 10, 20).toISOString() == "-100001020");

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.toISOString()));
        static assert(__traits(compiles, idate.toISOString()));
    }

    /++
        Converts this $(LREF Date) to a string with the format YYYY-MM-DD.
      +/
    string toISOExtString() @safe const pure nothrow
    {
        scope(failure) assert(0, "format() threw.");

        if (_year >= 0)
        {
            if (_year < 10_000)
                return format("%04d-%02d-%02d", _year, _month, _day);
            else
                return format("+%05d-%02d-%02d", _year, _month, _day);
        }
        else if (_year > -10_000)
            return format("%05d-%02d-%02d", _year, _month, _day);
        else
            return format("%06d-%02d-%02d", _year, _month, _day);
    }

    ///
    unittest
    {
        assert(Date(2010, 7, 4).toISOExtString() == "2010-07-04");
        assert(Date(1998, 12, 25).toISOExtString() == "1998-12-25");
        assert(Date(0, 1, 5).toISOExtString() == "0000-01-05");
        assert(Date(-4, 1, 5).toISOExtString() == "-0004-01-05");
    }

    unittest
    {
        //Test A.D.
        assert(Date(9, 12, 4).toISOExtString() == "0009-12-04");
        assert(Date(99, 12, 4).toISOExtString() == "0099-12-04");
        assert(Date(999, 12, 4).toISOExtString() == "0999-12-04");
        assert(Date(9999, 7, 4).toISOExtString() == "9999-07-04");
        assert(Date(10000, 10, 20).toISOExtString() == "+10000-10-20");

        //Test B.C.
        assert(Date(0, 12, 4).toISOExtString() == "0000-12-04");
        assert(Date(-9, 12, 4).toISOExtString() == "-0009-12-04");
        assert(Date(-99, 12, 4).toISOExtString() == "-0099-12-04");
        assert(Date(-999, 12, 4).toISOExtString() == "-0999-12-04");
        assert(Date(-9999, 7, 4).toISOExtString() == "-9999-07-04");
        assert(Date(-10000, 10, 20).toISOExtString() == "-10000-10-20");

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.toISOExtString()));
        static assert(__traits(compiles, idate.toISOExtString()));
    }

    /++
        Converts this $(LREF Date) to a string with the format YYYY-Mon-DD.
      +/
    string toSimpleString() @safe const pure nothrow
    {
        scope(failure) assert(0, "format() threw.");

        if (_year >= 0)
        {
            if (_year < 10_000)
                return format("%04d-%s-%02d", _year, monthToString(_month), _day);
            else
                return format("+%05d-%s-%02d", _year, monthToString(_month), _day);
        }
        else if (_year > -10_000)
            return format("%05d-%s-%02d", _year, monthToString(_month), _day);
        else
            return format("%06d-%s-%02d", _year, monthToString(_month), _day);
    }

    ///
    unittest
    {
        assert(Date(2010, 7, 4).toSimpleString() == "2010-Jul-04");
        assert(Date(1998, 12, 25).toSimpleString() == "1998-Dec-25");
        assert(Date(0, 1, 5).toSimpleString() == "0000-Jan-05");
        assert(Date(-4, 1, 5).toSimpleString() == "-0004-Jan-05");
    }

    unittest
    {
        //Test A.D.
        assert(Date(9, 12, 4).toSimpleString() == "0009-Dec-04");
        assert(Date(99, 12, 4).toSimpleString() == "0099-Dec-04");
        assert(Date(999, 12, 4).toSimpleString() == "0999-Dec-04");
        assert(Date(9999, 7, 4).toSimpleString() == "9999-Jul-04");
        assert(Date(10000, 10, 20).toSimpleString() == "+10000-Oct-20");

        //Test B.C.
        assert(Date(0, 12, 4).toSimpleString() == "0000-Dec-04");
        assert(Date(-9, 12, 4).toSimpleString() == "-0009-Dec-04");
        assert(Date(-99, 12, 4).toSimpleString() == "-0099-Dec-04");
        assert(Date(-999, 12, 4).toSimpleString() == "-0999-Dec-04");
        assert(Date(-9999, 7, 4).toSimpleString() == "-9999-Jul-04");
        assert(Date(-10000, 10, 20).toSimpleString() == "-10000-Oct-20");

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, cdate.toSimpleString()));
        static assert(__traits(compiles, idate.toSimpleString()));
    }


    /++
        Converts this $(LREF Date) to a string.
      +/
    string toString() @safe const pure nothrow
    {
        return toSimpleString();
    }

    unittest
    {
        auto date = Date(1999, 7, 6);
        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(__traits(compiles, date.toString()));
        static assert(__traits(compiles, cdate.toString()));
        static assert(__traits(compiles, idate.toString()));
    }


    /++
        Creates a $(LREF Date) from a string with the format YYYYMMDD. Whitespace
        is stripped from the given string.

        Params:
            isoString = A string formatted in the ISO format for dates.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF Date) would not be valid.
      +/
    static Date fromISOString(S)(in S isoString) @safe pure
        if (isSomeString!S)
    {
        import std.ascii : isDigit;
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : all, startsWith;

        auto dstr = to!dstring(strip(isoString));

        enforce(dstr.length >= 8, new DateTimeException(format("Invalid ISO String: %s", isoString)));

        auto day = dstr[$-2 .. $];
        auto month = dstr[$-4 .. $-2];
        auto year = dstr[0 .. $-4];

        enforce(all!isDigit(day), new DateTimeException(format("Invalid ISO String: %s", isoString)));
        enforce(all!isDigit(month), new DateTimeException(format("Invalid ISO String: %s", isoString)));

        if (year.length > 4)
        {
            enforce(year.startsWith('-', '+'),
                    new DateTimeException(format("Invalid ISO String: %s", isoString)));
            enforce(all!isDigit(year[1..$]),
                    new DateTimeException(format("Invalid ISO String: %s", isoString)));
        }
        else
            enforce(all!isDigit(year), new DateTimeException(format("Invalid ISO String: %s", isoString)));

        return Date(to!short(year), to!ubyte(month), to!ubyte(day));
    }

    ///
    unittest
    {
        assert(Date.fromISOString("20100704") == Date(2010, 7, 4));
        assert(Date.fromISOString("19981225") == Date(1998, 12, 25));
        assert(Date.fromISOString("00000105") == Date(0, 1, 5));
        assert(Date.fromISOString("-00040105") == Date(-4, 1, 5));
        assert(Date.fromISOString(" 20100704 ") == Date(2010, 7, 4));
    }

    unittest
    {
        assertThrown!DateTimeException(Date.fromISOString(""));
        assertThrown!DateTimeException(Date.fromISOString("990704"));
        assertThrown!DateTimeException(Date.fromISOString("0100704"));
        assertThrown!DateTimeException(Date.fromISOString("2010070"));
        assertThrown!DateTimeException(Date.fromISOString("2010070 "));
        assertThrown!DateTimeException(Date.fromISOString("120100704"));
        assertThrown!DateTimeException(Date.fromISOString("-0100704"));
        assertThrown!DateTimeException(Date.fromISOString("+0100704"));
        assertThrown!DateTimeException(Date.fromISOString("2010070a"));
        assertThrown!DateTimeException(Date.fromISOString("20100a04"));
        assertThrown!DateTimeException(Date.fromISOString("2010a704"));

        assertThrown!DateTimeException(Date.fromISOString("99-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("010-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-07-0"));
        assertThrown!DateTimeException(Date.fromISOString("2010-07-0 "));
        assertThrown!DateTimeException(Date.fromISOString("12010-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("-010-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("+010-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-07-0a"));
        assertThrown!DateTimeException(Date.fromISOString("2010-0a-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-a7-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010/07/04"));
        assertThrown!DateTimeException(Date.fromISOString("2010/7/04"));
        assertThrown!DateTimeException(Date.fromISOString("2010/7/4"));
        assertThrown!DateTimeException(Date.fromISOString("2010/07/4"));
        assertThrown!DateTimeException(Date.fromISOString("2010-7-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-7-4"));
        assertThrown!DateTimeException(Date.fromISOString("2010-07-4"));

        assertThrown!DateTimeException(Date.fromISOString("99Jul04"));
        assertThrown!DateTimeException(Date.fromISOString("010Jul04"));
        assertThrown!DateTimeException(Date.fromISOString("2010Jul0"));
        assertThrown!DateTimeException(Date.fromISOString("2010Jul0 "));
        assertThrown!DateTimeException(Date.fromISOString("12010Jul04"));
        assertThrown!DateTimeException(Date.fromISOString("-010Jul04"));
        assertThrown!DateTimeException(Date.fromISOString("+010Jul04"));
        assertThrown!DateTimeException(Date.fromISOString("2010Jul0a"));
        assertThrown!DateTimeException(Date.fromISOString("2010Jua04"));
        assertThrown!DateTimeException(Date.fromISOString("2010aul04"));

        assertThrown!DateTimeException(Date.fromISOString("99-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOString("010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jul-0"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jul-0 "));
        assertThrown!DateTimeException(Date.fromISOString("12010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOString("-010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOString("+010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jul-0a"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jua-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jal-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-aul-04"));

        assertThrown!DateTimeException(Date.fromISOString("2010-07-04"));
        assertThrown!DateTimeException(Date.fromISOString("2010-Jul-04"));

        assert(Date.fromISOString("19990706") == Date(1999, 7, 6));
        assert(Date.fromISOString("-19990706") == Date(-1999, 7, 6));
        assert(Date.fromISOString("+019990706") == Date(1999, 7, 6));
        assert(Date.fromISOString("19990706 ") == Date(1999, 7, 6));
        assert(Date.fromISOString(" 19990706") == Date(1999, 7, 6));
        assert(Date.fromISOString(" 19990706 ") == Date(1999, 7, 6));
    }


    /++
        Creates a $(LREF Date) from a string with the format YYYY-MM-DD. Whitespace
        is stripped from the given string.

        Params:
            isoExtString = A string formatted in the ISO Extended format for
                           dates.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO
            Extended format or if the resulting $(LREF Date) would not be valid.
      +/
    static Date fromISOExtString(S)(in S isoExtString) @safe pure
        if (isSomeString!(S))
    {
        import std.ascii : isDigit;
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : all, startsWith;

        auto dstr = to!dstring(strip(isoExtString));

        enforce(dstr.length >= 10, new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        auto day = dstr[$-2 .. $];
        auto month = dstr[$-5 .. $-3];
        auto year = dstr[0 .. $-6];

        enforce(dstr[$-3] == '-', new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(dstr[$-6] == '-', new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(all!isDigit(day),
                new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(all!isDigit(month),
                new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        if (year.length > 4)
        {
            enforce(year.startsWith('-', '+'),
                    new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
            enforce(all!isDigit(year[1..$]),
                    new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        }
        else
            enforce(all!isDigit(year),
                    new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        return Date(to!short(year), to!ubyte(month), to!ubyte(day));
    }

    ///
    unittest
    {
        assert(Date.fromISOExtString("2010-07-04") == Date(2010, 7, 4));
        assert(Date.fromISOExtString("1998-12-25") == Date(1998, 12, 25));
        assert(Date.fromISOExtString("0000-01-05") == Date(0, 1, 5));
        assert(Date.fromISOExtString("-0004-01-05") == Date(-4, 1, 5));
        assert(Date.fromISOExtString(" 2010-07-04 ") == Date(2010, 7, 4));
    }

    unittest
    {
        assertThrown!DateTimeException(Date.fromISOExtString(""));
        assertThrown!DateTimeException(Date.fromISOExtString("990704"));
        assertThrown!DateTimeException(Date.fromISOExtString("0100704"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010070"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010070 "));
        assertThrown!DateTimeException(Date.fromISOExtString("120100704"));
        assertThrown!DateTimeException(Date.fromISOExtString("-0100704"));
        assertThrown!DateTimeException(Date.fromISOExtString("+0100704"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010070a"));
        assertThrown!DateTimeException(Date.fromISOExtString("20100a04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010a704"));

        assertThrown!DateTimeException(Date.fromISOExtString("99-07-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("010-07-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-07-0"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-07-0 "));
        assertThrown!DateTimeException(Date.fromISOExtString("12010-07-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("-010-07-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("+010-07-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-07-0a"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-0a-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-a7-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010/07/04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010/7/04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010/7/4"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010/07/4"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-7-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-7-4"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-07-4"));

        assertThrown!DateTimeException(Date.fromISOExtString("99Jul04"));
        assertThrown!DateTimeException(Date.fromISOExtString("010Jul04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010Jul0"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jul-0 "));
        assertThrown!DateTimeException(Date.fromISOExtString("12010Jul04"));
        assertThrown!DateTimeException(Date.fromISOExtString("-010Jul04"));
        assertThrown!DateTimeException(Date.fromISOExtString("+010Jul04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010Jul0a"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010Jua04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010aul04"));

        assertThrown!DateTimeException(Date.fromISOExtString("99-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jul-0"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010Jul0 "));
        assertThrown!DateTimeException(Date.fromISOExtString("12010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("-010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("+010-Jul-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jul-0a"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jua-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jal-04"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-aul-04"));

        assertThrown!DateTimeException(Date.fromISOExtString("20100704"));
        assertThrown!DateTimeException(Date.fromISOExtString("2010-Jul-04"));

        assert(Date.fromISOExtString("1999-07-06") == Date(1999, 7, 6));
        assert(Date.fromISOExtString("-1999-07-06") == Date(-1999, 7, 6));
        assert(Date.fromISOExtString("+01999-07-06") == Date(1999, 7, 6));
        assert(Date.fromISOExtString("1999-07-06 ") == Date(1999, 7, 6));
        assert(Date.fromISOExtString(" 1999-07-06") == Date(1999, 7, 6));
        assert(Date.fromISOExtString(" 1999-07-06 ") == Date(1999, 7, 6));
    }


    /++
        Creates a $(LREF Date) from a string with the format YYYY-Mon-DD.
        Whitespace is stripped from the given string.

        Params:
            simpleString = A string formatted in the way that toSimpleString
                           formats dates.

        Throws:
            $(LREF DateTimeException) if the given string is not in the correct
            format or if the resulting $(LREF Date) would not be valid.
      +/
    static Date fromSimpleString(S)(in S simpleString) @safe pure
        if (isSomeString!(S))
    {
        import std.ascii : isDigit;
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : all, startsWith;

        auto dstr = to!dstring(strip(simpleString));

        enforce(dstr.length >= 11, new DateTimeException(format("Invalid string format: %s", simpleString)));

        auto day = dstr[$-2 .. $];
        auto month = monthFromString(to!string(dstr[$-6 .. $-3]));
        auto year = dstr[0 .. $-7];

        enforce(dstr[$-3] == '-', new DateTimeException(format("Invalid string format: %s", simpleString)));
        enforce(dstr[$-7] == '-', new DateTimeException(format("Invalid string format: %s", simpleString)));
        enforce(all!isDigit(day), new DateTimeException(format("Invalid string format: %s", simpleString)));

        if (year.length > 4)
        {
            enforce(year.startsWith('-', '+'),
                    new DateTimeException(format("Invalid string format: %s", simpleString)));
            enforce(all!isDigit(year[1..$]),
                    new DateTimeException(format("Invalid string format: %s", simpleString)));
        }
        else
            enforce(all!isDigit(year),
                    new DateTimeException(format("Invalid string format: %s", simpleString)));

        return Date(to!short(year), month, to!ubyte(day));
    }

    ///
    unittest
    {
        assert(Date.fromSimpleString("2010-Jul-04") == Date(2010, 7, 4));
        assert(Date.fromSimpleString("1998-Dec-25") == Date(1998, 12, 25));
        assert(Date.fromSimpleString("0000-Jan-05") == Date(0, 1, 5));
        assert(Date.fromSimpleString("-0004-Jan-05") == Date(-4, 1, 5));
        assert(Date.fromSimpleString(" 2010-Jul-04 ") == Date(2010, 7, 4));
    }

    unittest
    {
        assertThrown!DateTimeException(Date.fromSimpleString(""));
        assertThrown!DateTimeException(Date.fromSimpleString("990704"));
        assertThrown!DateTimeException(Date.fromSimpleString("0100704"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010070"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010070 "));
        assertThrown!DateTimeException(Date.fromSimpleString("120100704"));
        assertThrown!DateTimeException(Date.fromSimpleString("-0100704"));
        assertThrown!DateTimeException(Date.fromSimpleString("+0100704"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010070a"));
        assertThrown!DateTimeException(Date.fromSimpleString("20100a04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010a704"));

        assertThrown!DateTimeException(Date.fromSimpleString("99-07-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("010-07-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-07-0"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-07-0 "));
        assertThrown!DateTimeException(Date.fromSimpleString("12010-07-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("-010-07-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("+010-07-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-07-0a"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-0a-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-a7-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010/07/04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010/7/04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010/7/4"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010/07/4"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-7-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-7-4"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-07-4"));

        assertThrown!DateTimeException(Date.fromSimpleString("99Jul04"));
        assertThrown!DateTimeException(Date.fromSimpleString("010Jul04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010Jul0"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010Jul0 "));
        assertThrown!DateTimeException(Date.fromSimpleString("12010Jul04"));
        assertThrown!DateTimeException(Date.fromSimpleString("-010Jul04"));
        assertThrown!DateTimeException(Date.fromSimpleString("+010Jul04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010Jul0a"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010Jua04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010aul04"));

        assertThrown!DateTimeException(Date.fromSimpleString("99-Jul-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("010-Jul-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-Jul-0"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-Jul-0 "));
        assertThrown!DateTimeException(Date.fromSimpleString("12010-Jul-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("-010-Jul-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("+010-Jul-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-Jul-0a"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-Jua-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-Jal-04"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-aul-04"));

        assertThrown!DateTimeException(Date.fromSimpleString("20100704"));
        assertThrown!DateTimeException(Date.fromSimpleString("2010-07-04"));

        assert(Date.fromSimpleString("1999-Jul-06") == Date(1999, 7, 6));
        assert(Date.fromSimpleString("-1999-Jul-06") == Date(-1999, 7, 6));
        assert(Date.fromSimpleString("+01999-Jul-06") == Date(1999, 7, 6));
        assert(Date.fromSimpleString("1999-Jul-06 ") == Date(1999, 7, 6));
        assert(Date.fromSimpleString(" 1999-Jul-06") == Date(1999, 7, 6));
        assert(Date.fromSimpleString(" 1999-Jul-06 ") == Date(1999, 7, 6));
    }


    /++
        Returns the $(LREF Date) farthest in the past which is representable by
        $(LREF Date).
      +/
    @property static Date min() @safe pure nothrow
    {
        auto date = Date.init;
        date._year = short.min;
        date._month = Month.jan;
        date._day = 1;

        return date;
    }

    unittest
    {
        assert(Date.min.year < 0);
        assert(Date.min < Date.max);
    }


    /++
        Returns the $(LREF Date) farthest in the future which is representable by
        $(LREF Date).
      +/
    @property static Date max() @safe pure nothrow
    {
        auto date = Date.init;
        date._year = short.max;
        date._month = Month.dec;
        date._day = 31;

        return date;
    }

    unittest
    {
        assert(Date.max.year > 0);
        assert(Date.max > Date.min);
    }


private:

    /+
        Whether the given values form a valid date.

        Params:
            year  = The year to test.
            month = The month of the Gregorian Calendar to test.
            day   = The day of the month to test.
     +/
    static bool _valid(int year, int month, int day) @safe pure nothrow
    {
        if (!valid!"months"(month))
            return false;

        return valid!"days"(year, month, day);
    }

    /+
        Adds the given number of days to this $(LREF Date). A negative number will
        subtract.

        The month will be adjusted along with the day if the number of days
        added (or subtracted) would overflow (or underflow) the current month.
        The year will be adjusted along with the month if the increase (or
        decrease) to the month would cause it to overflow (or underflow) the
        current year.

        $(D _addDays(numDays)) is effectively equivalent to
        $(D date.dayOfGregorianCal = date.dayOfGregorianCal + days).

        Params:
            days = The number of days to add to this Date.
      +/
    ref Date _addDays(long days) return @safe pure nothrow
    {
        dayOfGregorianCal = cast(int)(dayOfGregorianCal + days);
        return this;
    }

    unittest
    {
        //Test A.D.
        {
            auto date = Date(1999, 2, 28);
            date._addDays(1);
            assert(date == Date(1999, 3, 1));
            date._addDays(-1);
            assert(date == Date(1999, 2, 28));
        }

        {
            auto date = Date(2000, 2, 28);
            date._addDays(1);
            assert(date == Date(2000, 2, 29));
            date._addDays(1);
            assert(date == Date(2000, 3, 1));
            date._addDays(-1);
            assert(date == Date(2000, 2, 29));
        }

        {
            auto date = Date(1999, 6, 30);
            date._addDays(1);
            assert(date == Date(1999, 7, 1));
            date._addDays(-1);
            assert(date == Date(1999, 6, 30));
        }

        {
            auto date = Date(1999, 7, 31);
            date._addDays(1);
            assert(date == Date(1999, 8, 1));
            date._addDays(-1);
            assert(date == Date(1999, 7, 31));
        }

        {
            auto date = Date(1999, 1, 1);
            date._addDays(-1);
            assert(date == Date(1998, 12, 31));
            date._addDays(1);
            assert(date == Date(1999, 1, 1));
        }

        {
            auto date = Date(1999, 7, 6);
            date._addDays(9);
            assert(date == Date(1999, 7, 15));
            date._addDays(-11);
            assert(date == Date(1999, 7, 4));
            date._addDays(30);
            assert(date == Date(1999, 8, 3));
            date._addDays(-3);
            assert(date == Date(1999, 7, 31));
        }

        {
            auto date = Date(1999, 7, 6);
            date._addDays(365);
            assert(date == Date(2000, 7, 5));
            date._addDays(-365);
            assert(date == Date(1999, 7, 6));
            date._addDays(366);
            assert(date == Date(2000, 7, 6));
            date._addDays(730);
            assert(date == Date(2002, 7, 6));
            date._addDays(-1096);
            assert(date == Date(1999, 7, 6));
        }

        //Test B.C.
        {
            auto date = Date(-1999, 2, 28);
            date._addDays(1);
            assert(date == Date(-1999, 3, 1));
            date._addDays(-1);
            assert(date == Date(-1999, 2, 28));
        }

        {
            auto date = Date(-2000, 2, 28);
            date._addDays(1);
            assert(date == Date(-2000, 2, 29));
            date._addDays(1);
            assert(date == Date(-2000, 3, 1));
            date._addDays(-1);
            assert(date == Date(-2000, 2, 29));
        }

        {
            auto date = Date(-1999, 6, 30);
            date._addDays(1);
            assert(date == Date(-1999, 7, 1));
            date._addDays(-1);
            assert(date == Date(-1999, 6, 30));
        }

        {
            auto date = Date(-1999, 7, 31);
            date._addDays(1);
            assert(date == Date(-1999, 8, 1));
            date._addDays(-1);
            assert(date == Date(-1999, 7, 31));
        }

        {
            auto date = Date(-1999, 1, 1);
            date._addDays(-1);
            assert(date == Date(-2000, 12, 31));
            date._addDays(1);
            assert(date == Date(-1999, 1, 1));
        }

        {
            auto date = Date(-1999, 7, 6);
            date._addDays(9);
            assert(date == Date(-1999, 7, 15));
            date._addDays(-11);
            assert(date == Date(-1999, 7, 4));
            date._addDays(30);
            assert(date == Date(-1999, 8, 3));
            date._addDays(-3);
        }

        {
            auto date = Date(-1999, 7, 6);
            date._addDays(365);
            assert(date == Date(-1998, 7, 6));
            date._addDays(-365);
            assert(date == Date(-1999, 7, 6));
            date._addDays(366);
            assert(date == Date(-1998, 7, 7));
            date._addDays(730);
            assert(date == Date(-1996, 7, 6));
            date._addDays(-1096);
            assert(date == Date(-1999, 7, 6));
        }

        //Test Both
        {
            auto date = Date(1, 7, 6);
            date._addDays(-365);
            assert(date == Date(0, 7, 6));
            date._addDays(365);
            assert(date == Date(1, 7, 6));
            date._addDays(-731);
            assert(date == Date(-1, 7, 6));
            date._addDays(730);
            assert(date == Date(1, 7, 5));
        }

        const cdate = Date(1999, 7, 6);
        immutable idate = Date(1999, 7, 6);
        static assert(!__traits(compiles, cdate._addDays(12)));
        static assert(!__traits(compiles, idate._addDays(12)));
    }


    @safe pure invariant()
    {
        assert(valid!"months"(_month),
               format("Invariant Failure: year [%s] month [%s] day [%s]", _year, _month, _day));
        assert(valid!"days"(_year, _month, _day),
               format("Invariant Failure: year [%s] month [%s] day [%s]", _year, _month, _day));
    }


    short _year  = 1;
    Month _month = Month.jan;
    ubyte _day   = 1;
}


/++
    Represents a time of day with hours, minutes, and seconds. It uses 24 hour
    time.
+/
struct TimeOfDay
{
    import std.exception : enforce;
    import std.format : format;

public:

    /++
        Params:
            hour   = Hour of the day [0 - 24$(RPAREN).
            minute = Minute of the hour [0 - 60$(RPAREN).
            second = Second of the minute [0 - 60$(RPAREN).

        Throws:
            $(LREF DateTimeException) if the resulting $(LREF TimeOfDay) would be not
            be valid.
     +/
    this(int hour, int minute, int second = 0) @safe pure
    {
        enforceValid!"hours"(hour);
        enforceValid!"minutes"(minute);
        enforceValid!"seconds"(second);

        _hour   = cast(ubyte)hour;
        _minute = cast(ubyte)minute;
        _second = cast(ubyte)second;
    }

    unittest
    {
        assert(TimeOfDay(0, 0) == TimeOfDay.init);

        {
            auto tod = TimeOfDay(0, 0);
            assert(tod._hour == 0);
            assert(tod._minute == 0);
            assert(tod._second == 0);
        }

        {
            auto tod = TimeOfDay(12, 30, 33);
            assert(tod._hour == 12);
            assert(tod._minute == 30);
            assert(tod._second == 33);
        }

        {
            auto tod = TimeOfDay(23, 59, 59);
            assert(tod._hour == 23);
            assert(tod._minute == 59);
            assert(tod._second == 59);
        }

        assertThrown!DateTimeException(TimeOfDay(24, 0, 0));
        assertThrown!DateTimeException(TimeOfDay(0, 60, 0));
        assertThrown!DateTimeException(TimeOfDay(0, 0, 60));
    }


    /++
        Compares this $(LREF TimeOfDay) with the given $(LREF TimeOfDay).

        Returns:
            $(BOOKTABLE,
            $(TR $(TD this &lt; rhs) $(TD &lt; 0))
            $(TR $(TD this == rhs) $(TD 0))
            $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(in TimeOfDay rhs) @safe const pure nothrow
    {
        if (_hour < rhs._hour)
            return -1;
        if (_hour > rhs._hour)
            return 1;

        if (_minute < rhs._minute)
            return -1;
        if (_minute > rhs._minute)
            return 1;

        if (_second < rhs._second)
            return -1;
        if (_second > rhs._second)
            return 1;

        return 0;
    }

    unittest
    {
        assert(TimeOfDay(0, 0, 0).opCmp(TimeOfDay.init) == 0);

        assert(TimeOfDay(0, 0, 0).opCmp(TimeOfDay(0, 0, 0)) == 0);
        assert(TimeOfDay(12, 0, 0).opCmp(TimeOfDay(12, 0, 0)) == 0);
        assert(TimeOfDay(0, 30, 0).opCmp(TimeOfDay(0, 30, 0)) == 0);
        assert(TimeOfDay(0, 0, 33).opCmp(TimeOfDay(0, 0, 33)) == 0);

        assert(TimeOfDay(12, 30, 0).opCmp(TimeOfDay(12, 30, 0)) == 0);
        assert(TimeOfDay(12, 30, 33).opCmp(TimeOfDay(12, 30, 33)) == 0);

        assert(TimeOfDay(0, 30, 33).opCmp(TimeOfDay(0, 30, 33)) == 0);
        assert(TimeOfDay(0, 0, 33).opCmp(TimeOfDay(0, 0, 33)) == 0);

        assert(TimeOfDay(12, 30, 33).opCmp(TimeOfDay(13, 30, 33)) < 0);
        assert(TimeOfDay(13, 30, 33).opCmp(TimeOfDay(12, 30, 33)) > 0);
        assert(TimeOfDay(12, 30, 33).opCmp(TimeOfDay(12, 31, 33)) < 0);
        assert(TimeOfDay(12, 31, 33).opCmp(TimeOfDay(12, 30, 33)) > 0);
        assert(TimeOfDay(12, 30, 33).opCmp(TimeOfDay(12, 30, 34)) < 0);
        assert(TimeOfDay(12, 30, 34).opCmp(TimeOfDay(12, 30, 33)) > 0);

        assert(TimeOfDay(13, 30, 33).opCmp(TimeOfDay(12, 30, 34)) > 0);
        assert(TimeOfDay(12, 30, 34).opCmp(TimeOfDay(13, 30, 33)) < 0);
        assert(TimeOfDay(13, 30, 33).opCmp(TimeOfDay(12, 31, 33)) > 0);
        assert(TimeOfDay(12, 31, 33).opCmp(TimeOfDay(13, 30, 33)) < 0);

        assert(TimeOfDay(12, 31, 33).opCmp(TimeOfDay(12, 30, 34)) > 0);
        assert(TimeOfDay(12, 30, 34).opCmp(TimeOfDay(12, 31, 33)) < 0);

        const ctod = TimeOfDay(12, 30, 33);
        immutable itod = TimeOfDay(12, 30, 33);
        static assert(__traits(compiles, ctod.opCmp(itod)));
        static assert(__traits(compiles, itod.opCmp(ctod)));
    }


    /++
        Hours past midnight.
     +/
    @property ubyte hour() @safe const pure nothrow
    {
        return _hour;
    }

    unittest
    {
        assert(TimeOfDay.init.hour == 0);
        assert(TimeOfDay(12, 0, 0).hour == 12);

        const ctod = TimeOfDay(12, 0, 0);
        immutable itod = TimeOfDay(12, 0, 0);
        static assert(__traits(compiles, ctod.hour == 12));
        static assert(__traits(compiles, itod.hour == 12));
    }


    /++
        Hours past midnight.

        Params:
            hour = The hour of the day to set this $(LREF TimeOfDay)'s hour to.

        Throws:
            $(LREF DateTimeException) if the given hour would result in an invalid
            $(LREF TimeOfDay).
     +/
    @property void hour(int hour) @safe pure
    {
        enforceValid!"hours"(hour);
        _hour = cast(ubyte)hour;
    }

    unittest
    {
        assertThrown!DateTimeException((){TimeOfDay(0, 0, 0).hour = 24;}());

        auto tod = TimeOfDay(0, 0, 0);
        tod.hour = 12;
        assert(tod == TimeOfDay(12, 0, 0));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.hour = 12));
        static assert(!__traits(compiles, itod.hour = 12));
    }


    /++
        Minutes past the hour.
     +/
    @property ubyte minute() @safe const pure nothrow
    {
        return _minute;
    }

    unittest
    {
        assert(TimeOfDay.init.minute == 0);
        assert(TimeOfDay(0, 30, 0).minute == 30);

        const ctod = TimeOfDay(0, 30, 0);
        immutable itod = TimeOfDay(0, 30, 0);
        static assert(__traits(compiles, ctod.minute == 30));
        static assert(__traits(compiles, itod.minute == 30));
    }


    /++
        Minutes past the hour.

        Params:
            minute = The minute to set this $(LREF TimeOfDay)'s minute to.

        Throws:
            $(LREF DateTimeException) if the given minute would result in an
            invalid $(LREF TimeOfDay).
     +/
    @property void minute(int minute) @safe pure
    {
        enforceValid!"minutes"(minute);
        _minute = cast(ubyte)minute;
    }

    unittest
    {
        assertThrown!DateTimeException((){TimeOfDay(0, 0, 0).minute = 60;}());

        auto tod = TimeOfDay(0, 0, 0);
        tod.minute = 30;
        assert(tod == TimeOfDay(0, 30, 0));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.minute = 30));
        static assert(!__traits(compiles, itod.minute = 30));
    }


    /++
        Seconds past the minute.
     +/
    @property ubyte second() @safe const pure nothrow
    {
        return _second;
    }

    unittest
    {
        assert(TimeOfDay.init.second == 0);
        assert(TimeOfDay(0, 0, 33).second == 33);

        const ctod = TimeOfDay(0, 0, 33);
        immutable itod = TimeOfDay(0, 0, 33);
        static assert(__traits(compiles, ctod.second == 33));
        static assert(__traits(compiles, itod.second == 33));
    }


    /++
        Seconds past the minute.

        Params:
            second = The second to set this $(LREF TimeOfDay)'s second to.

        Throws:
            $(LREF DateTimeException) if the given second would result in an
            invalid $(LREF TimeOfDay).
     +/
    @property void second(int second) @safe pure
    {
        enforceValid!"seconds"(second);
        _second = cast(ubyte)second;
    }

    unittest
    {
        assertThrown!DateTimeException((){TimeOfDay(0, 0, 0).second = 60;}());

        auto tod = TimeOfDay(0, 0, 0);
        tod.second = 33;
        assert(tod == TimeOfDay(0, 0, 33));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.second = 33));
        static assert(!__traits(compiles, itod.second = 33));
    }


    /++
        Adds the given number of units to this $(LREF TimeOfDay). A negative number
        will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. For instance, rolling a $(LREF TimeOfDay)
        one hours's worth of minutes gets the exact same
        $(LREF TimeOfDay).

        Accepted units are $(D "hours"), $(D "minutes"), and $(D "seconds").

        Params:
            units = The units to add.
            value = The number of $(D_PARAM units) to add to this
                    $(LREF TimeOfDay).
      +/
    ref TimeOfDay roll(string units)(long value) @safe pure nothrow
        if (units == "hours")
    {
        return this += dur!"hours"(value);
    }

    ///
    unittest
    {
        auto tod1 = TimeOfDay(7, 12, 0);
        tod1.roll!"hours"(1);
        assert(tod1 == TimeOfDay(8, 12, 0));

        auto tod2 = TimeOfDay(7, 12, 0);
        tod2.roll!"hours"(-1);
        assert(tod2 == TimeOfDay(6, 12, 0));

        auto tod3 = TimeOfDay(23, 59, 0);
        tod3.roll!"minutes"(1);
        assert(tod3 == TimeOfDay(23, 0, 0));

        auto tod4 = TimeOfDay(0, 0, 0);
        tod4.roll!"minutes"(-1);
        assert(tod4 == TimeOfDay(0, 59, 0));

        auto tod5 = TimeOfDay(23, 59, 59);
        tod5.roll!"seconds"(1);
        assert(tod5 == TimeOfDay(23, 59, 0));

        auto tod6 = TimeOfDay(0, 0, 0);
        tod6.roll!"seconds"(-1);
        assert(tod6 == TimeOfDay(0, 0, 59));
    }

    unittest
    {
        auto tod = TimeOfDay(12, 27, 2);
        tod.roll!"hours"(22).roll!"hours"(-7);
        assert(tod == TimeOfDay(3, 27, 2));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.roll!"hours"(53)));
        static assert(!__traits(compiles, itod.roll!"hours"(53)));
    }


    //Shares documentation with "hours" version.
    ref TimeOfDay roll(string units)(long value) @safe pure nothrow
        if (units == "minutes" ||
           units == "seconds")
    {
        enum memberVarStr = units[0 .. $ - 1];
        value %= 60;
        mixin(format("auto newVal = cast(ubyte)(_%s) + value;", memberVarStr));

        if (value < 0)
        {
            if (newVal < 0)
                newVal += 60;
        }
        else if (newVal >= 60)
            newVal -= 60;

        mixin(format("_%s = cast(ubyte)newVal;", memberVarStr));
        return this;
    }

    //Test roll!"minutes"().
    unittest
    {
        static void testTOD(TimeOfDay orig, int minutes, in TimeOfDay expected, size_t line = __LINE__)
        {
            orig.roll!"minutes"(minutes);
            assert(orig == expected);
        }

        testTOD(TimeOfDay(12, 30, 33), 0, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 1, TimeOfDay(12, 31, 33));
        testTOD(TimeOfDay(12, 30, 33), 2, TimeOfDay(12, 32, 33));
        testTOD(TimeOfDay(12, 30, 33), 3, TimeOfDay(12, 33, 33));
        testTOD(TimeOfDay(12, 30, 33), 4, TimeOfDay(12, 34, 33));
        testTOD(TimeOfDay(12, 30, 33), 5, TimeOfDay(12, 35, 33));
        testTOD(TimeOfDay(12, 30, 33), 10, TimeOfDay(12, 40, 33));
        testTOD(TimeOfDay(12, 30, 33), 15, TimeOfDay(12, 45, 33));
        testTOD(TimeOfDay(12, 30, 33), 29, TimeOfDay(12, 59, 33));
        testTOD(TimeOfDay(12, 30, 33), 30, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), 45, TimeOfDay(12, 15, 33));
        testTOD(TimeOfDay(12, 30, 33), 60, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 75, TimeOfDay(12, 45, 33));
        testTOD(TimeOfDay(12, 30, 33), 90, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), 100, TimeOfDay(12, 10, 33));

        testTOD(TimeOfDay(12, 30, 33), 689, TimeOfDay(12, 59, 33));
        testTOD(TimeOfDay(12, 30, 33), 690, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), 691, TimeOfDay(12, 1, 33));
        testTOD(TimeOfDay(12, 30, 33), 960, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 1439, TimeOfDay(12, 29, 33));
        testTOD(TimeOfDay(12, 30, 33), 1440, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 1441, TimeOfDay(12, 31, 33));
        testTOD(TimeOfDay(12, 30, 33), 2880, TimeOfDay(12, 30, 33));

        testTOD(TimeOfDay(12, 30, 33), -1, TimeOfDay(12, 29, 33));
        testTOD(TimeOfDay(12, 30, 33), -2, TimeOfDay(12, 28, 33));
        testTOD(TimeOfDay(12, 30, 33), -3, TimeOfDay(12, 27, 33));
        testTOD(TimeOfDay(12, 30, 33), -4, TimeOfDay(12, 26, 33));
        testTOD(TimeOfDay(12, 30, 33), -5, TimeOfDay(12, 25, 33));
        testTOD(TimeOfDay(12, 30, 33), -10, TimeOfDay(12, 20, 33));
        testTOD(TimeOfDay(12, 30, 33), -15, TimeOfDay(12, 15, 33));
        testTOD(TimeOfDay(12, 30, 33), -29, TimeOfDay(12, 1, 33));
        testTOD(TimeOfDay(12, 30, 33), -30, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), -45, TimeOfDay(12, 45, 33));
        testTOD(TimeOfDay(12, 30, 33), -60, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), -75, TimeOfDay(12, 15, 33));
        testTOD(TimeOfDay(12, 30, 33), -90, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), -100, TimeOfDay(12, 50, 33));

        testTOD(TimeOfDay(12, 30, 33), -749, TimeOfDay(12, 1, 33));
        testTOD(TimeOfDay(12, 30, 33), -750, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 30, 33), -751, TimeOfDay(12, 59, 33));
        testTOD(TimeOfDay(12, 30, 33), -960, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), -1439, TimeOfDay(12, 31, 33));
        testTOD(TimeOfDay(12, 30, 33), -1440, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), -1441, TimeOfDay(12, 29, 33));
        testTOD(TimeOfDay(12, 30, 33), -2880, TimeOfDay(12, 30, 33));

        testTOD(TimeOfDay(12, 0, 33), 1, TimeOfDay(12, 1, 33));
        testTOD(TimeOfDay(12, 0, 33), 0, TimeOfDay(12, 0, 33));
        testTOD(TimeOfDay(12, 0, 33), -1, TimeOfDay(12, 59, 33));

        testTOD(TimeOfDay(11, 59, 33), 1, TimeOfDay(11, 0, 33));
        testTOD(TimeOfDay(11, 59, 33), 0, TimeOfDay(11, 59, 33));
        testTOD(TimeOfDay(11, 59, 33), -1, TimeOfDay(11, 58, 33));

        testTOD(TimeOfDay(0, 0, 33), 1, TimeOfDay(0, 1, 33));
        testTOD(TimeOfDay(0, 0, 33), 0, TimeOfDay(0, 0, 33));
        testTOD(TimeOfDay(0, 0, 33), -1, TimeOfDay(0, 59, 33));

        testTOD(TimeOfDay(23, 59, 33), 1, TimeOfDay(23, 0, 33));
        testTOD(TimeOfDay(23, 59, 33), 0, TimeOfDay(23, 59, 33));
        testTOD(TimeOfDay(23, 59, 33), -1, TimeOfDay(23, 58, 33));

        auto tod = TimeOfDay(12, 27, 2);
        tod.roll!"minutes"(97).roll!"minutes"(-102);
        assert(tod == TimeOfDay(12, 22, 2));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.roll!"minutes"(7)));
        static assert(!__traits(compiles, itod.roll!"minutes"(7)));
    }

    //Test roll!"seconds"().
    unittest
    {
        static void testTOD(TimeOfDay orig, int seconds, in TimeOfDay expected, size_t line = __LINE__)
        {
            orig.roll!"seconds"(seconds);
            assert(orig == expected);
        }

        testTOD(TimeOfDay(12, 30, 33), 0, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 1, TimeOfDay(12, 30, 34));
        testTOD(TimeOfDay(12, 30, 33), 2, TimeOfDay(12, 30, 35));
        testTOD(TimeOfDay(12, 30, 33), 3, TimeOfDay(12, 30, 36));
        testTOD(TimeOfDay(12, 30, 33), 4, TimeOfDay(12, 30, 37));
        testTOD(TimeOfDay(12, 30, 33), 5, TimeOfDay(12, 30, 38));
        testTOD(TimeOfDay(12, 30, 33), 10, TimeOfDay(12, 30, 43));
        testTOD(TimeOfDay(12, 30, 33), 15, TimeOfDay(12, 30, 48));
        testTOD(TimeOfDay(12, 30, 33), 26, TimeOfDay(12, 30, 59));
        testTOD(TimeOfDay(12, 30, 33), 27, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 33), 30, TimeOfDay(12, 30, 3));
        testTOD(TimeOfDay(12, 30, 33), 59, TimeOfDay(12, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), 60, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 61, TimeOfDay(12, 30, 34));

        testTOD(TimeOfDay(12, 30, 33), 1766, TimeOfDay(12, 30, 59));
        testTOD(TimeOfDay(12, 30, 33), 1767, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 33), 1768, TimeOfDay(12, 30, 1));
        testTOD(TimeOfDay(12, 30, 33), 2007, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 33), 3599, TimeOfDay(12, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), 3600, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 3601, TimeOfDay(12, 30, 34));
        testTOD(TimeOfDay(12, 30, 33), 7200, TimeOfDay(12, 30, 33));

        testTOD(TimeOfDay(12, 30, 33), -1, TimeOfDay(12, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), -2, TimeOfDay(12, 30, 31));
        testTOD(TimeOfDay(12, 30, 33), -3, TimeOfDay(12, 30, 30));
        testTOD(TimeOfDay(12, 30, 33), -4, TimeOfDay(12, 30, 29));
        testTOD(TimeOfDay(12, 30, 33), -5, TimeOfDay(12, 30, 28));
        testTOD(TimeOfDay(12, 30, 33), -10, TimeOfDay(12, 30, 23));
        testTOD(TimeOfDay(12, 30, 33), -15, TimeOfDay(12, 30, 18));
        testTOD(TimeOfDay(12, 30, 33), -33, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 33), -34, TimeOfDay(12, 30, 59));
        testTOD(TimeOfDay(12, 30, 33), -35, TimeOfDay(12, 30, 58));
        testTOD(TimeOfDay(12, 30, 33), -59, TimeOfDay(12, 30, 34));
        testTOD(TimeOfDay(12, 30, 33), -60, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), -61, TimeOfDay(12, 30, 32));

        testTOD(TimeOfDay(12, 30, 0), 1, TimeOfDay(12, 30, 1));
        testTOD(TimeOfDay(12, 30, 0), 0, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 0), -1, TimeOfDay(12, 30, 59));

        testTOD(TimeOfDay(12, 0, 0), 1, TimeOfDay(12, 0, 1));
        testTOD(TimeOfDay(12, 0, 0), 0, TimeOfDay(12, 0, 0));
        testTOD(TimeOfDay(12, 0, 0), -1, TimeOfDay(12, 0, 59));

        testTOD(TimeOfDay(0, 0, 0), 1, TimeOfDay(0, 0, 1));
        testTOD(TimeOfDay(0, 0, 0), 0, TimeOfDay(0, 0, 0));
        testTOD(TimeOfDay(0, 0, 0), -1, TimeOfDay(0, 0, 59));

        testTOD(TimeOfDay(23, 59, 59), 1, TimeOfDay(23, 59, 0));
        testTOD(TimeOfDay(23, 59, 59), 0, TimeOfDay(23, 59, 59));
        testTOD(TimeOfDay(23, 59, 59), -1, TimeOfDay(23, 59, 58));

        auto tod = TimeOfDay(12, 27, 2);
        tod.roll!"seconds"(105).roll!"seconds"(-77);
        assert(tod == TimeOfDay(12, 27, 30));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod.roll!"seconds"(7)));
        static assert(!__traits(compiles, itod.roll!"seconds"(7)));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF TimeOfDay).

        The legal types of arithmetic for $(LREF TimeOfDay) using this operator are

        $(BOOKTABLE,
        $(TR $(TD TimeOfDay) $(TD +) $(TD duration) $(TD -->) $(TD TimeOfDay))
        $(TR $(TD TimeOfDay) $(TD -) $(TD duration) $(TD -->) $(TD TimeOfDay))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF TimeOfDay).
      +/
    TimeOfDay opBinary(string op, D)(in D duration) @safe const pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        TimeOfDay retval = this;

        static if (is(Unqual!D == Duration))
            immutable hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            immutable hnsecs = duration.hnsecs;

        mixin(format(`return retval._addSeconds(convert!("hnsecs", "seconds")(%shnsecs));`, op));
    }

    unittest
    {
        auto tod = TimeOfDay(12, 30, 33);

        assert(tod + dur!"hours"(7) == TimeOfDay(19, 30, 33));
        assert(tod + dur!"hours"(-7) == TimeOfDay(5, 30, 33));
        assert(tod + dur!"minutes"(7) == TimeOfDay(12, 37, 33));
        assert(tod + dur!"minutes"(-7) == TimeOfDay(12, 23, 33));
        assert(tod + dur!"seconds"(7) == TimeOfDay(12, 30, 40));
        assert(tod + dur!"seconds"(-7) == TimeOfDay(12, 30, 26));

        assert(tod + dur!"msecs"(7000) == TimeOfDay(12, 30, 40));
        assert(tod + dur!"msecs"(-7000) == TimeOfDay(12, 30, 26));
        assert(tod + dur!"usecs"(7_000_000) == TimeOfDay(12, 30, 40));
        assert(tod + dur!"usecs"(-7_000_000) == TimeOfDay(12, 30, 26));
        assert(tod + dur!"hnsecs"(70_000_000) == TimeOfDay(12, 30, 40));
        assert(tod + dur!"hnsecs"(-70_000_000) == TimeOfDay(12, 30, 26));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(tod + TickDuration.from!"usecs"(7_000_000) == TimeOfDay(12, 30, 40));
            assert(tod + TickDuration.from!"usecs"(-7_000_000) == TimeOfDay(12, 30, 26));
        }

        assert(tod - dur!"hours"(-7) == TimeOfDay(19, 30, 33));
        assert(tod - dur!"hours"(7) == TimeOfDay(5, 30, 33));
        assert(tod - dur!"minutes"(-7) == TimeOfDay(12, 37, 33));
        assert(tod - dur!"minutes"(7) == TimeOfDay(12, 23, 33));
        assert(tod - dur!"seconds"(-7) == TimeOfDay(12, 30, 40));
        assert(tod - dur!"seconds"(7) == TimeOfDay(12, 30, 26));

        assert(tod - dur!"msecs"(-7000) == TimeOfDay(12, 30, 40));
        assert(tod - dur!"msecs"(7000) == TimeOfDay(12, 30, 26));
        assert(tod - dur!"usecs"(-7_000_000) == TimeOfDay(12, 30, 40));
        assert(tod - dur!"usecs"(7_000_000) == TimeOfDay(12, 30, 26));
        assert(tod - dur!"hnsecs"(-70_000_000) == TimeOfDay(12, 30, 40));
        assert(tod - dur!"hnsecs"(70_000_000) == TimeOfDay(12, 30, 26));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(tod - TickDuration.from!"usecs"(-7_000_000) == TimeOfDay(12, 30, 40));
            assert(tod - TickDuration.from!"usecs"(7_000_000) == TimeOfDay(12, 30, 26));
        }

        auto duration = dur!"hours"(11);
        const ctod = TimeOfDay(12, 33, 30);
        immutable itod = TimeOfDay(12, 33, 30);
        static assert(__traits(compiles, tod + duration));
        static assert(__traits(compiles, ctod + duration));
        static assert(__traits(compiles, itod + duration));

        static assert(__traits(compiles, tod - duration));
        static assert(__traits(compiles, ctod - duration));
        static assert(__traits(compiles, itod - duration));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF TimeOfDay), as well as assigning the result to this
        $(LREF TimeOfDay).

        The legal types of arithmetic for $(LREF TimeOfDay) using this operator are

        $(BOOKTABLE,
        $(TR $(TD TimeOfDay) $(TD +) $(TD duration) $(TD -->) $(TD TimeOfDay))
        $(TR $(TD TimeOfDay) $(TD -) $(TD duration) $(TD -->) $(TD TimeOfDay))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF TimeOfDay).
      +/
    ref TimeOfDay opOpAssign(string op, D)(in D duration) @safe pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        static if (is(Unqual!D == Duration))
            immutable hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            immutable hnsecs = duration.hnsecs;

        mixin(format(`return _addSeconds(convert!("hnsecs", "seconds")(%shnsecs));`, op));
    }

    unittest
    {
        auto duration = dur!"hours"(12);

        assert(TimeOfDay(12, 30, 33) + dur!"hours"(7) == TimeOfDay(19, 30, 33));
        assert(TimeOfDay(12, 30, 33) + dur!"hours"(-7) == TimeOfDay(5, 30, 33));
        assert(TimeOfDay(12, 30, 33) + dur!"minutes"(7) == TimeOfDay(12, 37, 33));
        assert(TimeOfDay(12, 30, 33) + dur!"minutes"(-7) == TimeOfDay(12, 23, 33));
        assert(TimeOfDay(12, 30, 33) + dur!"seconds"(7) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) + dur!"seconds"(-7) == TimeOfDay(12, 30, 26));

        assert(TimeOfDay(12, 30, 33) + dur!"msecs"(7000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) + dur!"msecs"(-7000) == TimeOfDay(12, 30, 26));
        assert(TimeOfDay(12, 30, 33) + dur!"usecs"(7_000_000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) + dur!"usecs"(-7_000_000) == TimeOfDay(12, 30, 26));
        assert(TimeOfDay(12, 30, 33) + dur!"hnsecs"(70_000_000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) + dur!"hnsecs"(-70_000_000) == TimeOfDay(12, 30, 26));

        assert(TimeOfDay(12, 30, 33) - dur!"hours"(-7) == TimeOfDay(19, 30, 33));
        assert(TimeOfDay(12, 30, 33) - dur!"hours"(7) == TimeOfDay(5, 30, 33));
        assert(TimeOfDay(12, 30, 33) - dur!"minutes"(-7) == TimeOfDay(12, 37, 33));
        assert(TimeOfDay(12, 30, 33) - dur!"minutes"(7) == TimeOfDay(12, 23, 33));
        assert(TimeOfDay(12, 30, 33) - dur!"seconds"(-7) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) - dur!"seconds"(7) == TimeOfDay(12, 30, 26));

        assert(TimeOfDay(12, 30, 33) - dur!"msecs"(-7000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) - dur!"msecs"(7000) == TimeOfDay(12, 30, 26));
        assert(TimeOfDay(12, 30, 33) - dur!"usecs"(-7_000_000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) - dur!"usecs"(7_000_000) == TimeOfDay(12, 30, 26));
        assert(TimeOfDay(12, 30, 33) - dur!"hnsecs"(-70_000_000) == TimeOfDay(12, 30, 40));
        assert(TimeOfDay(12, 30, 33) - dur!"hnsecs"(70_000_000) == TimeOfDay(12, 30, 26));

        auto tod = TimeOfDay(19, 17, 22);
        (tod += dur!"seconds"(9)) += dur!"seconds"(-7292);
        assert(tod == TimeOfDay(17, 15, 59));

        const ctod = TimeOfDay(12, 33, 30);
        immutable itod = TimeOfDay(12, 33, 30);
        static assert(!__traits(compiles, ctod += duration));
        static assert(!__traits(compiles, itod += duration));
        static assert(!__traits(compiles, ctod -= duration));
        static assert(!__traits(compiles, itod -= duration));
    }


    /++
        Gives the difference between two $(LREF TimeOfDay)s.

        The legal types of arithmetic for $(LREF TimeOfDay) using this operator are

        $(BOOKTABLE,
        $(TR $(TD TimeOfDay) $(TD -) $(TD TimeOfDay) $(TD -->) $(TD duration))
        )

        Params:
            rhs = The $(LREF TimeOfDay) to subtract from this one.
      +/
    Duration opBinary(string op)(in TimeOfDay rhs) @safe const pure nothrow
        if (op == "-")
    {
        immutable lhsSec = _hour * 3600 + _minute * 60 + _second;
        immutable rhsSec = rhs._hour * 3600 + rhs._minute * 60 + rhs._second;

        return dur!"seconds"(lhsSec - rhsSec);
    }

    unittest
    {
        auto tod = TimeOfDay(12, 30, 33);

        assert(TimeOfDay(7, 12, 52) - TimeOfDay(12, 30, 33) == dur!"seconds"(-19_061));
        assert(TimeOfDay(12, 30, 33) - TimeOfDay(7, 12, 52) == dur!"seconds"(19_061));
        assert(TimeOfDay(12, 30, 33) - TimeOfDay(14, 30, 33) == dur!"seconds"(-7200));
        assert(TimeOfDay(14, 30, 33) - TimeOfDay(12, 30, 33) == dur!"seconds"(7200));
        assert(TimeOfDay(12, 30, 33) - TimeOfDay(12, 34, 33) == dur!"seconds"(-240));
        assert(TimeOfDay(12, 34, 33) - TimeOfDay(12, 30, 33) == dur!"seconds"(240));
        assert(TimeOfDay(12, 30, 33) - TimeOfDay(12, 30, 34) == dur!"seconds"(-1));
        assert(TimeOfDay(12, 30, 34) - TimeOfDay(12, 30, 33) == dur!"seconds"(1));

        const ctod = TimeOfDay(12, 30, 33);
        immutable itod = TimeOfDay(12, 30, 33);
        static assert(__traits(compiles, tod - tod));
        static assert(__traits(compiles, ctod - tod));
        static assert(__traits(compiles, itod - tod));

        static assert(__traits(compiles, tod - ctod));
        static assert(__traits(compiles, ctod - ctod));
        static assert(__traits(compiles, itod - ctod));

        static assert(__traits(compiles, tod - itod));
        static assert(__traits(compiles, ctod - itod));
        static assert(__traits(compiles, itod - itod));
    }


    /++
        Converts this $(LREF TimeOfDay) to a string with the format HHMMSS.
      +/
    string toISOString() @safe const pure nothrow
    {
        scope(failure) assert(0, "format() threw.");
        return format("%02d%02d%02d", _hour, _minute, _second);
    }

    ///
    unittest
    {
        assert(TimeOfDay(0, 0, 0).toISOString() == "000000");
        assert(TimeOfDay(12, 30, 33).toISOString() == "123033");
    }

    unittest
    {
        auto tod = TimeOfDay(12, 30, 33);
        const ctod = TimeOfDay(12, 30, 33);
        immutable itod = TimeOfDay(12, 30, 33);
        static assert(__traits(compiles, tod.toISOString()));
        static assert(__traits(compiles, ctod.toISOString()));
        static assert(__traits(compiles, itod.toISOString()));
    }


    /++
        Converts this $(LREF TimeOfDay) to a string with the format HH:MM:SS.
      +/
    string toISOExtString() @safe const pure nothrow
    {
        scope(failure) assert(0, "format() threw.");
        return format("%02d:%02d:%02d", _hour, _minute, _second);
    }

    ///
    unittest
    {
        assert(TimeOfDay(0, 0, 0).toISOExtString() == "00:00:00");
        assert(TimeOfDay(12, 30, 33).toISOExtString() == "12:30:33");
    }

    unittest
    {
        auto tod = TimeOfDay(12, 30, 33);
        const ctod = TimeOfDay(12, 30, 33);
        immutable itod = TimeOfDay(12, 30, 33);
        static assert(__traits(compiles, tod.toISOExtString()));
        static assert(__traits(compiles, ctod.toISOExtString()));
        static assert(__traits(compiles, itod.toISOExtString()));
    }


    /++
        Converts this TimeOfDay to a string.
      +/
    string toString() @safe const pure nothrow
    {
        return toISOExtString();
    }

    unittest
    {
        auto tod = TimeOfDay(12, 30, 33);
        const ctod = TimeOfDay(12, 30, 33);
        immutable itod = TimeOfDay(12, 30, 33);
        static assert(__traits(compiles, tod.toString()));
        static assert(__traits(compiles, ctod.toString()));
        static assert(__traits(compiles, itod.toString()));
    }


    /++
        Creates a $(LREF TimeOfDay) from a string with the format HHMMSS.
        Whitespace is stripped from the given string.

        Params:
            isoString = A string formatted in the ISO format for times.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF TimeOfDay) would not be valid.
      +/
    static TimeOfDay fromISOString(S)(in S isoString) @safe pure
        if (isSomeString!S)
    {
        import std.ascii : isDigit;
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : all;

        auto dstr = to!dstring(strip(isoString));

        enforce(dstr.length == 6, new DateTimeException(format("Invalid ISO String: %s", isoString)));

        auto hours = dstr[0 .. 2];
        auto minutes = dstr[2 .. 4];
        auto seconds = dstr[4 .. $];

        enforce(all!isDigit(hours), new DateTimeException(format("Invalid ISO String: %s", isoString)));
        enforce(all!isDigit(minutes), new DateTimeException(format("Invalid ISO String: %s", isoString)));
        enforce(all!isDigit(seconds), new DateTimeException(format("Invalid ISO String: %s", isoString)));

        return TimeOfDay(to!int(hours), to!int(minutes), to!int(seconds));
    }

    ///
    unittest
    {
        assert(TimeOfDay.fromISOString("000000") == TimeOfDay(0, 0, 0));
        assert(TimeOfDay.fromISOString("123033") == TimeOfDay(12, 30, 33));
        assert(TimeOfDay.fromISOString(" 123033 ") == TimeOfDay(12, 30, 33));
    }

    unittest
    {
        assertThrown!DateTimeException(TimeOfDay.fromISOString(""));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("00000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("13033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("1277"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12707"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12070"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12303a"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("1230a3"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("123a33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12a033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("1a0033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("a20033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("1200330"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("-120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("+120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("120033am"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("120033pm"));

        assertThrown!DateTimeException(TimeOfDay.fromISOString("0::"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString(":0:"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("::0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0:0:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0:0:00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("0:00:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("00:0:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("00:00:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("00:0:00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("13:0:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:7:7"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:7:07"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:07:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:30:3a"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:30:a3"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:3a:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:a0:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("1a:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("a2:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:003:30"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("120:03:30"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("012:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("01:200:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("-12:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("+12:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:00:33am"));
        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:00:33pm"));

        assertThrown!DateTimeException(TimeOfDay.fromISOString("12:00:33"));

        assert(TimeOfDay.fromISOString("011217") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOString("001412") == TimeOfDay(0, 14, 12));
        assert(TimeOfDay.fromISOString("000007") == TimeOfDay(0, 0, 7));
        assert(TimeOfDay.fromISOString("011217 ") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOString(" 011217") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOString(" 011217 ") == TimeOfDay(1, 12, 17));
    }


    /++
        Creates a $(LREF TimeOfDay) from a string with the format HH:MM:SS.
        Whitespace is stripped from the given string.

        Params:
            isoExtString = A string formatted in the ISO Extended format for times.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO
            Extended format or if the resulting $(LREF TimeOfDay) would not be
            valid.
      +/
    static TimeOfDay fromISOExtString(S)(in S isoExtString) @safe pure
        if (isSomeString!S)
    {
        import std.ascii : isDigit;
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : all;

        auto dstr = to!dstring(strip(isoExtString));

        enforce(dstr.length == 8, new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        auto hours = dstr[0 .. 2];
        auto minutes = dstr[3 .. 5];
        auto seconds = dstr[6 .. $];

        enforce(dstr[2] == ':', new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(dstr[5] == ':', new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(all!isDigit(hours),
                new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(all!isDigit(minutes),
                new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        enforce(all!isDigit(seconds),
                new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        return TimeOfDay(to!int(hours), to!int(minutes), to!int(seconds));
    }

    ///
    unittest
    {
        assert(TimeOfDay.fromISOExtString("00:00:00") == TimeOfDay(0, 0, 0));
        assert(TimeOfDay.fromISOExtString("12:30:33") == TimeOfDay(12, 30, 33));
        assert(TimeOfDay.fromISOExtString(" 12:30:33 ") == TimeOfDay(12, 30, 33));
    }

    unittest
    {
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString(""));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("00000"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("13033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("1277"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12707"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12070"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12303a"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("1230a3"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("123a33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12a033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("1a0033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("a20033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("1200330"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("-120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("+120033"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("120033am"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("120033pm"));

        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0::"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString(":0:"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("::0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0:0:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0:0:00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("0:00:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("00:0:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("00:00:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("00:0:00"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("13:0:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:7:7"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:7:07"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:07:0"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:30:3a"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:30:a3"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:3a:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:a0:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("1a:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("a2:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:003:30"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("120:03:30"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("012:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("01:200:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("-12:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("+12:00:33"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:00:33am"));
        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("12:00:33pm"));

        assertThrown!DateTimeException(TimeOfDay.fromISOExtString("120033"));

        assert(TimeOfDay.fromISOExtString("01:12:17") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOExtString("00:14:12") == TimeOfDay(0, 14, 12));
        assert(TimeOfDay.fromISOExtString("00:00:07") == TimeOfDay(0, 0, 7));
        assert(TimeOfDay.fromISOExtString("01:12:17 ") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOExtString(" 01:12:17") == TimeOfDay(1, 12, 17));
        assert(TimeOfDay.fromISOExtString(" 01:12:17 ") == TimeOfDay(1, 12, 17));
    }


    /++
        Returns midnight.
      +/
    @property static TimeOfDay min() @safe pure nothrow
    {
        return TimeOfDay.init;
    }

    unittest
    {
        assert(TimeOfDay.min.hour == 0);
        assert(TimeOfDay.min.minute == 0);
        assert(TimeOfDay.min.second == 0);
        assert(TimeOfDay.min < TimeOfDay.max);
    }


    /++
        Returns one second short of midnight.
      +/
    @property static TimeOfDay max() @safe pure nothrow
    {
        auto tod = TimeOfDay.init;
        tod._hour = maxHour;
        tod._minute = maxMinute;
        tod._second = maxSecond;

        return tod;
    }

    unittest
    {
        assert(TimeOfDay.max.hour == 23);
        assert(TimeOfDay.max.minute == 59);
        assert(TimeOfDay.max.second == 59);
        assert(TimeOfDay.max > TimeOfDay.min);
    }


package:

    /+
        Add seconds to the time of day. Negative values will subtract. If the
        number of seconds overflows (or underflows), then the seconds will wrap,
        increasing (or decreasing) the number of minutes accordingly. If the
        number of minutes overflows (or underflows), then the minutes will wrap.
        If the number of minutes overflows(or underflows), then the hour will
        wrap. (e.g. adding 90 seconds to 23:59:00 would result in 00:00:30).

        Params:
            seconds = The number of seconds to add to this TimeOfDay.
      +/
    ref TimeOfDay _addSeconds(long seconds) return @safe pure nothrow
    {
        long hnsecs = convert!("seconds", "hnsecs")(seconds);
        hnsecs += convert!("hours", "hnsecs")(_hour);
        hnsecs += convert!("minutes", "hnsecs")(_minute);
        hnsecs += convert!("seconds", "hnsecs")(_second);

        hnsecs %= convert!("days", "hnsecs")(1);

        if (hnsecs < 0)
            hnsecs += convert!("days", "hnsecs")(1);

        immutable newHours = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable newMinutes = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable newSeconds = splitUnitsFromHNSecs!"seconds"(hnsecs);

        _hour = cast(ubyte)newHours;
        _minute = cast(ubyte)newMinutes;
        _second = cast(ubyte)newSeconds;

        return this;
    }

    unittest
    {
        static void testTOD(TimeOfDay orig, int seconds, in TimeOfDay expected, size_t line = __LINE__)
        {
            orig._addSeconds(seconds);
            assert(orig == expected);
        }

        testTOD(TimeOfDay(12, 30, 33), 0, TimeOfDay(12, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 1, TimeOfDay(12, 30, 34));
        testTOD(TimeOfDay(12, 30, 33), 2, TimeOfDay(12, 30, 35));
        testTOD(TimeOfDay(12, 30, 33), 3, TimeOfDay(12, 30, 36));
        testTOD(TimeOfDay(12, 30, 33), 4, TimeOfDay(12, 30, 37));
        testTOD(TimeOfDay(12, 30, 33), 5, TimeOfDay(12, 30, 38));
        testTOD(TimeOfDay(12, 30, 33), 10, TimeOfDay(12, 30, 43));
        testTOD(TimeOfDay(12, 30, 33), 15, TimeOfDay(12, 30, 48));
        testTOD(TimeOfDay(12, 30, 33), 26, TimeOfDay(12, 30, 59));
        testTOD(TimeOfDay(12, 30, 33), 27, TimeOfDay(12, 31, 0));
        testTOD(TimeOfDay(12, 30, 33), 30, TimeOfDay(12, 31, 3));
        testTOD(TimeOfDay(12, 30, 33), 59, TimeOfDay(12, 31, 32));
        testTOD(TimeOfDay(12, 30, 33), 60, TimeOfDay(12, 31, 33));
        testTOD(TimeOfDay(12, 30, 33), 61, TimeOfDay(12, 31, 34));

        testTOD(TimeOfDay(12, 30, 33), 1766, TimeOfDay(12, 59, 59));
        testTOD(TimeOfDay(12, 30, 33), 1767, TimeOfDay(13, 0, 0));
        testTOD(TimeOfDay(12, 30, 33), 1768, TimeOfDay(13, 0, 1));
        testTOD(TimeOfDay(12, 30, 33), 2007, TimeOfDay(13, 4, 0));
        testTOD(TimeOfDay(12, 30, 33), 3599, TimeOfDay(13, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), 3600, TimeOfDay(13, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), 3601, TimeOfDay(13, 30, 34));
        testTOD(TimeOfDay(12, 30, 33), 7200, TimeOfDay(14, 30, 33));

        testTOD(TimeOfDay(12, 30, 33), -1, TimeOfDay(12, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), -2, TimeOfDay(12, 30, 31));
        testTOD(TimeOfDay(12, 30, 33), -3, TimeOfDay(12, 30, 30));
        testTOD(TimeOfDay(12, 30, 33), -4, TimeOfDay(12, 30, 29));
        testTOD(TimeOfDay(12, 30, 33), -5, TimeOfDay(12, 30, 28));
        testTOD(TimeOfDay(12, 30, 33), -10, TimeOfDay(12, 30, 23));
        testTOD(TimeOfDay(12, 30, 33), -15, TimeOfDay(12, 30, 18));
        testTOD(TimeOfDay(12, 30, 33), -33, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 33), -34, TimeOfDay(12, 29, 59));
        testTOD(TimeOfDay(12, 30, 33), -35, TimeOfDay(12, 29, 58));
        testTOD(TimeOfDay(12, 30, 33), -59, TimeOfDay(12, 29, 34));
        testTOD(TimeOfDay(12, 30, 33), -60, TimeOfDay(12, 29, 33));
        testTOD(TimeOfDay(12, 30, 33), -61, TimeOfDay(12, 29, 32));

        testTOD(TimeOfDay(12, 30, 33), -1833, TimeOfDay(12, 0, 0));
        testTOD(TimeOfDay(12, 30, 33), -1834, TimeOfDay(11, 59, 59));
        testTOD(TimeOfDay(12, 30, 33), -3600, TimeOfDay(11, 30, 33));
        testTOD(TimeOfDay(12, 30, 33), -3601, TimeOfDay(11, 30, 32));
        testTOD(TimeOfDay(12, 30, 33), -5134, TimeOfDay(11, 4, 59));
        testTOD(TimeOfDay(12, 30, 33), -7200, TimeOfDay(10, 30, 33));

        testTOD(TimeOfDay(12, 30, 0), 1, TimeOfDay(12, 30, 1));
        testTOD(TimeOfDay(12, 30, 0), 0, TimeOfDay(12, 30, 0));
        testTOD(TimeOfDay(12, 30, 0), -1, TimeOfDay(12, 29, 59));

        testTOD(TimeOfDay(12, 0, 0), 1, TimeOfDay(12, 0, 1));
        testTOD(TimeOfDay(12, 0, 0), 0, TimeOfDay(12, 0, 0));
        testTOD(TimeOfDay(12, 0, 0), -1, TimeOfDay(11, 59, 59));

        testTOD(TimeOfDay(0, 0, 0), 1, TimeOfDay(0, 0, 1));
        testTOD(TimeOfDay(0, 0, 0), 0, TimeOfDay(0, 0, 0));
        testTOD(TimeOfDay(0, 0, 0), -1, TimeOfDay(23, 59, 59));

        testTOD(TimeOfDay(23, 59, 59), 1, TimeOfDay(0, 0, 0));
        testTOD(TimeOfDay(23, 59, 59), 0, TimeOfDay(23, 59, 59));
        testTOD(TimeOfDay(23, 59, 59), -1, TimeOfDay(23, 59, 58));

        const ctod = TimeOfDay(0, 0, 0);
        immutable itod = TimeOfDay(0, 0, 0);
        static assert(!__traits(compiles, ctod._addSeconds(7)));
        static assert(!__traits(compiles, itod._addSeconds(7)));
    }


    /+
        Whether the given values form a valid $(LREF TimeOfDay).
     +/
    static bool _valid(int hour, int minute, int second) @safe pure nothrow
    {
        return valid!"hours"(hour) && valid!"minutes"(minute) && valid!"seconds"(second);
    }


    @safe pure invariant()
    {
        assert(_valid(_hour, _minute, _second),
               format("Invariant Failure: hour [%s] minute [%s] second [%s]", _hour, _minute, _second));
    }

    ubyte _hour;
    ubyte _minute;
    ubyte _second;

    enum ubyte maxHour   = 24 - 1;
    enum ubyte maxMinute = 60 - 1;
    enum ubyte maxSecond = 60 - 1;
}


/++
   Combines the $(LREF Date) and $(LREF TimeOfDay) structs to give an object
   which holds both the date and the time. It is optimized for calendar-based
   operations and has no concept of time zone. For an object which is
   optimized for time operations based on the system time, use
   $(LREF SysTime). $(LREF SysTime) has a concept of time zone and has much higher
   precision (hnsecs). $(D DateTime) is intended primarily for calendar-based
   uses rather than precise time operations.
  +/
struct DateTime
{
public:

    /++
        Params:
            date = The date portion of $(LREF DateTime).
            tod  = The time portion of $(LREF DateTime).
      +/
    this(in Date date, in TimeOfDay tod = TimeOfDay.init) @safe pure nothrow
    {
        _date = date;
        _tod = tod;
    }

    unittest
    {
        {
            auto dt = DateTime.init;
            assert(dt._date == Date.init);
            assert(dt._tod == TimeOfDay.init);
        }

        {
            auto dt = DateTime(Date(1999, 7 ,6));
            assert(dt._date == Date(1999, 7, 6));
            assert(dt._tod == TimeOfDay.init);
        }

        {
            auto dt = DateTime(Date(1999, 7 ,6), TimeOfDay(12, 30, 33));
            assert(dt._date == Date(1999, 7, 6));
            assert(dt._tod == TimeOfDay(12, 30, 33));
        }
    }


    /++
        Params:
            year   = The year portion of the date.
            month  = The month portion of the date.
            day    = The day portion of the date.
            hour   = The hour portion of the time;
            minute = The minute portion of the time;
            second = The second portion of the time;
      +/
    this(int year, int month, int day, int hour = 0, int minute = 0, int second = 0) @safe pure
    {
        _date = Date(year, month, day);
        _tod = TimeOfDay(hour, minute, second);
    }

    unittest
    {
        {
            auto dt = DateTime(1999, 7 ,6);
            assert(dt._date == Date(1999, 7, 6));
            assert(dt._tod == TimeOfDay.init);
        }

        {
            auto dt = DateTime(1999, 7 ,6, 12, 30, 33);
            assert(dt._date == Date(1999, 7, 6));
            assert(dt._tod == TimeOfDay(12, 30, 33));
        }
    }


    /++
        Compares this $(LREF DateTime) with the given $(D DateTime.).

        Returns:
            $(BOOKTABLE,
            $(TR $(TD this &lt; rhs) $(TD &lt; 0))
            $(TR $(TD this == rhs) $(TD 0))
            $(TR $(TD this &gt; rhs) $(TD &gt; 0))
            )
     +/
    int opCmp(in DateTime rhs) @safe const pure nothrow
    {
        immutable dateResult = _date.opCmp(rhs._date);

        if (dateResult != 0)
            return dateResult;

        return _tod.opCmp(rhs._tod);
    }

    unittest
    {
        //Test A.D.
        assert(DateTime(Date.init, TimeOfDay.init).opCmp(DateTime.init) == 0);

        assert(DateTime(Date(1999, 1, 1)).opCmp(DateTime(Date(1999, 1, 1))) == 0);
        assert(DateTime(Date(1, 7, 1)).opCmp(DateTime(Date(1, 7, 1))) == 0);
        assert(DateTime(Date(1, 1, 6)).opCmp(DateTime(Date(1, 1, 6))) == 0);

        assert(DateTime(Date(1999, 7, 1)).opCmp(DateTime(Date(1999, 7, 1))) == 0);
        assert(DateTime(Date(1999, 7, 6)).opCmp(DateTime(Date(1999, 7, 6))) == 0);

        assert(DateTime(Date(1, 7, 6)).opCmp(DateTime(Date(1, 7, 6))) == 0);

        assert(DateTime(Date(1999, 7, 6)).opCmp(DateTime(Date(2000, 7, 6))) < 0);
        assert(DateTime(Date(2000, 7, 6)).opCmp(DateTime(Date(1999, 7, 6))) > 0);
        assert(DateTime(Date(1999, 7, 6)).opCmp(DateTime(Date(1999, 8, 6))) < 0);
        assert(DateTime(Date(1999, 8, 6)).opCmp(DateTime(Date(1999, 7, 6))) > 0);
        assert(DateTime(Date(1999, 7, 6)).opCmp(DateTime(Date(1999, 7, 7))) < 0);
        assert(DateTime(Date(1999, 7, 7)).opCmp(DateTime(Date(1999, 7, 6))) > 0);

        assert(DateTime(Date(1999, 8, 7)).opCmp(DateTime(Date(2000, 7, 6))) < 0);
        assert(DateTime(Date(2000, 8, 6)).opCmp(DateTime(Date(1999, 7, 7))) > 0);
        assert(DateTime(Date(1999, 7, 7)).opCmp(DateTime(Date(2000, 7, 6))) < 0);
        assert(DateTime(Date(2000, 7, 6)).opCmp(DateTime(Date(1999, 7, 7))) > 0);
        assert(DateTime(Date(1999, 7, 7)).opCmp(DateTime(Date(1999, 8, 6))) < 0);
        assert(DateTime(Date(1999, 8, 6)).opCmp(DateTime(Date(1999, 7, 7))) > 0);


        assert(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0,  0)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0,  0))) == 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12,  0,  0)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12,  0,  0))) == 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay( 0, 30,  0)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay( 0, 30,  0))) == 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0, 33))) == 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30,  0)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30,  0))) == 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33))) == 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay( 0, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay( 0, 30, 33))) == 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay( 0,  0, 33))) == 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) < 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33))) < 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) < 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) < 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) < 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33))) < 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(2000, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) > 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) > 0);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)).opCmp(DateTime(Date(1999, 7, 7), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)).opCmp(DateTime(Date(1999, 7, 7), TimeOfDay(12, 31, 33))) < 0);
        assert(DateTime(Date(1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)).opCmp(DateTime(Date(1999, 7, 7), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34))) > 0);

        //Test B.C.
        assert(DateTime(Date(-1, 1, 1), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1, 1, 1), TimeOfDay(12, 30, 33))) == 0);
        assert(DateTime(Date(-1, 7, 1), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1, 7, 1), TimeOfDay(12, 30, 33))) == 0);
        assert(DateTime(Date(-1, 1, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1, 1, 6), TimeOfDay(12, 30, 33))) == 0);

        assert(DateTime(Date(-1999, 7, 1), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 1), TimeOfDay(12, 30, 33))) == 0);
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) == 0);

        assert(DateTime(Date(-1, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1, 7, 6), TimeOfDay(12, 30, 33))) == 0);

        assert(DateTime(Date(-2000, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-2000, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(-2000, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 8, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-2000, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(-2000, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-2000, 7, 6), TimeOfDay(12, 30, 33))) > 0);
        assert(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33))) > 0);

        //Test Both
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 7), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(-1999, 8, 7), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date( 1999, 7, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 8, 7), TimeOfDay(12, 30, 33))) > 0);

        assert(DateTime(Date(-1999, 8, 6), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date( 1999, 6, 6), TimeOfDay(12, 30, 33))) < 0);
        assert(DateTime(Date( 1999, 6, 8), TimeOfDay(12, 30, 33)).opCmp(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33))) > 0);

             auto mdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 33, 30));
            const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 33, 30));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 33, 30));
        static assert(__traits(compiles, mdt.opCmp(mdt)));
        static assert(__traits(compiles, mdt.opCmp(cdt)));
        static assert(__traits(compiles, mdt.opCmp(idt)));
        static assert(__traits(compiles, cdt.opCmp(mdt)));
        static assert(__traits(compiles, cdt.opCmp(cdt)));
        static assert(__traits(compiles, cdt.opCmp(idt)));
        static assert(__traits(compiles, idt.opCmp(mdt)));
        static assert(__traits(compiles, idt.opCmp(cdt)));
        static assert(__traits(compiles, idt.opCmp(idt)));
    }


    /++
        The date portion of $(LREF DateTime).
      +/
    @property Date date() @safe const pure nothrow
    {
        return _date;
    }

    unittest
    {
        {
            auto dt = DateTime.init;
            assert(dt.date == Date.init);
        }

        {
            auto dt = DateTime(Date(1999, 7, 6));
            assert(dt.date == Date(1999, 7, 6));
        }

            const cdt = DateTime(1999, 7, 6);
        immutable idt = DateTime(1999, 7, 6);
        static assert(__traits(compiles, cdt.date == Date(2010, 1, 1)));
        static assert(__traits(compiles, idt.date == Date(2010, 1, 1)));
    }


    /++
        The date portion of $(LREF DateTime).

        Params:
            date = The Date to set this $(LREF DateTime)'s date portion to.
      +/
    @property void date(in Date date) @safe pure nothrow
    {
        _date = date;
    }

    unittest
    {
        auto dt = DateTime.init;
        dt.date = Date(1999, 7, 6);
        assert(dt._date == Date(1999, 7, 6));
        assert(dt._tod == TimeOfDay.init);

            const cdt = DateTime(1999, 7, 6);
        immutable idt = DateTime(1999, 7, 6);
        static assert(!__traits(compiles, cdt.date = Date(2010, 1, 1)));
        static assert(!__traits(compiles, idt.date = Date(2010, 1, 1)));
    }


    /++
        The time portion of $(LREF DateTime).
      +/
    @property TimeOfDay timeOfDay() @safe const pure nothrow
    {
        return _tod;
    }

    unittest
    {
        {
            auto dt = DateTime.init;
            assert(dt.timeOfDay == TimeOfDay.init);
        }

        {
            auto dt = DateTime(Date.init, TimeOfDay(12, 30, 33));
            assert(dt.timeOfDay == TimeOfDay(12, 30, 33));
        }

            const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.timeOfDay == TimeOfDay(12, 30, 33)));
        static assert(__traits(compiles, idt.timeOfDay == TimeOfDay(12, 30, 33)));
    }


    /++
        The time portion of $(LREF DateTime).

        Params:
            tod = The $(LREF TimeOfDay) to set this $(LREF DateTime)'s time portion
                  to.
      +/
    @property void timeOfDay(in TimeOfDay tod) @safe pure nothrow
    {
        _tod = tod;
    }

    unittest
    {
        auto dt = DateTime.init;
        dt.timeOfDay = TimeOfDay(12, 30, 33);
        assert(dt._date == Date.init);
        assert(dt._tod == TimeOfDay(12, 30, 33));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.timeOfDay = TimeOfDay(12, 30, 33)));
        static assert(!__traits(compiles, idt.timeOfDay = TimeOfDay(12, 30, 33)));
    }


    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.
     +/
    @property short year() @safe const pure nothrow
    {
        return _date.year;
    }

    unittest
    {
        assert(Date.init.year == 1);
        assert(Date(1999, 7, 6).year == 1999);
        assert(Date(-1999, 7, 6).year == -1999);

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, idt.year));
        static assert(__traits(compiles, idt.year));
    }


    /++
        Year of the Gregorian Calendar. Positive numbers are A.D. Non-positive
        are B.C.

        Params:
            year = The year to set this $(LREF DateTime)'s year to.

        Throws:
            $(LREF DateTimeException) if the new year is not a leap year and if the
            resulting date would be on February 29th.
     +/
    @property void year(int year) @safe pure
    {
        _date.year = year;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(9, 7, 5)).year == 1999);
        assert(DateTime(Date(2010, 10, 4), TimeOfDay(0, 0, 30)).year == 2010);
        assert(DateTime(Date(-7, 4, 5), TimeOfDay(7, 45, 2)).year == -7);
    }

    unittest
    {
        static void testDT(DateTime dt, int year, in DateTime expected, size_t line = __LINE__)
        {
            dt.year = year;
            assert(dt == expected);
        }

        testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), 1999, DateTime(Date(1999, 1, 1), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), 0, DateTime(Date(0, 1, 1), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), -1999, DateTime(Date(-1999, 1, 1), TimeOfDay(12, 30, 33)));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.year = 7));
        static assert(!__traits(compiles, idt.year = 7));
    }


    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Throws:
            $(LREF DateTimeException) if $(D isAD) is true.
     +/
    @property short yearBC() @safe const pure
    {
        return _date.yearBC;
    }

    ///
    unittest
    {
        assert(DateTime(Date(0, 1, 1), TimeOfDay(12, 30, 33)).yearBC == 1);
        assert(DateTime(Date(-1, 1, 1), TimeOfDay(10, 7, 2)).yearBC == 2);
        assert(DateTime(Date(-100, 1, 1), TimeOfDay(4, 59, 0)).yearBC == 101);
    }

    unittest
    {
        assertThrown!DateTimeException((in DateTime dt){dt.yearBC;}(DateTime(Date(1, 1, 1))));

        auto dt = DateTime(1999, 7, 6, 12, 30, 33);
        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, dt.yearBC = 12));
        static assert(!__traits(compiles, cdt.yearBC = 12));
        static assert(!__traits(compiles, idt.yearBC = 12));
    }


    /++
        Year B.C. of the Gregorian Calendar counting year 0 as 1 B.C.

        Params:
            year = The year B.C. to set this $(LREF DateTime)'s year to.

        Throws:
            $(LREF DateTimeException) if a non-positive value is given.
     +/
    @property void yearBC(int year) @safe pure
    {
        _date.yearBC = year;
    }

    ///
    unittest
    {
        auto dt = DateTime(Date(2010, 1, 1), TimeOfDay(7, 30, 0));
        dt.yearBC = 1;
        assert(dt == DateTime(Date(0, 1, 1), TimeOfDay(7, 30, 0)));

        dt.yearBC = 10;
        assert(dt == DateTime(Date(-9, 1, 1), TimeOfDay(7, 30, 0)));
    }

    unittest
    {
        assertThrown!DateTimeException((DateTime dt){dt.yearBC = -1;}(DateTime(Date(1, 1, 1))));

        auto dt = DateTime(1999, 7, 6, 12, 30, 33);
        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, dt.yearBC = 12));
        static assert(!__traits(compiles, cdt.yearBC = 12));
        static assert(!__traits(compiles, idt.yearBC = 12));
    }


    /++
        Month of a Gregorian Year.
     +/
    @property Month month() @safe const pure nothrow
    {
        return _date.month;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(9, 7, 5)).month == 7);
        assert(DateTime(Date(2010, 10, 4), TimeOfDay(0, 0, 30)).month == 10);
        assert(DateTime(Date(-7, 4, 5), TimeOfDay(7, 45, 2)).month == 4);
    }

    unittest
    {
        assert(DateTime.init.month == 1);
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)).month == 7);
        assert(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)).month == 7);

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.month));
        static assert(__traits(compiles, idt.month));
    }


    /++
        Month of a Gregorian Year.

        Params:
            month = The month to set this $(LREF DateTime)'s month to.

        Throws:
            $(LREF DateTimeException) if the given month is not a valid month.
     +/
    @property void month(Month month) @safe pure
    {
        _date.month = month;
    }

    unittest
    {
        static void testDT(DateTime dt, Month month, in DateTime expected = DateTime.init, size_t line = __LINE__)
        {
            dt.month = month;
            assert(expected != DateTime.init);
            assert(dt == expected);
        }

        assertThrown!DateTimeException(testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), cast(Month)0));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), cast(Month)13));

        testDT(DateTime(Date(1, 1, 1), TimeOfDay(12, 30, 33)), cast(Month)7, DateTime(Date(1, 7, 1), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(12, 30, 33)), cast(Month)7, DateTime(Date(-1, 7, 1), TimeOfDay(12, 30, 33)));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.month = 12));
        static assert(!__traits(compiles, idt.month = 12));
    }


    /++
        Day of a Gregorian Month.
     +/
    @property ubyte day() @safe const pure nothrow
    {
        return _date.day;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(9, 7, 5)).day == 6);
        assert(DateTime(Date(2010, 10, 4), TimeOfDay(0, 0, 30)).day == 4);
        assert(DateTime(Date(-7, 4, 5), TimeOfDay(7, 45, 2)).day == 5);
    }

    unittest
    {
        import std.range;
        import std.format : format;

        static void test(DateTime dateTime, int expected)
        {
            assert(dateTime.day == expected, format("Value given: %s", dateTime));
        }

        foreach (year; chain(testYearsBC, testYearsAD))
        {
            foreach (md; testMonthDays)
            {
                foreach (tod; testTODs)
                    test(DateTime(Date(year, md.month, md.day), tod), md.day);
            }
        }

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.day));
        static assert(__traits(compiles, idt.day));
    }


    /++
        Day of a Gregorian Month.

        Params:
            day = The day of the month to set this $(LREF DateTime)'s day to.

        Throws:
            $(LREF DateTimeException) if the given day is not a valid day of the
            current month.
     +/
    @property void day(int day) @safe pure
    {
        _date.day = day;
    }

    unittest
    {
        static void testDT(DateTime dt, int day)
        {
            dt.day = day;
        }

        //Test A.D.
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 1, 1)), 0));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 1, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 2, 1)), 29));
        assertThrown!DateTimeException(testDT(DateTime(Date(4, 2, 1)), 30));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 3, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 4, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 5, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 6, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 7, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 8, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 9, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 10, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 11, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(1, 12, 1)), 32));

        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 1, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 2, 1)), 28));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(4, 2, 1)), 29));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 3, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 4, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 5, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 6, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 7, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 8, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 9, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 10, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 11, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(1, 12, 1)), 31));

        {
            auto dt = DateTime(Date(1, 1, 1), TimeOfDay(7, 12, 22));
            dt.day = 6;
            assert(dt == DateTime(Date(1, 1, 6), TimeOfDay(7, 12, 22)));
        }

        //Test B.C.
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 1, 1)), 0));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 1, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 2, 1)), 29));
        assertThrown!DateTimeException(testDT(DateTime(Date(0, 2, 1)), 30));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 3, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 4, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 5, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 6, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 7, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 8, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 9, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 10, 1)), 32));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 11, 1)), 31));
        assertThrown!DateTimeException(testDT(DateTime(Date(-1, 12, 1)), 32));

        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 1, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 2, 1)), 28));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(0, 2, 1)), 29));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 3, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 4, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 5, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 6, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 7, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 8, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 9, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 10, 1)), 31));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 11, 1)), 30));
        assertNotThrown!DateTimeException(testDT(DateTime(Date(-1, 12, 1)), 31));

        auto dt = DateTime(Date(-1, 1, 1), TimeOfDay(7, 12, 22));
        dt.day = 6;
        assert(dt == DateTime(Date(-1, 1, 6), TimeOfDay(7, 12, 22)));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.day = 27));
        static assert(!__traits(compiles, idt.day = 27));
    }


    /++
        Hours past midnight.
     +/
    @property ubyte hour() @safe const pure nothrow
    {
        return _tod.hour;
    }

    unittest
    {
        assert(DateTime.init.hour == 0);
        assert(DateTime(Date.init, TimeOfDay(12, 0, 0)).hour == 12);

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.hour));
        static assert(__traits(compiles, idt.hour));
    }


    /++
        Hours past midnight.

        Params:
            hour = The hour of the day to set this $(LREF DateTime)'s hour to.

        Throws:
            $(LREF DateTimeException) if the given hour would result in an invalid
            $(LREF DateTime).
     +/
    @property void hour(int hour) @safe pure
    {
        _tod.hour = hour;
    }

    unittest
    {
        assertThrown!DateTimeException((){DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 0)).hour = 24;}());

        auto dt = DateTime.init;
        dt.hour = 12;
        assert(dt == DateTime(1, 1, 1, 12, 0, 0));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.hour = 27));
        static assert(!__traits(compiles, idt.hour = 27));
    }


    /++
        Minutes past the hour.
     +/
    @property ubyte minute() @safe const pure nothrow
    {
        return _tod.minute;
    }

    unittest
    {
        assert(DateTime.init.minute == 0);
        assert(DateTime(1, 1, 1, 0, 30, 0).minute == 30);

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.minute));
        static assert(__traits(compiles, idt.minute));
    }


    /++
        Minutes past the hour.

        Params:
            minute = The minute to set this $(LREF DateTime)'s minute to.

        Throws:
            $(LREF DateTimeException) if the given minute would result in an
            invalid $(LREF DateTime).
     +/
    @property void minute(int minute) @safe pure
    {
        _tod.minute = minute;
    }

    unittest
    {
        assertThrown!DateTimeException((){DateTime.init.minute = 60;}());

        auto dt = DateTime.init;
        dt.minute = 30;
        assert(dt == DateTime(1, 1, 1, 0, 30, 0));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.minute = 27));
        static assert(!__traits(compiles, idt.minute = 27));
    }


    /++
        Seconds past the minute.
     +/
    @property ubyte second() @safe const pure nothrow
    {
        return _tod.second;
    }

    unittest
    {
        assert(DateTime.init.second == 0);
        assert(DateTime(1, 1, 1, 0, 0, 33).second == 33);

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.second));
        static assert(__traits(compiles, idt.second));
    }


    /++
        Seconds past the minute.

        Params:
            second = The second to set this $(LREF DateTime)'s second to.

        Throws:
            $(LREF DateTimeException) if the given seconds would result in an
            invalid $(LREF DateTime).
     +/
    @property void second(int second) @safe pure
    {
        _tod.second = second;
    }

    unittest
    {
        assertThrown!DateTimeException((){DateTime.init.second = 60;}());

        auto dt = DateTime.init;
        dt.second = 33;
        assert(dt == DateTime(1, 1, 1, 0, 0, 33));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.second = 27));
        static assert(!__traits(compiles, idt.second = 27));
    }


    /++
        Adds the given number of years or months to this $(LREF DateTime). A
        negative number will subtract.

        Note that if day overflow is allowed, and the date with the adjusted
        year/month overflows the number of days in the new month, then the month
        will be incremented by one, and the day set to the number of days
        overflowed. (e.g. if the day were 31 and the new month were June, then
        the month would be incremented to July, and the new day would be 1). If
        day overflow is not allowed, then the day will be set to the last valid
        day in the month (e.g. June 31st would become June 30th).

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF DateTime).
            allowOverflow = Whether the days should be allowed to overflow,
                            causing the month to increment.
      +/
    ref DateTime add(string units)
                    (long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "years" ||
           units == "months")
    {
        _date.add!units(value, allowOverflow);
        return this;
    }

    ///
    unittest
    {
        auto dt1 = DateTime(2010, 1, 1, 12, 30, 33);
        dt1.add!"months"(11);
        assert(dt1 == DateTime(2010, 12, 1, 12, 30, 33));

        auto dt2 = DateTime(2010, 1, 1, 12, 30, 33);
        dt2.add!"months"(-11);
        assert(dt2 == DateTime(2009, 2, 1, 12, 30, 33));

        auto dt3 = DateTime(2000, 2, 29, 12, 30, 33);
        dt3.add!"years"(1);
        assert(dt3 == DateTime(2001, 3, 1, 12, 30, 33));

        auto dt4 = DateTime(2000, 2, 29, 12, 30, 33);
        dt4.add!"years"(1, AllowDayOverflow.no);
        assert(dt4 == DateTime(2001, 2, 28, 12, 30, 33));
    }

    unittest
    {
        auto dt = DateTime(2000, 1, 31);
        dt.add!"years"(7).add!"months"(-4);
        assert(dt == DateTime(2006, 10, 1));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.add!"years"(4)));
        static assert(!__traits(compiles, idt.add!"years"(4)));
        static assert(!__traits(compiles, cdt.add!"months"(4)));
        static assert(!__traits(compiles, idt.add!"months"(4)));
    }


    /++
        Adds the given number of years or months to this $(LREF DateTime). A
        negative number will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. Rolling a $(LREF DateTime) 12 months
        gets the exact same $(LREF DateTime). However, the days can still be
        affected due to the differing number of days in each month.

        Because there are no units larger than years, there is no difference
        between adding and rolling years.

        Params:
            units         = The type of units to add ("years" or "months").
            value         = The number of months or years to add to this
                            $(LREF DateTime).
            allowOverflow = Whether the days should be allowed to overflow,
                            causing the month to increment.
      +/
    ref DateTime roll(string units)
                     (long value, AllowDayOverflow allowOverflow = AllowDayOverflow.yes) @safe pure nothrow
        if (units == "years" ||
           units == "months")
    {
        _date.roll!units(value, allowOverflow);
        return this;
    }

    ///
    unittest
    {
        auto dt1 = DateTime(2010, 1, 1, 12, 33, 33);
        dt1.roll!"months"(1);
        assert(dt1 == DateTime(2010, 2, 1, 12, 33, 33));

        auto dt2 = DateTime(2010, 1, 1, 12, 33, 33);
        dt2.roll!"months"(-1);
        assert(dt2 == DateTime(2010, 12, 1, 12, 33, 33));

        auto dt3 = DateTime(1999, 1, 29, 12, 33, 33);
        dt3.roll!"months"(1);
        assert(dt3 == DateTime(1999, 3, 1, 12, 33, 33));

        auto dt4 = DateTime(1999, 1, 29, 12, 33, 33);
        dt4.roll!"months"(1, AllowDayOverflow.no);
        assert(dt4 == DateTime(1999, 2, 28, 12, 33, 33));

        auto dt5 = DateTime(2000, 2, 29, 12, 30, 33);
        dt5.roll!"years"(1);
        assert(dt5 == DateTime(2001, 3, 1, 12, 30, 33));

        auto dt6 = DateTime(2000, 2, 29, 12, 30, 33);
        dt6.roll!"years"(1, AllowDayOverflow.no);
        assert(dt6 == DateTime(2001, 2, 28, 12, 30, 33));
    }

    unittest
    {
        auto dt = DateTime(2000, 1, 31);
        dt.roll!"years"(7).roll!"months"(-4);
        assert(dt == DateTime(2007, 10, 1));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.roll!"years"(4)));
        static assert(!__traits(compiles, idt.roll!"years"(4)));
        static assert(!__traits(compiles, cdt.roll!"months"(4)));
        static assert(!__traits(compiles, idt.roll!"months"(4)));
    }


    /++
        Adds the given number of units to this $(LREF DateTime). A negative number
        will subtract.

        The difference between rolling and adding is that rolling does not
        affect larger units. For instance, rolling a $(LREF DateTime) one
        year's worth of days gets the exact same $(LREF DateTime).

        Accepted units are $(D "days"), $(D "minutes"), $(D "hours"),
        $(D "minutes"), and $(D "seconds").

        Params:
            units = The units to add.
            value = The number of $(D_PARAM units) to add to this $(LREF DateTime).
      +/
    ref DateTime roll(string units)(long value) @safe pure nothrow
        if (units == "days")
    {
        _date.roll!"days"(value);
        return this;
    }

    ///
    unittest
    {
        auto dt1 = DateTime(2010, 1, 1, 11, 23, 12);
        dt1.roll!"days"(1);
        assert(dt1 == DateTime(2010, 1, 2, 11, 23, 12));
        dt1.roll!"days"(365);
        assert(dt1 == DateTime(2010, 1, 26, 11, 23, 12));
        dt1.roll!"days"(-32);
        assert(dt1 == DateTime(2010, 1, 25, 11, 23, 12));

        auto dt2 = DateTime(2010, 7, 4, 12, 0, 0);
        dt2.roll!"hours"(1);
        assert(dt2 == DateTime(2010, 7, 4, 13, 0, 0));

        auto dt3 = DateTime(2010, 1, 1, 0, 0, 0);
        dt3.roll!"seconds"(-1);
        assert(dt3 == DateTime(2010, 1, 1, 0, 0, 59));
    }

    unittest
    {
        auto dt = DateTime(2000, 1, 31);
        dt.roll!"days"(7).roll!"days"(-4);
        assert(dt == DateTime(2000, 1, 3));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.roll!"days"(4)));
        static assert(!__traits(compiles, idt.roll!"days"(4)));
    }


    //Shares documentation with "days" version.
    ref DateTime roll(string units)(long value) @safe pure nothrow
        if (units == "hours" ||
           units == "minutes" ||
           units == "seconds")
    {
        _tod.roll!units(value);
        return this;
    }

    //Test roll!"hours"().
    unittest
    {
        static void testDT(DateTime orig, int hours, in DateTime expected, size_t line = __LINE__)
        {
            orig.roll!"hours"(hours);
            assert(orig == expected);
        }

        //Test A.D.
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(1999, 7, 6), TimeOfDay(14, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(1999, 7, 6), TimeOfDay(15, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(1999, 7, 6), TimeOfDay(16, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(1999, 7, 6), TimeOfDay(17, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 6, DateTime(Date(1999, 7, 6), TimeOfDay(18, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 7, DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 8, DateTime(Date(1999, 7, 6), TimeOfDay(20, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 9, DateTime(Date(1999, 7, 6), TimeOfDay(21, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(1999, 7, 6), TimeOfDay(22, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 11, DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 12, DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 13, DateTime(Date(1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 14, DateTime(Date(1999, 7, 6), TimeOfDay(2, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(1999, 7, 6), TimeOfDay(3, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 16, DateTime(Date(1999, 7, 6), TimeOfDay(4, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 17, DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 18, DateTime(Date(1999, 7, 6), TimeOfDay(6, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 19, DateTime(Date(1999, 7, 6), TimeOfDay(7, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 20, DateTime(Date(1999, 7, 6), TimeOfDay(8, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 21, DateTime(Date(1999, 7, 6), TimeOfDay(9, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 22, DateTime(Date(1999, 7, 6), TimeOfDay(10, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 23, DateTime(Date(1999, 7, 6), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 24, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 25, DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(1999, 7, 6), TimeOfDay(10, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(1999, 7, 6), TimeOfDay(9, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(1999, 7, 6), TimeOfDay(8, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(1999, 7, 6), TimeOfDay(7, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -6, DateTime(Date(1999, 7, 6), TimeOfDay(6, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -7, DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -8, DateTime(Date(1999, 7, 6), TimeOfDay(4, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -9, DateTime(Date(1999, 7, 6), TimeOfDay(3, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(1999, 7, 6), TimeOfDay(2, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -11, DateTime(Date(1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -12, DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -13, DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -14, DateTime(Date(1999, 7, 6), TimeOfDay(22, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(1999, 7, 6), TimeOfDay(21, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -16, DateTime(Date(1999, 7, 6), TimeOfDay(20, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -17, DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -18, DateTime(Date(1999, 7, 6), TimeOfDay(18, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -19, DateTime(Date(1999, 7, 6), TimeOfDay(17, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -20, DateTime(Date(1999, 7, 6), TimeOfDay(16, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -21, DateTime(Date(1999, 7, 6), TimeOfDay(15, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -22, DateTime(Date(1999, 7, 6), TimeOfDay(14, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -23, DateTime(Date(1999, 7, 6), TimeOfDay(13, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -24, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -25, DateTime(Date(1999, 7, 6), TimeOfDay(11, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(23, 30, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(22, 30, 33)));

        testDT(DateTime(Date(1999, 7, 31), TimeOfDay(23, 30, 33)), 1, DateTime(Date(1999, 7, 31), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 8, 1), TimeOfDay(0, 30, 33)), -1, DateTime(Date(1999, 8, 1), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(1999, 12, 31), TimeOfDay(23, 30, 33)), 1, DateTime(Date(1999, 12, 31), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(2000, 1, 1), TimeOfDay(0, 30, 33)), -1, DateTime(Date(2000, 1, 1), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(1999, 2, 28), TimeOfDay(23, 30, 33)), 25, DateTime(Date(1999, 2, 28), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(1999, 3, 2), TimeOfDay(0, 30, 33)), -25, DateTime(Date(1999, 3, 2), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(2000, 2, 28), TimeOfDay(23, 30, 33)), 25, DateTime(Date(2000, 2, 28), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(2000, 3, 1), TimeOfDay(0, 30, 33)), -25, DateTime(Date(2000, 3, 1), TimeOfDay(23, 30, 33)));

        //Test B.C.
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(13, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(-1999, 7, 6), TimeOfDay(14, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(-1999, 7, 6), TimeOfDay(15, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(-1999, 7, 6), TimeOfDay(16, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(-1999, 7, 6), TimeOfDay(17, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 6, DateTime(Date(-1999, 7, 6), TimeOfDay(18, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 7, DateTime(Date(-1999, 7, 6), TimeOfDay(19, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 8, DateTime(Date(-1999, 7, 6), TimeOfDay(20, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 9, DateTime(Date(-1999, 7, 6), TimeOfDay(21, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(-1999, 7, 6), TimeOfDay(22, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 11, DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 12, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 13, DateTime(Date(-1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 14, DateTime(Date(-1999, 7, 6), TimeOfDay(2, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(-1999, 7, 6), TimeOfDay(3, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 16, DateTime(Date(-1999, 7, 6), TimeOfDay(4, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 17, DateTime(Date(-1999, 7, 6), TimeOfDay(5, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 18, DateTime(Date(-1999, 7, 6), TimeOfDay(6, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 19, DateTime(Date(-1999, 7, 6), TimeOfDay(7, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 20, DateTime(Date(-1999, 7, 6), TimeOfDay(8, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 21, DateTime(Date(-1999, 7, 6), TimeOfDay(9, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 22, DateTime(Date(-1999, 7, 6), TimeOfDay(10, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 23, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 24, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 25, DateTime(Date(-1999, 7, 6), TimeOfDay(13, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(-1999, 7, 6), TimeOfDay(10, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(-1999, 7, 6), TimeOfDay(9, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(-1999, 7, 6), TimeOfDay(8, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(-1999, 7, 6), TimeOfDay(7, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -6, DateTime(Date(-1999, 7, 6), TimeOfDay(6, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -7, DateTime(Date(-1999, 7, 6), TimeOfDay(5, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -8, DateTime(Date(-1999, 7, 6), TimeOfDay(4, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -9, DateTime(Date(-1999, 7, 6), TimeOfDay(3, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(-1999, 7, 6), TimeOfDay(2, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -11, DateTime(Date(-1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -12, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -13, DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -14, DateTime(Date(-1999, 7, 6), TimeOfDay(22, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(-1999, 7, 6), TimeOfDay(21, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -16, DateTime(Date(-1999, 7, 6), TimeOfDay(20, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -17, DateTime(Date(-1999, 7, 6), TimeOfDay(19, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -18, DateTime(Date(-1999, 7, 6), TimeOfDay(18, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -19, DateTime(Date(-1999, 7, 6), TimeOfDay(17, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -20, DateTime(Date(-1999, 7, 6), TimeOfDay(16, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -21, DateTime(Date(-1999, 7, 6), TimeOfDay(15, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -22, DateTime(Date(-1999, 7, 6), TimeOfDay(14, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -23, DateTime(Date(-1999, 7, 6), TimeOfDay(13, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -24, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -25, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(1, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(23, 30, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(22, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 31), TimeOfDay(23, 30, 33)), 1, DateTime(Date(-1999, 7, 31), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-1999, 8, 1), TimeOfDay(0, 30, 33)), -1, DateTime(Date(-1999, 8, 1), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(-2001, 12, 31), TimeOfDay(23, 30, 33)), 1, DateTime(Date(-2001, 12, 31), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-2000, 1, 1), TimeOfDay(0, 30, 33)), -1, DateTime(Date(-2000, 1, 1), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(-2001, 2, 28), TimeOfDay(23, 30, 33)), 25, DateTime(Date(-2001, 2, 28), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-2001, 3, 2), TimeOfDay(0, 30, 33)), -25, DateTime(Date(-2001, 3, 2), TimeOfDay(23, 30, 33)));

        testDT(DateTime(Date(-2000, 2, 28), TimeOfDay(23, 30, 33)), 25, DateTime(Date(-2000, 2, 28), TimeOfDay(0, 30, 33)));
        testDT(DateTime(Date(-2000, 3, 1), TimeOfDay(0, 30, 33)), -25, DateTime(Date(-2000, 3, 1), TimeOfDay(23, 30, 33)));

        //Test Both
        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)), 17_546, DateTime(Date(-1, 1, 1), TimeOfDay(13, 30, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)), -17_546, DateTime(Date(1, 1, 1), TimeOfDay(11, 30, 33)));

        auto dt = DateTime(2000, 1, 31, 9, 7, 6);
        dt.roll!"hours"(27).roll!"hours"(-9);
        assert(dt == DateTime(2000, 1, 31, 3, 7, 6));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.roll!"hours"(4)));
        static assert(!__traits(compiles, idt.roll!"hours"(4)));
    }

    //Test roll!"minutes"().
    unittest
    {
        static void testDT(DateTime orig, int minutes, in DateTime expected, size_t line = __LINE__)
        {
            orig.roll!"minutes"(minutes);
            assert(orig == expected);
        }

        //Test A.D.
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(1999, 7, 6), TimeOfDay(12, 32, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(1999, 7, 6), TimeOfDay(12, 33, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(1999, 7, 6), TimeOfDay(12, 34, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(1999, 7, 6), TimeOfDay(12, 35, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(1999, 7, 6), TimeOfDay(12, 40, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 29, DateTime(Date(1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 30, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 45, DateTime(Date(1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 60, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 75, DateTime(Date(1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 90, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 100, DateTime(Date(1999, 7, 6), TimeOfDay(12, 10, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 689, DateTime(Date(1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 690, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 691, DateTime(Date(1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 960, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1439, DateTime(Date(1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1440, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1441, DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 2880, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(1999, 7, 6), TimeOfDay(12, 28, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(1999, 7, 6), TimeOfDay(12, 27, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(1999, 7, 6), TimeOfDay(12, 26, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(1999, 7, 6), TimeOfDay(12, 25, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(1999, 7, 6), TimeOfDay(12, 20, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -29, DateTime(Date(1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -30, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -45, DateTime(Date(1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -60, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -75, DateTime(Date(1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -90, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -100, DateTime(Date(1999, 7, 6), TimeOfDay(12, 50, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -749, DateTime(Date(1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -750, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -751, DateTime(Date(1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -960, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1439, DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1440, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1441, DateTime(Date(1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -2880, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 59, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(11, 59, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(11, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(11, 59, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(11, 59, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(11, 59, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(11, 58, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(0, 1, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(0, 59, 33)));

        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 33)), 1, DateTime(Date(1999, 7, 5), TimeOfDay(23, 0, 33)));
        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 33)), 0, DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 33)));
        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 33)), -1, DateTime(Date(1999, 7, 5), TimeOfDay(23, 58, 33)));

        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 33)), 1, DateTime(Date(1998, 12, 31), TimeOfDay(23, 0, 33)));
        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 33)), 0, DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 33)));
        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 33)), -1, DateTime(Date(1998, 12, 31), TimeOfDay(23, 58, 33)));

        //Test B.C.
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 32, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 33, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 34, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 35, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 40, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 29, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 30, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 45, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 60, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 75, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 90, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 100, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 10, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 689, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 690, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 691, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 960, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1439, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1440, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1441, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 2880, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 28, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 27, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 26, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 25, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 20, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -29, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -30, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -45, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 45, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -60, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -75, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 15, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -90, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -100, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 50, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -749, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -750, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -751, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 59, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -960, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1439, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 31, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1440, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1441, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 29, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -2880, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 1, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 59, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(11, 59, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(11, 59, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 59, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(11, 59, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(11, 58, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 1, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 59, 33)));

        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 33)), 1, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 0, 33)));
        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 33)), 0, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 33)));
        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 33)), -1, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 58, 33)));

        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 33)), 1, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 0, 33)));
        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 33)), 0, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 33)));
        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 33)), -1, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 58, 33)));

        //Test Both
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(0, 0, 0)), -1, DateTime(Date(1, 1, 1), TimeOfDay(0, 59, 0)));
        testDT(DateTime(Date(0, 12, 31), TimeOfDay(23, 59, 0)), 1, DateTime(Date(0, 12, 31), TimeOfDay(23, 0, 0)));

        testDT(DateTime(Date(0, 1, 1), TimeOfDay(0, 0, 0)), -1, DateTime(Date(0, 1, 1), TimeOfDay(0, 59, 0)));
        testDT(DateTime(Date(-1, 12, 31), TimeOfDay(23, 59, 0)), 1, DateTime(Date(-1, 12, 31), TimeOfDay(23, 0, 0)));

        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)), 1_052_760, DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)), -1_052_760, DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)));

        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)), 1_052_782, DateTime(Date(-1, 1, 1), TimeOfDay(11, 52, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(13, 52, 33)), -1_052_782, DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)));

        auto dt = DateTime(2000, 1, 31, 9, 7, 6);
        dt.roll!"minutes"(92).roll!"minutes"(-292);
        assert(dt == DateTime(2000, 1, 31, 9, 47, 6));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.roll!"minutes"(4)));
        static assert(!__traits(compiles, idt.roll!"minutes"(4)));
    }

    //Test roll!"seconds"().
    unittest
    {
        static void testDT(DateTime orig, int seconds, in DateTime expected, size_t line = __LINE__)
        {
            orig.roll!"seconds"(seconds);
            assert(orig == expected);
        }

        //Test A.D.
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 35)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 36)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 37)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 38)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 43)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 48)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 26, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 27, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 30, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 3)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 59, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 60, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 61, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1766, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1767, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 1768, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 1)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 2007, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3599, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3600, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 3601, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), 7200, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 31)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 30)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 29)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 28)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 23)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 18)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -33, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -34, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -35, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 58)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -59, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -60, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)), -61, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 32)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 1)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 0)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 59)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 0)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 1)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 0)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 0)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(12, 0, 59)));

        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 0)), 1, DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 1)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 0)), 0, DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 0)));
        testDT(DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 0)), -1, DateTime(Date(1999, 7, 6), TimeOfDay(0, 0, 59)));

        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 59)), 1, DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 0)));
        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 59)), 0, DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 59)));
        testDT(DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 59)), -1, DateTime(Date(1999, 7, 5), TimeOfDay(23, 59, 58)));

        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 59)), 1, DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 0)));
        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 59)), 0, DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 59)));
        testDT(DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 59)), -1, DateTime(Date(1998, 12, 31), TimeOfDay(23, 59, 58)));

        //Test B.C.
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 2, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 35)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 36)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 4, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 37)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 5, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 38)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 10, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 43)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 15, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 48)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 26, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 27, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 30, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 3)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 59, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 60, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 61, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 34)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1766, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1767, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 1768, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 1)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 2007, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3599, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3600, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 3601, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), 7200, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 32)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -2, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 31)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -3, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 30)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -4, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 29)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -5, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 28)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -10, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 23)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -15, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 18)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -33, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -34, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 59)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -35, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 58)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -59, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 34)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -60, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)), -61, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 32)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 1)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 0)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 59)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 0)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 1)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 0)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 0)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(12, 0, 59)));

        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 0)), 1, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 1)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 0)), 0, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 0)));
        testDT(DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 0)), -1, DateTime(Date(-1999, 7, 6), TimeOfDay(0, 0, 59)));

        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 59)), 1, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 0)));
        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 59)), 0, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 59)));
        testDT(DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 59)), -1, DateTime(Date(-1999, 7, 5), TimeOfDay(23, 59, 58)));

        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 59)), 1, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 0)));
        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 59)), 0, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 59)));
        testDT(DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 59)), -1, DateTime(Date(-2000, 12, 31), TimeOfDay(23, 59, 58)));

        //Test Both
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(0, 0, 0)), -1, DateTime(Date(1, 1, 1), TimeOfDay(0, 0, 59)));
        testDT(DateTime(Date(0, 12, 31), TimeOfDay(23, 59, 59)), 1, DateTime(Date(0, 12, 31), TimeOfDay(23, 59, 0)));

        testDT(DateTime(Date(0, 1, 1), TimeOfDay(0, 0, 0)), -1, DateTime(Date(0, 1, 1), TimeOfDay(0, 0, 59)));
        testDT(DateTime(Date(-1, 12, 31), TimeOfDay(23, 59, 59)), 1, DateTime(Date(-1, 12, 31), TimeOfDay(23, 59, 0)));

        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)), 63_165_600L, DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)), -63_165_600L, DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)));

        testDT(DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 33)), 63_165_617L, DateTime(Date(-1, 1, 1), TimeOfDay(11, 30, 50)));
        testDT(DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 50)), -63_165_617L, DateTime(Date(1, 1, 1), TimeOfDay(13, 30, 33)));

        auto dt = DateTime(2000, 1, 31, 9, 7, 6);
        dt.roll!"seconds"(92).roll!"seconds"(-292);
        assert(dt == DateTime(2000, 1, 31, 9, 7, 46));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt.roll!"seconds"(4)));
        static assert(!__traits(compiles, idt.roll!"seconds"(4)));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF DateTime).

        The legal types of arithmetic for $(LREF DateTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD DateTime) $(TD +) $(TD duration) $(TD -->) $(TD DateTime))
        $(TR $(TD DateTime) $(TD -) $(TD duration) $(TD -->) $(TD DateTime))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF DateTime).
      +/
    DateTime opBinary(string op, D)(in D duration) @safe const pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        import std.format : format;

        DateTime retval = this;

        static if (is(Unqual!D == Duration))
            immutable hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            immutable hnsecs = duration.hnsecs;

        mixin(format(`return retval._addSeconds(convert!("hnsecs", "seconds")(%shnsecs));`, op));
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));

        assert(dt + dur!"weeks"(7) == DateTime(Date(1999, 8, 24), TimeOfDay(12, 30, 33)));
        assert(dt + dur!"weeks"(-7) == DateTime(Date(1999, 5, 18), TimeOfDay(12, 30, 33)));
        assert(dt + dur!"days"(7) == DateTime(Date(1999, 7, 13), TimeOfDay(12, 30, 33)));
        assert(dt + dur!"days"(-7) == DateTime(Date(1999, 6, 29), TimeOfDay(12, 30, 33)));

        assert(dt + dur!"hours"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        assert(dt + dur!"hours"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        assert(dt + dur!"minutes"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 37, 33)));
        assert(dt + dur!"minutes"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 23, 33)));
        assert(dt + dur!"seconds"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt + dur!"seconds"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt + dur!"msecs"(7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt + dur!"msecs"(-7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt + dur!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt + dur!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt + dur!"hnsecs"(70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt + dur!"hnsecs"(-70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(dt + TickDuration.from!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
            assert(dt + TickDuration.from!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        }

        assert(dt - dur!"weeks"(-7) == DateTime(Date(1999, 8, 24), TimeOfDay(12, 30, 33)));
        assert(dt - dur!"weeks"(7) == DateTime(Date(1999, 5, 18), TimeOfDay(12, 30, 33)));
        assert(dt - dur!"days"(-7) == DateTime(Date(1999, 7, 13), TimeOfDay(12, 30, 33)));
        assert(dt - dur!"days"(7) == DateTime(Date(1999, 6, 29), TimeOfDay(12, 30, 33)));

        assert(dt - dur!"hours"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        assert(dt - dur!"hours"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        assert(dt - dur!"minutes"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 37, 33)));
        assert(dt - dur!"minutes"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 23, 33)));
        assert(dt - dur!"seconds"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt - dur!"seconds"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt - dur!"msecs"(-7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt - dur!"msecs"(7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt - dur!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt - dur!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(dt - dur!"hnsecs"(-70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(dt - dur!"hnsecs"(70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));

        //This probably only runs in cases where gettimeofday() is used, but it's
        //hard to do this test correctly with variable ticksPerSec.
        if (TickDuration.ticksPerSec == 1_000_000)
        {
            assert(dt - TickDuration.from!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
            assert(dt - TickDuration.from!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        }

        auto duration = dur!"seconds"(12);
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt + duration));
        static assert(__traits(compiles, idt + duration));
        static assert(__traits(compiles, cdt - duration));
        static assert(__traits(compiles, idt - duration));
    }


    /++
        Gives the result of adding or subtracting a duration from this
        $(LREF DateTime), as well as assigning the result to this $(LREF DateTime).

        The legal types of arithmetic for $(LREF DateTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD DateTime) $(TD +) $(TD duration) $(TD -->) $(TD DateTime))
        $(TR $(TD DateTime) $(TD -) $(TD duration) $(TD -->) $(TD DateTime))
        )

        Params:
            duration = The duration to add to or subtract from this
                       $(LREF DateTime).
      +/
    ref DateTime opOpAssign(string op, D)(in D duration) @safe pure nothrow
        if ((op == "+" || op == "-") &&
           (is(Unqual!D == Duration) ||
            is(Unqual!D == TickDuration)))
    {
        import std.format : format;

        DateTime retval = this;

        static if (is(Unqual!D == Duration))
            immutable hnsecs = duration.total!"hnsecs";
        else static if (is(Unqual!D == TickDuration))
            immutable hnsecs = duration.hnsecs;

        mixin(format(`return _addSeconds(convert!("hnsecs", "seconds")(%shnsecs));`, op));
    }

    unittest
    {
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"weeks"(7) == DateTime(Date(1999, 8, 24), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"weeks"(-7) == DateTime(Date(1999, 5, 18), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"days"(7) == DateTime(Date(1999, 7, 13), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"days"(-7) == DateTime(Date(1999, 6, 29), TimeOfDay(12, 30, 33)));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"hours"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"hours"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"minutes"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 37, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"minutes"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 23, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"seconds"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"seconds"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"msecs"(7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"msecs"(-7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"hnsecs"(70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) + dur!"hnsecs"(-70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"weeks"(-7) == DateTime(Date(1999, 8, 24), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"weeks"(7) == DateTime(Date(1999, 5, 18), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"days"(-7) == DateTime(Date(1999, 7, 13), TimeOfDay(12, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"days"(7) == DateTime(Date(1999, 6, 29), TimeOfDay(12, 30, 33)));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"hours"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(19, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"hours"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(5, 30, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"minutes"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 37, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"minutes"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 23, 33)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"seconds"(-7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"seconds"(7) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"msecs"(-7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"msecs"(7_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"usecs"(-7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"usecs"(7_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"hnsecs"(-70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 40)));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) - dur!"hnsecs"(70_000_000) == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 26)));

        auto dt = DateTime(2000, 1, 31, 9, 7, 6);
        (dt += dur!"seconds"(92)) -= dur!"days"(-500);
        assert(dt == DateTime(2001, 6, 14, 9, 8, 38));

        auto duration = dur!"seconds"(12);
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(!__traits(compiles, cdt += duration));
        static assert(!__traits(compiles, idt += duration));
        static assert(!__traits(compiles, cdt -= duration));
        static assert(!__traits(compiles, idt -= duration));
    }


    /++
        Gives the difference between two $(LREF DateTime)s.

        The legal types of arithmetic for $(LREF DateTime) using this operator are

        $(BOOKTABLE,
        $(TR $(TD DateTime) $(TD -) $(TD DateTime) $(TD -->) $(TD duration))
        )
      +/
    Duration opBinary(string op)(in DateTime rhs) @safe const pure nothrow
        if (op == "-")
    {
        immutable dateResult = _date - rhs.date;
        immutable todResult = _tod - rhs._tod;

        return dur!"hnsecs"(dateResult.total!"hnsecs" + todResult.total!"hnsecs");
    }

    unittest
    {
        auto dt = DateTime(1999, 7, 6, 12, 30, 33);

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1998, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(31_536_000));
        assert(DateTime(Date(1998, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(-31_536_000));

        assert(DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(26_78_400));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 8, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(-26_78_400));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 5), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(86_400));
        assert(DateTime(Date(1999, 7, 5), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(-86_400));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(11, 30, 33)) ==
                    dur!"seconds"(3600));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(11, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(-3600));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(60));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 31, 33)) ==
                    dur!"seconds"(-60));

        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) ==
                    dur!"seconds"(1));
        assert(DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)) -
                     DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 34)) ==
                    dur!"seconds"(-1));

        assert(DateTime(1, 1, 1, 12, 30, 33) - DateTime(1, 1, 1, 0, 0, 0) == dur!"seconds"(45033));
        assert(DateTime(1, 1, 1, 0, 0, 0) - DateTime(1, 1, 1, 12, 30, 33) == dur!"seconds"(-45033));
        assert(DateTime(0, 12, 31, 12, 30, 33) - DateTime(1, 1, 1, 0, 0, 0) == dur!"seconds"(-41367));
        assert(DateTime(1, 1, 1, 0, 0, 0) - DateTime(0, 12, 31, 12, 30, 33) == dur!"seconds"(41367));

        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt - dt));
        static assert(__traits(compiles, cdt - dt));
        static assert(__traits(compiles, idt - dt));

        static assert(__traits(compiles, dt - cdt));
        static assert(__traits(compiles, cdt - cdt));
        static assert(__traits(compiles, idt - cdt));

        static assert(__traits(compiles, dt - idt));
        static assert(__traits(compiles, cdt - idt));
        static assert(__traits(compiles, idt - idt));
    }


    /++
        Returns the difference between the two $(LREF DateTime)s in months.

        To get the difference in years, subtract the year property
        of two $(LREF SysTime)s. To get the difference in days or weeks,
        subtract the $(LREF SysTime)s themselves and use the $(CXREF time, Duration)
        that results. Because converting between months and smaller
        units requires a specific date (which $(CXREF time, Duration)s don't have),
        getting the difference in months requires some math using both
        the year and month properties, so this is a convenience function for
        getting the difference in months.

        Note that the number of days in the months or how far into the month
        either date is is irrelevant. It is the difference in the month property
        combined with the difference in years * 12. So, for instance,
        December 31st and January 1st are one month apart just as December 1st
        and January 31st are one month apart.

        Params:
            rhs = The $(LREF DateTime) to subtract from this one.
      +/
    int diffMonths(in DateTime rhs) @safe const pure nothrow
    {
        return _date.diffMonths(rhs._date);
    }

    ///
    unittest
    {
        assert(DateTime(1999, 2, 1, 12, 2, 3).diffMonths(
                    DateTime(1999, 1, 31, 23, 59, 59)) == 1);

        assert(DateTime(1999, 1, 31, 0, 0, 0).diffMonths(
                    DateTime(1999, 2, 1, 12, 3, 42)) == -1);

        assert(DateTime(1999, 3, 1, 5, 30, 0).diffMonths(
                    DateTime(1999, 1, 1, 2, 4, 7)) == 2);

        assert(DateTime(1999, 1, 1, 7, 2, 4).diffMonths(
                    DateTime(1999, 3, 31, 0, 30, 58)) == -2);
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.diffMonths(dt)));
        static assert(__traits(compiles, cdt.diffMonths(dt)));
        static assert(__traits(compiles, idt.diffMonths(dt)));

        static assert(__traits(compiles, dt.diffMonths(cdt)));
        static assert(__traits(compiles, cdt.diffMonths(cdt)));
        static assert(__traits(compiles, idt.diffMonths(cdt)));

        static assert(__traits(compiles, dt.diffMonths(idt)));
        static assert(__traits(compiles, cdt.diffMonths(idt)));
        static assert(__traits(compiles, idt.diffMonths(idt)));
    }


    /++
        Whether this $(LREF DateTime) is in a leap year.
     +/
    @property bool isLeapYear() @safe const pure nothrow
    {
        return _date.isLeapYear;
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.isLeapYear));
        static assert(__traits(compiles, cdt.isLeapYear));
        static assert(__traits(compiles, idt.isLeapYear));
    }


    /++
        Day of the week this $(LREF DateTime) is on.
      +/
    @property DayOfWeek dayOfWeek() @safe const pure nothrow
    {
        return _date.dayOfWeek;
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.dayOfWeek));
        static assert(__traits(compiles, cdt.dayOfWeek));
        static assert(__traits(compiles, idt.dayOfWeek));
    }


    /++
        Day of the year this $(LREF DateTime) is on.
      +/
    @property ushort dayOfYear() @safe const pure nothrow
    {
        return _date.dayOfYear;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 1, 1), TimeOfDay(12, 22, 7)).dayOfYear == 1);
        assert(DateTime(Date(1999, 12, 31), TimeOfDay(7, 2, 59)).dayOfYear == 365);
        assert(DateTime(Date(2000, 12, 31), TimeOfDay(21, 20, 0)).dayOfYear == 366);
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.dayOfYear));
        static assert(__traits(compiles, cdt.dayOfYear));
        static assert(__traits(compiles, idt.dayOfYear));
    }


    /++
        Day of the year.

        Params:
            day = The day of the year to set which day of the year this
                  $(LREF DateTime) is on.
      +/
    @property void dayOfYear(int day) @safe pure
    {
        _date.dayOfYear = day;
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.dayOfYear = 12));
        static assert(!__traits(compiles, cdt.dayOfYear = 12));
        static assert(!__traits(compiles, idt.dayOfYear = 12));
    }


    /++
        The Xth day of the Gregorian Calendar that this $(LREF DateTime) is on.
     +/
    @property int dayOfGregorianCal() @safe const pure nothrow
    {
        return _date.dayOfGregorianCal;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1, 1, 1), TimeOfDay(0, 0, 0)).dayOfGregorianCal == 1);
        assert(DateTime(Date(1, 12, 31), TimeOfDay(23, 59, 59)).dayOfGregorianCal == 365);
        assert(DateTime(Date(2, 1, 1), TimeOfDay(2, 2, 2)).dayOfGregorianCal == 366);

        assert(DateTime(Date(0, 12, 31), TimeOfDay(7, 7, 7)).dayOfGregorianCal == 0);
        assert(DateTime(Date(0, 1, 1), TimeOfDay(19, 30, 0)).dayOfGregorianCal == -365);
        assert(DateTime(Date(-1, 12, 31), TimeOfDay(4, 7, 0)).dayOfGregorianCal == -366);

        assert(DateTime(Date(2000, 1, 1), TimeOfDay(9, 30, 20)).dayOfGregorianCal == 730_120);
        assert(DateTime(Date(2010, 12, 31), TimeOfDay(15, 45, 50)).dayOfGregorianCal == 734_137);
    }

    unittest
    {
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.dayOfGregorianCal));
        static assert(__traits(compiles, idt.dayOfGregorianCal));
    }


    /++
        The Xth day of the Gregorian Calendar that this $(LREF DateTime) is on.
        Setting this property does not affect the time portion of
        $(LREF DateTime).

        Params:
            days = The day of the Gregorian Calendar to set this $(LREF DateTime)
                   to.
     +/
    @property void dayOfGregorianCal(int days) @safe pure nothrow
    {
        _date.dayOfGregorianCal = days;
    }

    ///
    unittest
    {
        auto dt = DateTime(Date.init, TimeOfDay(12, 0, 0));
        dt.dayOfGregorianCal = 1;
        assert(dt == DateTime(Date(1, 1, 1), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = 365;
        assert(dt == DateTime(Date(1, 12, 31), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = 366;
        assert(dt == DateTime(Date(2, 1, 1), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = 0;
        assert(dt == DateTime(Date(0, 12, 31), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = -365;
        assert(dt == DateTime(Date(-0, 1, 1), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = -366;
        assert(dt == DateTime(Date(-1, 12, 31), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = 730_120;
        assert(dt == DateTime(Date(2000, 1, 1), TimeOfDay(12, 0, 0)));

        dt.dayOfGregorianCal = 734_137;
        assert(dt == DateTime(Date(2010, 12, 31), TimeOfDay(12, 0, 0)));
    }

    unittest
    {
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(!__traits(compiles, cdt.dayOfGregorianCal = 7));
        static assert(!__traits(compiles, idt.dayOfGregorianCal = 7));
    }


    /++
        The ISO 8601 week of the year that this $(LREF DateTime) is in.

        See_Also:
            $(WEB en.wikipedia.org/wiki/ISO_week_date, ISO Week Date)
      +/
    @property ubyte isoWeek() @safe const pure nothrow
    {
        return _date.isoWeek;
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.isoWeek));
        static assert(__traits(compiles, cdt.isoWeek));
        static assert(__traits(compiles, idt.isoWeek));
    }


    /++
        $(LREF DateTime) for the last day in the month that this $(LREF DateTime) is
        in. The time portion of endOfMonth is always 23:59:59.
      +/
    @property DateTime endOfMonth() @safe const pure nothrow
    {
        scope(failure) assert(0, "DateTime constructor threw.");
        return DateTime(_date.endOfMonth, TimeOfDay(23, 59, 59));
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 1, 6), TimeOfDay(0, 0, 0)).endOfMonth ==
               DateTime(Date(1999, 1, 31), TimeOfDay(23, 59, 59)));

        assert(DateTime(Date(1999, 2, 7), TimeOfDay(19, 30, 0)).endOfMonth ==
               DateTime(Date(1999, 2, 28), TimeOfDay(23, 59, 59)));

        assert(DateTime(Date(2000, 2, 7), TimeOfDay(5, 12, 27)).endOfMonth ==
               DateTime(Date(2000, 2, 29), TimeOfDay(23, 59, 59)));

        assert(DateTime(Date(2000, 6, 4), TimeOfDay(12, 22, 9)).endOfMonth ==
               DateTime(Date(2000, 6, 30), TimeOfDay(23, 59, 59)));
    }

    unittest
    {
        //Test A.D.
        assert(DateTime(1999, 1, 1, 0, 13, 26).endOfMonth == DateTime(1999, 1, 31, 23, 59, 59));
        assert(DateTime(1999, 2, 1, 1, 14, 27).endOfMonth == DateTime(1999, 2, 28, 23, 59, 59));
        assert(DateTime(2000, 2, 1, 2, 15, 28).endOfMonth == DateTime(2000, 2, 29, 23, 59, 59));
        assert(DateTime(1999, 3, 1, 3, 16, 29).endOfMonth == DateTime(1999, 3, 31, 23, 59, 59));
        assert(DateTime(1999, 4, 1, 4, 17, 30).endOfMonth == DateTime(1999, 4, 30, 23, 59, 59));
        assert(DateTime(1999, 5, 1, 5, 18, 31).endOfMonth == DateTime(1999, 5, 31, 23, 59, 59));
        assert(DateTime(1999, 6, 1, 6, 19, 32).endOfMonth == DateTime(1999, 6, 30, 23, 59, 59));
        assert(DateTime(1999, 7, 1, 7, 20, 33).endOfMonth == DateTime(1999, 7, 31, 23, 59, 59));
        assert(DateTime(1999, 8, 1, 8, 21, 34).endOfMonth == DateTime(1999, 8, 31, 23, 59, 59));
        assert(DateTime(1999, 9, 1, 9, 22, 35).endOfMonth == DateTime(1999, 9, 30, 23, 59, 59));
        assert(DateTime(1999, 10, 1, 10, 23, 36).endOfMonth == DateTime(1999, 10, 31, 23, 59, 59));
        assert(DateTime(1999, 11, 1, 11, 24, 37).endOfMonth == DateTime(1999, 11, 30, 23, 59, 59));
        assert(DateTime(1999, 12, 1, 12, 25, 38).endOfMonth == DateTime(1999, 12, 31, 23, 59, 59));

        //Test B.C.
        assert(DateTime(-1999, 1, 1, 0, 13, 26).endOfMonth == DateTime(-1999, 1, 31, 23, 59, 59));
        assert(DateTime(-1999, 2, 1, 1, 14, 27).endOfMonth == DateTime(-1999, 2, 28, 23, 59, 59));
        assert(DateTime(-2000, 2, 1, 2, 15, 28).endOfMonth == DateTime(-2000, 2, 29, 23, 59, 59));
        assert(DateTime(-1999, 3, 1, 3, 16, 29).endOfMonth == DateTime(-1999, 3, 31, 23, 59, 59));
        assert(DateTime(-1999, 4, 1, 4, 17, 30).endOfMonth == DateTime(-1999, 4, 30, 23, 59, 59));
        assert(DateTime(-1999, 5, 1, 5, 18, 31).endOfMonth == DateTime(-1999, 5, 31, 23, 59, 59));
        assert(DateTime(-1999, 6, 1, 6, 19, 32).endOfMonth == DateTime(-1999, 6, 30, 23, 59, 59));
        assert(DateTime(-1999, 7, 1, 7, 20, 33).endOfMonth == DateTime(-1999, 7, 31, 23, 59, 59));
        assert(DateTime(-1999, 8, 1, 8, 21, 34).endOfMonth == DateTime(-1999, 8, 31, 23, 59, 59));
        assert(DateTime(-1999, 9, 1, 9, 22, 35).endOfMonth == DateTime(-1999, 9, 30, 23, 59, 59));
        assert(DateTime(-1999, 10, 1, 10, 23, 36).endOfMonth == DateTime(-1999, 10, 31, 23, 59, 59));
        assert(DateTime(-1999, 11, 1, 11, 24, 37).endOfMonth == DateTime(-1999, 11, 30, 23, 59, 59));
        assert(DateTime(-1999, 12, 1, 12, 25, 38).endOfMonth == DateTime(-1999, 12, 31, 23, 59, 59));

        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.endOfMonth));
        static assert(__traits(compiles, idt.endOfMonth));
    }


    /++
        The last day in the month that this $(LREF DateTime) is in.
      +/
    @property ubyte daysInMonth() @safe const pure nothrow
    {
        return _date.daysInMonth;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1999, 1, 6), TimeOfDay(0, 0, 0)).daysInMonth == 31);
        assert(DateTime(Date(1999, 2, 7), TimeOfDay(19, 30, 0)).daysInMonth == 28);
        assert(DateTime(Date(2000, 2, 7), TimeOfDay(5, 12, 27)).daysInMonth == 29);
        assert(DateTime(Date(2000, 6, 4), TimeOfDay(12, 22, 9)).daysInMonth == 30);
    }

    unittest
    {
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.daysInMonth));
        static assert(__traits(compiles, idt.daysInMonth));
    }


    /++
        Whether the current year is a date in A.D.
      +/
    @property bool isAD() @safe const pure nothrow
    {
        return _date.isAD;
    }

    ///
    unittest
    {
        assert(DateTime(Date(1, 1, 1), TimeOfDay(12, 7, 0)).isAD);
        assert(DateTime(Date(2010, 12, 31), TimeOfDay(0, 0, 0)).isAD);
        assert(!DateTime(Date(0, 12, 31), TimeOfDay(23, 59, 59)).isAD);
        assert(!DateTime(Date(-2010, 1, 1), TimeOfDay(2, 2, 2)).isAD);
    }

    unittest
    {
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.isAD));
        static assert(__traits(compiles, idt.isAD));
    }


    /++
        The $(WEB en.wikipedia.org/wiki/Julian_day, Julian day) for this
        $(LREF DateTime) at the given time. For example, prior to noon,
        1996-03-31 would be the Julian day number 2_450_173, so this function
        returns 2_450_173, while from noon onward, the julian day number would
        be 2_450_174, so this function returns 2_450_174.
      +/
    @property long julianDay() @safe const pure nothrow
    {
        if (_tod._hour < 12)
            return _date.julianDay - 1;
        else
            return _date.julianDay;
    }

    unittest
    {
        assert(DateTime(Date(-4713, 11, 24), TimeOfDay(0, 0, 0)).julianDay == -1);
        assert(DateTime(Date(-4713, 11, 24), TimeOfDay(12, 0, 0)).julianDay == 0);

        assert(DateTime(Date(0, 12, 31), TimeOfDay(0, 0, 0)).julianDay == 1_721_424);
        assert(DateTime(Date(0, 12, 31), TimeOfDay(12, 0, 0)).julianDay == 1_721_425);

        assert(DateTime(Date(1, 1, 1), TimeOfDay(0, 0, 0)).julianDay == 1_721_425);
        assert(DateTime(Date(1, 1, 1), TimeOfDay(12, 0, 0)).julianDay == 1_721_426);

        assert(DateTime(Date(1582, 10, 15), TimeOfDay(0, 0, 0)).julianDay == 2_299_160);
        assert(DateTime(Date(1582, 10, 15), TimeOfDay(12, 0, 0)).julianDay == 2_299_161);

        assert(DateTime(Date(1858, 11, 17), TimeOfDay(0, 0, 0)).julianDay == 2_400_000);
        assert(DateTime(Date(1858, 11, 17), TimeOfDay(12, 0, 0)).julianDay == 2_400_001);

        assert(DateTime(Date(1982, 1, 4), TimeOfDay(0, 0, 0)).julianDay == 2_444_973);
        assert(DateTime(Date(1982, 1, 4), TimeOfDay(12, 0, 0)).julianDay == 2_444_974);

        assert(DateTime(Date(1996, 3, 31), TimeOfDay(0, 0, 0)).julianDay == 2_450_173);
        assert(DateTime(Date(1996, 3, 31), TimeOfDay(12, 0, 0)).julianDay == 2_450_174);

        assert(DateTime(Date(2010, 8, 24), TimeOfDay(0, 0, 0)).julianDay == 2_455_432);
        assert(DateTime(Date(2010, 8, 24), TimeOfDay(12, 0, 0)).julianDay == 2_455_433);

        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.julianDay));
        static assert(__traits(compiles, idt.julianDay));
    }


    /++
        The modified $(WEB en.wikipedia.org/wiki/Julian_day, Julian day) for any
        time on this date (since, the modified Julian day changes at midnight).
      +/
    @property long modJulianDay() @safe const pure nothrow
    {
        return _date.modJulianDay;
    }

    unittest
    {
        assert(DateTime(Date(1858, 11, 17), TimeOfDay(0, 0, 0)).modJulianDay == 0);
        assert(DateTime(Date(1858, 11, 17), TimeOfDay(12, 0, 0)).modJulianDay == 0);

        assert(DateTime(Date(2010, 8, 24), TimeOfDay(0, 0, 0)).modJulianDay == 55_432);
        assert(DateTime(Date(2010, 8, 24), TimeOfDay(12, 0, 0)).modJulianDay == 55_432);

        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, cdt.modJulianDay));
        static assert(__traits(compiles, idt.modJulianDay));
    }


    /++
        Converts this $(LREF DateTime) to a string with the format YYYYMMDDTHHMMSS.
      +/
    string toISOString() @safe const pure nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");
        return format("%sT%s", _date.toISOString(), _tod.toISOString());
    }

    ///
    unittest
    {
        assert(DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)).toISOString() ==
               "20100704T070612");

        assert(DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)).toISOString() ==
               "19981225T021500");

        assert(DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)).toISOString() ==
               "00000105T230959");

        assert(DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)).toISOString() ==
               "-00040105T000002");
    }

    unittest
    {
        //Test A.D.
        assert(DateTime(Date(9, 12, 4), TimeOfDay(0, 0, 0)).toISOString() == "00091204T000000");
        assert(DateTime(Date(99, 12, 4), TimeOfDay(5, 6, 12)).toISOString() == "00991204T050612");
        assert(DateTime(Date(999, 12, 4), TimeOfDay(13, 44, 59)).toISOString() == "09991204T134459");
        assert(DateTime(Date(9999, 7, 4), TimeOfDay(23, 59, 59)).toISOString() == "99990704T235959");
        assert(DateTime(Date(10000, 10, 20), TimeOfDay(1, 1, 1)).toISOString() == "+100001020T010101");

        //Test B.C.
        assert(DateTime(Date(0, 12, 4), TimeOfDay(0, 12, 4)).toISOString() == "00001204T001204");
        assert(DateTime(Date(-9, 12, 4), TimeOfDay(0, 0, 0)).toISOString() == "-00091204T000000");
        assert(DateTime(Date(-99, 12, 4), TimeOfDay(5, 6, 12)).toISOString() == "-00991204T050612");
        assert(DateTime(Date(-999, 12, 4), TimeOfDay(13, 44, 59)).toISOString() == "-09991204T134459");
        assert(DateTime(Date(-9999, 7, 4), TimeOfDay(23, 59, 59)).toISOString() == "-99990704T235959");
        assert(DateTime(Date(-10000, 10, 20), TimeOfDay(1, 1, 1)).toISOString() == "-100001020T010101");

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.toISOString()));
        static assert(__traits(compiles, idt.toISOString()));
    }


    /++
        Converts this $(LREF DateTime) to a string with the format
        YYYY-MM-DDTHH:MM:SS.
      +/
    string toISOExtString() @safe const pure nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");
        return format("%sT%s", _date.toISOExtString(), _tod.toISOExtString());
    }

    ///
    unittest
    {
        assert(DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)).toISOExtString() ==
               "2010-07-04T07:06:12");

        assert(DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)).toISOExtString() ==
               "1998-12-25T02:15:00");

        assert(DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)).toISOExtString() ==
               "0000-01-05T23:09:59");

        assert(DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)).toISOExtString() ==
               "-0004-01-05T00:00:02");
    }

    unittest
    {
        //Test A.D.
        assert(DateTime(Date(9, 12, 4), TimeOfDay(0, 0, 0)).toISOExtString() == "0009-12-04T00:00:00");
        assert(DateTime(Date(99, 12, 4), TimeOfDay(5, 6, 12)).toISOExtString() == "0099-12-04T05:06:12");
        assert(DateTime(Date(999, 12, 4), TimeOfDay(13, 44, 59)).toISOExtString() == "0999-12-04T13:44:59");
        assert(DateTime(Date(9999, 7, 4), TimeOfDay(23, 59, 59)).toISOExtString() == "9999-07-04T23:59:59");
        assert(DateTime(Date(10000, 10, 20), TimeOfDay(1, 1, 1)).toISOExtString() == "+10000-10-20T01:01:01");

        //Test B.C.
        assert(DateTime(Date(0, 12, 4), TimeOfDay(0, 12, 4)).toISOExtString() == "0000-12-04T00:12:04");
        assert(DateTime(Date(-9, 12, 4), TimeOfDay(0, 0, 0)).toISOExtString() == "-0009-12-04T00:00:00");
        assert(DateTime(Date(-99, 12, 4), TimeOfDay(5, 6, 12)).toISOExtString() == "-0099-12-04T05:06:12");
        assert(DateTime(Date(-999, 12, 4), TimeOfDay(13, 44, 59)).toISOExtString() == "-0999-12-04T13:44:59");
        assert(DateTime(Date(-9999, 7, 4), TimeOfDay(23, 59, 59)).toISOExtString() == "-9999-07-04T23:59:59");
        assert(DateTime(Date(-10000, 10, 20), TimeOfDay(1, 1, 1)).toISOExtString() == "-10000-10-20T01:01:01");

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.toISOExtString()));
        static assert(__traits(compiles, idt.toISOExtString()));
    }

    /++
        Converts this $(LREF DateTime) to a string with the format
        YYYY-Mon-DD HH:MM:SS.
      +/
    string toSimpleString() @safe const pure nothrow
    {
        import std.format : format;

        scope(failure) assert(0, "format() threw.");
        return format("%s %s", _date.toSimpleString(), _tod.toString());
    }

    ///
    unittest
    {
        assert(DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)).toSimpleString() ==
               "2010-Jul-04 07:06:12");

        assert(DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)).toSimpleString() ==
               "1998-Dec-25 02:15:00");

        assert(DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)).toSimpleString() ==
               "0000-Jan-05 23:09:59");

        assert(DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)).toSimpleString() ==
               "-0004-Jan-05 00:00:02");
    }

    unittest
    {
        //Test A.D.
        assert(DateTime(Date(9, 12, 4), TimeOfDay(0, 0, 0)).toSimpleString() == "0009-Dec-04 00:00:00");
        assert(DateTime(Date(99, 12, 4), TimeOfDay(5, 6, 12)).toSimpleString() == "0099-Dec-04 05:06:12");
        assert(DateTime(Date(999, 12, 4), TimeOfDay(13, 44, 59)).toSimpleString() == "0999-Dec-04 13:44:59");
        assert(DateTime(Date(9999, 7, 4), TimeOfDay(23, 59, 59)).toSimpleString() == "9999-Jul-04 23:59:59");
        assert(DateTime(Date(10000, 10, 20), TimeOfDay(1, 1, 1)).toSimpleString() == "+10000-Oct-20 01:01:01");

        //Test B.C.
        assert(DateTime(Date(0, 12, 4), TimeOfDay(0, 12, 4)).toSimpleString() == "0000-Dec-04 00:12:04");
        assert(DateTime(Date(-9, 12, 4), TimeOfDay(0, 0, 0)).toSimpleString() == "-0009-Dec-04 00:00:00");
        assert(DateTime(Date(-99, 12, 4), TimeOfDay(5, 6, 12)).toSimpleString() == "-0099-Dec-04 05:06:12");
        assert(DateTime(Date(-999, 12, 4), TimeOfDay(13, 44, 59)).toSimpleString() == "-0999-Dec-04 13:44:59");
        assert(DateTime(Date(-9999, 7, 4), TimeOfDay(23, 59, 59)).toSimpleString() == "-9999-Jul-04 23:59:59");
        assert(DateTime(Date(-10000, 10, 20), TimeOfDay(1, 1, 1)).toSimpleString() == "-10000-Oct-20 01:01:01");

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(__traits(compiles, cdt.toSimpleString()));
        static assert(__traits(compiles, idt.toSimpleString()));
    }


    /++
        Converts this $(LREF DateTime) to a string.
      +/
    string toString() @safe const pure nothrow
    {
        return toSimpleString();
    }

    unittest
    {
        auto dt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        const cdt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        immutable idt = DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33));
        static assert(__traits(compiles, dt.toString()));
        static assert(__traits(compiles, cdt.toString()));
        static assert(__traits(compiles, idt.toString()));
    }



    /++
        Creates a $(LREF DateTime) from a string with the format YYYYMMDDTHHMMSS.
        Whitespace is stripped from the given string.

        Params:
            isoString = A string formatted in the ISO format for dates and times.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO format
            or if the resulting $(LREF DateTime) would not be valid.
      +/
    static DateTime fromISOString(S)(in S isoString) @safe pure
        if (isSomeString!S)
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : countUntil;
        import std.format : format;
        import std.exception : enforce;

        immutable dstr = to!dstring(strip(isoString));

        enforce(dstr.length >= 15, new DateTimeException(format("Invalid ISO String: %s", isoString)));
        auto t = dstr.countUntil('T');

        enforce(t != -1, new DateTimeException(format("Invalid ISO String: %s", isoString)));

        immutable date = Date.fromISOString(dstr[0..t]);
        immutable tod = TimeOfDay.fromISOString(dstr[t+1 .. $]);

        return DateTime(date, tod);
    }

    ///
    unittest
    {
        assert(DateTime.fromISOString("20100704T070612") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));

        assert(DateTime.fromISOString("19981225T021500") ==
               DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)));

        assert(DateTime.fromISOString("00000105T230959") ==
               DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)));

        assert(DateTime.fromISOString("-00040105T000002") ==
               DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)));

        assert(DateTime.fromISOString(" 20100704T070612 ") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));
    }

    unittest
    {
        assertThrown!DateTimeException(DateTime.fromISOString(""));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704 000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704t000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704T000000."));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704T000000.0"));

        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04T00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04T00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04T00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromISOString("2010-12-22T172201"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Dec-22 17:22:01"));

        assert(DateTime.fromISOString("20101222T172201") == DateTime(Date(2010, 12, 22), TimeOfDay(17, 22, 01)));
        assert(DateTime.fromISOString("19990706T123033") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOString("-19990706T123033") == DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOString("+019990706T123033") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOString("19990706T123033 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOString(" 19990706T123033") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOString(" 19990706T123033 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
    }


    /++
        Creates a $(LREF DateTime) from a string with the format
        YYYY-MM-DDTHH:MM:SS. Whitespace is stripped from the given string.

        Params:
            isoExtString = A string formatted in the ISO Extended format for dates
                           and times.

        Throws:
            $(LREF DateTimeException) if the given string is not in the ISO
            Extended format or if the resulting $(LREF DateTime) would not be
            valid.
      +/
    static DateTime fromISOExtString(S)(in S isoExtString) @safe pure
        if (isSomeString!(S))
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : countUntil;
        import std.format : format;
        import std.exception : enforce;

        immutable dstr = to!dstring(strip(isoExtString));

        enforce(dstr.length >= 15, new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));
        auto t = dstr.countUntil('T');

        enforce(t != -1, new DateTimeException(format("Invalid ISO Extended String: %s", isoExtString)));

        immutable date = Date.fromISOExtString(dstr[0..t]);
        immutable tod = TimeOfDay.fromISOExtString(dstr[t+1 .. $]);

        return DateTime(date, tod);
    }

    ///
    unittest
    {
        assert(DateTime.fromISOExtString("2010-07-04T07:06:12") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));

        assert(DateTime.fromISOExtString("1998-12-25T02:15:00") ==
               DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)));

        assert(DateTime.fromISOExtString("0000-01-05T23:09:59") ==
               DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)));

        assert(DateTime.fromISOExtString("-0004-01-05T00:00:02") ==
               DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)));

        assert(DateTime.fromISOExtString(" 2010-07-04T07:06:12 ") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));
    }

    unittest
    {
        assertThrown!DateTimeException(DateTime.fromISOExtString(""));
        assertThrown!DateTimeException(DateTime.fromISOExtString("20100704000000"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("20100704 000000"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("20100704t000000"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("20100704T000000."));
        assertThrown!DateTimeException(DateTime.fromISOExtString("20100704T000000.0"));

        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07:0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07-04T00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-07-04T00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-Jul-04 00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-Jul-04 00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromISOExtString("20101222T172201"));
        assertThrown!DateTimeException(DateTime.fromISOExtString("2010-Dec-22 17:22:01"));

        assert(DateTime.fromISOExtString("2010-12-22T17:22:01") == DateTime(Date(2010, 12, 22), TimeOfDay(17, 22, 01)));
        assert(DateTime.fromISOExtString("1999-07-06T12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOExtString("-1999-07-06T12:30:33") == DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOExtString("+01999-07-06T12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOExtString("1999-07-06T12:30:33 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOExtString(" 1999-07-06T12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromISOExtString(" 1999-07-06T12:30:33 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
    }


    /++
        Creates a $(LREF DateTime) from a string with the format
        YYYY-Mon-DD HH:MM:SS. Whitespace is stripped from the given string.

        Params:
            simpleString = A string formatted in the way that toSimpleString
                           formats dates and times.

        Throws:
            $(LREF DateTimeException) if the given string is not in the correct
            format or if the resulting $(LREF DateTime) would not be valid.
      +/
    static DateTime fromSimpleString(S)(in S simpleString) @safe pure
        if (isSomeString!(S))
    {
        import std.string : strip;
        import std.conv : to;
        import std.algorithm : countUntil;
        import std.format : format;
        import std.exception : enforce;

        immutable dstr = to!dstring(strip(simpleString));

        enforce(dstr.length >= 15, new DateTimeException(format("Invalid string format: %s", simpleString)));
        auto t = dstr.countUntil(' ');

        enforce(t != -1, new DateTimeException(format("Invalid string format: %s", simpleString)));

        immutable date = Date.fromSimpleString(dstr[0..t]);
        immutable tod = TimeOfDay.fromISOExtString(dstr[t+1 .. $]);

        return DateTime(date, tod);
    }

    ///
    unittest
    {
        assert(DateTime.fromSimpleString("2010-Jul-04 07:06:12") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));
        assert(DateTime.fromSimpleString("1998-Dec-25 02:15:00") ==
               DateTime(Date(1998, 12, 25), TimeOfDay(2, 15, 0)));
        assert(DateTime.fromSimpleString("0000-Jan-05 23:09:59") ==
               DateTime(Date(0, 1, 5), TimeOfDay(23, 9, 59)));
        assert(DateTime.fromSimpleString("-0004-Jan-05 00:00:02") ==
               DateTime(Date(-4, 1, 5), TimeOfDay(0, 0, 2)));
        assert(DateTime.fromSimpleString(" 2010-Jul-04 07:06:12 ") ==
               DateTime(Date(2010, 7, 4), TimeOfDay(7, 6, 12)));
    }

    unittest
    {
        assertThrown!DateTimeException(DateTime.fromISOString(""));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704 000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704t000000"));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704T000000."));
        assertThrown!DateTimeException(DateTime.fromISOString("20100704T000000.0"));

        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04T00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-07-04T00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-0400:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04t00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04T00:00:00"));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00."));
        assertThrown!DateTimeException(DateTime.fromISOString("2010-Jul-04 00:00:00.0"));

        assertThrown!DateTimeException(DateTime.fromSimpleString("20101222T172201"));
        assertThrown!DateTimeException(DateTime.fromSimpleString("2010-12-22T172201"));

        assert(DateTime.fromSimpleString("2010-Dec-22 17:22:01") == DateTime(Date(2010, 12, 22), TimeOfDay(17, 22, 01)));
        assert(DateTime.fromSimpleString("1999-Jul-06 12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromSimpleString("-1999-Jul-06 12:30:33") == DateTime(Date(-1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromSimpleString("+01999-Jul-06 12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromSimpleString("1999-Jul-06 12:30:33 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromSimpleString(" 1999-Jul-06 12:30:33") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
        assert(DateTime.fromSimpleString(" 1999-Jul-06 12:30:33 ") == DateTime(Date(1999, 7, 6), TimeOfDay(12, 30, 33)));
    }


    /++
        Returns the $(LREF DateTime) farthest in the past which is representable by
        $(LREF DateTime).
      +/
    @property static DateTime min() @safe pure nothrow
    out(result)
    {
        assert(result._date == Date.min);
        assert(result._tod == TimeOfDay.min);
    }
    body
    {
        auto dt = DateTime.init;
        dt._date._year = short.min;
        dt._date._month = Month.jan;
        dt._date._day = 1;

        return dt;
    }

    unittest
    {
        assert(DateTime.min.year < 0);
        assert(DateTime.min < DateTime.max);
    }


    /++
        Returns the $(LREF DateTime) farthest in the future which is representable
        by $(LREF DateTime).
      +/
    @property static DateTime max() @safe pure nothrow
    out(result)
    {
        assert(result._date == Date.max);
        assert(result._tod == TimeOfDay.max);
    }
    body
    {
        auto dt = DateTime.init;
        dt._date._year = short.max;
        dt._date._month = Month.dec;
        dt._date._day = 31;
        dt._tod._hour = TimeOfDay.maxHour;
        dt._tod._minute = TimeOfDay.maxMinute;
        dt._tod._second = TimeOfDay.maxSecond;

        return dt;
    }

    unittest
    {
        assert(DateTime.max.year > 0);
        assert(DateTime.max > DateTime.min);
    }


private:

    /+
        Add seconds to the time of day. Negative values will subtract. If the
        number of seconds overflows (or underflows), then the seconds will wrap,
        increasing (or decreasing) the number of minutes accordingly. The
        same goes for any larger units.

        Params:
            seconds = The number of seconds to add to this $(LREF DateTime).
      +/
    ref DateTime _addSeconds(long seconds) return @safe pure nothrow
    {
        long hnsecs = convert!("seconds", "hnsecs")(seconds);
        hnsecs += convert!("hours", "hnsecs")(_tod._hour);
        hnsecs += convert!("minutes", "hnsecs")(_tod._minute);
        hnsecs += convert!("seconds", "hnsecs")(_tod._second);

        auto days = splitUnitsFromHNSecs!"days"(hnsecs);

        if (hnsecs < 0)
        {
            hnsecs += convert!("days", "hnsecs")(1);
            --days;
        }

        _date._addDays(days);

        immutable newHours = splitUnitsFromHNSecs!"hours"(hnsecs);
        immutable newMinutes = splitUnitsFromHNSecs!"minutes"(hnsecs);
        immutable newSeconds = splitUnitsFromHNSecs!"seconds"(hnsecs);

        _tod._hour = cast(ubyte)newHours;
        _tod._minute = cast(ubyte)newMinutes;
        _tod._second = cast(ubyte)newSeconds;

        return this;
    }

    unittest
    {
        static void testDT(DateTime orig, int seconds, in DateTime expected, size_t line = __LINE__)
        {
            orig._addSeconds(seconds);
            assert(orig == expected);
        }

        //Test A.D.
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 0, DateTime(1999, 7, 6, 12, 30, 33));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 1, DateTime(1999, 7, 6, 12, 30, 34));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 2, DateTime(1999, 7, 6, 12, 30, 35));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 3, DateTime(1999, 7, 6, 12, 30, 36));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 4, DateTime(1999, 7, 6, 12, 30, 37));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 5, DateTime(1999, 7, 6, 12, 30, 38));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 10, DateTime(1999, 7, 6, 12, 30, 43));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 15, DateTime(1999, 7, 6, 12, 30, 48));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 26, DateTime(1999, 7, 6, 12, 30, 59));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 27, DateTime(1999, 7, 6, 12, 31, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 30, DateTime(1999, 7, 6, 12, 31, 3));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 59, DateTime(1999, 7, 6, 12, 31, 32));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 60, DateTime(1999, 7, 6, 12, 31, 33));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 61, DateTime(1999, 7, 6, 12, 31, 34));

        testDT(DateTime(1999, 7, 6, 12, 30, 33), 1766, DateTime(1999, 7, 6, 12, 59, 59));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 1767, DateTime(1999, 7, 6, 13, 0, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 1768, DateTime(1999, 7, 6, 13, 0, 1));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 2007, DateTime(1999, 7, 6, 13, 4, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 3599, DateTime(1999, 7, 6, 13, 30, 32));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 3600, DateTime(1999, 7, 6, 13, 30, 33));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 3601, DateTime(1999, 7, 6, 13, 30, 34));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), 7200, DateTime(1999, 7, 6, 14, 30, 33));
        testDT(DateTime(1999, 7, 6, 23, 0, 0), 432_123, DateTime(1999, 7, 11, 23, 2, 3));

        testDT(DateTime(1999, 7, 6, 12, 30, 33), -1, DateTime(1999, 7, 6, 12, 30, 32));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -2, DateTime(1999, 7, 6, 12, 30, 31));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -3, DateTime(1999, 7, 6, 12, 30, 30));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -4, DateTime(1999, 7, 6, 12, 30, 29));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -5, DateTime(1999, 7, 6, 12, 30, 28));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -10, DateTime(1999, 7, 6, 12, 30, 23));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -15, DateTime(1999, 7, 6, 12, 30, 18));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -33, DateTime(1999, 7, 6, 12, 30, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -34, DateTime(1999, 7, 6, 12, 29, 59));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -35, DateTime(1999, 7, 6, 12, 29, 58));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -59, DateTime(1999, 7, 6, 12, 29, 34));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -60, DateTime(1999, 7, 6, 12, 29, 33));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -61, DateTime(1999, 7, 6, 12, 29, 32));

        testDT(DateTime(1999, 7, 6, 12, 30, 33), -1833, DateTime(1999, 7, 6, 12, 0, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -1834, DateTime(1999, 7, 6, 11, 59, 59));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -3600, DateTime(1999, 7, 6, 11, 30, 33));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -3601, DateTime(1999, 7, 6, 11, 30, 32));
        testDT(DateTime(1999, 7, 6, 12, 30, 33), -5134, DateTime(1999, 7, 6, 11, 4, 59));
        testDT(DateTime(1999, 7, 6, 23, 0, 0), -432_123, DateTime(1999, 7, 1, 22, 57, 57));

        testDT(DateTime(1999, 7, 6, 12, 30, 0), 1, DateTime(1999, 7, 6, 12, 30, 1));
        testDT(DateTime(1999, 7, 6, 12, 30, 0), 0, DateTime(1999, 7, 6, 12, 30, 0));
        testDT(DateTime(1999, 7, 6, 12, 30, 0), -1, DateTime(1999, 7, 6, 12, 29, 59));

        testDT(DateTime(1999, 7, 6, 12, 0, 0), 1, DateTime(1999, 7, 6, 12, 0, 1));
        testDT(DateTime(1999, 7, 6, 12, 0, 0), 0, DateTime(1999, 7, 6, 12, 0, 0));
        testDT(DateTime(1999, 7, 6, 12, 0, 0), -1, DateTime(1999, 7, 6, 11, 59, 59));

        testDT(DateTime(1999, 7, 6, 0, 0, 0), 1, DateTime(1999, 7, 6, 0, 0, 1));
        testDT(DateTime(1999, 7, 6, 0, 0, 0), 0, DateTime(1999, 7, 6, 0, 0, 0));
        testDT(DateTime(1999, 7, 6, 0, 0, 0), -1, DateTime(1999, 7, 5, 23, 59, 59));

        testDT(DateTime(1999, 7, 5, 23, 59, 59), 1, DateTime(1999, 7, 6, 0, 0, 0));
        testDT(DateTime(1999, 7, 5, 23, 59, 59), 0, DateTime(1999, 7, 5, 23, 59, 59));
        testDT(DateTime(1999, 7, 5, 23, 59, 59), -1, DateTime(1999, 7, 5, 23, 59, 58));

        testDT(DateTime(1998, 12, 31, 23, 59, 59), 1, DateTime(1999, 1, 1, 0, 0, 0));
        testDT(DateTime(1998, 12, 31, 23, 59, 59), 0, DateTime(1998, 12, 31, 23, 59, 59));
        testDT(DateTime(1998, 12, 31, 23, 59, 59), -1, DateTime(1998, 12, 31, 23, 59, 58));

        testDT(DateTime(1998, 1, 1, 0, 0, 0), 1, DateTime(1998, 1, 1, 0, 0, 1));
        testDT(DateTime(1998, 1, 1, 0, 0, 0), 0, DateTime(1998, 1, 1, 0, 0, 0));
        testDT(DateTime(1998, 1, 1, 0, 0, 0), -1, DateTime(1997, 12, 31, 23, 59, 59));

        //Test B.C.
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 0, DateTime(-1999, 7, 6, 12, 30, 33));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 1, DateTime(-1999, 7, 6, 12, 30, 34));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 2, DateTime(-1999, 7, 6, 12, 30, 35));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 3, DateTime(-1999, 7, 6, 12, 30, 36));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 4, DateTime(-1999, 7, 6, 12, 30, 37));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 5, DateTime(-1999, 7, 6, 12, 30, 38));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 10, DateTime(-1999, 7, 6, 12, 30, 43));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 15, DateTime(-1999, 7, 6, 12, 30, 48));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 26, DateTime(-1999, 7, 6, 12, 30, 59));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 27, DateTime(-1999, 7, 6, 12, 31, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 30, DateTime(-1999, 7, 6, 12, 31, 3));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 59, DateTime(-1999, 7, 6, 12, 31, 32));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 60, DateTime(-1999, 7, 6, 12, 31, 33));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 61, DateTime(-1999, 7, 6, 12, 31, 34));

        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 1766, DateTime(-1999, 7, 6, 12, 59, 59));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 1767, DateTime(-1999, 7, 6, 13, 0, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 1768, DateTime(-1999, 7, 6, 13, 0, 1));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 2007, DateTime(-1999, 7, 6, 13, 4, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 3599, DateTime(-1999, 7, 6, 13, 30, 32));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 3600, DateTime(-1999, 7, 6, 13, 30, 33));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 3601, DateTime(-1999, 7, 6, 13, 30, 34));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), 7200, DateTime(-1999, 7, 6, 14, 30, 33));
        testDT(DateTime(-1999, 7, 6, 23, 0, 0), 432_123, DateTime(-1999, 7, 11, 23, 2, 3));

        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -1, DateTime(-1999, 7, 6, 12, 30, 32));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -2, DateTime(-1999, 7, 6, 12, 30, 31));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -3, DateTime(-1999, 7, 6, 12, 30, 30));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -4, DateTime(-1999, 7, 6, 12, 30, 29));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -5, DateTime(-1999, 7, 6, 12, 30, 28));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -10, DateTime(-1999, 7, 6, 12, 30, 23));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -15, DateTime(-1999, 7, 6, 12, 30, 18));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -33, DateTime(-1999, 7, 6, 12, 30, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -34, DateTime(-1999, 7, 6, 12, 29, 59));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -35, DateTime(-1999, 7, 6, 12, 29, 58));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -59, DateTime(-1999, 7, 6, 12, 29, 34));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -60, DateTime(-1999, 7, 6, 12, 29, 33));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -61, DateTime(-1999, 7, 6, 12, 29, 32));

        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -1833, DateTime(-1999, 7, 6, 12, 0, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -1834, DateTime(-1999, 7, 6, 11, 59, 59));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -3600, DateTime(-1999, 7, 6, 11, 30, 33));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -3601, DateTime(-1999, 7, 6, 11, 30, 32));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -5134, DateTime(-1999, 7, 6, 11, 4, 59));
        testDT(DateTime(-1999, 7, 6, 12, 30, 33), -7200, DateTime(-1999, 7, 6, 10, 30, 33));
        testDT(DateTime(-1999, 7, 6, 23, 0, 0), -432_123, DateTime(-1999, 7, 1, 22, 57, 57));

        testDT(DateTime(-1999, 7, 6, 12, 30, 0), 1, DateTime(-1999, 7, 6, 12, 30, 1));
        testDT(DateTime(-1999, 7, 6, 12, 30, 0), 0, DateTime(-1999, 7, 6, 12, 30, 0));
        testDT(DateTime(-1999, 7, 6, 12, 30, 0), -1, DateTime(-1999, 7, 6, 12, 29, 59));

        testDT(DateTime(-1999, 7, 6, 12, 0, 0), 1, DateTime(-1999, 7, 6, 12, 0, 1));
        testDT(DateTime(-1999, 7, 6, 12, 0, 0), 0, DateTime(-1999, 7, 6, 12, 0, 0));
        testDT(DateTime(-1999, 7, 6, 12, 0, 0), -1, DateTime(-1999, 7, 6, 11, 59, 59));

        testDT(DateTime(-1999, 7, 6, 0, 0, 0), 1, DateTime(-1999, 7, 6, 0, 0, 1));
        testDT(DateTime(-1999, 7, 6, 0, 0, 0), 0, DateTime(-1999, 7, 6, 0, 0, 0));
        testDT(DateTime(-1999, 7, 6, 0, 0, 0), -1, DateTime(-1999, 7, 5, 23, 59, 59));

        testDT(DateTime(-1999, 7, 5, 23, 59, 59), 1, DateTime(-1999, 7, 6, 0, 0, 0));
        testDT(DateTime(-1999, 7, 5, 23, 59, 59), 0, DateTime(-1999, 7, 5, 23, 59, 59));
        testDT(DateTime(-1999, 7, 5, 23, 59, 59), -1, DateTime(-1999, 7, 5, 23, 59, 58));

        testDT(DateTime(-2000, 12, 31, 23, 59, 59), 1, DateTime(-1999, 1, 1, 0, 0, 0));
        testDT(DateTime(-2000, 12, 31, 23, 59, 59), 0, DateTime(-2000, 12, 31, 23, 59, 59));
        testDT(DateTime(-2000, 12, 31, 23, 59, 59), -1, DateTime(-2000, 12, 31, 23, 59, 58));

        testDT(DateTime(-2000, 1, 1, 0, 0, 0), 1, DateTime(-2000, 1, 1, 0, 0, 1));
        testDT(DateTime(-2000, 1, 1, 0, 0, 0), 0, DateTime(-2000, 1, 1, 0, 0, 0));
        testDT(DateTime(-2000, 1, 1, 0, 0, 0), -1, DateTime(-2001, 12, 31, 23, 59, 59));

        //Test Both
        testDT(DateTime(1, 1, 1, 0, 0, 0), -1, DateTime(0, 12, 31, 23, 59, 59));
        testDT(DateTime(0, 12, 31, 23, 59, 59), 1, DateTime(1, 1, 1, 0, 0, 0));

        testDT(DateTime(0, 1, 1, 0, 0, 0), -1, DateTime(-1, 12, 31, 23, 59, 59));
        testDT(DateTime(-1, 12, 31, 23, 59, 59), 1, DateTime(0, 1, 1, 0, 0, 0));

        testDT(DateTime(-1, 1, 1, 11, 30, 33), 63_165_600L, DateTime(1, 1, 1, 13, 30, 33));
        testDT(DateTime(1, 1, 1, 13, 30, 33), -63_165_600L, DateTime(-1, 1, 1, 11, 30, 33));

        testDT(DateTime(-1, 1, 1, 11, 30, 33), 63_165_617L, DateTime(1, 1, 1, 13, 30, 50));
        testDT(DateTime(1, 1, 1, 13, 30, 50), -63_165_617L, DateTime(-1, 1, 1, 11, 30, 33));

        const cdt = DateTime(1999, 7, 6, 12, 30, 33);
        immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
        static assert(!__traits(compiles, cdt._addSeconds(4)));
        static assert(!__traits(compiles, idt._addSeconds(4)));
    }


    Date      _date;
    TimeOfDay _tod;
}


//==============================================================================
// Section with trait templates.
//==============================================================================

/++
    Whether the given type defines all of the necessary functions for it to
    function as a time point.
  +/
enum bool isTimePoint(T) =
    hasMin!T &&
    hasMax!T &&
    hasOverloadedOpBinaryWithDuration!T &&
    hasOverloadedOpAssignWithDuration!T &&
    hasOverloadedOpBinaryWithSelf!T;

/+
    Whether the given type defines the static property min which returns the
    minimum value for the type.
  +/
private enum bool hasMin(T) =
    __traits(hasMember, T, "min") &&
    __traits(isStaticFunction, T.min) &&
    is(typeof(T.min) == Unqual!T);

/+
    Whether the given type defines the static property max which returns the
    maximum value for the type.
  +/
private enum bool hasMax(T) =
    __traits(hasMember, T, "max") &&
    __traits(isStaticFunction, T.max) &&
    is(typeof(T.max) == Unqual!T);

/+
    Whether the given type defines the overloaded opBinary operators that a time
    point is supposed to define which work with time durations. Namely:

    $(BOOKTABLE,
    $(TR $(TD TimePoint opBinary"+"(duration)))
    $(TR $(TD TimePoint opBinary"-"(duration)))
    )
  +/
private enum bool hasOverloadedOpBinaryWithDuration(T) =
    __traits(compiles, T.init + dur!"days"(5)) &&
             is(typeof(T.init + dur!"days"(5)) == Unqual!T) &&
    __traits(compiles, T.init - dur!"days"(5)) &&
             is(typeof(T.init - dur!"days"(5)) == Unqual!T) &&
    __traits(compiles, T.init + TickDuration.from!"hnsecs"(5)) &&
             is(typeof(T.init + TickDuration.from!"hnsecs"(5)) == Unqual!T) &&
    __traits(compiles, T.init - TickDuration.from!"hnsecs"(5)) &&
             is(typeof(T.init - TickDuration.from!"hnsecs"(5)) == Unqual!T);

/+
    Whether the given type defines the overloaded opOpAssign operators that a time point is supposed
    to define. Namely:

    $(BOOKTABLE,
    $(TR $(TD TimePoint opOpAssign"+"(duration)))
    $(TR $(TD TimePoint opOpAssign"-"(duration)))
    )
  +/
private enum bool hasOverloadedOpAssignWithDuration(T) =
    is(typeof(
    {
        auto  d = dur!"days"(5);
        auto td = TickDuration.from!"hnsecs"(5);
        alias U = Unqual!T;
        static assert(is(typeof(U.init +=  d) == U));
        static assert(is(typeof(U.init -=  d) == U));
        static assert(is(typeof(U.init += td) == U));
        static assert(is(typeof(U.init -= td) == U));
    }));

/+
    Whether the given type defines the overloaded opBinary operator that a time point is supposed
    to define which works with itself. Namely:

    $(BOOKTABLE,
    $(TR $(TD duration opBinary"-"(Date)))
    )
  +/
private enum bool hasOverloadedOpBinaryWithSelf(T) =
    __traits(compiles, T.init - T.init) &&
    is(Unqual!(typeof(T.init - T.init)) == Duration);

// Tests for the four time-point types
unittest
{
    import std.typetuple : TypeTuple;

    foreach (TP; TypeTuple!(Date, DateTime, TimeOfDay, SysTime))
    {
        static assert(isTimePoint!(TP));
        static assert(isTimePoint!(const TP));
        static assert(isTimePoint!(immutable TP));

        static assert(hasMin!(TP));
        static assert(hasMin!(const TP));
        static assert(hasMin!(immutable TP));

        static assert(hasMax!(TP));
        static assert(hasMax!(const TP));
        static assert(hasMax!(immutable TP));

        static assert(hasOverloadedOpBinaryWithDuration!(TP));
        static assert(hasOverloadedOpBinaryWithDuration!(const TP));
        static assert(hasOverloadedOpBinaryWithDuration!(immutable TP));

        static assert(hasOverloadedOpAssignWithDuration!(TP));
        static assert(hasOverloadedOpAssignWithDuration!(const TP));
        static assert(hasOverloadedOpAssignWithDuration!(immutable TP));

        static assert(hasOverloadedOpBinaryWithSelf!(TP));
        static assert(hasOverloadedOpBinaryWithSelf!(const TP));
        static assert(hasOverloadedOpBinaryWithSelf!(immutable TP));

        /* Issue 6642 */
        static assert(!hasUnsharedAliasing!TP);
    }
}


//==============================================================================
// Section with public helper functions.
//==============================================================================

/++
    Whether the given Gregorian Year is a leap year.

    Params:
        year = The year to to be tested.
 +/
static bool yearIsLeapYear(int year) @safe pure nothrow
{
    if (year % 400 == 0)
        return true;
    if (year % 100 == 0)
        return false;
    return year % 4 == 0;
}

unittest
{
    import std.format : format;
    foreach (year; [1, 2, 3, 5, 6, 7, 100, 200, 300, 500, 600, 700, 1998, 1999,
                   2001, 2002, 2003, 2005, 2006, 2007, 2009, 2010, 2011])
    {
        assert(!yearIsLeapYear(+year), format("year: %s.", year));
        assert(!yearIsLeapYear(-year), format("year: %s.", year));
    }

    foreach (year; [0, 4, 8, 400, 800, 1600, 1996, 2000, 2004, 2008, 2012])
    {
        assert(yearIsLeapYear(+year), format("year: %s.", year));
        assert(yearIsLeapYear(-year), format("year: %s.", year));
    }
}

//==============================================================================
// Section with private helper functions.
//==============================================================================

private:


/+
    Splits out a particular unit from hnsecs and gives the value for that
    unit and the remaining hnsecs. It really shouldn't be used unless unless
    all units larger than the given units have already been split out.

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs. Upon returning, it is the hnsecs left
                 after splitting out the given units.

    Returns:
        The number of the given units from converting hnsecs to those units.
  +/
long splitUnitsFromHNSecs(string units)(ref long hnsecs) @safe pure nothrow
    if (validTimeUnits(units) &&
       CmpTimeUnits!(units, "months") < 0)
{
    immutable value = convert!("hnsecs", units)(hnsecs);
    hnsecs -= convert!(units, "hnsecs")(value);

    return value;
}

unittest
{
    auto hnsecs = 2595000000007L;
    immutable days = splitUnitsFromHNSecs!"days"(hnsecs);
    assert(days == 3);
    assert(hnsecs == 3000000007);

    immutable minutes = splitUnitsFromHNSecs!"minutes"(hnsecs);
    assert(minutes == 5);
    assert(hnsecs == 7);
}


/+
    This function is used to split out the units without getting the remaining
    hnsecs.

    See_Also:
        $(LREF splitUnitsFromHNSecs)

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs.

    Returns:
        The split out value.
  +/
long getUnitsFromHNSecs(string units)(long hnsecs) @safe pure nothrow
    if (validTimeUnits(units) &&
       CmpTimeUnits!(units, "months") < 0)
{
    return convert!("hnsecs", units)(hnsecs);
}

unittest
{
    auto hnsecs = 2595000000007L;
    immutable days = getUnitsFromHNSecs!"days"(hnsecs);
    assert(days == 3);
    assert(hnsecs == 2595000000007L);
}


/+
    This function is used to split out the units without getting the units but
    just the remaining hnsecs.

    See_Also:
        $(LREF splitUnitsFromHNSecs)

    Params:
        units  = The units to split out.
        hnsecs = The current total hnsecs.

    Returns:
        The remaining hnsecs.
  +/
long removeUnitsFromHNSecs(string units)(long hnsecs) @safe pure nothrow
    if (validTimeUnits(units) &&
       CmpTimeUnits!(units, "months") < 0)
{
    immutable value = convert!("hnsecs", units)(hnsecs);

    return hnsecs - convert!(units, "hnsecs")(value);
}

unittest
{
    auto hnsecs = 2595000000007L;
    auto returned = removeUnitsFromHNSecs!"days"(hnsecs);
    assert(returned == 3000000007);
    assert(hnsecs == 2595000000007L);
}


//==============================================================================
// Section for unittest.
//==============================================================================

version(unittest)
{
    import std.typecons;
    import std.algorithm;
    //Variables to help in testing.
    Duration currLocalDiffFromUTC;
    immutable (TimeZone)[] testTZs;

    //All of these helper arrays are sorted in ascending order.
    auto testYearsBC = [-1999, -1200, -600, -4, -1, 0];
    auto testYearsAD = [1, 4, 1000, 1999, 2000, 2012];

    //I'd use a Tuple, but I get forward reference errors if I try.
    struct MonthDay
    {
        Month month;
        short day;

        this(int m, short d)
        {
            month = cast(Month)m;
            day = d;
        }
    }

    MonthDay[] testMonthDays = [
        MonthDay(1, 1),
        MonthDay(1, 2),
        MonthDay(3, 17),
        MonthDay(7, 4),
        MonthDay(10, 27),
        MonthDay(12, 30),
        MonthDay(12, 31)
    ];

    auto testDays = [1, 2, 9, 10, 16, 20, 25, 28, 29, 30, 31];

    auto testTODs = [
        TimeOfDay(0, 0, 0),
        TimeOfDay(0, 0, 1),
        TimeOfDay(0, 1, 0),
        TimeOfDay(1, 0, 0),
        TimeOfDay(13, 13, 13),
        TimeOfDay(23, 59, 59)
    ];

    auto testHours = [0, 1, 12, 22, 23];
    auto testMinSecs = [0, 1, 30, 58, 59];

    //Throwing exceptions is incredibly expensive, so we want to use a smaller
    //set of values for tests using assertThrown.
    auto testTODsThrown = [
        TimeOfDay(0, 0, 0),
        TimeOfDay(13, 13, 13),
        TimeOfDay(23, 59, 59)
    ];

    Date[] testDatesBC;
    Date[] testDatesAD;

    DateTime[] testDateTimesBC;
    DateTime[] testDateTimesAD;

    Duration[] testFracSecs;

    SysTime[] testSysTimesBC;
    SysTime[] testSysTimesAD;

    //I'd use a Tuple, but I get forward reference errors if I try.
    struct GregDay { int day; Date date; }
    auto testGregDaysBC = [
        GregDay(-1_373_427, Date(-3760, 9, 7)), //Start of the Hebrew Calendar
        GregDay(-735_233, Date(-2012, 1, 1)),
        GregDay(-735_202, Date(-2012, 2, 1)),
        GregDay(-735_175, Date(-2012, 2, 28)),
        GregDay(-735_174, Date(-2012, 2, 29)),
        GregDay(-735_173, Date(-2012, 3, 1)),
        GregDay(-734_502, Date(-2010, 1, 1)),
        GregDay(-734_472, Date(-2010, 1, 31)),
        GregDay(-734_471, Date(-2010, 2, 1)),
        GregDay(-734_444, Date(-2010, 2, 28)),
        GregDay(-734_443, Date(-2010, 3, 1)),
        GregDay(-734_413, Date(-2010, 3, 31)),
        GregDay(-734_412, Date(-2010, 4, 1)),
        GregDay(-734_383, Date(-2010, 4, 30)),
        GregDay(-734_382, Date(-2010, 5, 1)),
        GregDay(-734_352, Date(-2010, 5, 31)),
        GregDay(-734_351, Date(-2010, 6, 1)),
        GregDay(-734_322, Date(-2010, 6, 30)),
        GregDay(-734_321, Date(-2010, 7, 1)),
        GregDay(-734_291, Date(-2010, 7, 31)),
        GregDay(-734_290, Date(-2010, 8, 1)),
        GregDay(-734_260, Date(-2010, 8, 31)),
        GregDay(-734_259, Date(-2010, 9, 1)),
        GregDay(-734_230, Date(-2010, 9, 30)),
        GregDay(-734_229, Date(-2010, 10, 1)),
        GregDay(-734_199, Date(-2010, 10, 31)),
        GregDay(-734_198, Date(-2010, 11, 1)),
        GregDay(-734_169, Date(-2010, 11, 30)),
        GregDay(-734_168, Date(-2010, 12, 1)),
        GregDay(-734_139, Date(-2010, 12, 30)),
        GregDay(-734_138, Date(-2010, 12, 31)),
        GregDay(-731_215, Date(-2001, 1, 1)),
        GregDay(-730_850, Date(-2000, 1, 1)),
        GregDay(-730_849, Date(-2000, 1, 2)),
        GregDay(-730_486, Date(-2000, 12, 30)),
        GregDay(-730_485, Date(-2000, 12, 31)),
        GregDay(-730_484, Date(-1999, 1, 1)),
        GregDay(-694_690, Date(-1901, 1, 1)),
        GregDay(-694_325, Date(-1900, 1, 1)),
        GregDay(-585_118, Date(-1601, 1, 1)),
        GregDay(-584_753, Date(-1600, 1, 1)),
        GregDay(-584_388, Date(-1600, 12, 31)),
        GregDay(-584_387, Date(-1599, 1, 1)),
        GregDay(-365_972, Date(-1001, 1, 1)),
        GregDay(-365_607, Date(-1000, 1, 1)),
        GregDay(-183_351, Date(-501, 1, 1)),
        GregDay(-182_986, Date(-500, 1, 1)),
        GregDay(-182_621, Date(-499, 1, 1)),
        GregDay(-146_827, Date(-401, 1, 1)),
        GregDay(-146_462, Date(-400, 1, 1)),
        GregDay(-146_097, Date(-400, 12, 31)),
        GregDay(-110_302, Date(-301, 1, 1)),
        GregDay(-109_937, Date(-300, 1, 1)),
        GregDay(-73_778, Date(-201, 1, 1)),
        GregDay(-73_413, Date(-200, 1, 1)),
        GregDay(-38_715, Date(-105, 1, 1)),
        GregDay(-37_254, Date(-101, 1, 1)),
        GregDay(-36_889, Date(-100, 1, 1)),
        GregDay(-36_524, Date(-99, 1, 1)),
        GregDay(-36_160, Date(-99, 12, 31)),
        GregDay(-35_794, Date(-97, 1, 1)),
        GregDay(-18_627, Date(-50, 1, 1)),
        GregDay(-18_262, Date(-49, 1, 1)),
        GregDay(-3652, Date(-9, 1, 1)),
        GregDay(-2191, Date(-5, 1, 1)),
        GregDay(-1827, Date(-5, 12, 31)),
        GregDay(-1826, Date(-4, 1, 1)),
        GregDay(-1825, Date(-4, 1, 2)),
        GregDay(-1462, Date(-4, 12, 30)),
        GregDay(-1461, Date(-4, 12, 31)),
        GregDay(-1460, Date(-3, 1, 1)),
        GregDay(-1096, Date(-3, 12, 31)),
        GregDay(-1095, Date(-2, 1, 1)),
        GregDay(-731, Date(-2, 12, 31)),
        GregDay(-730, Date(-1, 1, 1)),
        GregDay(-367, Date(-1, 12, 30)),
        GregDay(-366, Date(-1, 12, 31)),
        GregDay(-365, Date(0, 1, 1)),
        GregDay(-31, Date(0, 11, 30)),
        GregDay(-30, Date(0, 12, 1)),
        GregDay(-1, Date(0, 12, 30)),
        GregDay(0, Date(0, 12, 31))
    ];

    auto testGregDaysAD = [
        GregDay(1, Date(1, 1, 1)),
        GregDay(2, Date(1, 1, 2)),
        GregDay(32, Date(1, 2, 1)),
        GregDay(365, Date(1, 12, 31)),
        GregDay(366, Date(2, 1, 1)),
        GregDay(731, Date(3, 1, 1)),
        GregDay(1096, Date(4, 1, 1)),
        GregDay(1097, Date(4, 1, 2)),
        GregDay(1460, Date(4, 12, 30)),
        GregDay(1461, Date(4, 12, 31)),
        GregDay(1462, Date(5, 1, 1)),
        GregDay(17_898, Date(50, 1, 1)),
        GregDay(35_065, Date(97, 1, 1)),
        GregDay(36_160, Date(100, 1, 1)),
        GregDay(36_525, Date(101, 1, 1)),
        GregDay(37_986, Date(105, 1, 1)),
        GregDay(72_684, Date(200, 1, 1)),
        GregDay(73_049, Date(201, 1, 1)),
        GregDay(109_208, Date(300, 1, 1)),
        GregDay(109_573, Date(301, 1, 1)),
        GregDay(145_732, Date(400, 1, 1)),
        GregDay(146_098, Date(401, 1, 1)),
        GregDay(182_257, Date(500, 1, 1)),
        GregDay(182_622, Date(501, 1, 1)),
        GregDay(364_878, Date(1000, 1, 1)),
        GregDay(365_243, Date(1001, 1, 1)),
        GregDay(584_023, Date(1600, 1, 1)),
        GregDay(584_389, Date(1601, 1, 1)),
        GregDay(693_596, Date(1900, 1, 1)),
        GregDay(693_961, Date(1901, 1, 1)),
        GregDay(729_755, Date(1999, 1, 1)),
        GregDay(730_120, Date(2000, 1, 1)),
        GregDay(730_121, Date(2000, 1, 2)),
        GregDay(730_484, Date(2000, 12, 30)),
        GregDay(730_485, Date(2000, 12, 31)),
        GregDay(730_486, Date(2001, 1, 1)),
        GregDay(733_773, Date(2010, 1, 1)),
        GregDay(733_774, Date(2010, 1, 2)),
        GregDay(733_803, Date(2010, 1, 31)),
        GregDay(733_804, Date(2010, 2, 1)),
        GregDay(733_831, Date(2010, 2, 28)),
        GregDay(733_832, Date(2010, 3, 1)),
        GregDay(733_862, Date(2010, 3, 31)),
        GregDay(733_863, Date(2010, 4, 1)),
        GregDay(733_892, Date(2010, 4, 30)),
        GregDay(733_893, Date(2010, 5, 1)),
        GregDay(733_923, Date(2010, 5, 31)),
        GregDay(733_924, Date(2010, 6, 1)),
        GregDay(733_953, Date(2010, 6, 30)),
        GregDay(733_954, Date(2010, 7, 1)),
        GregDay(733_984, Date(2010, 7, 31)),
        GregDay(733_985, Date(2010, 8, 1)),
        GregDay(734_015, Date(2010, 8, 31)),
        GregDay(734_016, Date(2010, 9, 1)),
        GregDay(734_045, Date(2010, 9, 30)),
        GregDay(734_046, Date(2010, 10, 1)),
        GregDay(734_076, Date(2010, 10, 31)),
        GregDay(734_077, Date(2010, 11, 1)),
        GregDay(734_106, Date(2010, 11, 30)),
        GregDay(734_107, Date(2010, 12, 1)),
        GregDay(734_136, Date(2010, 12, 30)),
        GregDay(734_137, Date(2010, 12, 31)),
        GregDay(734_503, Date(2012, 1, 1)),
        GregDay(734_534, Date(2012, 2, 1)),
        GregDay(734_561, Date(2012, 2, 28)),
        GregDay(734_562, Date(2012, 2, 29)),
        GregDay(734_563, Date(2012, 3, 1)),
        GregDay(734_858, Date(2012, 12, 21))
    ];

    //I'd use a Tuple, but I get forward reference errors if I try.
    struct DayOfYear { int day; MonthDay md; }
    auto testDaysOfYear = [
        DayOfYear(  1, MonthDay( 1,  1)),
        DayOfYear(  2, MonthDay( 1,  2)),
        DayOfYear(  3, MonthDay( 1,  3)),
        DayOfYear( 31, MonthDay( 1, 31)),
        DayOfYear( 32, MonthDay( 2,  1)),
        DayOfYear( 59, MonthDay( 2, 28)),
        DayOfYear( 60, MonthDay( 3,  1)),
        DayOfYear( 90, MonthDay( 3, 31)),
        DayOfYear( 91, MonthDay( 4,  1)),
        DayOfYear(120, MonthDay( 4, 30)),
        DayOfYear(121, MonthDay( 5,  1)),
        DayOfYear(151, MonthDay( 5, 31)),
        DayOfYear(152, MonthDay( 6,  1)),
        DayOfYear(181, MonthDay( 6, 30)),
        DayOfYear(182, MonthDay( 7,  1)),
        DayOfYear(212, MonthDay( 7, 31)),
        DayOfYear(213, MonthDay( 8,  1)),
        DayOfYear(243, MonthDay( 8, 31)),
        DayOfYear(244, MonthDay( 9,  1)),
        DayOfYear(273, MonthDay( 9, 30)),
        DayOfYear(274, MonthDay(10,  1)),
        DayOfYear(304, MonthDay(10, 31)),
        DayOfYear(305, MonthDay(11,  1)),
        DayOfYear(334, MonthDay(11, 30)),
        DayOfYear(335, MonthDay(12,  1)),
        DayOfYear(363, MonthDay(12, 29)),
        DayOfYear(364, MonthDay(12, 30)),
        DayOfYear(365, MonthDay(12, 31))
    ];

    auto testDaysOfLeapYear = [DayOfYear(1, MonthDay(1, 1)),
                               DayOfYear(2, MonthDay(1, 2)),
                               DayOfYear(3, MonthDay(1, 3)),
                               DayOfYear(31, MonthDay(1, 31)),
                               DayOfYear(32, MonthDay(2, 1)),
                               DayOfYear(59, MonthDay(2, 28)),
                               DayOfYear(60, MonthDay(2, 29)),
                               DayOfYear(61, MonthDay(3, 1)),
                               DayOfYear(91, MonthDay(3, 31)),
                               DayOfYear(92, MonthDay(4, 1)),
                               DayOfYear(121, MonthDay(4, 30)),
                               DayOfYear(122, MonthDay(5, 1)),
                               DayOfYear(152, MonthDay(5, 31)),
                               DayOfYear(153, MonthDay(6, 1)),
                               DayOfYear(182, MonthDay(6, 30)),
                               DayOfYear(183, MonthDay(7, 1)),
                               DayOfYear(213, MonthDay(7, 31)),
                               DayOfYear(214, MonthDay(8, 1)),
                               DayOfYear(244, MonthDay(8, 31)),
                               DayOfYear(245, MonthDay(9, 1)),
                               DayOfYear(274, MonthDay(9, 30)),
                               DayOfYear(275, MonthDay(10, 1)),
                               DayOfYear(305, MonthDay(10, 31)),
                               DayOfYear(306, MonthDay(11, 1)),
                               DayOfYear(335, MonthDay(11, 30)),
                               DayOfYear(336, MonthDay(12, 1)),
                               DayOfYear(364, MonthDay(12, 29)),
                               DayOfYear(365, MonthDay(12, 30)),
                               DayOfYear(366, MonthDay(12, 31))];

    void initializeTests()
    {
        immutable lt = LocalTime().utcToTZ(0);
        currLocalDiffFromUTC = dur!"hnsecs"(lt);

        immutable otherTZ = lt < 0 ? TimeZone.getTimeZone("Australia/Sydney")
                                   : TimeZone.getTimeZone("America/Denver");
        immutable ot = otherTZ.utcToTZ(0);

        auto diffs = [0L, lt, ot];
        auto diffAA = [0L : Rebindable!(immutable TimeZone)(UTC())];
        diffAA[lt] = Rebindable!(immutable TimeZone)(LocalTime());
        diffAA[ot] = Rebindable!(immutable TimeZone)(otherTZ);

        sort(diffs);
        testTZs = [diffAA[diffs[0]], diffAA[diffs[1]], diffAA[diffs[2]]];

        testFracSecs = [Duration.zero, hnsecs(1), hnsecs(5007), hnsecs(9999999)];

        foreach (year; testYearsBC)
        {
            foreach (md; testMonthDays)
                testDatesBC ~= Date(year, md.month, md.day);
        }

        foreach (year; testYearsAD)
        {
            foreach (md; testMonthDays)
                testDatesAD ~= Date(year, md.month, md.day);
        }

        foreach (dt; testDatesBC)
        {
            foreach (tod; testTODs)
                testDateTimesBC ~= DateTime(dt, tod);
        }

        foreach (dt; testDatesAD)
        {
            foreach (tod; testTODs)
                testDateTimesAD ~= DateTime(dt, tod);
        }

        foreach (dt; testDateTimesBC)
        {
            foreach (tz; testTZs)
            {
                foreach (fs; testFracSecs)
                    testSysTimesBC ~= SysTime(dt, fs, tz);
            }
        }

        foreach (dt; testDateTimesAD)
        {
            foreach (tz; testTZs)
            {
                foreach (fs; testFracSecs)
                    testSysTimesAD ~= SysTime(dt, fs, tz);
            }
        }
    }
}
