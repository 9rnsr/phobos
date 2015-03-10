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

    Copyright: Copyright 2010 - 2015
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis, Kato Shoichi, and Kenji Hara
    Source:    $(PHOBOSSRC std/_datetime/package.d)
    Macros:
        LREF2=<a href="#$1">$(D $2)</a>
+/
module std.datetime;

public import core.time;

//import std.range.primitives;    //
//import std.traits;              //

//version(Windows)
//{
//    import core.sys.windows.windows;
//    import core.sys.windows.winsock2;
//    import std.windows.registry;
//}
//else version(Posix)
//{
//    import core.sys.posix.stdlib;
//    import core.sys.posix.sys.time;
//}
//
public import std.datetime.timepoint;
public import std.datetime.interval;
public import std.datetime.timezone;
public import std.datetime.conv;
public import std.datetime.util;

//version(unittest)
//{
//    import std.stdio;
//}

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
            import core.sys.windows.windows;

            FILETIME fileTime;
            GetSystemTimeAsFileTime(&fileTime);

            return FILETIMEToStdTime(&fileTime);
        }
        else version(Posix)
        {
            import core.sys.posix.sys.time;

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
