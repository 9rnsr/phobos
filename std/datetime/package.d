//Written in the D programming language

/++
    Module containing Date/Time functionality.

    This module provides:
    $(UL
        $(LI Types to represent points in time: $(LREF SysTime), $(LREF Date),
             $(LREF TimeOfDay), and $(LREF2 .DateTime, DateTime).)
        $(LI Types to represent intervals of time.)
        $(LI Types to represent ranges over intervals of time.)
        $(LI Types to represent time zones (used by $(LREF SysTime)).)
        $(LI A platform-independent, high precision stopwatch type:
             $(LREF StopWatch))
        $(LI Benchmarking functions.)
        $(LI Various helper functions.)
    )

    Closely related to std.datetime is <a href="core_time.html">$(D core.time)</a>,
    and some of the time types used in std.datetime come from there - such as
    $(CXREF time, Duration), $(CXREF time, TickDuration), and
    $(CXREF time, FracSec).
    core.time is publically imported into std.datetime, it isn't necessary
    to import it separately.

    Three of the main concepts used in this module are time points, time
    durations, and time intervals.

    A time point is a specific point in time. e.g. January 5th, 2010
    or 5:00.

    A time duration is a length of time with units. e.g. 5 days or 231 seconds.

    A time interval indicates a period of time associated with a fixed point in
    time. It is either two time points associated with each other,
    indicating the time starting at the first point up to, but not including,
    the second point - e.g. [January 5th, 2010 - March 10th, 2010$(RPAREN) - or
    it is a time point and a time duration associated with one another. e.g.
    January 5th, 2010 and 5 days, indicating [January 5th, 2010 -
    January 10th, 2010$(RPAREN).

    Various arithmetic operations are supported between time points and
    durations (e.g. the difference between two time points is a time duration),
    and ranges can be gotten from time intervals, so range-based operations may
    be done on a series of time points.

    The types that the typical user is most likely to be interested in are
    $(LREF Date) (if they want dates but don't care about time), $(LREF DateTime)
    (if they want dates and times but don't care about time zones), $(LREF SysTime)
    (if they want the date and time from the OS and/or do care about time
    zones), and StopWatch (a platform-independent, high precision stop watch).
    $(LREF Date) and $(LREF DateTime) are optimized for calendar-based operations,
    while $(LREF SysTime) is designed for dealing with time from the OS. Check out
    their specific documentation for more details.

    To get the current time, use $(LREF2 .Clock.currTime, Clock.currTime).
    It will return the current
    time as a $(LREF SysTime). To print it, $(D toString) is
    sufficient, but if using $(D toISOString), $(D toISOExtString), or
    $(D toSimpleString), use the corresponding $(D fromISOString),
    $(D fromISOExtString), or $(D fromSimpleString) to create a
    $(LREF SysTime) from the string.

    --------------------
    auto currentTime = Clock.currTime();
    auto timeString = currentTime.toISOExtString();
    auto restoredTime = SysTime.fromISOExtString(timeString);
    --------------------

    Various functions take a string (or strings) to represent a unit of time
    (e.g. $(D convert!("days", "hours")(numDays))). The valid strings to use
    with such functions are $(D "years"), $(D "months"), $(D "weeks"),
    $(D "days"), $(D "hours"), $(D "minutes"), $(D "seconds"),
    $(D "msecs") (milliseconds), $(D "usecs") (microseconds),
    $(D "hnsecs") (hecto-nanoseconds - i.e. 100 ns), or some subset thereof.
    There are a few functions in core.time which take $(D "nsecs"), but because
    nothing in std.datetime has precision greater than hnsecs, and very little
    in core.time does, no functions in std.datetime accept $(D "nsecs").
    To remember which units are abbreviated and which aren't,
    all units seconds and greater use their full names, and all
    sub-second units are abbreviated (since they'd be rather long if they
    weren't).

    Note:
        $(LREF DateTimeException) is an alias for $(CXREF time, TimeException),
        so you don't need to worry about core.time functions and std.datetime
        functions throwing different exception types (except in the rare case
        that they throw something other than $(CXREF time, TimeException) or
        $(LREF DateTimeException)).

    See_Also:
        <a href="../intro-to-datetime.html">Introduction to std&#46;_datetime </a><br>
        $(WEB en.wikipedia.org/wiki/ISO_8601, ISO 8601)<br>
        $(WEB en.wikipedia.org/wiki/Tz_database,
              Wikipedia entry on TZ Database)<br>
        $(WEB en.wikipedia.org/wiki/List_of_tz_database_time_zones,
              List of Time Zones)<br>

    Copyright: Copyright 2010 - 2011
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis and Kato Shoichi
    Source:    $(PHOBOSSRC std/_datetime.d)
    Macros:
        LREF2=<a href="#$1">$(D $2)</a>
+/
module std.datetime;

public import core.time;

//import core.exception;
import core.stdc.time;

import std.exception;
import std.range.primitives;
import std.traits;
// FIXME
import std.functional; //: unaryFun;

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

version(unittest)
{
    import std.stdio;
}

// Verify module example.
unittest
{
    auto currentTime = Clock.currTime();
    auto timeString = currentTime.toISOExtString();
    auto restoredTime = SysTime.fromISOExtString(timeString);
}

// Verify Examples for core.time.Duration which couldn't be in core.time.
unittest
{
    assert(std.datetime.Date(2010, 9, 7) + dur!"days"(5) ==
           std.datetime.Date(2010, 9, 12));

    assert(std.datetime.Date(2010, 9, 7) - std.datetime.Date(2010, 10, 3) ==
           dur!"days"(-26));
}


//==============================================================================
// Section with public enums and constants.
//==============================================================================

/++
    Represents the 12 months of the Gregorian year (January is 1).
  +/
enum Month : ubyte
{
    jan = 1, ///
    feb,     ///
    mar,     ///
    apr,     ///
    may,     ///
    jun,     ///
    jul,     ///
    aug,     ///
    sep,     ///
    oct,     ///
    nov,     ///
    dec      ///
}

/++
    Represents the 7 days of the Gregorian week (Sunday is 0).
  +/
enum DayOfWeek : ubyte
{
    sun = 0, ///
    mon,     ///
    tue,     ///
    wed,     ///
    thu,     ///
    fri,     ///
    sat      ///
}

/++
    In some date calculations, adding months or years can cause the date to fall
    on a day of the month which is not valid (e.g. February 29th 2001 or
    June 31st 2000). If overflow is allowed (as is the default), then the month
    will be incremented accordingly (so, February 29th 2001 would become
    March 1st 2001, and June 31st 2000 would become July 1st 2000). If overflow
    is not allowed, then the day will be adjusted to the last valid day in that
    month (so, February 29th 2001 would become February 28th 2001 and
    June 31st 2000 would become June 30th 2000).

    AllowDayOverflow only applies to calculations involving months or years.
  +/
enum AllowDayOverflow
{
    no,     /// No, don't allow day overflow.
    yes     /// Yes, allow day overflow.
}

/++
    Indicates a direction in time. One example of its use is $(LREF2 .Interval, Interval)'s
    $(LREF expand, expand) function which uses it to indicate whether the interval should
    be expanded backwards (into the past), forwards (into the future), or both.
  +/
enum Direction
{
    bwd,    /// Backward.
    fwd,    /// Forward.
    both    /// Both backward and forward.
}

/++
    Used to indicate whether $(D popFront) should be called immediately upon
    creating a range. The idea is that for some functions used to generate a
    range for an interval, $(D front) is not necessarily a time point which
    would ever be generated by the range. To get the first time point
    in the range to match what the function generates, then use
    $(D PopFirst.yes) to indicate that the range should have $(D popFront)
    called on it before the range is returned so that $(D front) is a time point
    which the function would generate.

    For instance, if the function used to generate a range of time points
    generated successive Easters (i.e. you're iterating over all of the Easters
    within the interval), the initial date probably isn't an Easter. Using
    $(D PopFirst.yes) would tell the function which returned the
    range that $(D popFront) was to be called so that front would then be
    an Easter - the next one generated by the function (which when
    iterating forward would be the Easter following the original $(D front),
    while when iterating backward, it would be the Easter prior to the
    original $(D front)). If $(D PopFirst.no) were used, then $(D front) would
    remain the original time point and it would not necessarily be a time point
    which would be generated by the range-generating function (which in many
    cases is exactly what is desired -
    e.g. if iterating over every day starting at the beginning
    of the interval).
  +/
enum PopFirst
{
    no,     /// No, don't call popFront() before returning the range.
    yes     /// Yes, call popFront() before returning the range.
}

/++
   Used by StopWatch to indicate whether it should start immediately upon
   construction.
  +/
enum AutoStart
{
    no,     /// No, don't start the StopWatch when it is constructed.
    yes     /// Yes, do start the StopWatch when it is constructed.
}

/++
    Array of the strings representing time units, starting with the smallest
    unit and going to the largest. It does not include $(D "nsecs").

   Includes $(D "hnsecs") (hecto-nanoseconds (100 ns)),
   $(D "usecs") (microseconds), $(D "msecs") (milliseconds), $(D "seconds"),
   $(D "minutes"), $(D "hours"), $(D "days"), $(D "weeks"), $(D "months"), and
   $(D "years")
  +/
immutable string[] timeStrings =
[
    "hnsecs", "usecs", "msecs", "seconds", "minutes",
    "hours", "days", "weeks", "months", "years"
];


//==============================================================================
// Section with other types.
//==============================================================================

/++
    Exception type used by std.datetime. It's an alias to $(CXREF time, TimeException).
    Either can be caught without concern about which
    module it came from.
  +/
alias DateTimeException = TimeException;

/++
    Effectively a namespace to make it clear that the methods it contains are
    getting the time from the system clock. It cannot be instantiated.
 +/
final class Clock
{
public:

    /++
        Returns the current time in the given time zone.

        Throws:
            $(XREF exception, ErrnoException) (on Posix) or $(XREF exception, Exception) (on Windows)
            if it fails to get the time of day.
      +/
    static SysTime currTime(immutable TimeZone tz = LocalTime()) @safe
    {
        return SysTime(currStdTime, tz);
    }

    unittest
    {
        assert(currTime(UTC()).timezone is UTC());

        // I have no idea why, but for some reason, Windows/Wine likes to get
        // time_t wrong when getting it with core.stdc.time.time. On one box
        // I have (which has its local time set to UTC), it always gives time_t
        // in the real local time (America/Los_Angeles), and after the most recent
        // DST switch, every Windows box that I've tried it in is reporting
        // time_t as being 1 hour off of where it's supposed to be. So, I really
        // don't know what the deal is, but given what I'm seeing, I don't trust
        // core.stdc.time.time on Windows, so I'm just going to disable this test
        // on Windows.
        version(Posix)
        {
            immutable unixTimeD = currTime().toUnixTime();
            immutable unixTimeC = core.stdc.time.time(null);
            immutable diff = unixTimeC - unixTimeD;

            assert(diff >= -2);
            assert(diff <= 2);
        }
    }

    /++
        Returns the number of hnsecs since midnight, January 1st, 1 A.D. for the
        current time.

        Throws:
            $(LREF DateTimeException) if it fails to get the time.
      +/
    static @property long currStdTime() @trusted
    {
        version(Windows)
        {
            FILETIME fileTime;
            GetSystemTimeAsFileTime(&fileTime);

            return FILETIMEToStdTime(&fileTime);
        }
        else version(Posix)
        {
            enum hnsecsToUnixEpoch = 621_355_968_000_000_000L;

            static if (is(typeof(clock_gettime)))
            {
                timespec ts;

                if (clock_gettime(CLOCK_REALTIME, &ts) != 0)
                    throw new TimeException("Failed in clock_gettime().");

                return convert!("seconds", "hnsecs")(ts.tv_sec) +
                       ts.tv_nsec / 100 +
                       hnsecsToUnixEpoch;
            }
            else
            {
                timeval tv;

                if (gettimeofday(&tv, null) != 0)
                    throw new TimeException("Failed in gettimeofday().");

                return convert!("seconds", "hnsecs")(tv.tv_sec) +
                       convert!("usecs", "hnsecs")(tv.tv_usec) +
                       hnsecsToUnixEpoch;
            }
        }
    }

    /++
        The current system tick. The number of ticks per second varies from
        system to system. currSystemTick uses a monotonic clock, so it's
        intended for precision timing by comparing relative time values, not
        for getting the current system time.

        Warning:
            On some systems, the monotonic clock may stop counting when
            the computer goes to sleep or hibernates. So, the monotonic
            clock could be off if that occurs. This is known to happen
            on Mac OS X. It has not been tested whether it occurs on
            either Windows or Linux.

        Throws:
            $(LREF DateTimeException) if it fails to get the time.
      +/
    static @property TickDuration currSystemTick() @safe nothrow
    {
        return TickDuration.currSystemTick;
    }

    unittest
    {
        assert(Clock.currSystemTick.length > 0);
    }

    /++
        The current number of system ticks since the application started.
        The number of ticks per second varies from system to system.
        This uses a monotonic clock.

        Warning:
            On some systems, the monotonic clock may stop counting when
            the computer goes to sleep or hibernates. So, the monotonic
            clock could be off if that occurs. This is known to happen
            on Mac OS X. It has not been tested whether it occurs on
            either Windows or on Linux.

        Throws:
            $(LREF DateTimeException) if it fails to get the time.
      +/
    static @property TickDuration currAppTick() @safe
    {
        return currSystemTick - TickDuration.appOrigin;
    }

    unittest
    {
        auto a = Clock.currSystemTick;
        auto b = Clock.currAppTick;
        assert(a.length);
        assert(b.length);
        assert(a > b);
    }

private:

    @disable this() {}
}

//==============================================================================
// Section with time points.
//==============================================================================

public import std.datetime.timepoint;

//==============================================================================
// Section with intervals.
//==============================================================================

public import std.datetime.interval;

//==============================================================================
// Section with time zones.
//==============================================================================

public import std.datetime.timezone;

//==============================================================================
// Section with StopWatch and Benchmark Code.
//==============================================================================

public import std.datetime.util;

//==============================================================================
// Section with public helper functions and templates.
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

unittest
{
    import std.typetuple : TypeTuple;

    foreach (T; TypeTuple!(
                    Date,       const Date,         immutable Date,
                    DateTime,   const DateTime,     immutable DateTime,
                    TimeOfDay,  const TimeOfDay,    immutable TimeOfDay,
                    SysTime,    const SysTime,      immutable SysTime))
    {
        static assert(isTimePoint!T);
    }
}

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

/++
    Converts a $(D time_t) (which uses midnight, January 1st, 1970 UTC as its
    epoch and seconds as its units) to std time (which uses midnight,
    January 1st, 1 A.D. UTC and hnsecs as its units).

    Params:
        unixTime = The $(D time_t) to convert.
  +/
long unixTimeToStdTime(time_t unixTime) @safe pure nothrow
{
    return 621_355_968_000_000_000L + convert!("seconds", "hnsecs")(unixTime);

}

unittest
{
    assert(unixTimeToStdTime(      0) == 621_355_968_000_000_000L);                     // Midnight, January 1st, 1970
    assert(unixTimeToStdTime(+86_400) == 621_355_968_000_000_000L + 864_000_000_000L);  // Midnight, January 2nd, 1970
    assert(unixTimeToStdTime(-86_400) == 621_355_968_000_000_000L - 864_000_000_000L);  // Midnight, December 31st, 1969

    assert(unixTimeToStdTime(0) == (Date(1970, 1, 1) - Date(1, 1, 1)).total!"hnsecs");
    assert(unixTimeToStdTime(0) == (DateTime(1970, 1, 1) - DateTime(1, 1, 1)).total!"hnsecs");
}


/++
    Converts std time (which uses midnight, January 1st, 1 A.D. UTC as its epoch
    and hnsecs as its units) to $(D time_t) (which uses midnight, January 1st,
    1970 UTC as its epoch and seconds as its units). If $(D time_t) is 32 bits,
    rather than 64, and the result can't fit in a 32-bit value, then the closest
    value that can be held in 32 bits will be used (so $(D time_t.max) if it
    goes over and $(D time_t.min) if it goes under).

    Note:
        While Windows systems require that $(D time_t) be non-negative (in spite
        of $(D time_t) being signed), this function still returns negative
        numbers on Windows, since it's more flexible to allow negative time_t
        for those who need it. If on Windows and using the
        standard C functions or Win32 API functions which take a $(D time_t),
        check whether the return value of
        $(D stdTimeToUnixTime) is non-negative.

    Params:
        stdTime = The std time to convert.
  +/
time_t stdTimeToUnixTime(long stdTime) @safe pure nothrow
{
    immutable unixTime = convert!("hnsecs", "seconds")(stdTime - 621_355_968_000_000_000L);

    static if (time_t.sizeof >= long.sizeof)
        return cast(time_t)unixTime;
    else
    {
        if (unixTime > 0)
        {
            if (unixTime > time_t.max)
                return time_t.max;
            return cast(time_t)unixTime;
        }

        if (unixTime < time_t.min)
            return time_t.min;

        return cast(time_t)unixTime;
    }
}

unittest
{
    assert(stdTimeToUnixTime(621_355_968_000_000_000L                   ) ==       0);  // Midnight, January 1st, 1970
    assert(stdTimeToUnixTime(621_355_968_000_000_000L + 864_000_000_000L) == +86_400);  // Midnight, January 2nd, 1970
    assert(stdTimeToUnixTime(621_355_968_000_000_000L - 864_000_000_000L) == -86_400);  // Midnight, December 31st, 1969

    assert(stdTimeToUnixTime((Date(1970, 1, 1) - Date(1, 1, 1)).total!"hnsecs") == 0);
    assert(stdTimeToUnixTime((DateTime(1970, 1, 1) - DateTime(1, 1, 1)).total!"hnsecs") == 0);
}


version(StdDdoc)
{
    version(Windows) {}
    else
    {
        alias SYSTEMTIME = void*;
        alias FILETIME = void*;
    }

    /++
        $(BLUE This function is Windows-Only.)

        Converts a $(D SYSTEMTIME) struct to a $(LREF SysTime).

        Params:
            st = The $(D SYSTEMTIME) struct to convert.
            tz = The time zone that the time in the $(D SYSTEMTIME) struct is
                 assumed to be (if the $(D SYSTEMTIME) was supplied by a Windows
                 system call, the $(D SYSTEMTIME) will either be in local time
                 or UTC, depending on the call).

        Throws:
            $(LREF DateTimeException) if the given $(D SYSTEMTIME) will not fit in
            a $(LREF SysTime), which is highly unlikely to happen given that
            $(D SysTime.max) is in 29,228 A.D. and the maximum $(D SYSTEMTIME)
            is in 30,827 A.D.
      +/
    SysTime SYSTEMTIMEToSysTime(const SYSTEMTIME* st, immutable TimeZone tz = LocalTime()) @safe;


    /++
        $(BLUE This function is Windows-Only.)

        Converts a $(LREF SysTime) to a $(D SYSTEMTIME) struct.

        The $(D SYSTEMTIME) which is returned will be set using the given
        $(LREF SysTime)'s time zone, so to get the $(D SYSTEMTIME) in
        UTC, set the $(LREF SysTime)'s time zone to UTC.

        Params:
            sysTime = The $(LREF SysTime) to convert.

        Throws:
            $(LREF DateTimeException) if the given $(LREF SysTime) will not fit in a
            $(D SYSTEMTIME). This will only happen if the $(LREF SysTime)'s date is
            prior to 1601 A.D.
      +/
    SYSTEMTIME SysTimeToSYSTEMTIME(in SysTime sysTime) @safe;


    /++
        $(BLUE This function is Windows-Only.)

        Converts a $(D FILETIME) struct to the number of hnsecs since midnight,
        January 1st, 1 A.D.

        Params:
            ft = The $(D FILETIME) struct to convert.

        Throws:
            $(LREF DateTimeException) if the given $(D FILETIME) cannot be
            represented as the return value.
      +/
    long FILETIMEToStdTime(const FILETIME* ft) @safe;


    /++
        $(BLUE This function is Windows-Only.)

        Converts a $(D FILETIME) struct to a $(LREF SysTime).

        Params:
            ft = The $(D FILETIME) struct to convert.
            tz = The time zone that the $(LREF SysTime) will be in ($(D FILETIME)s
                 are in UTC).

        Throws:
            $(LREF DateTimeException) if the given $(D FILETIME) will not fit in a
            $(LREF SysTime).
      +/
    SysTime FILETIMEToSysTime(const FILETIME* ft, immutable TimeZone tz = LocalTime()) @safe;


    /++
        $(BLUE This function is Windows-Only.)

        Converts a number of hnsecs since midnight, January 1st, 1 A.D. to a
        $(D FILETIME) struct.

        Params:
            stdTime = The number of hnsecs since midnight, January 1st, 1 A.D. UTC.

        Throws:
            $(LREF DateTimeException) if the given value will not fit in a
            $(D FILETIME).
      +/
    FILETIME stdTimeToFILETIME(long stdTime) @safe;


    /++
        $(BLUE This function is Windows-Only.)

        Converts a $(LREF SysTime) to a $(D FILETIME) struct.

        $(D FILETIME)s are always in UTC.

        Params:
            sysTime = The $(LREF SysTime) to convert.

        Throws:
            $(LREF DateTimeException) if the given $(LREF SysTime) will not fit in a
            $(D FILETIME).
      +/
    FILETIME SysTimeToFILETIME(SysTime sysTime) @safe;
}
else version(Windows)
{
    SysTime SYSTEMTIMEToSysTime(const SYSTEMTIME* st, immutable TimeZone tz = LocalTime()) @safe
    {
        const max = SysTime.max;

        static void throwLaterThanMax()
        {
            throw new DateTimeException("The given SYSTEMTIME is for a date greater than SysTime.max.");
        }

        if (st.wYear > max.year)
            throwLaterThanMax();
        else if (st.wYear == max.year)
        {
            if (st.wMonth > max.month)
                throwLaterThanMax();
            else if (st.wMonth == max.month)
            {
                if (st.wDay > max.day)
                    throwLaterThanMax();
                else if (st.wDay == max.day)
                {
                    if (st.wHour > max.hour)
                        throwLaterThanMax();
                    else if (st.wHour == max.hour)
                    {
                        if (st.wMinute > max.minute)
                            throwLaterThanMax();
                        else if (st.wMinute == max.minute)
                        {
                            if (st.wSecond > max.second)
                                throwLaterThanMax();
                            else if (st.wSecond == max.second)
                            {
                                if (st.wMilliseconds > max.fracSecs.total!"msecs")
                                    throwLaterThanMax();
                            }
                        }
                    }
                }
            }
        }

        auto dt = DateTime(st.wYear, st.wMonth, st.wDay,
                           st.wHour, st.wMinute, st.wSecond);

        return SysTime(dt, msecs(st.wMilliseconds), tz);
    }

    unittest
    {
        auto sysTime = Clock.currTime(UTC());
        SYSTEMTIME st = void;
        GetSystemTime(&st);
        auto converted = SYSTEMTIMEToSysTime(&st, UTC());

        assert(abs((converted - sysTime)) <= dur!"seconds"(2));
    }


    SYSTEMTIME SysTimeToSYSTEMTIME(in SysTime sysTime) @safe
    {
        immutable dt = cast(DateTime)sysTime;

        if (dt.year < 1601)
            throw new DateTimeException("SYSTEMTIME cannot hold dates prior to the year 1601.");

        SYSTEMTIME st;

        st.wYear = dt.year;
        st.wMonth = dt.month;
        st.wDayOfWeek = dt.dayOfWeek;
        st.wDay = dt.day;
        st.wHour = dt.hour;
        st.wMinute = dt.minute;
        st.wSecond = dt.second;
        st.wMilliseconds = cast(ushort)sysTime.fracSecs.total!"msecs";

        return st;
    }

    unittest
    {
        SYSTEMTIME st = void;
        GetSystemTime(&st);
        auto sysTime = SYSTEMTIMEToSysTime(&st, UTC());

        SYSTEMTIME result = SysTimeToSYSTEMTIME(sysTime);

        assert(st.wYear == result.wYear);
        assert(st.wMonth == result.wMonth);
        assert(st.wDayOfWeek == result.wDayOfWeek);
        assert(st.wDay == result.wDay);
        assert(st.wHour == result.wHour);
        assert(st.wMinute == result.wMinute);
        assert(st.wSecond == result.wSecond);
        assert(st.wMilliseconds == result.wMilliseconds);
    }

    private enum hnsecsFrom1601 = 504_911_232_000_000_000L;

    long FILETIMEToStdTime(const FILETIME* ft) @safe
    {
        ULARGE_INTEGER ul;
        ul.HighPart = ft.dwHighDateTime;
        ul.LowPart = ft.dwLowDateTime;
        ulong tempHNSecs = ul.QuadPart;

        if (tempHNSecs > long.max - hnsecsFrom1601)
            throw new DateTimeException("The given FILETIME cannot be represented as a stdTime value.");

        return cast(long)tempHNSecs + hnsecsFrom1601;
    }

    SysTime FILETIMEToSysTime(const FILETIME* ft, immutable TimeZone tz = LocalTime()) @safe
    {
        auto sysTime = SysTime(FILETIMEToStdTime(ft), UTC());
        sysTime.timezone = tz;

        return sysTime;
    }

    unittest
    {
        auto sysTime = Clock.currTime(UTC());
        SYSTEMTIME st = void;
        GetSystemTime(&st);

        FILETIME ft = void;
        SystemTimeToFileTime(&st, &ft);

        auto converted = FILETIMEToSysTime(&ft);

        assert(abs((converted - sysTime)) <= dur!"seconds"(2));
    }


    FILETIME stdTimeToFILETIME(long stdTime) @safe
    {
        if (stdTime < hnsecsFrom1601)
            throw new DateTimeException("The given stdTime value cannot be represented as a FILETIME.");

        ULARGE_INTEGER ul;
        ul.QuadPart = cast(ulong)stdTime - hnsecsFrom1601;

        FILETIME ft;
        ft.dwHighDateTime = ul.HighPart;
        ft.dwLowDateTime = ul.LowPart;

        return ft;
    }

    FILETIME SysTimeToFILETIME(SysTime sysTime) @safe
    {
        return stdTimeToFILETIME(sysTime.stdTime);
    }

    unittest
    {
        SYSTEMTIME st = void;
        GetSystemTime(&st);

        FILETIME ft = void;
        SystemTimeToFileTime(&st, &ft);
        auto sysTime = FILETIMEToSysTime(&ft, UTC());

        FILETIME result = SysTimeToFILETIME(sysTime);

        assert(ft.dwLowDateTime == result.dwLowDateTime);
        assert(ft.dwHighDateTime == result.dwHighDateTime);
    }
}


/++
    Type representing the DOS file date/time format.
  +/
alias DosFileTime = uint;

/++
    Converts from DOS file date/time to $(LREF SysTime).

    Params:
        dft = The DOS file time to convert.
        tz  = The time zone which the DOS file time is assumed to be in.

    Throws:
        $(LREF DateTimeException) if the $(D DosFileTime) is invalid.
  +/
SysTime DosFileTimeToSysTime(DosFileTime dft, immutable TimeZone tz = LocalTime()) @safe
{
    uint dt = cast(uint)dft;

    if (dt == 0)
        throw new DateTimeException("Invalid DosFileTime.");

    int year = ((dt >> 25) & 0x7F) + 1980;
    int month = ((dt >> 21) & 0x0F);       // 1..12
    int dayOfMonth = ((dt >> 16) & 0x1F);  // 1..31
    int hour = (dt >> 11) & 0x1F;          // 0..23
    int minute = (dt >> 5) & 0x3F;         // 0..59
    int second = (dt << 1) & 0x3E;         // 0..58 (in 2 second increments)

    try
        return SysTime(DateTime(year, month, dayOfMonth, hour, minute, second), tz);
    catch (DateTimeException dte)
        throw new DateTimeException("Invalid DosFileTime", __FILE__, __LINE__, dte);
}

unittest
{
    assert(DosFileTimeToSysTime(0b00000000001000010000000000000000) ==
                    SysTime(DateTime(1980, 1, 1, 0, 0, 0)));

    assert(DosFileTimeToSysTime(0b11111111100111111011111101111101) ==
                    SysTime(DateTime(2107, 12, 31, 23, 59, 58)));

    assert(DosFileTimeToSysTime(0x3E3F8456) ==
                    SysTime(DateTime(2011, 1, 31, 16, 34, 44)));
}


/++
    Converts from $(LREF SysTime) to DOS file date/time.

    Params:
        sysTime = The $(LREF SysTime) to convert.

    Throws:
        $(LREF DateTimeException) if the given $(LREF SysTime) cannot be converted to
        a $(D DosFileTime).
  +/
DosFileTime SysTimeToDosFileTime(SysTime sysTime) @safe
{
    auto dateTime = cast(DateTime)sysTime;

    if (dateTime.year < 1980)
        throw new DateTimeException("DOS File Times cannot hold dates prior to 1980.");

    if (dateTime.year > 2107)
        throw new DateTimeException("DOS File Times cannot hold dates past 2107.");

    uint retval = 0;
    retval = (dateTime.year - 1980) << 25;
    retval |= (dateTime.month & 0x0F) << 21;
    retval |= (dateTime.day & 0x1F) << 16;
    retval |= (dateTime.hour & 0x1F) << 11;
    retval |= (dateTime.minute & 0x3F) << 5;
    retval |= (dateTime.second >> 1) & 0x1F;

    return cast(DosFileTime)retval;
}

unittest
{
    assert(SysTimeToDosFileTime(SysTime(DateTime(1980, 1, 1, 0, 0, 0))) ==
                    0b00000000001000010000000000000000);

    assert(SysTimeToDosFileTime(SysTime(DateTime(2107, 12, 31, 23, 59, 58))) ==
                    0b11111111100111111011111101111101);

    assert(SysTimeToDosFileTime(SysTime(DateTime(2011, 1, 31, 16, 34, 44))) ==
                    0x3E3F8456);
}


/++
    The given array of $(D char) or random-access range of $(D char) or
    $(D ubyte) is expected to be in the format specified in
    $(WEB tools.ietf.org/html/rfc5322, RFC 5322) section 3.3 with the
    grammar rule $(I date-time). It is the date-time format commonly used in
    internet messages such as e-mail and HTTP. The corresponding
    $(LREF SysTime) will be returned.

    RFC 822 was the original spec (hence the function's name), whereas RFC 5322
    is the current spec.

    The day of the week is ignored beyond verifying that it's a valid day of the
    week, as the day of the week can be inferred from the date. It is not
    checked whether the given day of the week matches the actual day of the week
    of the given date (though it is technically invalid per the spec if the
    day of the week doesn't match the actual day of the week of the given date).

    If the time zone is $(D "-0000") (or considered to be equivalent to
    $(D "-0000") by section 4.3 of the spec), a $(LREF SimpleTimeZone) with a
    utc offset of $(D 0) is used rather than $(LREF UTC), whereas $(D "+0000")
    uses $(LREF UTC).

    Note that because $(LREF SysTime) does not currently support having a second
    value of 60 (as is sometimes done for leap seconds), if the date-time value
    does have a value of 60 for the seconds, it is treated as 59.

    The one area in which this function violates RFC 5322 is that it accepts
    $(D "\n") in folding whitespace in the place of $(D "\r\n"), because the
    HTTP spec requires it.

    Throws:
        $(LREF DateTimeException) if the given string doesn't follow the grammar
        for a date-time field or if the resulting $(LREF SysTime) is invalid.
  +/
SysTime parseRFC822DateTime()(in char[] value) @safe
{
    import std.string : representation;
    return parseRFC822DateTime(value.representation);
}

/++ Ditto +/
SysTime parseRFC822DateTime(R)(R value) @safe
    if (isRandomAccessRange!R && hasSlicing!R && hasLength!R &&
       (is(Unqual!(ElementType!R) == char) || is(Unqual!(ElementType!R) == ubyte)))
{
    import std.functional : not;
    import std.ascii : isDigit;
    import std.typecons : Rebindable;
    import std.string : capitalize, format;
    import std.conv : to;
    import std.algorithm : find, all;

    void stripAndCheckLen(R valueBefore, size_t minLen, size_t line = __LINE__)
    {
        value = _stripCFWS(valueBefore);
        if (value.length < minLen)
            throw new DateTimeException("date-time value too short", __FILE__, line);
    }
    stripAndCheckLen(value, "7Dec1200:00A".length);

    static if (isArray!R && (is(ElementEncodingType!R == char) || is(ElementEncodingType!R == ubyte)))
    {
        static string sliceAsString(R str) @trusted
        {
            return cast(string)str;
        }
    }
    else
    {
        char[4] temp;
        char[] sliceAsString(R str) @trusted
        {
            size_t i = 0;
            foreach (c; str)
                temp[i++] = cast(char)c;
            return temp[0 .. str.length];
        }
    }

    // day-of-week
    if (std.ascii.isAlpha(value[0]))
    {
        auto dowStr = sliceAsString(value[0 .. 3]);
        switch (dowStr)
        {
            foreach (dow; EnumMembers!DayOfWeek)
            {
                enum dowC = capitalize(to!string(dow));
                case dowC:
                    goto afterDoW;
            }
            default: throw new DateTimeException(format("Invalid day-of-week: %s", dowStr));
        }
afterDoW: stripAndCheckLen(value[3 .. value.length], ",7Dec1200:00A".length);
        if (value[0] != ',')
            throw new DateTimeException("day-of-week missing comma");
        stripAndCheckLen(value[1 .. value.length], "7Dec1200:00A".length);
    }

    // day
    immutable digits = std.ascii.isDigit(value[1]) ? 2 : 1;
    immutable day = _convDigits!short(value[0 .. digits]);
    if (day == -1)
        throw new DateTimeException("Invalid day");
    stripAndCheckLen(value[digits .. value.length], "Dec1200:00A".length);

    // month
    Month month;
    {
        auto monStr = sliceAsString(value[0 .. 3]);
        switch (monStr)
        {
            foreach (mon; EnumMembers!Month)
            {
                enum monC = capitalize(to!string(mon));
                case monC:
                {
                    month = mon;
                    goto afterMon;
                }
            }
            default: throw new DateTimeException(format("Invalid month: %s", monStr));
        }
    afterMon:
        stripAndCheckLen(value[3 .. value.length], "1200:00A".length);
    }

    // year
    auto found = value[2 .. value.length].find!(not!(std.ascii.isDigit))();
    size_t yearLen = value.length - found.length;
    if (found.length == 0)
        throw new DateTimeException("Invalid year");
    if (found[0] == ':')
        yearLen -= 2;
    auto year = _convDigits!short(value[0 .. yearLen]);
    if (year < 1900)
    {
        if (year == -1)
            throw new DateTimeException("Invalid year");
        if (yearLen < 4)
        {
            if (yearLen == 3)
                year += 1900;
            else if (yearLen == 2)
                year += year < 50 ? 2000 : 1900;
            else
                throw new DateTimeException("Invalid year. Too few digits.");
        }
        else
            throw new DateTimeException("Invalid year. Cannot be earlier than 1900.");
    }
    stripAndCheckLen(value[yearLen .. value.length], "00:00A".length);

    // hour
    immutable hour = _convDigits!short(value[0 .. 2]);
    stripAndCheckLen(value[2 .. value.length], ":00A".length);
    if (value[0] != ':')
        throw new DateTimeException("Invalid hour");
    stripAndCheckLen(value[1 .. value.length], "00A".length);

    // minute
    immutable minute = _convDigits!short(value[0 .. 2]);
    stripAndCheckLen(value[2 .. value.length], "A".length);

    // second
    short second;
    if (value[0] == ':')
    {
        stripAndCheckLen(value[1 .. value.length], "00A".length);
        second = _convDigits!short(value[0 .. 2]);
        // this is just if/until SysTime is sorted out to fully support leap seconds
        if (second == 60)
            second = 59;
        stripAndCheckLen(value[2 .. value.length], "A".length);
    }

    immutable(TimeZone) parseTZ(int sign)
    {
        if (value.length < 5)
            throw new DateTimeException("Invalid timezone");
        immutable zoneHours = _convDigits!short(value[1 .. 3]);
        immutable zoneMinutes = _convDigits!short(value[3 .. 5]);
        if (zoneHours == -1 || zoneMinutes == -1 || zoneMinutes > 59)
            throw new DateTimeException("Invalid timezone");
        value = value[5 .. value.length];
        immutable utcOffset = (dur!"hours"(zoneHours) + dur!"minutes"(zoneMinutes)) * sign;
        if (utcOffset == Duration.zero)
        {
            return sign == 1 ? cast(immutable(TimeZone))UTC()
                             : cast(immutable(TimeZone))new immutable SimpleTimeZone(Duration.zero);
        }
        return new immutable(SimpleTimeZone)(utcOffset);
    }

    // zone
    Rebindable!(immutable TimeZone) tz;
    if (value[0] == '-')
        tz = parseTZ(-1);
    else if (value[0] == '+')
        tz = parseTZ(1);
    else
    {
        // obs-zone
        immutable tzLen = value.length - find(value, ' ', '\t', '(')[0].length;
        switch (sliceAsString(value[0 .. tzLen <= 4 ? tzLen : 4]))
        {
            case "UT": case "GMT": tz = UTC(); break;
            case "EST": tz = new immutable SimpleTimeZone(dur!"hours"(-5)); break;
            case "EDT": tz = new immutable SimpleTimeZone(dur!"hours"(-4)); break;
            case "CST": tz = new immutable SimpleTimeZone(dur!"hours"(-6)); break;
            case "CDT": tz = new immutable SimpleTimeZone(dur!"hours"(-5)); break;
            case "MST": tz = new immutable SimpleTimeZone(dur!"hours"(-7)); break;
            case "MDT": tz = new immutable SimpleTimeZone(dur!"hours"(-6)); break;
            case "PST": tz = new immutable SimpleTimeZone(dur!"hours"(-8)); break;
            case "PDT": tz = new immutable SimpleTimeZone(dur!"hours"(-7)); break;
            case "J": case "j": throw new DateTimeException("Invalid timezone");
            default:
            {
                if (all!(std.ascii.isAlpha)(value[0 .. tzLen]))
                {
                    tz = new immutable SimpleTimeZone(Duration.zero);
                    break;
                }
                throw new DateTimeException("Invalid timezone");
            }
        }
        value = value[tzLen .. value.length];
    }

    // This is kind of arbitrary. Technically, nothing but CFWS is legal past
    // the end of the timezone, but we don't want to be picky about that in a
    // function that's just parsing rather than validating. So, the idea here is
    // that if the next character is printable (and not part of CFWS), then it
    // might be part of the timezone and thus affect what the timezone was
    // supposed to be, so we'll throw, but otherwise, we'll just ignore it.
    if (!value.empty && std.ascii.isPrintable(value[0]) && value[0] != ' ' && value[0] != '(')
        throw new DateTimeException("Invalid timezone");

    try
        return SysTime(DateTime(year, month, day, hour, minute, second), tz);
    catch (DateTimeException dte)
        throw new DateTimeException("date-time format is correct, but the resulting SysTime is invalid.", dte);
}

///
unittest
{
    auto tz = new immutable SimpleTimeZone(hours(-8));
    assert(parseRFC822DateTime("Sat, 6 Jan 1990 12:14:19 -0800") ==
           SysTime(DateTime(1990, 1, 6, 12, 14, 19), tz));

    assert(parseRFC822DateTime("9 Jul 2002 13:11 +0000") ==
           SysTime(DateTime(2002, 7, 9, 13, 11, 0), UTC()));

    auto badStr = "29 Feb 2001 12:17:16 +0200";
    assertThrown!DateTimeException(parseRFC822DateTime(badStr));
}

version(unittest) void testParse822(alias cr)(string str, SysTime expected, size_t line = __LINE__)
{
    import std.string;
    import std.format : format;
    import core.exception : AssertError;

    auto value = cr(str);
    auto result = parseRFC822DateTime(value);
    if (result != expected)
        throw new AssertError(format("wrong result. expected [%s], actual[%s]", expected, result), __FILE__, line);
}

version(unittest) void testBadParse822(alias cr)(string str, size_t line = __LINE__)
{
    import core.exception : AssertError;

    try
        parseRFC822DateTime(cr(str));
    catch (DateTimeException)
        return;
    throw new AssertError("No DateTimeException was thrown", __FILE__, line);
}

unittest
{
    import std.algorithm;
    import std.ascii;
    import std.format : format;
    import std.range;
    import std.string;
    import std.typecons;
    import std.typetuple;

    static struct Rand3Letters
    {
        enum empty = false;
        @property auto front() { return _mon; }
        void popFront()
        {
            import std.random;
            _mon = rndGen.map!(a => letters[a % letters.length])().take(3).array().assumeUnique();
        }
        string _mon;
        static auto start() { Rand3Letters retval; retval.popFront(); return retval; }
    }

    foreach (cr; TypeTuple!(function(string a){return cast(char[])a;},
                           function(string a){return cast(ubyte[])a;},
                           function(string a){return a;},
                           function(string a){return map!(b => cast(char)b)(a.representation);}))
    (){ // avoid slow optimizations for large functions @@@BUG@@@ 2396
        scope(failure) writeln(typeof(cr).stringof);
        alias test = testParse822!cr;
        alias testBad = testBadParse822!cr;

        immutable std1 = DateTime(2012, 12, 21, 13, 14, 15);
        immutable std2 = DateTime(2012, 12, 21, 13, 14, 0);
        immutable dst1 = DateTime(1976, 7, 4, 5, 4, 22);
        immutable dst2 = DateTime(1976, 7, 4, 5, 4, 0);

        test("21 Dec 2012 13:14:15 +0000", SysTime(std1, UTC()));
        test("21 Dec 2012 13:14 +0000", SysTime(std2, UTC()));
        test("Fri, 21 Dec 2012 13:14 +0000", SysTime(std2, UTC()));
        test("Fri, 21 Dec 2012 13:14:15 +0000", SysTime(std1, UTC()));

        test("04 Jul 1976 05:04:22 +0000", SysTime(dst1, UTC()));
        test("04 Jul 1976 05:04 +0000", SysTime(dst2, UTC()));
        test("Sun, 04 Jul 1976 05:04 +0000", SysTime(dst2, UTC()));
        test("Sun, 04 Jul 1976 05:04:22 +0000", SysTime(dst1, UTC()));

        test("4 Jul 1976 05:04:22 +0000", SysTime(dst1, UTC()));
        test("4 Jul 1976 05:04 +0000", SysTime(dst2, UTC()));
        test("Sun, 4 Jul 1976 05:04 +0000", SysTime(dst2, UTC()));
        test("Sun, 4 Jul 1976 05:04:22 +0000", SysTime(dst1, UTC()));

        auto badTZ = new immutable SimpleTimeZone(Duration.zero);
        test("21 Dec 2012 13:14:15 -0000", SysTime(std1, badTZ));
        test("21 Dec 2012 13:14 -0000", SysTime(std2, badTZ));
        test("Fri, 21 Dec 2012 13:14 -0000", SysTime(std2, badTZ));
        test("Fri, 21 Dec 2012 13:14:15 -0000", SysTime(std1, badTZ));

        test("04 Jul 1976 05:04:22 -0000", SysTime(dst1, badTZ));
        test("04 Jul 1976 05:04 -0000", SysTime(dst2, badTZ));
        test("Sun, 04 Jul 1976 05:04 -0000", SysTime(dst2, badTZ));
        test("Sun, 04 Jul 1976 05:04:22 -0000", SysTime(dst1, badTZ));

        test("4 Jul 1976 05:04:22 -0000", SysTime(dst1, badTZ));
        test("4 Jul 1976 05:04 -0000", SysTime(dst2, badTZ));
        test("Sun, 4 Jul 1976 05:04 -0000", SysTime(dst2, badTZ));
        test("Sun, 4 Jul 1976 05:04:22 -0000", SysTime(dst1, badTZ));

        auto pst = new immutable SimpleTimeZone(dur!"hours"(-8));
        auto pdt = new immutable SimpleTimeZone(dur!"hours"(-7));
        test("21 Dec 2012 13:14:15 -0800", SysTime(std1, pst));
        test("21 Dec 2012 13:14 -0800", SysTime(std2, pst));
        test("Fri, 21 Dec 2012 13:14 -0800", SysTime(std2, pst));
        test("Fri, 21 Dec 2012 13:14:15 -0800", SysTime(std1, pst));

        test("04 Jul 1976 05:04:22 -0700", SysTime(dst1, pdt));
        test("04 Jul 1976 05:04 -0700", SysTime(dst2, pdt));
        test("Sun, 04 Jul 1976 05:04 -0700", SysTime(dst2, pdt));
        test("Sun, 04 Jul 1976 05:04:22 -0700", SysTime(dst1, pdt));

        test("4 Jul 1976 05:04:22 -0700", SysTime(dst1, pdt));
        test("4 Jul 1976 05:04 -0700", SysTime(dst2, pdt));
        test("Sun, 4 Jul 1976 05:04 -0700", SysTime(dst2, pdt));
        test("Sun, 4 Jul 1976 05:04:22 -0700", SysTime(dst1, pdt));

        auto cet = new immutable SimpleTimeZone(dur!"hours"(1));
        auto cest = new immutable SimpleTimeZone(dur!"hours"(2));
        test("21 Dec 2012 13:14:15 +0100", SysTime(std1, cet));
        test("21 Dec 2012 13:14 +0100", SysTime(std2, cet));
        test("Fri, 21 Dec 2012 13:14 +0100", SysTime(std2, cet));
        test("Fri, 21 Dec 2012 13:14:15 +0100", SysTime(std1, cet));

        test("04 Jul 1976 05:04:22 +0200", SysTime(dst1, cest));
        test("04 Jul 1976 05:04 +0200", SysTime(dst2, cest));
        test("Sun, 04 Jul 1976 05:04 +0200", SysTime(dst2, cest));
        test("Sun, 04 Jul 1976 05:04:22 +0200", SysTime(dst1, cest));

        test("4 Jul 1976 05:04:22 +0200", SysTime(dst1, cest));
        test("4 Jul 1976 05:04 +0200", SysTime(dst2, cest));
        test("Sun, 4 Jul 1976 05:04 +0200", SysTime(dst2, cest));
        test("Sun, 4 Jul 1976 05:04:22 +0200", SysTime(dst1, cest));

        // dst and std times are switched in the Southern Hemisphere which is why the
        // time zone names and DateTime variables don't match.
        auto cstStd = new immutable SimpleTimeZone(dur!"hours"(9) + dur!"minutes"(30));
        auto cstDST = new immutable SimpleTimeZone(dur!"hours"(10) + dur!"minutes"(30));
        test("21 Dec 2012 13:14:15 +1030", SysTime(std1, cstDST));
        test("21 Dec 2012 13:14 +1030", SysTime(std2, cstDST));
        test("Fri, 21 Dec 2012 13:14 +1030", SysTime(std2, cstDST));
        test("Fri, 21 Dec 2012 13:14:15 +1030", SysTime(std1, cstDST));

        test("04 Jul 1976 05:04:22 +0930", SysTime(dst1, cstStd));
        test("04 Jul 1976 05:04 +0930", SysTime(dst2, cstStd));
        test("Sun, 04 Jul 1976 05:04 +0930", SysTime(dst2, cstStd));
        test("Sun, 04 Jul 1976 05:04:22 +0930", SysTime(dst1, cstStd));

        test("4 Jul 1976 05:04:22 +0930", SysTime(dst1, cstStd));
        test("4 Jul 1976 05:04 +0930", SysTime(dst2, cstStd));
        test("Sun, 4 Jul 1976 05:04 +0930", SysTime(dst2, cstStd));
        test("Sun, 4 Jul 1976 05:04:22 +0930", SysTime(dst1, cstStd));

        foreach (int i, mon; _monthNames)
        {
            test(format("17 %s 2012 00:05:02 +0000", mon), SysTime(DateTime(2012, i + 1, 17, 0, 5, 2), UTC()));
            test(format("17 %s 2012 00:05 +0000", mon), SysTime(DateTime(2012, i + 1, 17, 0, 5, 0), UTC()));
        }

        import std.uni;
        foreach (mon; chain(_monthNames[].map!(a => toLower(a))(),
                           _monthNames[].map!(a => toUpper(a))(),
                           ["Jam", "Jen", "Fec", "Fdb", "Mas", "Mbr", "Aps", "Aqr", "Mai", "Miy",
                            "Jum", "Jbn", "Jup", "Jal", "Aur", "Apg", "Sem", "Sap", "Ocm", "Odt",
                            "Nom", "Nav", "Dem", "Dac"],
                           Rand3Letters.start().take(20)))
        {
            scope(failure) writefln("Month: %s", mon);
            testBad(format("17 %s 2012 00:05:02 +0000", mon));
            testBad(format("17 %s 2012 00:05 +0000", mon));
        }

        immutable string[7] daysOfWeekNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

        {
            auto start = SysTime(DateTime(2012, 11, 11, 9, 42, 0), UTC());
            int day = 11;

            foreach (int i, dow; daysOfWeekNames)
            {
                auto curr = start + dur!"days"(i);
                test(format("%s, %s Nov 2012 09:42:00 +0000", dow, day), curr);
                test(format("%s, %s Nov 2012 09:42 +0000", dow, day++), curr);

                // Whether the day of the week matches the date is ignored.
                test(format("%s, 11 Nov 2012 09:42:00 +0000", dow), start);
                test(format("%s, 11 Nov 2012 09:42 +0000", dow), start);
            }
        }

        foreach (dow; chain(daysOfWeekNames[].map!(a => toLower(a))(),
                           daysOfWeekNames[].map!(a => toUpper(a))(),
                           ["Sum", "Spn", "Mom", "Man", "Tuf", "Tae", "Wem", "Wdd", "The", "Tur",
                            "Fro", "Fai", "San", "Sut"],
                           Rand3Letters.start().take(20)))
        {
            scope(failure) writefln("Day of Week: %s", dow);
            testBad(format("%s, 11 Nov 2012 09:42:00 +0000", dow));
            testBad(format("%s, 11 Nov 2012 09:42 +0000", dow));
        }

        testBad("31 Dec 1899 23:59:59 +0000");
        test("01 Jan 1900 00:00:00 +0000", SysTime(Date(1900, 1, 1), UTC()));
        test("01 Jan 1900 00:00:00 -0000", SysTime(Date(1900, 1, 1),
                                                   new immutable SimpleTimeZone(Duration.zero)));
        test("01 Jan 1900 00:00:00 -0700", SysTime(Date(1900, 1, 1),
                                                   new immutable SimpleTimeZone(dur!"hours"(-7))));

        {
            auto st1 = SysTime(Date(1900, 1, 1), UTC());
            auto st2 = SysTime(Date(1900, 1, 1), new immutable SimpleTimeZone(dur!"hours"(-11)));
            foreach (i; 1900 .. 2102)
            {
                test(format("1 Jan %05d 00:00 +0000", i), st1);
                test(format("1 Jan %05d 00:00 -1100", i), st2);
                st1.add!"years"(1);
                st2.add!"years"(1);
            }
            st1.year = 9998;
            st2.year = 9998;
            foreach (i; 9998 .. 11_002)
            {
                test(format("1 Jan %05d 00:00 +0000", i), st1);
                test(format("1 Jan %05d 00:00 -1100", i), st2);
                st1.add!"years"(1);
                st2.add!"years"(1);
            }
        }

        testBad("12 Feb 1907 23:17:09 0000");
        testBad("12 Feb 1907 23:17:09 +000");
        testBad("12 Feb 1907 23:17:09 -000");
        testBad("12 Feb 1907 23:17:09 +00000");
        testBad("12 Feb 1907 23:17:09 -00000");
        testBad("12 Feb 1907 23:17:09 +A");
        testBad("12 Feb 1907 23:17:09 +PST");
        testBad("12 Feb 1907 23:17:09 -A");
        testBad("12 Feb 1907 23:17:09 -PST");

        // test trailing stuff that gets ignored
        {
            foreach (c; chain(iota(0, 33), ['('], iota(127, ubyte.max + 1)))
            {
                scope(failure) writefln("c: %d", c);
                test(format("21 Dec 2012 13:14:15 +0000%c", cast(char)c), SysTime(std1, UTC()));
                test(format("21 Dec 2012 13:14:15 +0000%c  ", cast(char)c), SysTime(std1, UTC()));
                test(format("21 Dec 2012 13:14:15 +0000%chello", cast(char)c), SysTime(std1, UTC()));
            }
        }

        // test trailing stuff that doesn't get ignored
        {
            foreach (c; chain(iota(33, '('), iota('(' + 1, 127)))
            {
                scope(failure) writefln("c: %d", c);
                testBad(format("21 Dec 2012 13:14:15 +0000%c", cast(char)c));
                testBad(format("21 Dec 2012 13:14:15 +0000%c   ", cast(char)c));
                testBad(format("21 Dec 2012 13:14:15 +0000%chello", cast(char)c));
            }
        }

        testBad("32 Jan 2012 12:13:14 -0800");
        testBad("31 Jan 2012 24:13:14 -0800");
        testBad("31 Jan 2012 12:60:14 -0800");
        testBad("31 Jan 2012 12:13:61 -0800");
        testBad("31 Jan 2012 12:13:14 -0860");
        test("31 Jan 2012 12:13:14 -0859",
             SysTime(DateTime(2012, 1, 31, 12, 13, 14),
                     new immutable SimpleTimeZone(dur!"hours"(-8) + dur!"minutes"(-59))));

        // leap-seconds
        test("21 Dec 2012 15:59:60 -0800", SysTime(DateTime(2012, 12, 21, 15, 59, 59), pst));

        // FWS
        test("Sun,4 Jul 1976 05:04 +0930", SysTime(dst2, cstStd));
        test("Sun,4 Jul 1976 05:04:22 +0930", SysTime(dst1, cstStd));
        test("Sun,4 Jul 1976 05:04 +0930 (foo)", SysTime(dst2, cstStd));
        test("Sun,4 Jul 1976 05:04:22 +0930 (foo)", SysTime(dst1, cstStd));
        test("Sun,4  \r\n  Jul  \r\n  1976  \r\n  05:04  \r\n  +0930  \r\n  (foo)", SysTime(dst2, cstStd));
        test("Sun,4  \r\n  Jul  \r\n  1976  \r\n  05:04:22  \r\n  +0930  \r\n  (foo)", SysTime(dst1, cstStd));

        auto str = "01 Jan 2012 12:13:14 -0800 ";
        test(str, SysTime(DateTime(2012, 1, 1, 12, 13, 14), new immutable SimpleTimeZone(hours(-8))));
        foreach (i; 0 .. str.length)
        {
            auto currStr = str.dup;
            currStr[i] = 'x';
            scope(failure) writefln("failed: %s", currStr);
            testBad(cast(string)currStr);
        }
        foreach (i; 2 .. str.length)
        {
            auto currStr = str[0 .. $ - i];
            scope(failure) writefln("failed: %s", currStr);
            testBad(cast(string)currStr);
            testBad((cast(string)currStr) ~ "                                    ");
        }
    }();
}

// Obsolete Format per section 4.3 of RFC 5322.
unittest
{
    import std.algorithm;
    import std.ascii;
    import std.format : format;
    import std.range;
    import std.string;
    import std.typecons;
    import std.typetuple;

    auto std1 = SysTime(DateTime(2012, 12, 21, 13, 14, 15), UTC());
    auto std2 = SysTime(DateTime(2012, 12, 21, 13, 14, 0), UTC());
    auto std3 = SysTime(DateTime(1912, 12, 21, 13, 14, 15), UTC());
    auto std4 = SysTime(DateTime(1912, 12, 21, 13, 14, 0), UTC());
    auto dst1 = SysTime(DateTime(1976, 7, 4, 5, 4, 22), UTC());
    auto dst2 = SysTime(DateTime(1976, 7, 4, 5, 4, 0), UTC());
    auto tooLate1 = SysTime(Date(10_000, 1, 1), UTC());
    auto tooLate2 = SysTime(DateTime(12_007, 12, 31, 12, 22, 19), UTC());

    foreach (cr; TypeTuple!(function(string a){return cast(char[])a;},
                           function(string a){return cast(ubyte[])a;},
                           function(string a){return a;},
                           function(string a){return map!(b => cast(char)b)(a.representation);}))
    (){ // avoid slow optimizations for large functions @@@BUG@@@ 2396
        scope(failure) writeln(typeof(cr).stringof);
        alias test = testParse822!cr;
        {
            auto list = ["", " ", " \r\n\t", "\t\r\n (hello world( frien(dog)) silly \r\n )  \t\t \r\n ()",
                         " \n ", "\t\n\t", " \n\t (foo) \n (bar) \r\n (baz) \n "];

            foreach (i, cfws; list)
            {
                scope(failure) writefln("i: %s", i);

                test(format("%1$s21%1$sDec%1$s2012%1$s13:14:15%1$s+0000%1$s", cfws), std1);
                test(format("%1$s21%1$sDec%1$s2012%1$s13:14%1$s+0000%1$s", cfws), std2);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s2012%1$s13:14%1$s+0000%1$s", cfws), std2);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s2012%1$s13:14:15%1$s+0000%1$s", cfws), std1);

                test(format("%1$s04%1$sJul%1$s1976%1$s05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s04%1$sJul%1$s1976%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s1976%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s1976%1$s05:04:22 +0000%1$s", cfws), dst1);

                test(format("%1$s4%1$sJul%1$s1976%1$s05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s4%1$sJul%1$s1976%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s1976%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s1976%1$s05:04:22%1$s+0000%1$s", cfws), dst1);

                test(format("%1$s21%1$sDec%1$s12%1$s13:14:15%1$s+0000%1$s", cfws), std1);
                test(format("%1$s21%1$sDec%1$s12%1$s13:14%1$s+0000%1$s", cfws), std2);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s12%1$s13:14%1$s+0000%1$s", cfws), std2);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s12%1$s13:14:15%1$s+0000%1$s", cfws), std1);

                test(format("%1$s04%1$sJul%1$s76%1$s05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s04%1$sJul%1$s76%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s76%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s76%1$s05:04:22%1$s+0000%1$s", cfws), dst1);

                test(format("%1$s4%1$sJul%1$s76 05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s4%1$sJul%1$s76 05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s76%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s76%1$s05:04:22%1$s+0000%1$s", cfws), dst1);

                test(format("%1$s21%1$sDec%1$s012%1$s13:14:15%1$s+0000%1$s", cfws), std3);
                test(format("%1$s21%1$sDec%1$s012%1$s13:14%1$s+0000%1$s", cfws), std4);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s012%1$s13:14%1$s+0000%1$s", cfws), std4);
                test(format("%1$sFri%1$s,%1$s21%1$sDec%1$s012%1$s13:14:15%1$s+0000%1$s", cfws), std3);

                test(format("%1$s04%1$sJul%1$s076%1$s05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s04%1$sJul%1$s076%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s076%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s04%1$sJul%1$s076%1$s05:04:22%1$s+0000%1$s", cfws), dst1);

                test(format("%1$s4%1$sJul%1$s076%1$s05:04:22%1$s+0000%1$s", cfws), dst1);
                test(format("%1$s4%1$sJul%1$s076%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s076%1$s05:04%1$s+0000%1$s", cfws), dst2);
                test(format("%1$sSun%1$s,%1$s4%1$sJul%1$s076%1$s05:04:22%1$s+0000%1$s", cfws), dst1);

                test(format("%1$s1%1$sJan%1$s10000%1$s00:00:00%1$s+0000%1$s", cfws), tooLate1);
                test(format("%1$s31%1$sDec%1$s12007%1$s12:22:19%1$s+0000%1$s", cfws), tooLate2);
                test(format("%1$sSat%1$s,%1$s1%1$sJan%1$s10000%1$s00:00:00%1$s+0000%1$s", cfws), tooLate1);
                test(format("%1$sSun%1$s,%1$s31%1$sDec%1$s12007%1$s12:22:19%1$s+0000%1$s", cfws), tooLate2);
            }
        }

        // test years of 1, 2, and 3 digits.
        {
            auto st1 = SysTime(Date(2000, 1, 1), UTC());
            auto st2 = SysTime(Date(2000, 1, 1), new immutable SimpleTimeZone(dur!"hours"(-12)));
            foreach (i; 0 .. 50)
            {
                test(format("1 Jan %02d 00:00 GMT", i), st1);
                test(format("1 Jan %02d 00:00 -1200", i), st2);
                st1.add!"years"(1);
                st2.add!"years"(1);
            }
        }

        {
            auto st1 = SysTime(Date(1950, 1, 1), UTC());
            auto st2 = SysTime(Date(1950, 1, 1), new immutable SimpleTimeZone(dur!"hours"(-12)));
            foreach (i; 50 .. 100)
            {
                test(format("1 Jan %02d 00:00 GMT", i), st1);
                test(format("1 Jan %02d 00:00 -1200", i), st2);
                st1.add!"years"(1);
                st2.add!"years"(1);
            }
        }

        {
            auto st1 = SysTime(Date(1900, 1, 1), UTC());
            auto st2 = SysTime(Date(1900, 1, 1), new immutable SimpleTimeZone(dur!"hours"(-11)));
            foreach (i; 0 .. 1000)
            {
                test(format("1 Jan %03d 00:00 GMT", i), st1);
                test(format("1 Jan %03d 00:00 -1100", i), st2);
                st1.add!"years"(1);
                st2.add!"years"(1);
            }
        }

        foreach (i; 0 .. 10)
        {
            auto str1 = cr(format("1 Jan %d 00:00 GMT", i));
            auto str2 = cr(format("1 Jan %d 00:00 -1200", i));
            assertThrown!DateTimeException(parseRFC822DateTime(str1));
            assertThrown!DateTimeException(parseRFC822DateTime(str1));
        }

        // test time zones
        {
            auto dt = DateTime(1982, 05, 03, 12, 22, 04);
            test("Wed, 03 May 1982 12:22:04 UT", SysTime(dt, UTC()));
            test("Wed, 03 May 1982 12:22:04 GMT", SysTime(dt, UTC()));
            test("Wed, 03 May 1982 12:22:04 EST", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-5))));
            test("Wed, 03 May 1982 12:22:04 EDT", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-4))));
            test("Wed, 03 May 1982 12:22:04 CST", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-6))));
            test("Wed, 03 May 1982 12:22:04 CDT", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-5))));
            test("Wed, 03 May 1982 12:22:04 MST", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-7))));
            test("Wed, 03 May 1982 12:22:04 MDT", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-6))));
            test("Wed, 03 May 1982 12:22:04 PST", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-8))));
            test("Wed, 03 May 1982 12:22:04 PDT", SysTime(dt, new immutable SimpleTimeZone(dur!"hours"(-7))));

            auto badTZ = new immutable SimpleTimeZone(Duration.zero);
            foreach (dchar c; filter!(a => a != 'j' && a != 'J')(letters))
            {
                scope(failure) writefln("c: %s", c);
                test(format("Wed, 03 May 1982 12:22:04 %s", c), SysTime(dt, badTZ));
                test(format("Wed, 03 May 1982 12:22:04%s", c), SysTime(dt, badTZ));
            }

            foreach (dchar c; ['j', 'J'])
            {
                scope(failure) writefln("c: %s", c);
                assertThrown!DateTimeException(parseRFC822DateTime(cr(format("Wed, 03 May 1982 12:22:04 %s", c))));
                assertThrown!DateTimeException(parseRFC822DateTime(cr(format("Wed, 03 May 1982 12:22:04%s", c))));
            }

            foreach (string s; ["AAA", "GQW", "DDT", "PDA", "GT", "GM"])
            {
                scope(failure) writefln("s: %s", s);
                test(format("Wed, 03 May 1982 12:22:04 %s", s), SysTime(dt, badTZ));
            }

            // test trailing stuff that gets ignored
            {
                foreach (c; chain(iota(0, 33), ['('], iota(127, ubyte.max + 1)))
                {
                    scope(failure) writefln("c: %d", c);
                    test(format("21Dec1213:14:15+0000%c", cast(char)c), std1);
                    test(format("21Dec1213:14:15+0000%c  ", cast(char)c), std1);
                    test(format("21Dec1213:14:15+0000%chello", cast(char)c), std1);
                }
            }

            // test trailing stuff that doesn't get ignored
            {
                foreach (c; chain(iota(33, '('), iota('(' + 1, 127)))
                {
                    scope(failure) writefln("c: %d", c);
                    assertThrown!DateTimeException(parseRFC822DateTime(cr(format("21Dec1213:14:15+0000%c", cast(char)c))));
                    assertThrown!DateTimeException(parseRFC822DateTime(cr(format("21Dec1213:14:15+0000%c  ", cast(char)c))));
                    assertThrown!DateTimeException(parseRFC822DateTime(cr(format("21Dec1213:14:15+0000%chello", cast(char)c))));
                }
            }
        }

        // test that the checks for minimum length work correctly and avoid
        // any RangeErrors.
        test("7Dec1200:00A", SysTime(DateTime(2012, 12, 7, 00, 00, 00),
                                     new immutable SimpleTimeZone(Duration.zero)));
        test("Fri,7Dec1200:00A", SysTime(DateTime(2012, 12, 7, 00, 00, 00),
                                         new immutable SimpleTimeZone(Duration.zero)));
        test("7Dec1200:00:00A", SysTime(DateTime(2012, 12, 7, 00, 00, 00),
                                        new immutable SimpleTimeZone(Duration.zero)));
        test("Fri,7Dec1200:00:00A", SysTime(DateTime(2012, 12, 7, 00, 00, 00),
                                            new immutable SimpleTimeZone(Duration.zero)));

        auto tooShortMsg = collectExceptionMsg!DateTimeException(parseRFC822DateTime(""));
        foreach (str; ["Fri,7Dec1200:00:00", "7Dec1200:00:00"])
        {
            foreach (i; 0 .. str.length)
            {
                auto value = str[0 .. $ - i];
                scope(failure) writeln(value);
                assert(collectExceptionMsg!DateTimeException(parseRFC822DateTime(value)) == tooShortMsg);
            }
        }
    }();
}


/++
    Whether all of the given strings are valid units of time.

    $(D "nsecs") is not considered a valid unit of time. Nothing in std.datetime
    can handle precision greater than hnsecs, and the few functions in core.time
    which deal with "nsecs" deal with it explicitly.
  +/
bool validTimeUnits(string[] units...) @safe pure nothrow
{
    import std.algorithm : canFind;
    foreach (str; units)
    {
        if (!canFind(timeStrings[], str))
            return false;
    }

    return true;
}


/++
    Compares two time unit strings. $(D "years") are the largest units and
    $(D "hnsecs") are the smallest.

    Returns:
        $(BOOKTABLE,
        $(TR $(TD this &lt; rhs) $(TD &lt; 0))
        $(TR $(TD this == rhs) $(TD 0))
        $(TR $(TD this &gt; rhs) $(TD &gt; 0))
        )

    Throws:
        $(LREF DateTimeException) if either of the given strings is not a valid
        time unit string.
 +/
int cmpTimeUnits(string lhs, string rhs) @safe pure
{
    import std.format : format;
    import std.algorithm : countUntil;

    auto tstrings = timeStrings;
    immutable indexOfLHS = countUntil(tstrings, lhs);
    immutable indexOfRHS = countUntil(tstrings, rhs);

    enforce(indexOfLHS != -1, format("%s is not a valid TimeString", lhs));
    enforce(indexOfRHS != -1, format("%s is not a valid TimeString", rhs));

    if (indexOfLHS < indexOfRHS)
        return -1;
    if (indexOfLHS > indexOfRHS)
        return 1;

    return 0;
}

unittest
{
    foreach (i, outerUnits; timeStrings)
    {
        assert(cmpTimeUnits(outerUnits, outerUnits) == 0);

        //For some reason, $ won't compile.
        foreach (innerUnits; timeStrings[i+1 .. timeStrings.length])
            assert(cmpTimeUnits(outerUnits, innerUnits) == -1);
    }

    foreach (i, outerUnits; timeStrings)
    {
        foreach (innerUnits; timeStrings[0 .. i])
            assert(cmpTimeUnits(outerUnits, innerUnits) == 1);
    }
}


/++
    Compares two time unit strings at compile time. $(D "years") are the largest
    units and $(D "hnsecs") are the smallest.

    This template is used instead of $(D cmpTimeUnits) because exceptions
    can't be thrown at compile time and $(D cmpTimeUnits) must enforce that
    the strings it's given are valid time unit strings. This template uses a
    template constraint instead.

    Returns:
        $(BOOKTABLE,
        $(TR $(TD this &lt; rhs) $(TD &lt; 0))
        $(TR $(TD this == rhs) $(TD 0))
        $(TR $(TD this &gt; rhs) $(TD &gt; 0))
        )
 +/
template CmpTimeUnits(string lhs, string rhs)
    if (validTimeUnits(lhs, rhs))
{
    enum CmpTimeUnits = cmpTimeUnitsCTFE(lhs, rhs);
}


/+
    Helper function for $(D CmpTimeUnits).
 +/
private int cmpTimeUnitsCTFE(string lhs, string rhs) @safe pure nothrow
{
    import std.algorithm : countUntil;
    auto tstrings = timeStrings;
    immutable indexOfLHS = countUntil(tstrings, lhs);
    immutable indexOfRHS = countUntil(tstrings, rhs);

    if (indexOfLHS < indexOfRHS)
        return -1;
    if (indexOfLHS > indexOfRHS)
        return 1;

    return 0;
}

unittest
{
    import std.format : format;
    import std.string;
    import std.typecons;
    import std.typetuple;

    static string genTest(size_t index)
    {
        auto currUnits = timeStrings[index];
        auto test = format(`assert(CmpTimeUnits!("%s", "%s") == 0);`, currUnits, currUnits);

        foreach (units; timeStrings[index + 1 .. $])
            test ~= format(`assert(CmpTimeUnits!("%s", "%s") == -1);`, currUnits, units);

        foreach (units; timeStrings[0 .. index])
            test ~= format(`assert(CmpTimeUnits!("%s", "%s") == 1);`, currUnits, units);

        return test;
    }

    static assert(timeStrings.length == 10);
    foreach (n; TypeTuple!(0, 1, 2, 3, 4, 5, 6, 7, 8, 9))
        mixin(genTest(n));
}


/++
    Returns whether the given value is valid for the given unit type when in a
    time point. Naturally, a duration is not held to a particular range, but
    the values in a time point are (e.g. a month must be in the range of
    1 - 12 inclusive).

    Params:
        units = The units of time to validate.
        value = The number to validate.
  +/
bool valid(string units)(int value) @safe pure nothrow
    if (units == "months" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds")
{
    static if (units == "months")
        return value >= Month.jan && value <= Month.dec;
    else static if (units == "hours")
        return value >= 0 && value <= TimeOfDay.maxHour;
    else static if (units == "minutes")
        return value >= 0 && value <= TimeOfDay.maxMinute;
    else static if (units == "seconds")
        return value >= 0 && value <= TimeOfDay.maxSecond;
}

///
unittest
{
    assert( valid!"hours"(12));
    assert(!valid!"hours"(32));
    assert( valid!"months"(12));
    assert(!valid!"months"(13));
}


/++
    Returns whether the given day is valid for the given year and month.

    Params:
        units = The units of time to validate.
        year  = The year of the day to validate.
        month = The month of the day to validate.
        day   = The day to validate.
  +/
bool valid(string units)(int year, int month, int day) @safe pure nothrow
    if (units == "days")
{
    return day > 0 && day <= maxDay(year, month);
}


/++
    Params:
        units = The units of time to validate.
        value = The number to validate.
        file  = The file that the $(LREF DateTimeException) will list if thrown.
        line  = The line number that the $(LREF DateTimeException) will list if
                thrown.

    Throws:
        $(LREF DateTimeException) if $(D valid!units(value)) is false.
  +/
void enforceValid(string units)(int value, string file = __FILE__, size_t line = __LINE__) @safe pure
    if (units == "months" ||
       units == "hours" ||
       units == "minutes" ||
       units == "seconds")
{
    import std.format : format;

    static if (units == "months")
    {
        if (!valid!units(value))
            throw new DateTimeException(format("%s is not a valid month of the year.", value), file, line);
    }
    else static if (units == "hours")
    {
        if (!valid!units(value))
            throw new DateTimeException(format("%s is not a valid hour of the day.", value), file, line);
    }
    else static if (units == "minutes")
    {
        if (!valid!units(value))
            throw new DateTimeException(format("%s is not a valid minute of an hour.", value), file, line);
    }
    else static if (units == "seconds")
    {
        if (!valid!units(value))
            throw new DateTimeException(format("%s is not a valid second of a minute.", value), file, line);
    }
}


/++
    Params:
        units = The units of time to validate.
        year  = The year of the day to validate.
        month = The month of the day to validate.
        day   = The day to validate.
        file  = The file that the $(LREF DateTimeException) will list if thrown.
        line  = The line number that the $(LREF DateTimeException) will list if
                thrown.

    Throws:
        $(LREF DateTimeException) if $(D valid!"days"(year, month, day)) is false.
  +/
void enforceValid(string units)
                 (int year, Month month, int day, string file = __FILE__, size_t line = __LINE__) @safe pure
    if (units == "days")
{
    import std.format : format;
    if (!valid!"days"(year, month, day))
        throw new DateTimeException(format("%s is not a valid day in %s in %s", day, month, year), file, line);
}


/++
    Returns the number of months from the current months of the year to the
    given month of the year. If they are the same, then the result is 0.

    Params:
        currMonth = The current month of the year.
        month     = The month of the year to get the number of months to.
  +/
static int monthsToMonth(int currMonth, int month) @safe pure
{
    enforceValid!"months"(currMonth);
    enforceValid!"months"(month);

    if (currMonth == month)
        return 0;

    if (currMonth < month)
        return month - currMonth;

    return (Month.dec - currMonth) + month;
}

unittest
{
    assert(monthsToMonth(Month.jan, Month.jan) == 0);
    assert(monthsToMonth(Month.jan, Month.feb) == 1);
    assert(monthsToMonth(Month.jan, Month.mar) == 2);
    assert(monthsToMonth(Month.jan, Month.apr) == 3);
    assert(monthsToMonth(Month.jan, Month.may) == 4);
    assert(monthsToMonth(Month.jan, Month.jun) == 5);
    assert(monthsToMonth(Month.jan, Month.jul) == 6);
    assert(monthsToMonth(Month.jan, Month.aug) == 7);
    assert(monthsToMonth(Month.jan, Month.sep) == 8);
    assert(monthsToMonth(Month.jan, Month.oct) == 9);
    assert(monthsToMonth(Month.jan, Month.nov) == 10);
    assert(monthsToMonth(Month.jan, Month.dec) == 11);

    assert(monthsToMonth(Month.may, Month.jan) == 8);
    assert(monthsToMonth(Month.may, Month.feb) == 9);
    assert(monthsToMonth(Month.may, Month.mar) == 10);
    assert(monthsToMonth(Month.may, Month.apr) == 11);
    assert(monthsToMonth(Month.may, Month.may) == 0);
    assert(monthsToMonth(Month.may, Month.jun) == 1);
    assert(monthsToMonth(Month.may, Month.jul) == 2);
    assert(monthsToMonth(Month.may, Month.aug) == 3);
    assert(monthsToMonth(Month.may, Month.sep) == 4);
    assert(monthsToMonth(Month.may, Month.oct) == 5);
    assert(monthsToMonth(Month.may, Month.nov) == 6);
    assert(monthsToMonth(Month.may, Month.dec) == 7);

    assert(monthsToMonth(Month.oct, Month.jan) == 3);
    assert(monthsToMonth(Month.oct, Month.feb) == 4);
    assert(monthsToMonth(Month.oct, Month.mar) == 5);
    assert(monthsToMonth(Month.oct, Month.apr) == 6);
    assert(monthsToMonth(Month.oct, Month.may) == 7);
    assert(monthsToMonth(Month.oct, Month.jun) == 8);
    assert(monthsToMonth(Month.oct, Month.jul) == 9);
    assert(monthsToMonth(Month.oct, Month.aug) == 10);
    assert(monthsToMonth(Month.oct, Month.sep) == 11);
    assert(monthsToMonth(Month.oct, Month.oct) == 0);
    assert(monthsToMonth(Month.oct, Month.nov) == 1);
    assert(monthsToMonth(Month.oct, Month.dec) == 2);

    assert(monthsToMonth(Month.dec, Month.jan) == 1);
    assert(monthsToMonth(Month.dec, Month.feb) == 2);
    assert(monthsToMonth(Month.dec, Month.mar) == 3);
    assert(monthsToMonth(Month.dec, Month.apr) == 4);
    assert(monthsToMonth(Month.dec, Month.may) == 5);
    assert(monthsToMonth(Month.dec, Month.jun) == 6);
    assert(monthsToMonth(Month.dec, Month.jul) == 7);
    assert(monthsToMonth(Month.dec, Month.aug) == 8);
    assert(monthsToMonth(Month.dec, Month.sep) == 9);
    assert(monthsToMonth(Month.dec, Month.oct) == 10);
    assert(monthsToMonth(Month.dec, Month.nov) == 11);
    assert(monthsToMonth(Month.dec, Month.dec) == 0);
}


/++
    Returns the number of days from the current day of the week to the given
    day of the week. If they are the same, then the result is 0.

    Params:
        currDoW = The current day of the week.
        dow     = The day of the week to get the number of days to.
  +/
static int daysToDayOfWeek(DayOfWeek currDoW, DayOfWeek dow) @safe pure nothrow
{
    if (currDoW == dow)
        return 0;

    if (currDoW < dow)
        return dow - currDoW;

    return (DayOfWeek.sat - currDoW) + dow + 1;
}

unittest
{
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.sun) == 0);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.mon) == 1);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.tue) == 2);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.wed) == 3);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.thu) == 4);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.fri) == 5);
    assert(daysToDayOfWeek(DayOfWeek.sun, DayOfWeek.sat) == 6);

    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.sun) == 6);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.mon) == 0);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.tue) == 1);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.wed) == 2);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.thu) == 3);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.fri) == 4);
    assert(daysToDayOfWeek(DayOfWeek.mon, DayOfWeek.sat) == 5);

    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.sun) == 5);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.mon) == 6);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.tue) == 0);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.wed) == 1);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.thu) == 2);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.fri) == 3);
    assert(daysToDayOfWeek(DayOfWeek.tue, DayOfWeek.sat) == 4);

    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.sun) == 4);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.mon) == 5);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.tue) == 6);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.wed) == 0);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.thu) == 1);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.fri) == 2);
    assert(daysToDayOfWeek(DayOfWeek.wed, DayOfWeek.sat) == 3);

    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.sun) == 3);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.mon) == 4);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.tue) == 5);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.wed) == 6);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.thu) == 0);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.fri) == 1);
    assert(daysToDayOfWeek(DayOfWeek.thu, DayOfWeek.sat) == 2);

    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.sun) == 2);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.mon) == 3);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.tue) == 4);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.wed) == 5);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.thu) == 6);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.fri) == 0);
    assert(daysToDayOfWeek(DayOfWeek.fri, DayOfWeek.sat) == 1);

    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.sun) == 1);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.mon) == 2);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.tue) == 3);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.wed) == 4);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.thu) == 5);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.fri) == 6);
    assert(daysToDayOfWeek(DayOfWeek.sat, DayOfWeek.sat) == 0);
}


version(StdDdoc)
{
    /++
        Function for starting to a stop watch time when the function is called
        and stopping it when its return value goes out of scope and is destroyed.

        When the value that is returned by this function is destroyed,
        $(D func) will run. $(D func) is a unary function that takes a
        $(CXREF time, TickDuration).

        Examples:
            --------------------
            {
                auto mt = measureTime!((TickDuration a)
                    { /+ do something when the scope is exited +/ });
                // do something that needs to be timed
            }
            --------------------

        which is functionally equivalent to

            --------------------
            {
                auto sw = StopWatch(AutoStart.yes);
                scope(exit)
                {
                    TickDuration a = sw.peek();
                    /+ do something when the scope is exited +/
                }
                // do something that needs to be timed
            }
            --------------------

        See_Also:
            $(LREF benchmark)
      +/
    auto measureTime(alias func)();
}
else
{
    @safe auto measureTime(alias func)()
        if (isSafe!((){StopWatch sw; unaryFun!func(sw.peek());}))
    {
        struct Result
        {
            private StopWatch _sw = void;
            this(AutoStart as)
            {
                _sw = StopWatch(as);
            }
            ~this()
            {
                unaryFun!(func)(_sw.peek());
            }
        }
        return Result(AutoStart.yes);
    }

    auto measureTime(alias func)()
        if (!isSafe!((){StopWatch sw; unaryFun!func(sw.peek());}))
    {
        struct Result
        {
            private StopWatch _sw = void;
            this(AutoStart as)
            {
                _sw = StopWatch(as);
            }
            ~this()
            {
                unaryFun!(func)(_sw.peek());
            }
        }
        return Result(AutoStart.yes);
    }
}

// Verify Example.
unittest
{
    {
        auto mt = measureTime!((TickDuration a)
            { /+ do something when the scope is exited +/ });
        // do something that needs to be timed
    }

    {
        auto sw = StopWatch(AutoStart.yes);
        scope(exit)
        {
            TickDuration a = sw.peek();
            /+ do something when the scope is exited +/
        }
        // do something that needs to be timed
    }
}

@safe unittest
{
    import std.math : isNaN;

    @safe static void func(TickDuration td)
    {
        assert(!td.to!("seconds", real)().isNaN());
    }

    auto mt = measureTime!(func)();

    /+
    with (measureTime!((a){assert(a.seconds);}))
    {
        // doSomething();
        // @@@BUG@@@ doesn't work yet.
    }
    +/
}

unittest
{
    import std.math : isNaN;

    static void func(TickDuration td)
    {
        assert(!td.to!("seconds", real)().isNaN());
    }

    auto mt = measureTime!(func)();

    /+
    with (measureTime!((a){assert(a.seconds);}))
    {
        // doSomething();
        // @@@BUG@@@ doesn't work yet.
    }
    +/
}

//Bug# 8450
unittest
{
    @safe    void safeFunc() {}
    @trusted void trustFunc() {}
    @system  void sysFunc() {}
    auto safeResult  = measureTime!((a){safeFunc();})();
    auto trustResult = measureTime!((a){trustFunc();})();
    auto sysResult   = measureTime!((a){sysFunc();})();
}

//==============================================================================
// Private Section.
//==============================================================================
package:

//==============================================================================
// Section with private enums and constants.
//==============================================================================

enum daysInYear     = 365;  // The number of days in a non-leap year.
enum daysInLeapYear = 366;  // The numbef or days in a leap year.
enum daysIn4Years   = daysInYear * 3 + daysInLeapYear;  /// Number of days in 4 years.
enum daysIn100Years = daysIn4Years * 25 - 1;  // The number of days in 100 years.
enum daysIn400Years = daysIn100Years * 4 + 1; // The number of days in 400 years.

/+
    Array of integers representing the last days of each month in a year.
  +/
immutable int[13] lastDayNonLeap = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365];

/+
    Array of integers representing the last days of each month in a leap year.
  +/
immutable int[13] lastDayLeap = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366];

/+
    Array of the short (three letter) names of each month.
  +/
immutable string[12] _monthNames =
[
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
];


//==============================================================================
// Section with private helper functions and templates.
//==============================================================================

/+
    Template to help with converting between time units.
 +/
template hnsecsPer(string units)
    if (CmpTimeUnits!(units, "months") < 0)
{
    static if (units == "hnsecs")
        enum hnsecsPer = 1L;
    else static if (units == "usecs")
        enum hnsecsPer = 10L;
    else static if (units == "msecs")
        enum hnsecsPer = 1000 * hnsecsPer!"usecs";
    else static if (units == "seconds")
        enum hnsecsPer = 1000 * hnsecsPer!"msecs";
    else static if (units == "minutes")
        enum hnsecsPer = 60 * hnsecsPer!"seconds";
    else static if (units == "hours")
        enum hnsecsPer = 60 * hnsecsPer!"minutes";
    else static if (units == "days")
        enum hnsecsPer = 24 * hnsecsPer!"hours";
    else static if (units == "weeks")
        enum hnsecsPer = 7 * hnsecsPer!"days";
}


// splitUnitsFromHNSecs
// getUnitsFromHNSecs
// removeUnitsFromHNSecs

/+
    The maximum valid Day in the given month in the given year.

    Params:
        year  = The year to get the day for.
        month = The month of the Gregorian Calendar to get the day for.
 +/
static ubyte maxDay(int year, int month) @safe pure nothrow
in
{
    assert(valid!"months"(month));
}
body
{
    switch (month)
    {
        case Month.jan, Month.mar, Month.may, Month.jul, Month.aug, Month.oct, Month.dec:
            return 31;
        case Month.feb:
            return yearIsLeapYear(year) ? 29 : 28;
        case Month.apr, Month.jun, Month.sep, Month.nov:
            return 30;
        default:
            assert(0, "Invalid month.");
    }
}

unittest
{
    //Test A.D.
    assert(maxDay(1999, 1) == 31);
    assert(maxDay(1999, 2) == 28);
    assert(maxDay(1999, 3) == 31);
    assert(maxDay(1999, 4) == 30);
    assert(maxDay(1999, 5) == 31);
    assert(maxDay(1999, 6) == 30);
    assert(maxDay(1999, 7) == 31);
    assert(maxDay(1999, 8) == 31);
    assert(maxDay(1999, 9) == 30);
    assert(maxDay(1999, 10) == 31);
    assert(maxDay(1999, 11) == 30);
    assert(maxDay(1999, 12) == 31);

    assert(maxDay(2000, 1) == 31);
    assert(maxDay(2000, 2) == 29);
    assert(maxDay(2000, 3) == 31);
    assert(maxDay(2000, 4) == 30);
    assert(maxDay(2000, 5) == 31);
    assert(maxDay(2000, 6) == 30);
    assert(maxDay(2000, 7) == 31);
    assert(maxDay(2000, 8) == 31);
    assert(maxDay(2000, 9) == 30);
    assert(maxDay(2000, 10) == 31);
    assert(maxDay(2000, 11) == 30);
    assert(maxDay(2000, 12) == 31);

    //Test B.C.
    assert(maxDay(-1999, 1) == 31);
    assert(maxDay(-1999, 2) == 28);
    assert(maxDay(-1999, 3) == 31);
    assert(maxDay(-1999, 4) == 30);
    assert(maxDay(-1999, 5) == 31);
    assert(maxDay(-1999, 6) == 30);
    assert(maxDay(-1999, 7) == 31);
    assert(maxDay(-1999, 8) == 31);
    assert(maxDay(-1999, 9) == 30);
    assert(maxDay(-1999, 10) == 31);
    assert(maxDay(-1999, 11) == 30);
    assert(maxDay(-1999, 12) == 31);

    assert(maxDay(-2000, 1) == 31);
    assert(maxDay(-2000, 2) == 29);
    assert(maxDay(-2000, 3) == 31);
    assert(maxDay(-2000, 4) == 30);
    assert(maxDay(-2000, 5) == 31);
    assert(maxDay(-2000, 6) == 30);
    assert(maxDay(-2000, 7) == 31);
    assert(maxDay(-2000, 8) == 31);
    assert(maxDay(-2000, 9) == 30);
    assert(maxDay(-2000, 10) == 31);
    assert(maxDay(-2000, 11) == 30);
    assert(maxDay(-2000, 12) == 31);
}


/+
    Returns the day of the week for the given day of the Gregorian Calendar.

    Params:
        day = The day of the Gregorian Calendar for which to get the day of
              the week.
  +/
DayOfWeek getDayOfWeek(int day) @safe pure nothrow
{
    //January 1st, 1 A.D. was a Monday
    if (day >= 0)
        return cast(DayOfWeek)(day % 7);
    else
    {
        immutable dow = cast(DayOfWeek)((day % 7) + 7);

        if (dow == 7)
            return DayOfWeek.sun;
        else
            return dow;
    }
}

unittest
{
    //Test A.D.
    assert(getDayOfWeek(SysTime(Date(1, 1, 1)).dayOfGregorianCal) == DayOfWeek.mon);
    assert(getDayOfWeek(SysTime(Date(1, 1, 2)).dayOfGregorianCal) == DayOfWeek.tue);
    assert(getDayOfWeek(SysTime(Date(1, 1, 3)).dayOfGregorianCal) == DayOfWeek.wed);
    assert(getDayOfWeek(SysTime(Date(1, 1, 4)).dayOfGregorianCal) == DayOfWeek.thu);
    assert(getDayOfWeek(SysTime(Date(1, 1, 5)).dayOfGregorianCal) == DayOfWeek.fri);
    assert(getDayOfWeek(SysTime(Date(1, 1, 6)).dayOfGregorianCal) == DayOfWeek.sat);
    assert(getDayOfWeek(SysTime(Date(1, 1, 7)).dayOfGregorianCal) == DayOfWeek.sun);
    assert(getDayOfWeek(SysTime(Date(1, 1, 8)).dayOfGregorianCal) == DayOfWeek.mon);
    assert(getDayOfWeek(SysTime(Date(1, 1, 9)).dayOfGregorianCal) == DayOfWeek.tue);
    assert(getDayOfWeek(SysTime(Date(2, 1, 1)).dayOfGregorianCal) == DayOfWeek.tue);
    assert(getDayOfWeek(SysTime(Date(3, 1, 1)).dayOfGregorianCal) == DayOfWeek.wed);
    assert(getDayOfWeek(SysTime(Date(4, 1, 1)).dayOfGregorianCal) == DayOfWeek.thu);
    assert(getDayOfWeek(SysTime(Date(5, 1, 1)).dayOfGregorianCal) == DayOfWeek.sat);
    assert(getDayOfWeek(SysTime(Date(2000, 1, 1)).dayOfGregorianCal) == DayOfWeek.sat);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 22)).dayOfGregorianCal) == DayOfWeek.sun);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 23)).dayOfGregorianCal) == DayOfWeek.mon);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 24)).dayOfGregorianCal) == DayOfWeek.tue);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 25)).dayOfGregorianCal) == DayOfWeek.wed);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 26)).dayOfGregorianCal) == DayOfWeek.thu);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 27)).dayOfGregorianCal) == DayOfWeek.fri);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 28)).dayOfGregorianCal) == DayOfWeek.sat);
    assert(getDayOfWeek(SysTime(Date(2010, 8, 29)).dayOfGregorianCal) == DayOfWeek.sun);

    //Test B.C.
    assert(getDayOfWeek(SysTime(Date(0, 12, 31)).dayOfGregorianCal) == DayOfWeek.sun);
    assert(getDayOfWeek(SysTime(Date(0, 12, 30)).dayOfGregorianCal) == DayOfWeek.sat);
    assert(getDayOfWeek(SysTime(Date(0, 12, 29)).dayOfGregorianCal) == DayOfWeek.fri);
    assert(getDayOfWeek(SysTime(Date(0, 12, 28)).dayOfGregorianCal) == DayOfWeek.thu);
    assert(getDayOfWeek(SysTime(Date(0, 12, 27)).dayOfGregorianCal) == DayOfWeek.wed);
    assert(getDayOfWeek(SysTime(Date(0, 12, 26)).dayOfGregorianCal) == DayOfWeek.tue);
    assert(getDayOfWeek(SysTime(Date(0, 12, 25)).dayOfGregorianCal) == DayOfWeek.mon);
    assert(getDayOfWeek(SysTime(Date(0, 12, 24)).dayOfGregorianCal) == DayOfWeek.sun);
    assert(getDayOfWeek(SysTime(Date(0, 12, 23)).dayOfGregorianCal) == DayOfWeek.sat);
}


/+
    Returns the string representation of the given month.
  +/
string monthToString(Month month) @safe pure
{
    import std.format : format;
    assert(month >= Month.jan && month <= Month.dec, format("Invalid month: %s", month));
    return _monthNames[month - Month.jan];
}

unittest
{
    assert(monthToString(Month.jan) == "Jan");
    assert(monthToString(Month.feb) == "Feb");
    assert(monthToString(Month.mar) == "Mar");
    assert(monthToString(Month.apr) == "Apr");
    assert(monthToString(Month.may) == "May");
    assert(monthToString(Month.jun) == "Jun");
    assert(monthToString(Month.jul) == "Jul");
    assert(monthToString(Month.aug) == "Aug");
    assert(monthToString(Month.sep) == "Sep");
    assert(monthToString(Month.oct) == "Oct");
    assert(monthToString(Month.nov) == "Nov");
    assert(monthToString(Month.dec) == "Dec");
}


/+
    Returns the Month corresponding to the given string.

    Params:
        monthStr = The string representation of the month to get the Month for.

    Throws:
        $(LREF DateTimeException) if the given month is not a valid month string.
  +/
Month monthFromString(string monthStr) @safe pure
{
    import std.format : format;
    switch (monthStr)
    {
        case "Jan": return Month.jan;
        case "Feb": return Month.feb;
        case "Mar": return Month.mar;
        case "Apr": return Month.apr;
        case "May": return Month.may;
        case "Jun": return Month.jun;
        case "Jul": return Month.jul;
        case "Aug": return Month.aug;
        case "Sep": return Month.sep;
        case "Oct": return Month.oct;
        case "Nov": return Month.nov;
        case "Dec": return Month.dec;
        default:    throw new DateTimeException(format("Invalid month %s", monthStr));
    }
}

unittest
{
    foreach (badStr; ["Ja", "Janu", "Januar", "Januarys", "JJanuary", "JANUARY",
                     "JAN", "january", "jaNuary", "jaN", "jaNuaRy", "jAn"])
    {
        scope(failure) writeln(badStr);
        assertThrown!DateTimeException(monthFromString(badStr));
    }

    foreach (month; EnumMembers!Month)
    {
        scope(failure) writeln(month);
        assert(monthFromString(monthToString(month)) == month);
    }
}


/+
    The time units which are one step smaller than the given units.
  +/
template nextSmallerTimeUnits(string units)
    if (validTimeUnits(units) &&
       timeStrings.front != units)
{
    import std.algorithm : countUntil;
    enum nextSmallerTimeUnits = timeStrings[countUntil(timeStrings, units) - 1];
}

unittest
{
    assert(nextSmallerTimeUnits!"years" == "months");
    assert(nextSmallerTimeUnits!"months" == "weeks");
    assert(nextSmallerTimeUnits!"weeks" == "days");
    assert(nextSmallerTimeUnits!"days" == "hours");
    assert(nextSmallerTimeUnits!"hours" == "minutes");
    assert(nextSmallerTimeUnits!"minutes" == "seconds");
    assert(nextSmallerTimeUnits!"seconds" == "msecs");
    assert(nextSmallerTimeUnits!"msecs" == "usecs");
    assert(nextSmallerTimeUnits!"usecs" == "hnsecs");
    static assert(!__traits(compiles, nextSmallerTimeUnits!"hnsecs"));
}


/+
    The time units which are one step larger than the given units.
  +/
template nextLargerTimeUnits(string units)
    if (validTimeUnits(units) &&
       timeStrings.back != units)
{
    import std.algorithm : countUntil;
    enum nextLargerTimeUnits = timeStrings[countUntil(timeStrings, units) + 1];
}

unittest
{
    assert(nextLargerTimeUnits!"hnsecs" == "usecs");
    assert(nextLargerTimeUnits!"usecs" == "msecs");
    assert(nextLargerTimeUnits!"msecs" == "seconds");
    assert(nextLargerTimeUnits!"seconds" == "minutes");
    assert(nextLargerTimeUnits!"minutes" == "hours");
    assert(nextLargerTimeUnits!"hours" == "days");
    assert(nextLargerTimeUnits!"days" == "weeks");
    assert(nextLargerTimeUnits!"weeks" == "months");
    assert(nextLargerTimeUnits!"months" == "years");
    static assert(!__traits(compiles, nextLargerTimeUnits!"years"));
}


/+
    Returns the given hnsecs as an ISO string of fractional seconds.
  +/
static string fracSecsToISOString(int hnsecs) @safe pure nothrow
{
    import std.format : format;
    assert(hnsecs >= 0);

    try
    {
        if (hnsecs == 0)
            return "";

        string isoString = format(".%07d", hnsecs);

        while (isoString[$ - 1] == '0')
            isoString.popBack();

        return isoString;
    }
    catch (Exception e)
        assert(0, "format() threw.");
}

unittest
{
    assert(fracSecsToISOString(0) == "");
    assert(fracSecsToISOString(1) == ".0000001");
    assert(fracSecsToISOString(10) == ".000001");
    assert(fracSecsToISOString(100) == ".00001");
    assert(fracSecsToISOString(1000) == ".0001");
    assert(fracSecsToISOString(10_000) == ".001");
    assert(fracSecsToISOString(100_000) == ".01");
    assert(fracSecsToISOString(1_000_000) == ".1");
    assert(fracSecsToISOString(1_000_001) == ".1000001");
    assert(fracSecsToISOString(1_001_001) == ".1001001");
    assert(fracSecsToISOString(1_071_601) == ".1071601");
    assert(fracSecsToISOString(1_271_641) == ".1271641");
    assert(fracSecsToISOString(9_999_999) == ".9999999");
    assert(fracSecsToISOString(9_999_990) == ".999999");
    assert(fracSecsToISOString(9_999_900) == ".99999");
    assert(fracSecsToISOString(9_999_000) == ".9999");
    assert(fracSecsToISOString(9_990_000) == ".999");
    assert(fracSecsToISOString(9_900_000) == ".99");
    assert(fracSecsToISOString(9_000_000) == ".9");
    assert(fracSecsToISOString(999) == ".0000999");
    assert(fracSecsToISOString(9990) == ".000999");
    assert(fracSecsToISOString(99_900) == ".00999");
    assert(fracSecsToISOString(999_000) == ".0999");
}


/+
    Returns a Duration corresponding to to the given ISO string of
    fractional seconds.
  +/
static Duration fracSecsFromISOString(S)(in S isoString) @trusted pure
    if (isSomeString!S)
{
    import std.ascii : isDigit;
    import std.string : representation;
    import std.conv : to;
    import std.algorithm : all;

    if (isoString.empty)
        return Duration.zero;

    auto str = isoString.representation;

    enforce(str[0] == '.', new DateTimeException("Invalid ISO String"));
    str.popFront();

    enforce(!str.empty && str.length <= 7, new DateTimeException("Invalid ISO String"));
    enforce(all!isDigit(str), new DateTimeException("Invalid ISO String"));

    dchar[7] fullISOString = void;
    foreach (i, ref dchar c; fullISOString)
    {
        if (i < str.length)
            c = str[i];
        else
            c = '0';
    }

    return hnsecs(to!int(fullISOString[]));
}

unittest
{
    static void testFSInvalid(string isoString)
    {
        fracSecsFromISOString(isoString);
    }

    assertThrown!DateTimeException(testFSInvalid("."));
    assertThrown!DateTimeException(testFSInvalid("0."));
    assertThrown!DateTimeException(testFSInvalid("0"));
    assertThrown!DateTimeException(testFSInvalid("0000000"));
    assertThrown!DateTimeException(testFSInvalid(".00000000"));
    assertThrown!DateTimeException(testFSInvalid(".00000001"));
    assertThrown!DateTimeException(testFSInvalid("T"));
    assertThrown!DateTimeException(testFSInvalid("T."));
    assertThrown!DateTimeException(testFSInvalid(".T"));

    assert(fracSecsFromISOString("") == Duration.zero);
    assert(fracSecsFromISOString(".0000001") == hnsecs(1));
    assert(fracSecsFromISOString(".000001") == hnsecs(10));
    assert(fracSecsFromISOString(".00001") == hnsecs(100));
    assert(fracSecsFromISOString(".0001") == hnsecs(1000));
    assert(fracSecsFromISOString(".001") == hnsecs(10_000));
    assert(fracSecsFromISOString(".01") == hnsecs(100_000));
    assert(fracSecsFromISOString(".1") == hnsecs(1_000_000));
    assert(fracSecsFromISOString(".1000001") == hnsecs(1_000_001));
    assert(fracSecsFromISOString(".1001001") == hnsecs(1_001_001));
    assert(fracSecsFromISOString(".1071601") == hnsecs(1_071_601));
    assert(fracSecsFromISOString(".1271641") == hnsecs(1_271_641));
    assert(fracSecsFromISOString(".9999999") == hnsecs(9_999_999));
    assert(fracSecsFromISOString(".9999990") == hnsecs(9_999_990));
    assert(fracSecsFromISOString(".999999") == hnsecs(9_999_990));
    assert(fracSecsFromISOString(".9999900") == hnsecs(9_999_900));
    assert(fracSecsFromISOString(".99999") == hnsecs(9_999_900));
    assert(fracSecsFromISOString(".9999000") == hnsecs(9_999_000));
    assert(fracSecsFromISOString(".9999") == hnsecs(9_999_000));
    assert(fracSecsFromISOString(".9990000") == hnsecs(9_990_000));
    assert(fracSecsFromISOString(".999") == hnsecs(9_990_000));
    assert(fracSecsFromISOString(".9900000") == hnsecs(9_900_000));
    assert(fracSecsFromISOString(".9900") == hnsecs(9_900_000));
    assert(fracSecsFromISOString(".99") == hnsecs(9_900_000));
    assert(fracSecsFromISOString(".9000000") == hnsecs(9_000_000));
    assert(fracSecsFromISOString(".9") == hnsecs(9_000_000));
    assert(fracSecsFromISOString(".0000999") == hnsecs(999));
    assert(fracSecsFromISOString(".0009990") == hnsecs(9990));
    assert(fracSecsFromISOString(".000999") == hnsecs(9990));
    assert(fracSecsFromISOString(".0099900") == hnsecs(99_900));
    assert(fracSecsFromISOString(".00999") == hnsecs(99_900));
    assert(fracSecsFromISOString(".0999000") == hnsecs(999_000));
    assert(fracSecsFromISOString(".0999") == hnsecs(999_000));
}


/+
    Strips what RFC 5322, section 3.2.2 refers to as CFWS from the left-hand
    side of the given range (it strips comments delimited by $(D '(') and
    $(D ')') as well as folding whitespace).

    It is assumed that the given range contains the value of a header field and
    no terminating CRLF for the line (though the CRLF for folding whitespace is
    of course expected and stripped) and thus that the only case of CR or LF is
    in folding whitespace.

    If a comment does not terminate correctly (e.g. mismatched parens) or if the
    the FWS is malformed, then the range will be empty when stripCWFS is done.
    However, only minimal validation of the content is done (e.g. quoted pairs
    within a comment aren't validated beyond \$LPAREN or \$RPAREN, because
    they're inside a comment, and thus their value doesn't matter anyway). It's
    only when the content does not conform to the grammar rules for FWS and thus
    literally cannot be parsed that content is considered invalid, and an empty
    range is returned.

    Note that _stripCFWS is eager, not lazy. It does not create a new range.
    Rather, it pops off the CFWS from the range and returns it.
  +/
R _stripCFWS(R)(R range)
    if (isRandomAccessRange!R && hasSlicing!R && hasLength!R &&
       (is(Unqual!(ElementType!R) == char) || is(Unqual!(ElementType!R) == ubyte)))
{
    immutable e = range.length;
    outer: for (size_t i = 0; i < e; )
    {
        switch (range[i])
        {
            case ' ': case '\t':
            {
                ++i;
                break;
            }
            case '\r':
            {
                if (i + 2 < e && range[i + 1] == '\n' && (range[i + 2] == ' ' || range[i + 2] == '\t'))
                {
                    i += 3;
                    break;
                }
                break outer;
            }
            case '\n':
            {
                if (i + 1 < e && (range[i + 1] == ' ' || range[i + 1] == '\t'))
                {
                    i += 2;
                    break;
                }
                break outer;
            }
            case '(':
            {
                ++i;
                size_t commentLevel = 1;
                while (i < e)
                {
                    if (range[i] == '(')
                        ++commentLevel;
                    else if (range[i] == ')')
                    {
                        ++i;
                        if (--commentLevel == 0)
                            continue outer;
                        continue;
                    }
                    else if (range[i] == '\\')
                    {
                        if (++i == e)
                            break outer;
                    }
                    ++i;
                }
                break outer;
            }
            default: return range[i .. e];
        }
    }
    return range[e .. e];
}

unittest
{
    import std.algorithm;
    import std.string;
    import std.typecons;
    import std.typetuple;

    foreach (cr; TypeTuple!(function(string a) { return cast(ubyte[])a; },
                            function(string a) { return map!(b => cast(char)b)(a.representation); }))
    (){ // avoid slow optimizations for large functions @@@BUG@@@ 2396
        scope(failure) writeln(typeof(cr).stringof);

        assert(_stripCFWS(cr("")).empty);
        assert(_stripCFWS(cr("\r")).empty);
        assert(_stripCFWS(cr("\r\n")).empty);
        assert(_stripCFWS(cr("\r\n ")).empty);
        assert(_stripCFWS(cr(" \t\r\n")).empty);
        assert(equal(_stripCFWS(cr(" \t\r\n hello")), cr("hello")));
        assert(_stripCFWS(cr(" \t\r\nhello")).empty);
        assert(_stripCFWS(cr(" \t\r\n\v")).empty);
        assert(equal(_stripCFWS(cr("\v \t\r\n\v")), cr("\v \t\r\n\v")));
        assert(_stripCFWS(cr("()")).empty);
        assert(_stripCFWS(cr("(hello world)")).empty);
        assert(_stripCFWS(cr("(hello world)(hello world)")).empty);
        assert(_stripCFWS(cr("(hello world\r\n foo\r where's\nwaldo)")).empty);
        assert(_stripCFWS(cr(" \t (hello \tworld\r\n foo\r where's\nwaldo)\t\t ")).empty);
        assert(_stripCFWS(cr("      ")).empty);
        assert(_stripCFWS(cr("\t\t\t")).empty);
        assert(_stripCFWS(cr("\t \r\n\r \n")).empty);
        assert(_stripCFWS(cr("(hello world) (can't find waldo) (he's lost)")).empty);
        assert(_stripCFWS(cr("(hello\\) world) (can't \\(find waldo) (he's \\(\\)lost)")).empty);
        assert(_stripCFWS(cr("(((((")).empty);
        assert(_stripCFWS(cr("(((()))")).empty);
        assert(_stripCFWS(cr("(((())))")).empty);
        assert(equal(_stripCFWS(cr("(((()))))")), cr(")")));
        assert(equal(_stripCFWS(cr(")))))")), cr(")))))")));
        assert(equal(_stripCFWS(cr("()))))")), cr("))))")));
        assert(equal(_stripCFWS(cr(" hello hello ")), cr("hello hello ")));
        assert(equal(_stripCFWS(cr("\thello (world)")), cr("hello (world)")));
        assert(equal(_stripCFWS(cr(" \r\n \\((\\))  foo")), cr("\\((\\))  foo")));
        assert(equal(_stripCFWS(cr(" \r\n (\\((\\)))  foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" \r\n (\\(()))  foo")), cr(")  foo")));
        assert(_stripCFWS(cr(" \r\n (((\\)))  foo")).empty);

        assert(_stripCFWS(cr("(hello)(hello)")).empty);
        assert(_stripCFWS(cr(" \r\n (hello)\r\n (hello)")).empty);
        assert(_stripCFWS(cr(" \r\n (hello) \r\n (hello) \r\n ")).empty);
        assert(_stripCFWS(cr("\t\t\t\t(hello)\t\t\t\t(hello)\t\t\t\t")).empty);
        assert(equal(_stripCFWS(cr(" \r\n (hello)\r\n (hello) \r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \r\n (hello) \r\n (hello) \r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr("\t\r\n\t(hello)\r\n\t(hello)\t\r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr("\t\r\n\t(hello)\t\r\n\t(hello)\t\r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \r\n (hello) \r\n \r\n (hello) \r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \r\n (hello) \r\n (hello) \r\n \r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \r\n \r\n (hello)\t\r\n (hello) \r\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \r\n\t\r\n\t(hello)\t\r\n (hello) \r\n hello")), cr("hello")));

        assert(equal(_stripCFWS(cr(" (\r\n ( \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\t\r\n ( \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n\t( \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n (\t\r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n (\r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n (\r\n\t) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n )\t\r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n )\r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n\t) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n ) \r\n foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n )\t\r\n foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n ( \r\n ) \r\n )\r\n foo")), cr("foo")));

        assert(equal(_stripCFWS(cr(" ( \r\n \r\n ( \r\n \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n \r\n ( \r\n \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\t\r\n \r\n ( \r\n \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n \r\n\t( \r\n \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n \r\n( \r\n \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n \r\n ( \r\n \r\n\t) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n \r\n ( \r\n \r\n )\t\r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" (\r\n \r\n ( \r\n \r\n )\r\n ) foo")), cr("foo")));

        assert(equal(_stripCFWS(cr(" ( \r\n bar \r\n ( \r\n bar \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n () \r\n ( \r\n () \r\n ) \r\n ) foo")), cr("foo")));
        assert(equal(_stripCFWS(cr(" ( \r\n \\\\ \r\n ( \r\n \\\\ \r\n ) \r\n ) foo")), cr("foo")));

        assert(_stripCFWS(cr("(hello)(hello)")).empty);
        assert(_stripCFWS(cr(" \n (hello)\n (hello) \n ")).empty);
        assert(_stripCFWS(cr(" \n (hello) \n (hello) \n ")).empty);
        assert(equal(_stripCFWS(cr(" \n (hello)\n (hello) \n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \n (hello) \n (hello) \n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr("\t\n\t(hello)\n\t(hello)\t\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr("\t\n\t(hello)\t\n\t(hello)\t\n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \n (hello) \n \n (hello) \n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \n (hello) \n (hello) \n \n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \n \n (hello)\t\n (hello) \n hello")), cr("hello")));
        assert(equal(_stripCFWS(cr(" \n\t\n\t(hello)\t\n (hello) \n hello")), cr("hello")));
    }();
}

// This is so that we don't have to worry about std.conv.to throwing. It also
// doesn't have to worry about quite as many cases as std.conv.to, since it
// doesn't have to worry about a sign on the value or about whether it fits.
T _convDigits(T, R)(R str)
    if (isIntegral!T && isSigned!T) // The constraints on R were already covered by parseRFC822DateTime.
{
    import std.ascii : isDigit;

    assert(!str.empty);
    T num = 0;
    foreach (i; 0 .. str.length)
    {
        if (i != 0)
            num *= 10;
        if (!std.ascii.isDigit(str[i]))
            return -1;
        num += str[i] - '0';
    }
    return num;
}

unittest
{
    import std.conv : to;
    import std.range;
    foreach (i; chain(iota(0, 101), [250, 999, 1000, 1001, 2345, 9999]))
    {
        scope(failure) writeln(i);
        assert(_convDigits!int(to!string(i)) == i);
    }
    foreach (str; ["-42", "+42", "1a", "1 ", " ", " 42 "])
    {
        scope(failure) writeln(str);
        assert(_convDigits!int(str) == -1);
    }
}


/+
    Whether the given type defines the static property min which returns the
    minimum value for the type.
  +/
enum bool hasMin(T) =
    __traits(hasMember, T, "min") &&
    __traits(isStaticFunction, T.min) &&
    is(typeof(T.min) == Unqual!T);

/+
    Whether the given type defines the static property max which returns the
    maximum value for the type.
  +/
enum bool hasMax(T) =
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
enum bool hasOverloadedOpBinaryWithDuration(T) =
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
enum bool hasOverloadedOpAssignWithDuration(T) =
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
enum bool hasOverloadedOpBinaryWithSelf(T) =
    __traits(compiles, T.init - T.init) &&
    is(Unqual!(typeof(T.init - T.init)) == Duration);

unittest
{
    import std.typetuple : TypeTuple;

    foreach (TP; TypeTuple!(Date, DateTime, TimeOfDay, SysTime))
    {
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
    }
}
