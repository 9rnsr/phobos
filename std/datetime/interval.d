//Written in the D programming language

/++
    Module containing Date/Time functionality.

    Copyright: Copyright 2010 - 2011
    License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors:   Jonathan M Davis and Kato Shoichi
    Source:    $(PHOBOSSRC std/_datetime.d)
    Macros:
        LREF2=<a href="#$1">$(D $2)</a>
+/
module std.datetime.interval;

public import core.time;

import std.datetime;
import std.traits;

version(unittest)
{
    import std.exception : assertThrown;
    import std.range.primitives;
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
    Represents an interval of time.

    An $(D Interval) has a starting point and an end point. The interval of time
    is therefore the time starting at the starting point up to, but not
    including, the end point. e.g.

    $(BOOKTABLE,
    $(TR $(TD [January 5th, 2010 - March 10th, 2010$(RPAREN)))
    $(TR $(TD [05:00:30 - 12:00:00$(RPAREN)))
    $(TR $(TD [1982-01-04T08:59:00 - 2010-07-04T12:00:00$(RPAREN)))
    )

    A range can be obtained from an $(D Interval), allowing iteration over
    that interval, with the exact time points which are iterated over depending
    on the function which generates the range.
  +/
struct Interval(TP)
{
    import std.exception : enforce;
    import std.format : format;

public:

    /++
        Params:
            begin = The time point which begins the interval.
            end   = The time point which ends (but is not included in) the
                    interval.

        Throws:
            $(LREF DateTimeException) if $(D_PARAM end) is before $(D_PARAM begin).

        Examples:
            --------------------
            Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
            --------------------
      +/
    this(U)(in TP begin, in U end) pure
        if (is(Unqual!TP == Unqual!U))
    {
        if (!_valid(begin, end))
            throw new DateTimeException("Arguments would result in an invalid Interval.");

        _begin = cast(TP)begin;
        _end = cast(TP)end;
    }


    /++
        Params:
            begin    = The time point which begins the interval.
            duration = The duration from the starting point to the end point.

        Throws:
            $(LREF DateTimeException) if the resulting $(D end) is before
            $(D begin).

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), dur!"years"(3)) ==
                   Interval!Date(Date(1996, 1, 2), Date(1999, 1, 2)));
            --------------------
      +/
    this(D)(in TP begin, in D duration) pure
        if (__traits(compiles, begin + duration))
    {
        _begin = cast(TP)begin;
        _end = begin + duration;

        if (!_valid(_begin, _end))
            throw new DateTimeException("Arguments would result in an invalid Interval.");
    }


    /++
        Params:
            rhs = The $(LREF2 .Interval, Interval) to assign to this one.
      +/
    ref Interval opAssign(const ref Interval rhs) pure nothrow
    {
        _begin = cast(TP)rhs._begin;
        _end = cast(TP)rhs._end;
        return this;
    }


    /++
        Params:
            rhs = The $(LREF2 .Interval, Interval) to assign to this one.
      +/
    ref Interval opAssign(Interval rhs) pure nothrow
    {
        _begin = cast(TP)rhs._begin;
        _end = cast(TP)rhs._end;
        return this;
    }


    /++
        The starting point of the interval. It is included in the interval.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).begin ==
                   Date(1996, 1, 2));
            --------------------
      +/
    @property TP begin() const pure nothrow
    {
        return cast(TP)_begin;
    }


    /++
        The starting point of the interval. It is included in the interval.

        Params:
            timePoint = The time point to set $(D begin) to.

        Throws:
            $(LREF DateTimeException) if the resulting interval would be invalid.
      +/
    @property void begin(TP timePoint) pure
    {
        if (!_valid(timePoint, _end))
            throw new DateTimeException("Arguments would result in an invalid Interval.");

        _begin = timePoint;
    }


    /++
        The end point of the interval. It is excluded from the interval.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).end ==
                   Date(2012, 3, 1));
            --------------------
      +/
    @property TP end() const pure nothrow
    {
        return cast(TP)_end;
    }


    /++
        The end point of the interval. It is excluded from the interval.

        Params:
            timePoint = The time point to set end to.

        Throws:
            $(LREF DateTimeException) if the resulting interval would be invalid.
      +/
    @property void end(TP timePoint) pure
    {
        if (!_valid(_begin, timePoint))
            throw new DateTimeException("Arguments would result in an invalid Interval.");

        _end = timePoint;
    }


    /++
        Returns the duration between $(D begin) and $(D end).

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).length ==
                   dur!"days"(5903));
            --------------------
      +/
    @property auto length() const pure nothrow
    {
        return _end - _begin;
    }


    /++
        Whether the interval's length is 0, that is, whether $(D begin == end).

        Examples:
            --------------------
            assert( Interval!Date(Date(1996, 1, 2), Date(1996, 1, 2)).empty);
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).empty);
            --------------------
      +/
    @property bool empty() const pure nothrow
    {
        return _begin == _end;
    }


    /++
        Whether the given time point is within this interval.

        Params:
            timePoint = The time point to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1))
                   .contains(Date(1994, 12, 24)) == false);

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1))
                   .contains(Date(2000, 1, 5)) == true);
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1))
                   .contains(Date(2012, 3, 1)) == false);
            --------------------
      +/
    bool contains(in TP timePoint) const pure
    {
        _enforceNotEmpty();

        return timePoint >= _begin && timePoint < _end;
    }


    /++
        Whether the given interval is completely within this interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(
                        Interval!Date(Date(1998, 2, 28), Date(2013, 5, 1))));
            --------------------
      +/
    bool contains(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        return interval._begin >= _begin &&
               interval._begin < _end &&
               interval._end <= _end;
    }


    /++
        Whether the given interval is completely within this interval.

        Always returns false (unless this interval is empty), because an
        interval going to positive infinity can never be contained in a finite
        interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(
                        PosInfInterval!Date(Date(1999, 5, 4))));
            --------------------
      +/
    bool contains(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return false;
    }


    /++
        Whether the given interval is completely within this interval.

        Always returns false (unless this interval is empty), because an
        interval beginning at negative infinity can never be contained in a
        finite interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(
                        NegInfInterval!Date(Date(1996, 5, 4))));
            --------------------
      +/
    bool contains(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return false;
    }


    /++
        Whether this interval is before the given time point.

        Params:
            timePoint = The time point to check whether this interval is before
                        it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Date(1994, 12, 24)));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Date(2000, 1, 5)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Date(2012, 3, 1)));
            --------------------
      +/
    bool isBefore(in TP timePoint) const pure
    {
        _enforceNotEmpty();

        return _end <= timePoint;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect with it.

        Params:
            interval = The interval to check for against this interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        Interval!Date(Date(2012, 3, 1), Date(2013, 5, 1))));
            --------------------
      +/
    bool isBefore(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        return _end <= interval._begin;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect with it.

        Params:
            interval = The interval to check for against this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        PosInfInterval!Date(Date(1999, 5, 4))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        PosInfInterval!Date(Date(2013, 3, 7))));
            --------------------
      +/
    bool isBefore(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _end <= interval._begin;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect with it.

        Always returns false (unless this interval is empty) because a finite
        interval can never be before an interval beginning at negative infinity.

        Params:
            interval = The interval to check for against this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(
                        NegInfInterval!Date(Date(1996, 5, 4))));
            --------------------
      +/
    bool isBefore(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return false;
    }


    /++
        Whether this interval is after the given time point.

        Params:
            timePoint = The time point to check whether this interval is after
                        it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Date(1994, 12, 24)));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Date(2000, 1, 5)));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Date(2012, 3, 1)));
            --------------------
      +/
    bool isAfter(in TP timePoint) const pure
    {
        _enforceNotEmpty();

        return timePoint < _begin;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Params:
            interval = The interval to check against this interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));
            --------------------
      +/
    bool isAfter(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        return _begin >= interval._end;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Always returns false (unless this interval is empty) because a finite
        interval can never be after an interval going to positive infinity.

        Params:
            interval = The interval to check against this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        PosInfInterval!Date(Date(1999, 5, 4))));
            --------------------
      +/
    bool isAfter(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return false;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Params:
            interval = The interval to check against this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(
                        NegInfInterval!Date(Date(1996, 1, 2))));
            --------------------
      +/
    bool isAfter(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _begin >= interval._end;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));
            --------------------
      +/
    bool intersects(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        return interval._begin < _end && interval._end > _begin;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        PosInfInterval!Date(Date(1999, 5, 4))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        PosInfInterval!Date(Date(2012, 3, 1))));
            --------------------
      +/
    bool intersects(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _end > interval._begin;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        NegInfInterval!Date(Date(1996, 1, 2))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(
                        NegInfInterval!Date(Date(2000, 1, 2))));
            --------------------
      +/
    bool intersects(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _begin < interval._end;
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect or if
            either interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2000, 8, 2)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) ==
                   Interval!Date(Date(1999, 1 , 12), Date(2011, 9, 17)));
            --------------------
      +/
    Interval intersection(in Interval interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        auto begin = _begin > interval._begin ? _begin : interval._begin;
        auto end = _end < interval._end ? _end : interval._end;

        return Interval(begin, end);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect or if
            this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2012, 3, 1)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        PosInfInterval!Date(Date(1999, 1, 12))) ==
                   Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));
            --------------------
      +/
    Interval intersection(in PosInfInterval!TP interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        return Interval(_begin > interval._begin ? _begin : interval._begin, _end);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect or if
            this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        NegInfInterval!Date(Date(1999, 7, 6))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(1999, 7, 6)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(
                        NegInfInterval!Date(Date(2013, 1, 12))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2012, 3, 1)));
            --------------------
      +/
    Interval intersection(in NegInfInterval!TP interval) const
    {
        enforce(this.intersects(interval),
                new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        return Interval(_begin, _end < interval._end ? _end : interval._end);
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        Interval!Date(Date(1990, 7, 6), Date(1996, 1, 2))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        Interval!Date(Date(2012, 3, 1), Date(2013, 9, 17))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        Interval!Date(Date(1989, 3, 1), Date(2012, 3, 1))));
            --------------------
      +/
    bool isAdjacent(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        return _begin == interval._end || _end == interval._begin;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        PosInfInterval!Date(Date(1999, 5, 4))));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        PosInfInterval!Date(Date(2012, 3, 1))));
            --------------------
      +/
    bool isAdjacent(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _end == interval._begin;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        NegInfInterval!Date(Date(1996, 1, 2))));

            assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(
                        NegInfInterval!Date(Date(2000, 1, 2))));
            --------------------
      +/
    bool isAdjacent(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return _begin == interval._end;
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect and are
            not adjacent or if either interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
                   Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        Interval!Date(Date(2012, 3, 1), Date(2013, 5, 7))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2013, 5, 7)));
            --------------------
      +/
    Interval merge(in Interval interval) const
    {
        enforce(this.isAdjacent(interval) || this.intersects(interval),
                new DateTimeException(format("%s and %s are not adjacent and do not intersect.", this, interval)));

        auto begin = _begin < interval._begin ? _begin : interval._begin;
        auto end = _end > interval._end ? _end : interval._end;

        return Interval(begin, end);
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect and are
            not adjacent or if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        PosInfInterval!Date(Date(2012, 3, 1))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval!TP merge(in PosInfInterval!TP interval) const
    {
        enforce(this.isAdjacent(interval) || this.intersects(interval),
                new DateTimeException(format("%s and %s are not adjacent and do not intersect.", this, interval)));

        return PosInfInterval!TP(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect and are not
            adjacent or if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        NegInfInterval!Date(Date(1996, 1, 2))) ==
                   NegInfInterval!Date(Date(2012, 3 , 1)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(
                        NegInfInterval!Date(Date(2013, 1, 12))) ==
                   NegInfInterval!Date(Date(2013, 1 , 12)));
            --------------------
      +/
    NegInfInterval!TP merge(in NegInfInterval!TP interval) const
    {
        enforce(this.isAdjacent(interval) || this.intersects(interval),
                new DateTimeException(format("%s and %s are not adjacent and do not intersect.", this, interval)));

        return NegInfInterval!TP(_end > interval._end ? _end : interval._end);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this interval.

        Throws:
            $(LREF DateTimeException) if either interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        Interval!Date(Date(1990, 7, 6), Date(1991, 1, 8))) ==
                   Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        Interval!Date(Date(2012, 3, 1), Date(2013, 5, 7))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2013, 5, 7)));
            --------------------
      +/
    Interval span(in Interval interval) const pure
    {
        _enforceNotEmpty();
        interval._enforceNotEmpty();

        auto begin = _begin < interval._begin ? _begin : interval._begin;
        auto end = _end > interval._end ? _end : interval._end;

        return Interval(begin, end);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        PosInfInterval!Date(Date(2050, 1, 1))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval!TP span(in PosInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return PosInfInterval!TP(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this interval.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Examples:
            --------------------
            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        NegInfInterval!Date(Date(1602, 5, 21))) ==
                   NegInfInterval!Date(Date(2012, 3 , 1)));

            assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(
                        NegInfInterval!Date(Date(2013, 1, 12))) ==
                   NegInfInterval!Date(Date(2013, 1 , 12)));
            --------------------
      +/
    NegInfInterval!TP span(in NegInfInterval!TP interval) const pure
    {
        _enforceNotEmpty();

        return NegInfInterval!TP(_end > interval._end ? _end : interval._end);
    }


    /++
        Shifts the interval forward or backwards in time by the given duration
        (a positive duration shifts the interval forward; a negative duration
        shifts it backward). Effectively, it does $(D begin += duration) and
        $(D end += duration).

        Params:
            duration = The duration to shift the interval by.

        Throws:
            $(LREF DateTimeException) this interval is empty or if the resulting
            interval would be invalid.

        Examples:
            --------------------
            auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 4, 5));
            auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 4, 5));

            interval1.shift(dur!"days"(50));
            assert(interval1 == Interval!Date(Date(1996, 2, 21), Date(2012, 5, 25)));

            interval2.shift(dur!"days"(-50));
            assert(interval2 == Interval!Date(Date(1995, 11, 13), Date(2012, 2, 15)));
            --------------------
      +/
    void shift(D)(D duration) pure
        if (__traits(compiles, begin + duration))
    {
        _enforceNotEmpty();

        auto begin = _begin + duration;
        auto end = _end + duration;

        if (!_valid(begin, end))
            throw new DateTimeException("Argument would result in an invalid Interval.");

        _begin = begin;
        _end = end;
    }


    static if (__traits(compiles, begin.add!"months"(1)) &&
              __traits(compiles, begin.add!"years"(1)))
    {
        /++
            Shifts the interval forward or backwards in time by the given number
            of years and/or months (a positive number of years and months shifts
            the interval forward; a negative number shifts it backward).
            It adds the years the given years and months to both begin and end.
            It effectively calls $(D add!"years"()) and then $(D add!"months"())
            on begin and end with the given number of years and months.

            Params:
                years         = The number of years to shift the interval by.
                months        = The number of months to shift the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D begin) and $(D end), causing their month
                                to increment.

            Throws:
                $(LREF DateTimeException) if this interval is empty or if the
                resulting interval would be invalid.

            Examples:
                --------------------
                auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
                auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

                interval1.shift(2);
                assert(interval1 == Interval!Date(Date(1998, 1, 2), Date(2014, 3, 1)));

                interval2.shift(-2);
                assert(interval2 == Interval!Date(Date(1994, 1, 2), Date(2010, 3, 1)));
                --------------------
          +/
        void shift(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes)
            if (isIntegral!T)
        {
            _enforceNotEmpty();

            auto begin = _begin;
            auto end = _end;

            begin.add!"years"(years, allowOverflow);
            begin.add!"months"(months, allowOverflow);
            end.add!"years"(years, allowOverflow);
            end.add!"months"(months, allowOverflow);

            enforce(_valid(begin, end), new DateTimeException("Argument would result in an invalid Interval."));

            _begin = begin;
            _end = end;
        }
    }


    /++
        Expands the interval forwards and/or backwards in time. Effectively,
        it does $(D begin -= duration) and/or $(D end += duration). Whether
        it expands forwards and/or backwards in time is determined by
        $(D_PARAM dir).

        Params:
            duration = The duration to expand the interval by.
            dir      = The direction in time to expand the interval.

        Throws:
            $(LREF DateTimeException) this interval is empty or if the resulting
            interval would be invalid.

        Examples:
            --------------------
            auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
            auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

            interval1.expand(2);
            assert(interval1 == Interval!Date(Date(1994, 1, 2), Date(2014, 3, 1)));

            interval2.expand(-2);
            assert(interval2 == Interval!Date(Date(1998, 1, 2), Date(2010, 3, 1)));
            --------------------
      +/
    void expand(D)(D duration, Direction dir = Direction.both) pure
        if (__traits(compiles, begin + duration))
    {
        _enforceNotEmpty();

        switch (dir)
        {
            case Direction.both:
            {
                auto begin = _begin - duration;
                auto end = _end + duration;

                if (!_valid(begin, end))
                    throw new DateTimeException("Argument would result in an invalid Interval.");

                _begin = begin;
                _end = end;

                return;
            }
            case Direction.fwd:
            {
                auto end = _end + duration;

                if (!_valid(_begin, end))
                    throw new DateTimeException("Argument would result in an invalid Interval.");
                _end = end;

                return;
            }
            case Direction.bwd:
            {
                auto begin = _begin - duration;

                if (!_valid(begin, _end))
                    throw new DateTimeException("Argument would result in an invalid Interval.");
                _begin = begin;

                return;
            }
            default:
                assert(0, "Invalid Direction.");
        }
    }

    static if (__traits(compiles, begin.add!"months"(1)) &&
              __traits(compiles, begin.add!"years"(1)))
    {
        /++
            Expands the interval forwards and/or backwards in time. Effectively,
            it subtracts the given number of months/years from $(D begin) and
            adds them to $(D end). Whether it expands forwards and/or backwards
            in time is determined by $(D_PARAM dir).

            Params:
                years         = The number of years to expand the interval by.
                months        = The number of months to expand the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D begin) and $(D end), causing their month
                                to increment.
                dir           = The direction in time to expand the interval.

            Throws:
                $(LREF DateTimeException) if this interval is empty or if the
                resulting interval would be invalid.

            Examples:
                --------------------
                auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
                auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

                interval1.expand(2);
                assert(interval1 == Interval!Date(Date(1994, 1, 2), Date(2014, 3, 1)));

                interval2.expand(-2);
                assert(interval2 == Interval!Date(Date(1998, 1, 2), Date(2010, 3, 1)));
                --------------------
          +/
        void expand(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes, Direction dir = Direction.both)
            if (isIntegral!T)
        {
            _enforceNotEmpty();

            switch (dir)
            {
                case Direction.both:
                {
                    auto begin = _begin;
                    auto end = _end;

                    begin.add!"years"(-years, allowOverflow);
                    begin.add!"months"(-months, allowOverflow);
                    end.add!"years"(years, allowOverflow);
                    end.add!"months"(months, allowOverflow);

                    enforce(_valid(begin, end), new DateTimeException("Argument would result in an invalid Interval."));
                    _begin = begin;
                    _end = end;

                    return;
                }
                case Direction.fwd:
                {
                    auto end = _end;

                    end.add!"years"(years, allowOverflow);
                    end.add!"months"(months, allowOverflow);

                    enforce(_valid(_begin, end), new DateTimeException("Argument would result in an invalid Interval."));
                    _end = end;

                    return;
                }
                case Direction.bwd:
                {
                    auto begin = _begin;

                    begin.add!"years"(-years, allowOverflow);
                    begin.add!"months"(-months, allowOverflow);

                    enforce(_valid(begin, _end), new DateTimeException("Argument would result in an invalid Interval."));
                    _begin = begin;

                    return;
                }
                default:
                    assert(0, "Invalid Direction.");
            }
        }
    }


    /++
        Returns a range which iterates forward over the interval, starting
        at $(D begin), using $(D_PARAM func) to generate each successive time
        point.

        The range's $(D front) is the interval's $(D begin). $(D_PARAM func) is
        used to generate the next $(D front) when $(D popFront) is called. If
        $(D_PARAM popFirst) is $(D PopFirst.yes), then $(D popFront) is called
        before the range is returned (so that $(D front) is a time point which
        $(D_PARAM func) would generate).

        If $(D_PARAM func) ever generates a time point less than or equal to the
        current $(D front) of the range, then a $(LREF DateTimeException) will be
        thrown. The range will be empty and iteration complete when
        $(D_PARAM func) generates a time point equal to or beyond the $(D end)
        of the interval.

        There are helper functions in this module which generate common
        delegates to pass to $(D fwdRange). Their documentation starts with
        "Range-generating function," making them easily searchable.

        Params:
            func     = The function used to generate the time points of the
                       range over the interval.
            popFirst = Whether $(D popFront) should be called on the range
                       before returning it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Warning:
            $(D_PARAM func) must be logically pure. Ideally, $(D_PARAM func)
            would be a function pointer to a pure function, but forcing
            $(D_PARAM func) to be pure is far too restrictive to be useful, and
            in order to have the ease of use of having functions which generate
            functions to pass to $(D fwdRange), $(D_PARAM func) must be a
            delegate.

            If $(D_PARAM func) retains state which changes as it is called, then
            some algorithms will not work correctly, because the range's
            $(D save) will have failed to have really saved the range's state.
            To avoid such bugs, don't pass a delegate which is
            not logically pure to $(D fwdRange). If $(D_PARAM func) is given the
            same time point with two different calls, it must return the same
            result both times.

            Of course, none of the functions in this module have this problem,
            so it's only relevant if when creating a custom delegate.

        Examples:
            --------------------
            auto interval = Interval!Date(Date(2010, 9, 1), Date(2010, 9, 9));
            auto func = (in Date date) //For iterating over even-numbered days.
                        {
                            if ((date.day & 1) == 0)
                                return date + dur!"days"(2);

                            return date + dur!"days"(1);
                        };
            auto range = interval.fwdRange(func);

             //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 2).
            assert(range.front == Date(2010, 9, 1));

            range.popFront();
            assert(range.front == Date(2010, 9, 2));

            range.popFront();
            assert(range.front == Date(2010, 9, 4));

            range.popFront();
            assert(range.front == Date(2010, 9, 6));

            range.popFront();
            assert(range.front == Date(2010, 9, 8));

            range.popFront();
            assert(range.empty);
            --------------------
      +/
    IntervalRange!(TP, Direction.fwd) fwdRange(TP delegate(in TP) func, PopFirst popFirst = PopFirst.no) const
    {
        _enforceNotEmpty();

        auto range = IntervalRange!(TP, Direction.fwd)(this, func);

        if (popFirst == PopFirst.yes)
            range.popFront();

        return range;
    }


    /++
        Returns a range which iterates backwards over the interval, starting
        at $(D end), using $(D_PARAM func) to generate each successive time
        point.

        The range's $(D front) is the interval's $(D end). $(D_PARAM func) is
        used to generate the next $(D front) when $(D popFront) is called. If
        $(D_PARAM popFirst) is $(D PopFirst.yes), then $(D popFront) is called
        before the range is returned (so that $(D front) is a time point which
        $(D_PARAM func) would generate).

        If $(D_PARAM func) ever generates a time point greater than or equal to
        the current $(D front) of the range, then a $(LREF DateTimeException) will
        be thrown. The range will be empty and iteration complete when
        $(D_PARAM func) generates a time point equal to or less than the
        $(D begin) of the interval.

        There are helper functions in this module which generate common
        delegates to pass to $(D bwdRange). Their documentation starts with
        "Range-generating function," making them easily searchable.

        Params:
            func     = The function used to generate the time points of the
                       range over the interval.
            popFirst = Whether $(D popFront) should be called on the range
                       before returning it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Warning:
            $(D_PARAM func) must be logically pure. Ideally, $(D_PARAM func)
            would be a function pointer to a pure function, but forcing
            $(D_PARAM func) to be pure is far too restrictive to be useful, and
            in order to have the ease of use of having functions which generate
            functions to pass to $(D fwdRange), $(D_PARAM func) must be a
            delegate.

            If $(D_PARAM func) retains state which changes as it is called, then
            some algorithms will not work correctly, because the range's
            $(D save) will have failed to have really saved the range's state.
            To avoid such bugs, don't pass a delegate which is
            not logically pure to $(D fwdRange). If $(D_PARAM func) is given the
            same time point with two different calls, it must return the same
            result both times.

            Of course, none of the functions in this module have this problem,
            so it's only relevant for custom delegates.

        Examples:
            --------------------
            auto interval = Interval!Date(Date(2010, 9, 1), Date(2010, 9, 9));
            auto func = (in Date date) //For iterating over even-numbered days.
                        {
                            if ((date.day & 1) == 0)
                                return date - dur!"days"(2);

                            return date - dur!"days"(1);
                        };
            auto range = interval.bwdRange(func);

            //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 8).
            assert(range.front == Date(2010, 9, 9));

            range.popFront();
            assert(range.front == Date(2010, 9, 8));

            range.popFront();
            assert(range.front == Date(2010, 9, 6));

            range.popFront();
            assert(range.front == Date(2010, 9, 4));

            range.popFront();
            assert(range.front == Date(2010, 9, 2));

            range.popFront();
            assert(range.empty);
            --------------------
      +/
    IntervalRange!(TP, Direction.bwd) bwdRange(TP delegate(in TP) func, PopFirst popFirst = PopFirst.no) const
    {
        _enforceNotEmpty();

        auto range = IntervalRange!(TP, Direction.bwd)(this, func);

        if (popFirst == PopFirst.yes)
            range.popFront();

        return range;
    }


    /+
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString()
    {
        return _toStringImpl();
    }


    /++
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString() const nothrow
    {
        return _toStringImpl();
    }


private:

    /+
        Since we have two versions of toString, we have _toStringImpl
        so that they can share implementations.
      +/
    string _toStringImpl() const nothrow
    {
        try
            return format("[%s - %s)", _begin, _end);
        catch (Exception e)
            assert(0, "format() threw.");
    }


    /+
        Throws:
            $(LREF DateTimeException) if this interval is empty.
      +/
    void _enforceNotEmpty(size_t line = __LINE__) const pure
    {
        if (empty)
            throw new DateTimeException("Invalid operation for an empty Interval.", __FILE__, line);
    }


    /+
        Whether the given values form a valid time interval.

        Params:
            begin = The starting point of the interval.
            end   = The end point of the interval.
     +/
    static bool _valid(in TP begin, in TP end) pure nothrow
    {
        return begin <= end;
    }


    pure invariant()
    {
        assert(_valid(_begin, _end), "Invariant Failure: begin is not before or equal to end.");
    }


    TP _begin;
    TP _end;
}

//Test Interval's constructors.
unittest
{
    assertThrown!DateTimeException(Interval!Date(Date(2010, 1, 1), Date(1, 1, 1)));

    Interval!Date(Date.init, Date.init);
    Interval!TimeOfDay(TimeOfDay.init, TimeOfDay.init);
    Interval!DateTime(DateTime.init, DateTime.init);
    Interval!SysTime(SysTime(0), SysTime(0));

    Interval!DateTime(DateTime.init, dur!"days"(7));

    //Verify Examples.
    Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
    assert(Interval!Date(Date(1996, 1, 2), dur!"weeks"(3)) == Interval!Date(Date(1996, 1, 2), Date(1996, 1, 23)));
    assert(Interval!Date(Date(1996, 1, 2), dur!"days"(3)) == Interval!Date(Date(1996, 1, 2), Date(1996, 1, 5)));
    assert(Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), dur!"hours"(3))    == Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), DateTime(1996, 1, 2, 15, 0, 0)));
    assert(Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), dur!"minutes"(3))  == Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), DateTime(1996, 1, 2, 12, 3, 0)));
    assert(Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), dur!"seconds"(3))  == Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), DateTime(1996, 1, 2, 12, 0, 3)));
    assert(Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), dur!"msecs"(3000)) == Interval!DateTime(DateTime(1996, 1, 2, 12, 0, 0), DateTime(1996, 1, 2, 12, 0, 3)));
}

//Test Interval's begin.
unittest
{
    assert(Interval!Date(Date(1, 1, 1), Date(2010, 1, 1)).begin == Date(1, 1, 1));
    assert(Interval!Date(Date(2010, 1, 1), Date(2010, 1, 1)).begin == Date(2010, 1, 1));
    assert(Interval!Date(Date(1997, 12, 31), Date(1998, 1, 1)).begin == Date(1997, 12, 31));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.begin));
    static assert(__traits(compiles, iInterval.begin));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).begin == Date(1996, 1, 2));
}

//Test Interval's end.
unittest
{
    assert(Interval!Date(Date(1, 1, 1), Date(2010, 1, 1)).end == Date(2010, 1, 1));
    assert(Interval!Date(Date(2010, 1, 1), Date(2010, 1, 1)).end == Date(2010, 1, 1));
    assert(Interval!Date(Date(1997, 12, 31), Date(1998, 1, 1)).end == Date(1998, 1, 1));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.end));
    static assert(__traits(compiles, iInterval.end));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).end == Date(2012, 3, 1));
}

//Test Interval's length.
unittest
{
    assert(Interval!Date(Date(2010, 1, 1), Date(2010, 1, 1)).length == dur!"days"(0));
    assert(Interval!Date(Date(2010, 1, 1), Date(2010, 4, 1)).length == dur!"days"(90));
    assert(Interval!TimeOfDay(TimeOfDay(0, 30, 0), TimeOfDay(12, 22, 7)).length == dur!"seconds"(42_727));
    assert(Interval!DateTime(DateTime(2010, 1, 1, 0, 30, 0), DateTime(2010, 1, 2, 12, 22, 7)).length == dur!"seconds"(129_127));
    assert(Interval!SysTime(SysTime(DateTime(2010, 1, 1, 0, 30, 0)), SysTime(DateTime(2010, 1, 2, 12, 22, 7))).length == dur!"seconds"(129_127));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.length));
    static assert(__traits(compiles, iInterval.length));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).length == dur!"days"(5903));
}

//Test Interval's empty.
unittest
{
    assert(Interval!Date(Date(2010, 1, 1), Date(2010, 1, 1)).empty);
    assert(!Interval!Date(Date(2010, 1, 1), Date(2010, 4, 1)).empty);
    assert(!Interval!TimeOfDay(TimeOfDay(0, 30, 0), TimeOfDay(12, 22, 7)).empty);
    assert(!Interval!DateTime(DateTime(2010, 1, 1, 0, 30, 0), DateTime(2010, 1, 2, 12, 22, 7)).empty);
    assert(!Interval!SysTime(SysTime(DateTime(2010, 1, 1, 0, 30, 0)), SysTime(DateTime(2010, 1, 2, 12, 22, 7))).empty);

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.empty));
    static assert(__traits(compiles, iInterval.empty));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(1996, 1, 2)).empty);
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).empty);
}

//Test Interval's contains(time point).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).contains(Date(2010, 7, 4)));

    assert(!interval.contains(Date(2009, 7, 4)));
    assert(!interval.contains(Date(2010, 7, 3)));
    assert( interval.contains(Date(2010, 7, 4)));
    assert( interval.contains(Date(2010, 7, 5)));
    assert( interval.contains(Date(2011, 7, 1)));
    assert( interval.contains(Date(2012, 1, 6)));
    assert(!interval.contains(Date(2012, 1, 7)));
    assert(!interval.contains(Date(2012, 1, 8)));
    assert(!interval.contains(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, interval.contains(cdate)));
    static assert(__traits(compiles, cInterval.contains(cdate)));
    static assert(__traits(compiles, iInterval.contains(cdate)));

    //Verify Examples.
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Date(1994, 12, 24)));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Date(2000, 1, 5)));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Date(2012, 3, 1)));
}

//Test Interval's contains(Interval).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(interval.contains(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).contains(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).contains(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(interval.contains(interval));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!interval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert( interval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert( interval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert( interval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!interval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!interval.contains(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!interval.contains(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).contains(interval));
    assert( Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).contains(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).contains(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).contains(interval));
    assert( Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).contains(interval));
    assert( Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).contains(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).contains(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).contains(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).contains(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).contains(interval));
    assert(!Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).contains(interval));
    assert(!Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).contains(interval));

    assert(!interval.contains(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.contains(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.contains(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.contains(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.contains(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.contains(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!interval.contains(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.contains(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.contains(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.contains(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.contains(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.contains(NegInfInterval!Date(Date(2012, 1, 8))));

        const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
          auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
        const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
          auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
        const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.contains(interval)));
    static assert(__traits(compiles, interval.contains(cInterval)));
    static assert(__traits(compiles, interval.contains(iInterval)));
    static assert(__traits(compiles, interval.contains(posInfInterval)));
    static assert(__traits(compiles, interval.contains(cPosInfInterval)));
    static assert(__traits(compiles, interval.contains(iPosInfInterval)));
    static assert(__traits(compiles, interval.contains(negInfInterval)));
    static assert(__traits(compiles, interval.contains(cNegInfInterval)));
    static assert(__traits(compiles, interval.contains(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.contains(interval)));
    static assert(__traits(compiles, cInterval.contains(cInterval)));
    static assert(__traits(compiles, cInterval.contains(iInterval)));
    static assert(__traits(compiles, cInterval.contains(posInfInterval)));
    static assert(__traits(compiles, cInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.contains(negInfInterval)));
    static assert(__traits(compiles, cInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.contains(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.contains(interval)));
    static assert(__traits(compiles, iInterval.contains(cInterval)));
    static assert(__traits(compiles, iInterval.contains(iInterval)));
    static assert(__traits(compiles, iInterval.contains(posInfInterval)));
    static assert(__traits(compiles, iInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.contains(negInfInterval)));
    static assert(__traits(compiles, iInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.contains(iNegInfInterval)));

    //Verify Examples.
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Interval!Date(Date(1990, 7,  6), Date(2000, 8,  2))));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(Interval!Date(Date(1998, 2, 28), Date(2013, 5,  1))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(PosInfInterval!Date(Date(1999, 5, 4))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).contains(NegInfInterval!Date(Date(1996, 5, 4))));
}

//Test Interval's isBefore(time point).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isBefore(Date(2010, 7, 4)));

    assert(!interval.isBefore(Date(2009, 7, 3)));
    assert(!interval.isBefore(Date(2010, 7, 3)));
    assert(!interval.isBefore(Date(2010, 7, 4)));
    assert(!interval.isBefore(Date(2010, 7, 5)));
    assert(!interval.isBefore(Date(2011, 7, 1)));
    assert(!interval.isBefore(Date(2012, 1, 6)));
    assert( interval.isBefore(Date(2012, 1, 7)));
    assert( interval.isBefore(Date(2012, 1, 8)));
    assert( interval.isBefore(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, interval.isBefore(cdate)));
    static assert(__traits(compiles, cInterval.isBefore(cdate)));
    static assert(__traits(compiles, iInterval.isBefore(cdate)));

    //Verify Examples.
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Date(1994, 12, 24)));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Date(2000, 1, 5)));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Date(2012, 3, 1)));
}

//Test Interval's isBefore(Interval).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(interval.isBefore(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isBefore(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isBefore(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!interval.isBefore(interval));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!interval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!interval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!interval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert( interval.isBefore(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert( interval.isBefore(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert( Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).isBefore(interval));
    assert( Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).isBefore(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).isBefore(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).isBefore(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).isBefore(interval));
    assert(!Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).isBefore(interval));
    assert(!Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).isBefore(interval));

    assert(!interval.isBefore(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.isBefore(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isBefore(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isBefore(PosInfInterval!Date(Date(2012, 1, 6))));
    assert( interval.isBefore(PosInfInterval!Date(Date(2012, 1, 7))));
    assert( interval.isBefore(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!interval.isBefore(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.isBefore(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isBefore(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isBefore(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.isBefore(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.isBefore(NegInfInterval!Date(Date(2012, 1, 8))));

        const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
          auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
        const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
          auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
        const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles,  interval.isBefore(interval)));
    static assert(__traits(compiles,  interval.isBefore(cInterval)));
    static assert(__traits(compiles,  interval.isBefore(iInterval)));
    static assert(__traits(compiles,  interval.isBefore(posInfInterval)));
    static assert(__traits(compiles,  interval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles,  interval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles,  interval.isBefore(negInfInterval)));
    static assert(__traits(compiles,  interval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles,  interval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(interval)));
    static assert(__traits(compiles, cInterval.isBefore(cInterval)));
    static assert(__traits(compiles, cInterval.isBefore(iInterval)));
    static assert(__traits(compiles, cInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(interval)));
    static assert(__traits(compiles, iInterval.isBefore(cInterval)));
    static assert(__traits(compiles, iInterval.isBefore(iInterval)));
    static assert(__traits(compiles, iInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.isBefore(iNegInfInterval)));

    //Verify Examples.
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Interval!Date(Date(1990, 7,  6), Date(2000, 8,  2))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(Interval!Date(Date(2012, 3,  1), Date(2013, 5,  1))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(PosInfInterval!Date(Date(1999, 5, 4))));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(PosInfInterval!Date(Date(2013, 3, 7))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isBefore(NegInfInterval!Date(Date(1996, 5, 4))));
}

//Test Interval's isAfter(time point).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isAfter(Date(2010, 7, 4)));

    assert( interval.isAfter(Date(2009, 7, 4)));
    assert( interval.isAfter(Date(2010, 7, 3)));
    assert(!interval.isAfter(Date(2010, 7, 4)));
    assert(!interval.isAfter(Date(2010, 7, 5)));
    assert(!interval.isAfter(Date(2011, 7, 1)));
    assert(!interval.isAfter(Date(2012, 1, 6)));
    assert(!interval.isAfter(Date(2012, 1, 7)));
    assert(!interval.isAfter(Date(2012, 1, 8)));
    assert(!interval.isAfter(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
        const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, interval.isAfter(cdate)));
    static assert(__traits(compiles, cInterval.isAfter(cdate)));
    static assert(__traits(compiles, iInterval.isAfter(cdate)));

    //Verify Examples.
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Date(1994, 12, 24)));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Date(2000, 1, 5)));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Date(2012, 3, 1)));
}

//Test Interval's isAfter(Interval).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(interval.isAfter(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isAfter(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).isAfter(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!interval.isAfter(interval));
    assert( interval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert( interval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!interval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!interval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!interval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!interval.isAfter(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!interval.isAfter(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).isAfter(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).isAfter(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).isAfter(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).isAfter(interval));
    assert( Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).isAfter(interval));
    assert( Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).isAfter(interval));

    assert(!interval.isAfter(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.isAfter(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isAfter(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isAfter(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.isAfter(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.isAfter(PosInfInterval!Date(Date(2012, 1, 8))));

    assert( interval.isAfter(NegInfInterval!Date(Date(2010, 7, 3))));
    assert( interval.isAfter(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isAfter(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isAfter(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.isAfter(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.isAfter(NegInfInterval!Date(Date(2012, 1, 8))));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles,  interval.isAfter(interval)));
    static assert(__traits(compiles,  interval.isAfter(cInterval)));
    static assert(__traits(compiles,  interval.isAfter(iInterval)));
    static assert(__traits(compiles,  interval.isAfter(posInfInterval)));
    static assert(__traits(compiles,  interval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles,  interval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles,  interval.isAfter(negInfInterval)));
    static assert(__traits(compiles,  interval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles,  interval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(interval)));
    static assert(__traits(compiles, cInterval.isAfter(cInterval)));
    static assert(__traits(compiles, cInterval.isAfter(iInterval)));
    static assert(__traits(compiles, cInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(interval)));
    static assert(__traits(compiles, iInterval.isAfter(cInterval)));
    static assert(__traits(compiles, iInterval.isAfter(iInterval)));
    static assert(__traits(compiles, iInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.isAfter(iNegInfInterval)));

    //Verify Examples.
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(PosInfInterval!Date(Date(1999, 5, 4))));

    assert( Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAfter(NegInfInterval!Date(Date(1996, 1, 2))));
}

//Test Interval's intersects().
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(interval.intersects(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).intersects(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).intersects(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(interval.intersects(interval));
    assert(!interval.intersects(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!interval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(interval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(interval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(interval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!interval.intersects(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!interval.intersects(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).intersects(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).intersects(interval));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).intersects(interval));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).intersects(interval));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).intersects(interval));
    assert(!Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).intersects(interval));
    assert(!Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).intersects(interval));

    assert(interval.intersects(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(interval.intersects(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(interval.intersects(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(interval.intersects(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.intersects(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.intersects(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!interval.intersects(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.intersects(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(interval.intersects(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(interval.intersects(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(interval.intersects(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(interval.intersects(NegInfInterval!Date(Date(2012, 1, 8))));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.intersects(interval)));
    static assert(__traits(compiles, interval.intersects(cInterval)));
    static assert(__traits(compiles, interval.intersects(iInterval)));
    static assert(__traits(compiles, interval.intersects(posInfInterval)));
    static assert(__traits(compiles, interval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, interval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, interval.intersects(negInfInterval)));
    static assert(__traits(compiles, interval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, interval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(interval)));
    static assert(__traits(compiles, cInterval.intersects(cInterval)));
    static assert(__traits(compiles, cInterval.intersects(iInterval)));
    static assert(__traits(compiles, cInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(interval)));
    static assert(__traits(compiles, iInterval.intersects(cInterval)));
    static assert(__traits(compiles, iInterval.intersects(iInterval)));
    static assert(__traits(compiles, iInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.intersects(iNegInfInterval)));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(NegInfInterval!Date(Date(1996, 1, 2))));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersects(NegInfInterval!Date(Date(2000, 1, 2))));
}

//Test Interval's intersection().
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    assertThrown!DateTimeException(interval.intersection(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).intersection(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 4), dur!"days"(0)).intersection(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(interval.intersection(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assertThrown!DateTimeException(interval.intersection(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assertThrown!DateTimeException(interval.intersection(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assertThrown!DateTimeException(interval.intersection(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).intersection(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).intersection(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).intersection(interval));
    assertThrown!DateTimeException(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).intersection(interval));

    assertThrown!DateTimeException(interval.intersection(PosInfInterval!Date(Date(2012, 1, 7))));
    assertThrown!DateTimeException(interval.intersection(PosInfInterval!Date(Date(2012, 1, 8))));

    assertThrown!DateTimeException(interval.intersection(NegInfInterval!Date(Date(2010, 7, 3))));
    assertThrown!DateTimeException(interval.intersection(NegInfInterval!Date(Date(2010, 7, 4))));

    assert(interval.intersection(interval) == interval);
    assert(interval.intersection(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)));
    assert(interval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)));
    assert(interval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)));
    assert(interval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));
    assert(interval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));

    assert(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).intersection(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).intersection(interval) == Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).intersection(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).intersection(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).intersection(interval) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).intersection(interval) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).intersection(interval) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).intersection(interval) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));

    assert(interval.intersection(PosInfInterval!Date(Date(2010, 7, 3))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(PosInfInterval!Date(Date(2010, 7, 4))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(PosInfInterval!Date(Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)));
    assert(interval.intersection(PosInfInterval!Date(Date(2012, 1, 6))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));

    assert(interval.intersection(NegInfInterval!Date(Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)));
    assert(interval.intersection(NegInfInterval!Date(Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 6)));
    assert(interval.intersection(NegInfInterval!Date(Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.intersection(NegInfInterval!Date(Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.intersection(interval)));
    static assert(__traits(compiles, interval.intersection(cInterval)));
    static assert(__traits(compiles, interval.intersection(iInterval)));
    static assert(__traits(compiles, interval.intersection(posInfInterval)));
    static assert(__traits(compiles, interval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, interval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, interval.intersection(negInfInterval)));
    static assert(__traits(compiles, interval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, interval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(interval)));
    static assert(__traits(compiles, cInterval.intersection(cInterval)));
    static assert(__traits(compiles, cInterval.intersection(iInterval)));
    static assert(__traits(compiles, cInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(interval)));
    static assert(__traits(compiles, iInterval.intersection(cInterval)));
    static assert(__traits(compiles, iInterval.intersection(iInterval)));
    static assert(__traits(compiles, iInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.intersection(iNegInfInterval)));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == Interval!Date(Date(1996, 1 , 2), Date(2000, 8, 2)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) == Interval!Date(Date(1999, 1 , 12), Date(2011, 9, 17)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(PosInfInterval!Date(Date(1990, 7, 6))) == Interval!Date(Date(1996, 1 , 2), Date(2012, 3, 1)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(PosInfInterval!Date(Date(1999, 1, 12))) == Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(NegInfInterval!Date(Date(1999, 7, 6))) == Interval!Date(Date(1996, 1 , 2), Date(1999, 7, 6)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).intersection(NegInfInterval!Date(Date(2013, 1, 12))) == Interval!Date(Date(1996, 1 , 2), Date(2012, 3, 1)));
}

//Test Interval's isAdjacent().
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    static void testInterval(in Interval!Date interval1, in Interval!Date interval2)
    {
        interval1.isAdjacent(interval2);
    }

    assertThrown!DateTimeException(testInterval(interval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), interval));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!interval.isAdjacent(interval));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(interval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!interval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!interval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!interval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(interval.isAdjacent(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!interval.isAdjacent(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).isAdjacent(interval));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).isAdjacent(interval));
    assert(!Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).isAdjacent(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).isAdjacent(interval));
    assert(!Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).isAdjacent(interval));
    assert(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).isAdjacent(interval));
    assert(!Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).isAdjacent(interval));

    assert(!interval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!interval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(interval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!interval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(interval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!interval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!interval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!interval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!interval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 8))));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.isAdjacent(interval)));
    static assert(__traits(compiles, interval.isAdjacent(cInterval)));
    static assert(__traits(compiles, interval.isAdjacent(iInterval)));
    static assert(__traits(compiles, interval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, interval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, interval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, interval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, interval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, interval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(interval)));
    static assert(__traits(compiles, cInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(interval)));
    static assert(__traits(compiles, iInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.isAdjacent(iNegInfInterval)));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(1990, 7, 6), Date(1996, 1, 2))));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(2012, 3, 1), Date(2013, 9, 17))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(1989, 3, 1), Date(2012, 3, 1))));

    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(NegInfInterval!Date(Date(1996, 1, 2))));
    assert(!Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).isAdjacent(NegInfInterval!Date(Date(2000, 1, 2))));
}

//Test Interval's merge().
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    static void testInterval(I)(in Interval!Date interval1, in I interval2)
    {
        interval1.merge(interval2);
    }

    assertThrown!DateTimeException(testInterval(interval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), interval));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(testInterval(interval, Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assertThrown!DateTimeException(testInterval(interval, Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)), interval));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)), interval));

    assertThrown!DateTimeException(testInterval(interval, PosInfInterval!Date(Date(2012, 1, 8))));

    assertThrown!DateTimeException(testInterval(interval, NegInfInterval!Date(Date(2010, 7, 3))));

    assert(interval.merge(interval) == interval);
    assert(interval.merge(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(interval.merge(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));

    assert(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).merge(interval) == Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).merge(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).merge(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).merge(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).merge(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).merge(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).merge(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).merge(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).merge(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).merge(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));

    assert(interval.merge(PosInfInterval!Date(Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(interval.merge(PosInfInterval!Date(Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.merge(PosInfInterval!Date(Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.merge(PosInfInterval!Date(Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.merge(PosInfInterval!Date(Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(interval.merge(NegInfInterval!Date(Date(2010, 7, 4))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.merge(NegInfInterval!Date(Date(2010, 7, 5))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.merge(NegInfInterval!Date(Date(2012, 1, 6))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.merge(NegInfInterval!Date(Date(2012, 1, 7))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.merge(NegInfInterval!Date(Date(2012, 1, 8))) == NegInfInterval!Date(Date(2012, 1, 8)));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.merge(interval)));
    static assert(__traits(compiles, interval.merge(cInterval)));
    static assert(__traits(compiles, interval.merge(iInterval)));
    static assert(__traits(compiles, interval.merge(posInfInterval)));
    static assert(__traits(compiles, interval.merge(cPosInfInterval)));
    static assert(__traits(compiles, interval.merge(iPosInfInterval)));
    static assert(__traits(compiles, interval.merge(negInfInterval)));
    static assert(__traits(compiles, interval.merge(cNegInfInterval)));
    static assert(__traits(compiles, interval.merge(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.merge(interval)));
    static assert(__traits(compiles, cInterval.merge(cInterval)));
    static assert(__traits(compiles, cInterval.merge(iInterval)));
    static assert(__traits(compiles, cInterval.merge(posInfInterval)));
    static assert(__traits(compiles, cInterval.merge(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.merge(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.merge(negInfInterval)));
    static assert(__traits(compiles, cInterval.merge(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.merge(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.merge(interval)));
    static assert(__traits(compiles, iInterval.merge(cInterval)));
    static assert(__traits(compiles, iInterval.merge(iInterval)));
    static assert(__traits(compiles, iInterval.merge(posInfInterval)));
    static assert(__traits(compiles, iInterval.merge(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.merge(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.merge(negInfInterval)));
    static assert(__traits(compiles, iInterval.merge(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.merge(iNegInfInterval)));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(Interval!Date(Date(2012, 3, 1), Date(2013, 5, 7))) == Interval!Date(Date(1996, 1 , 2), Date(2013, 5, 7)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(PosInfInterval!Date(Date(1990, 7, 6))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(PosInfInterval!Date(Date(2012, 3, 1))) == PosInfInterval!Date(Date(1996, 1 , 2)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(NegInfInterval!Date(Date(1996, 1, 2))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).merge(NegInfInterval!Date(Date(2013, 1, 12))) == NegInfInterval!Date(Date(2013, 1 , 12)));
}

//Test Interval's span().
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    static void testInterval(in Interval!Date interval1, in Interval!Date interval2)
    {
        interval1.span(interval2);
    }

    assertThrown!DateTimeException(testInterval(interval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), interval));
    assertThrown!DateTimeException(testInterval(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(interval.span(interval) == interval);
    assert(interval.span(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))) == Interval!Date(Date(2010, 7, 1), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)));
    assert(interval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)));
    assert(interval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(interval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(interval.span(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(interval.span(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 9)));

    assert(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)).span(interval) == Interval!Date(Date(2010, 7, 1), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)).span(interval) == Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)).span(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)).span(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)).span(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)).span(interval) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)).span(interval) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 9)));

    assert(interval.span(PosInfInterval!Date(Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(interval.span(PosInfInterval!Date(Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.span(PosInfInterval!Date(Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.span(PosInfInterval!Date(Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.span(PosInfInterval!Date(Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(interval.span(PosInfInterval!Date(Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(interval.span(NegInfInterval!Date(Date(2010, 7, 3))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.span(NegInfInterval!Date(Date(2010, 7, 4))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.span(NegInfInterval!Date(Date(2010, 7, 5))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.span(NegInfInterval!Date(Date(2012, 1, 6))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.span(NegInfInterval!Date(Date(2012, 1, 7))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(interval.span(NegInfInterval!Date(Date(2012, 1, 8))) == NegInfInterval!Date(Date(2012, 1, 8)));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, interval.span(interval)));
    static assert(__traits(compiles, interval.span(cInterval)));
    static assert(__traits(compiles, interval.span(iInterval)));
    static assert(__traits(compiles, interval.span(posInfInterval)));
    static assert(__traits(compiles, interval.span(cPosInfInterval)));
    static assert(__traits(compiles, interval.span(iPosInfInterval)));
    static assert(__traits(compiles, interval.span(negInfInterval)));
    static assert(__traits(compiles, interval.span(cNegInfInterval)));
    static assert(__traits(compiles, interval.span(iNegInfInterval)));
    static assert(__traits(compiles, cInterval.span(interval)));
    static assert(__traits(compiles, cInterval.span(cInterval)));
    static assert(__traits(compiles, cInterval.span(iInterval)));
    static assert(__traits(compiles, cInterval.span(posInfInterval)));
    static assert(__traits(compiles, cInterval.span(cPosInfInterval)));
    static assert(__traits(compiles, cInterval.span(iPosInfInterval)));
    static assert(__traits(compiles, cInterval.span(negInfInterval)));
    static assert(__traits(compiles, cInterval.span(cNegInfInterval)));
    static assert(__traits(compiles, cInterval.span(iNegInfInterval)));
    static assert(__traits(compiles, iInterval.span(interval)));
    static assert(__traits(compiles, iInterval.span(cInterval)));
    static assert(__traits(compiles, iInterval.span(iInterval)));
    static assert(__traits(compiles, iInterval.span(posInfInterval)));
    static assert(__traits(compiles, iInterval.span(cPosInfInterval)));
    static assert(__traits(compiles, iInterval.span(iPosInfInterval)));
    static assert(__traits(compiles, iInterval.span(negInfInterval)));
    static assert(__traits(compiles, iInterval.span(cNegInfInterval)));
    static assert(__traits(compiles, iInterval.span(iNegInfInterval)));

    //Verify Examples.
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(Interval!Date(Date(1990, 7, 6), Date(1991, 1, 8))) == Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(Interval!Date(Date(2012, 3, 1), Date(2013, 5, 7))) == Interval!Date(Date(1996, 1 , 2), Date(2013, 5, 7)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(PosInfInterval!Date(Date(1990, 7, 6))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(PosInfInterval!Date(Date(2050, 1, 1))) == PosInfInterval!Date(Date(1996, 1 , 2)));

    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(NegInfInterval!Date(Date(1602, 5, 21))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1)).span(NegInfInterval!Date(Date(2013, 1, 12))) == NegInfInterval!Date(Date(2013, 1 , 12)));
}

//Test Interval's shift(duration).
unittest
{
    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

    static void testIntervalFail(Interval!Date interval, in Duration duration)
    {
        interval.shift(duration);
    }

    assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), dur!"days"(1)));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.shift(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), Interval!Date(Date(2010, 7, 26), Date(2012, 1, 29)));
    testInterval(interval, dur!"days"(-22), Interval!Date(Date(2010, 6, 12), Date(2011, 12, 16)));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.shift(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.shift(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 4, 5));
    auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 4, 5));

    interval1.shift(dur!"days"(50));
    assert(interval1 == Interval!Date(Date(1996, 2, 21), Date(2012, 5, 25)));

    interval2.shift(dur!"days"(-50));
    assert(interval2 == Interval!Date(Date(1995, 11, 13), Date(2012, 2, 15)));
}

//Test Interval's shift(int, int, AllowDayOverflow).
unittest
{
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

        static void testIntervalFail(Interval!Date interval, int years, int months)
        {
            interval.shift(years, months);
        }

        assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), 1, 0));

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, in I expected, size_t line = __LINE__)
        {
            interval.shift(years, months, allow);
            assert(interval == expected);
        }

        testInterval(interval,  5, 0, AllowDayOverflow.yes, Interval!Date(Date(2015, 7, 4), Date(2017, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, Interval!Date(Date(2005, 7, 4), Date(2007, 1, 7)));

        auto interval2 = Interval!Date(Date(2000, 1, 29), Date(2010, 5, 31));

        testInterval(interval2,  1,  1, AllowDayOverflow.yes, Interval!Date(Date(2001,  3,  1), Date(2011, 7, 1)));
        testInterval(interval2,  1, -1, AllowDayOverflow.yes, Interval!Date(Date(2000, 12, 29), Date(2011, 5, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, Interval!Date(Date(1998, 12, 29), Date(2009, 5, 1)));
        testInterval(interval2, -1,  1, AllowDayOverflow.yes, Interval!Date(Date(1999,  3,  1), Date(2009, 7, 1)));

        testInterval(interval2,  1,  1, AllowDayOverflow.no, Interval!Date(Date(2001,  2, 28), Date(2011, 6, 30)));
        testInterval(interval2,  1, -1, AllowDayOverflow.no, Interval!Date(Date(2000, 12, 29), Date(2011, 4, 30)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, Interval!Date(Date(1998, 12, 29), Date(2009, 4, 30)));
        testInterval(interval2, -1,  1, AllowDayOverflow.no, Interval!Date(Date(1999,  2, 28), Date(2009, 6, 30)));
    }

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.shift(5)));
    static assert(!__traits(compiles, iInterval.shift(5)));

    //Verify Examples.
    auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
    auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

    interval1.shift(2);
    assert(interval1 == Interval!Date(Date(1998, 1, 2), Date(2014, 3, 1)));

    interval2.shift(-2);
    assert(interval2 == Interval!Date(Date(1994, 1, 2), Date(2010, 3, 1)));
}

//Test Interval's expand(Duration).
unittest
{
    auto interval = Interval!Date(Date(2000, 7, 4), Date(2012, 1, 7));

    static void testIntervalFail(I)(I interval, in Duration duration)
    {
        interval.expand(duration);
    }

    assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), dur!"days"(1)));
    assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)), dur!"days"(-5)));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.expand(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), Interval!Date(Date(2000, 6, 12), Date(2012, 1, 29)));
    testInterval(interval, dur!"days"(-22), Interval!Date(Date(2000, 7, 26), Date(2011, 12, 16)));

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.expand(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.expand(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
    auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

    interval1.expand(dur!"days"(2));
    assert(interval1 == Interval!Date(Date(1995, 12, 31), Date(2012, 3, 3)));

    interval2.expand(dur!"days"(-2));
    assert(interval2 == Interval!Date(Date(1996, 1, 4), Date(2012, 2, 28)));
}

//Test Interval's expand(int, int, AllowDayOverflow, Direction)
unittest
{
    {
        auto interval = Interval!Date(Date(2000, 7, 4), Date(2012, 1, 7));

        static void testIntervalFail(Interval!Date interval, int years, int months)
        {
            interval.expand(years, months);
        }

        assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), dur!"days"(0)), 1, 0));
        assertThrown!DateTimeException(testIntervalFail(Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)), -5, 0));

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, Direction dir, in I expected, size_t line = __LINE__)
        {
            interval.expand(years, months, allow, dir);
            assert(interval == expected);
        }

        testInterval(interval, 5, 0, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(1995, 7, 4), Date(2017, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(2005, 7, 4), Date(2007, 1, 7)));

        testInterval(interval, 5, 0, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 7, 4), Date(2017, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 7, 4), Date(2007, 1, 7)));

        testInterval(interval, 5, 0, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(1995, 7, 4), Date(2012, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(2005, 7, 4), Date(2012, 1, 7)));

        auto interval2 = Interval!Date(Date(2000, 1, 29), Date(2010, 5, 31));

        testInterval(interval2,  1,  1, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(1998, 12, 29), Date(2011, 7, 1)));
        testInterval(interval2,  1, -1, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(1999,  3,  1), Date(2011, 5, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(2001,  3,  1), Date(2009, 5, 1)));
        testInterval(interval2, -1,  1, AllowDayOverflow.yes, Direction.both, Interval!Date(Date(2000, 12, 29), Date(2009, 7, 1)));

        testInterval(interval2,  1,  1, AllowDayOverflow.no, Direction.both, Interval!Date(Date(1998, 12, 29), Date(2011, 6, 30)));
        testInterval(interval2,  1, -1, AllowDayOverflow.no, Direction.both, Interval!Date(Date(1999,  2, 28), Date(2011, 4, 30)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, Direction.both, Interval!Date(Date(2001,  2, 28), Date(2009, 4, 30)));
        testInterval(interval2, -1,  1, AllowDayOverflow.no, Direction.both, Interval!Date(Date(2000, 12, 29), Date(2009, 6, 30)));

        testInterval(interval2,  1,  1, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2011, 7, 1)));
        testInterval(interval2,  1, -1, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2011, 5, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2009, 5, 1)));
        testInterval(interval2, -1,  1, AllowDayOverflow.yes, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2009, 7, 1)));

        testInterval(interval2,  1,  1, AllowDayOverflow.no, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2011, 6, 30)));
        testInterval(interval2,  1, -1, AllowDayOverflow.no, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2011, 4, 30)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2009, 4, 30)));
        testInterval(interval2, -1,  1, AllowDayOverflow.no, Direction.fwd, Interval!Date(Date(2000, 1, 29), Date(2009, 6, 30)));

        testInterval(interval2,  1,  1, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(1998, 12, 29), Date(2010, 5, 31)));
        testInterval(interval2,  1, -1, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(1999,  3,  1), Date(2010, 5, 31)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(2001,  3,  1), Date(2010, 5, 31)));
        testInterval(interval2, -1,  1, AllowDayOverflow.yes, Direction.bwd, Interval!Date(Date(2000, 12, 29), Date(2010, 5, 31)));

        testInterval(interval2,  1,  1, AllowDayOverflow.no, Direction.bwd, Interval!Date(Date(1998, 12, 29), Date(2010, 5, 31)));
        testInterval(interval2,  1, -1, AllowDayOverflow.no, Direction.bwd, Interval!Date(Date(1999,  2, 28), Date(2010, 5, 31)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, Direction.bwd, Interval!Date(Date(2001,  2, 28), Date(2010, 5, 31)));
        testInterval(interval2, -1,  1, AllowDayOverflow.no, Direction.bwd, Interval!Date(Date(2000, 12, 29), Date(2010, 5, 31)));
    }

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.expand(5)));
    static assert(!__traits(compiles, iInterval.expand(5)));

    //Verify Examples.
    auto interval1 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));
    auto interval2 = Interval!Date(Date(1996, 1, 2), Date(2012, 3, 1));

    interval1.expand(2);
    assert(interval1 == Interval!Date(Date(1994, 1, 2), Date(2014, 3, 1)));

    interval2.expand(-2);
    assert(interval2 == Interval!Date(Date(1998, 1, 2), Date(2010, 3, 1)));
}

//Test Interval's fwdRange.
unittest
{
    {
        auto interval = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 21));

        static void testInterval1(Interval!Date interval)
        {
            interval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
        }

        assertThrown!DateTimeException(testInterval1(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

        static void testInterval2(Interval!Date interval)
        {
            interval.fwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri)).popFront();
        }

        assertThrown!DateTimeException(testInterval2(interval));

        assert(!interval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri)).empty);
        assert(interval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri), PopFirst.yes).empty);

        assert(Interval!Date(Date(2010, 9, 12), Date(2010, 10, 1)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri)).front ==
                    Date(2010, 9, 12));

        assert(Interval!Date(Date(2010, 9, 12), Date(2010, 10, 1)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri), PopFirst.yes).front ==
                    Date(2010, 9, 17));
    }

    //Verify Examples.
    {
        auto interval = Interval!Date(Date(2010, 9, 1), Date(2010, 9, 9));
        auto func = delegate (in Date date)
                    {
                        if ((date.day & 1) == 0)
                            return date + dur!"days"(2);

                        return date + dur!"days"(1);
                    };
        auto range = interval.fwdRange(func);

        assert(range.front == Date(2010, 9, 1)); //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 2).

        range.popFront();
        assert(range.front == Date(2010, 9, 2));

        range.popFront();
        assert(range.front == Date(2010, 9, 4));

        range.popFront();
        assert(range.front == Date(2010, 9, 6));

        range.popFront();
        assert(range.front == Date(2010, 9, 8));

        range.popFront();
        assert(range.empty);
    }

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
    static assert(__traits(compiles, iInterval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
}

//Test Interval's bwdRange.
unittest
{
    {
        auto interval = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 21));

        static void testInterval1(Interval!Date interval)
        {
            interval.bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
        }

        assertThrown!DateTimeException(testInterval1(Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

        static void testInterval2(Interval!Date interval)
        {
            interval.bwdRange(everyDayOfWeek!(Date, Direction.fwd)(DayOfWeek.fri)).popFront();
        }

        assertThrown!DateTimeException(testInterval2(interval));

        assert(!interval.bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri)).empty);
        assert(interval.bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri), PopFirst.yes).empty);

        assert(Interval!Date(Date(2010, 9, 19), Date(2010, 10, 1)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri)).front ==
                    Date(2010, 10, 1));

        assert(Interval!Date(Date(2010, 9, 19), Date(2010, 10, 1)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri), PopFirst.yes).front ==
                    Date(2010, 9, 24));
    }

    //Verify Examples.
    {
        auto interval = Interval!Date(Date(2010, 9, 1), Date(2010, 9, 9));
        auto func = delegate (in Date date)
                    {
                        if ((date.day & 1) == 0)
                            return date - dur!"days"(2);

                        return date - dur!"days"(1);
                    };
        auto range = interval.bwdRange(func);

        assert(range.front == Date(2010, 9, 9)); //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 8).

        range.popFront();
        assert(range.front == Date(2010, 9, 8));

        range.popFront();
        assert(range.front == Date(2010, 9, 6));

        range.popFront();
        assert(range.front == Date(2010, 9, 4));

        range.popFront();
        assert(range.front == Date(2010, 9, 2));

        range.popFront();
        assert(range.empty);
    }

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.bwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
    static assert(__traits(compiles, iInterval.bwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
}

//Test Interval's toString().
unittest
{
    assert(Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).toString() == "[2010-Jul-04 - 2012-Jan-07)");

    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cInterval.toString()));
    static assert(__traits(compiles, iInterval.toString()));
}


/++
    Represents an interval of time which has positive infinity as its end point.

    Any ranges which iterate over a $(D PosInfInterval) are infinite. So, the
    main purpose of using $(D PosInfInterval) is to create an infinite range
    which starts at a fixed point in time and goes to positive infinity.
  +/
struct PosInfInterval(TP)
{
    import std.exception : enforce;
    import std.format : format;

public:

    /++
        Params:
            begin = The time point which begins the interval.

        Examples:
            --------------------
            auto interval = PosInfInterval!Date(Date(1996, 1, 2));
            --------------------
      +/
    this(in TP begin) pure nothrow
    {
        _begin = cast(TP)begin;
    }


    /++
        Params:
            rhs = The $(D PosInfInterval) to assign to this one.
      +/
    ref PosInfInterval opAssign(const ref PosInfInterval rhs) pure nothrow
    {
        _begin = cast(TP)rhs._begin;
        return this;
    }


    /++
        Params:
            rhs = The $(D PosInfInterval) to assign to this one.
      +/
    ref PosInfInterval opAssign(PosInfInterval rhs) pure nothrow
    {
        _begin = cast(TP)rhs._begin;
        return this;
    }


    /++
        The starting point of the interval. It is included in the interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).begin == Date(1996, 1, 2));
            --------------------
      +/
    @property TP begin() const pure nothrow
    {
        return cast(TP)_begin;
    }


    /++
        The starting point of the interval. It is included in the interval.

        Params:
            timePoint = The time point to set $(D begin) to.
      +/
    @property void begin(TP timePoint) pure nothrow
    {
        _begin = timePoint;
    }


    /++
        Whether the interval's length is 0. Always returns false.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).empty);
            --------------------
      +/
    @property bool empty() const pure nothrow
    {
        return false;
    }


    /++
        Whether the given time point is within this interval.

        Params:
            timePoint = The time point to check for inclusion in this interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(Date(1994, 12, 24)));
            assert( PosInfInterval!Date(Date(1996, 1, 2)).contains(Date(2000, 1, 5)));
            --------------------
      +/
    bool contains(TP timePoint) const pure nothrow
    {
        return timePoint >= _begin;
    }


    /++
        Whether the given interval is completely within this interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        Interval!Date(Date(1998, 2, 28), Date(2013, 5, 1))));
            --------------------
      +/
    bool contains(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return interval._begin >= _begin;
    }


    /++
        Whether the given interval is completely within this interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        PosInfInterval!Date(Date(1999, 5, 4))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        PosInfInterval!Date(Date(1995, 7, 2))));
            --------------------
      +/
    bool contains(in PosInfInterval interval) const pure nothrow
    {
        return interval._begin >= _begin;
    }


    /++
        Whether the given interval is completely within this interval.

        Always returns false because an interval going to positive infinity
        can never contain an interval beginning at negative infinity.

        Params:
            interval = The interval to check for inclusion in this interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(
                        NegInfInterval!Date(Date(1996, 5, 4))));
            --------------------
      +/
    bool contains(in NegInfInterval!TP interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is before the given time point.

        Always returns false because an interval going to positive infinity
        can never be before any time point.

        Params:
            timePoint = The time point to check whether this interval is before
                        it.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Date(1994, 12, 24)));
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Date(2000, 1, 5)));
            --------------------
      +/
    bool isBefore(in TP timePoint) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Always returns false (unless the given interval is empty) because an
        interval going to positive infinity can never be before any other
        interval.

        Params:
            interval = The interval to check for against this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
            --------------------
      +/
    bool isBefore(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return false;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Always returns false because an interval going to positive infinity can
        never be before any other interval.

        Params:
            interval = The interval to check for against this interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(
                        PosInfInterval!Date(Date(1992, 5, 4))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(
                        PosInfInterval!Date(Date(2013, 3, 7))));
            --------------------
      +/
    bool isBefore(in PosInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Always returns false because an interval going to positive infinity can
        never be before any other interval.

        Params:
            interval = The interval to check for against this interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(
                        NegInfInterval!Date(Date(1996, 5, 4))));
            --------------------
      +/
    bool isBefore(in NegInfInterval!TP interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is after the given time point.

        Params:
            timePoint = The time point to check whether this interval is after
                        it.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Date(1994, 12, 24)));
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Date(2000, 1, 5)));
            --------------------
      +/
    bool isAfter(in TP timePoint) const pure nothrow
    {
        return timePoint < _begin;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Params:
            interval = The interval to check against this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));
            --------------------
      +/
    bool isAfter(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return _begin >= interval._end;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Always returns false because an interval going to positive infinity can
        never be after another interval going to positive infinity.

        Params:
            interval = The interval to check against this interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        PosInfInterval!Date(Date(1990, 1, 7))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        PosInfInterval!Date(Date(1999, 5, 4))));
            --------------------
      +/
    bool isAfter(in PosInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Params:
            interval = The interval to check against this interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        NegInfInterval!Date(Date(1996, 1, 2))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(
                        NegInfInterval!Date(Date(2000, 7, 1))));
            --------------------
      +/
    bool isAfter(in NegInfInterval!TP interval) const pure nothrow
    {
        return _begin >= interval._end;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));
            --------------------
      +/
    bool intersects(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return interval._end > _begin;
    }


    /++
        Whether the given interval overlaps this interval.

        Always returns true because two intervals going to positive infinity
        always overlap.

        Params:
            interval = The interval to check for intersection with this
                       interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        PosInfInterval!Date(Date(1990, 1, 7))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        PosInfInterval!Date(Date(1999, 5, 4))));
            --------------------
      +/
    bool intersects(in PosInfInterval interval) const pure nothrow
    {
        return true;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this
                       interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        NegInfInterval!Date(Date(1996, 1, 2))));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(
                        NegInfInterval!Date(Date(2000, 7, 1))));
            --------------------
      +/
    bool intersects(in NegInfInterval!TP interval) const pure nothrow
    {
        return _begin < interval._end;
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect or if
            the given interval is empty.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2000, 8, 2)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) ==
                   Interval!Date(Date(1999, 1 , 12), Date(2011, 9, 17)));
            --------------------
      +/
    Interval!TP intersection(in Interval!TP interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        auto begin = _begin > interval._begin ? _begin : interval._begin;

        return Interval!TP(begin, interval._end);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        PosInfInterval!Date(Date(1999, 1, 12))) ==
                   PosInfInterval!Date(Date(1999, 1 , 12)));
            --------------------
      +/
    PosInfInterval intersection(in PosInfInterval interval) const pure nothrow
    {
        return PosInfInterval(_begin < interval._begin ? interval._begin : _begin);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        NegInfInterval!Date(Date(1999, 7, 6))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(1999, 7, 6)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(
                        NegInfInterval!Date(Date(2013, 1, 12))) ==
                   Interval!Date(Date(1996, 1 , 2), Date(2013, 1, 12)));
            --------------------
      +/
    Interval!TP intersection(in NegInfInterval!TP interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        return Interval!TP(_begin, interval._end);
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(
                        Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));

            assert(!PosInfInterval!Date(Date(1999, 1, 12)).isAdjacent(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
            --------------------
      +/
    bool isAdjacent(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return _begin == interval._end;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Always returns false because two intervals going to positive infinity
        can never be adjacent to one another.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Examples:
            --------------------
            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(
                        PosInfInterval!Date(Date(1990, 1, 7))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(
                        PosInfInterval!Date(Date(1996, 1, 2))));
            --------------------
      +/
    bool isAdjacent(in PosInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(
                        NegInfInterval!Date(Date(1996, 1, 2))));

            assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(
                        NegInfInterval!Date(Date(2000, 7, 1))));
            --------------------
      +/
    bool isAdjacent(in NegInfInterval!TP interval) const pure nothrow
    {
        return _begin == interval._end;
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect and are
            not adjacent or if the given interval is empty.

        Note:
            There is no overload for $(D merge) which takes a
            $(D NegInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval merge(in Interval!TP interval) const
    {
        enforce(this.isAdjacent(interval) || this.intersects(interval),
                new DateTimeException(format("%s and %s are not adjacent and do not intersect.", this, interval)));

        return PosInfInterval(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Note:
            There is no overload for $(D merge) which takes a
            $(D NegInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(
                        PosInfInterval!Date(Date(1999, 1, 12))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval merge(in PosInfInterval interval) const pure nothrow
    {
        return PosInfInterval(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this
                       interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Note:
            There is no overload for $(D span) which takes a
            $(D NegInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).span(
                        Interval!Date(Date(500, 8, 9), Date(1602, 1, 31))) ==
                   PosInfInterval!Date(Date(500, 8, 9)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).span(
                        Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).span(
                        Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval span(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return PosInfInterval(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this
                       interval.

        Note:
            There is no overload for $(D span) which takes a
            $(D NegInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
            --------------------
            assert(PosInfInterval!Date(Date(1996, 1, 2)).span(
                        PosInfInterval!Date(Date(1990, 7, 6))) ==
                   PosInfInterval!Date(Date(1990, 7 , 6)));

            assert(PosInfInterval!Date(Date(1996, 1, 2)).span(
                        PosInfInterval!Date(Date(1999, 1, 12))) ==
                   PosInfInterval!Date(Date(1996, 1 , 2)));
            --------------------
      +/
    PosInfInterval span(in PosInfInterval interval) const pure nothrow
    {
        return PosInfInterval(_begin < interval._begin ? _begin : interval._begin);
    }


    /++
        Shifts the $(D begin) of this interval forward or backwards in time by
        the given duration (a positive duration shifts the interval forward; a
        negative duration shifts it backward). Effectively, it does
        $(D begin += duration).

        Params:
            duration = The duration to shift the interval by.

        Examples:
            --------------------
            auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
            auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

            interval1.shift(dur!"days"(50));
            assert(interval1 == PosInfInterval!Date(Date(1996, 2, 21)));

            interval2.shift(dur!"days"(-50));
            assert(interval2 == PosInfInterval!Date(Date(1995, 11, 13)));
            --------------------
      +/
    void shift(D)(D duration) pure nothrow
        if (__traits(compiles, begin + duration))
    {
        _begin += duration;
    }


    static if (__traits(compiles, begin.add!"months"(1)) &&
              __traits(compiles, begin.add!"years"(1)))
    {
        /++
            Shifts the $(D begin) of this interval forward or backwards in time
            by the given number of years and/or months (a positive number of years
            and months shifts the interval forward; a negative number shifts it
            backward). It adds the years the given years and months to
            $(D begin). It effectively calls $(D add!"years"()) and then
            $(D add!"months"()) on $(D begin) with the given number of years and
            months.

            Params:
                years         = The number of years to shift the interval by.
                months        = The number of months to shift the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D begin), causing its month to increment.

            Throws:
                $(LREF DateTimeException) if this interval is empty or if the
                resulting interval would be invalid.

            Examples:
                --------------------
                auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
                auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

                interval1.shift(dur!"days"(50));
                assert(interval1 == PosInfInterval!Date(Date(1996, 2, 21)));

                interval2.shift(dur!"days"(-50));
                assert(interval2 == PosInfInterval!Date(Date(1995, 11, 13)));
                --------------------
          +/
        void shift(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes)
            if (isIntegral!T)
        {
            auto begin = _begin;

            begin.add!"years"(years, allowOverflow);
            begin.add!"months"(months, allowOverflow);

            _begin = begin;
        }
    }


    /++
        Expands the interval backwards in time. Effectively, it does
        $(D begin -= duration).

        Params:
            duration = The duration to expand the interval by.

        Examples:
            --------------------
            auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
            auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

            interval1.expand(dur!"days"(2));
            assert(interval1 == PosInfInterval!Date(Date(1995, 12, 31)));

            interval2.expand(dur!"days"(-2));
            assert(interval2 == PosInfInterval!Date(Date(1996, 1, 4)));
--------------------
      +/
    void expand(D)(D duration) pure nothrow
        if (__traits(compiles, begin + duration))
    {
        _begin -= duration;
    }


    static if (__traits(compiles, begin.add!"months"(1)) &&
              __traits(compiles, begin.add!"years"(1)))
    {
        /++
            Expands the interval forwards and/or backwards in time. Effectively,
            it subtracts the given number of months/years from $(D begin).

            Params:
                years         = The number of years to expand the interval by.
                months        = The number of months to expand the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D begin), causing its month to increment.

            Throws:
                $(LREF DateTimeException) if this interval is empty or if the
                resulting interval would be invalid.

            Examples:
                --------------------
                auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
                auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

                interval1.expand(2);
                assert(interval1 == PosInfInterval!Date(Date(1994, 1, 2)));

                interval2.expand(-2);
                assert(interval2 == PosInfInterval!Date(Date(1998, 1, 2)));
                --------------------
          +/
        void expand(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes)
            if (isIntegral!T)
        {
            auto begin = _begin;

            begin.add!"years"(-years, allowOverflow);
            begin.add!"months"(-months, allowOverflow);

            _begin = begin;

            return;
        }
    }


    /++
        Returns a range which iterates forward over the interval, starting
        at $(D begin), using $(D_PARAM func) to generate each successive time
        point.

        The range's $(D front) is the interval's $(D begin). $(D_PARAM func) is
        used to generate the next $(D front) when $(D popFront) is called. If
        $(D_PARAM popFirst) is $(D PopFirst.yes), then $(D popFront) is called
        before the range is returned (so that $(D front) is a time point which
        $(D_PARAM func) would generate).

        If $(D_PARAM func) ever generates a time point less than or equal to the
        current $(D front) of the range, then a $(LREF DateTimeException) will be
        thrown.

        There are helper functions in this module which generate common
        delegates to pass to $(D fwdRange). Their documentation starts with
        "Range-generating function," to make them easily searchable.

        Params:
            func     = The function used to generate the time points of the
                       range over the interval.
            popFirst = Whether $(D popFront) should be called on the range
                       before returning it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Warning:
            $(D_PARAM func) must be logically pure. Ideally, $(D_PARAM func)
            would be a function pointer to a pure function, but forcing
            $(D_PARAM func) to be pure is far too restrictive to be useful, and
            in order to have the ease of use of having functions which generate
            functions to pass to $(D fwdRange), $(D_PARAM func) must be a
            delegate.

            If $(D_PARAM func) retains state which changes as it is called, then
            some algorithms will not work correctly, because the range's
            $(D save) will have failed to have really saved the range's state.
            To avoid such bugs, don't pass a delegate which is
            not logically pure to $(D fwdRange). If $(D_PARAM func) is given the
            same time point with two different calls, it must return the same
            result both times.

            Of course, none of the functions in this module have this problem,
            so it's only relevant for custom delegates.

        Examples:
            --------------------
            auto interval = PosInfInterval!Date(Date(2010, 9, 1));
            auto func = (in Date date) //For iterating over even-numbered days.
                        {
                            if ((date.day & 1) == 0)
                                return date + dur!"days"(2);

                            return date + dur!"days"(1);
                        };
            auto range = interval.fwdRange(func);

            //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 2).
            assert(range.front == Date(2010, 9, 1));

            range.popFront();
            assert(range.front == Date(2010, 9, 2));

            range.popFront();
            assert(range.front == Date(2010, 9, 4));

            range.popFront();
            assert(range.front == Date(2010, 9, 6));

            range.popFront();
            assert(range.front == Date(2010, 9, 8));

            range.popFront();
            assert(!range.empty);
            --------------------
      +/
    PosInfIntervalRange!(TP) fwdRange(TP delegate(in TP) func, PopFirst popFirst = PopFirst.no) const
    {
        auto range = PosInfIntervalRange!(TP)(this, func);

        if (popFirst == PopFirst.yes)
            range.popFront();

        return range;
    }


    /+
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString()
    {
        return _toStringImpl();
    }


    /++
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString() const nothrow
    {
        return _toStringImpl();
    }

private:

    /+
        Since we have two versions of toString(), we have _toStringImpl()
        so that they can share implementations.
      +/
    string _toStringImpl() const nothrow
    {
        try
            return format("[%s - ∞)", _begin);
        catch (Exception e)
            assert(0, "format() threw.");
    }


    TP _begin;
}

//Test PosInfInterval's constructor.
unittest
{
    PosInfInterval!Date(Date.init);
    PosInfInterval!TimeOfDay(TimeOfDay.init);
    PosInfInterval!DateTime(DateTime.init);
    PosInfInterval!SysTime(SysTime(0));

    //Verify Examples.
    auto interval = PosInfInterval!Date(Date(1996, 1, 2));
}

//Test PosInfInterval's begin.
unittest
{
    assert(PosInfInterval!Date(Date(1, 1, 1)).begin == Date(1, 1, 1));
    assert(PosInfInterval!Date(Date(2010, 1, 1)).begin == Date(2010, 1, 1));
    assert(PosInfInterval!Date(Date(1997, 12, 31)).begin == Date(1997, 12, 31));

    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, cPosInfInterval.begin));
    static assert(__traits(compiles, iPosInfInterval.begin));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).begin == Date(1996, 1, 2));
}

//Test PosInfInterval's empty.
unittest
{
    assert(!PosInfInterval!Date(Date(2010, 1, 1)).empty);
    assert(!PosInfInterval!TimeOfDay(TimeOfDay(0, 30, 0)).empty);
    assert(!PosInfInterval!DateTime(DateTime(2010, 1, 1, 0, 30, 0)).empty);
    assert(!PosInfInterval!SysTime(SysTime(DateTime(2010, 1, 1, 0, 30, 0))).empty);

    const cPosInfInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iPosInfInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    static assert(__traits(compiles, cPosInfInterval.empty));
    static assert(__traits(compiles, iPosInfInterval.empty));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).empty);
}

//Test PosInfInterval's contains(time point).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    assert(!posInfInterval.contains(Date(2009, 7, 4)));
    assert(!posInfInterval.contains(Date(2010, 7, 3)));
    assert(posInfInterval.contains(Date(2010, 7, 4)));
    assert(posInfInterval.contains(Date(2010, 7, 5)));
    assert(posInfInterval.contains(Date(2011, 7, 1)));
    assert(posInfInterval.contains(Date(2012, 1, 6)));
    assert(posInfInterval.contains(Date(2012, 1, 7)));
    assert(posInfInterval.contains(Date(2012, 1, 8)));
    assert(posInfInterval.contains(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, posInfInterval.contains(cdate)));
    static assert(__traits(compiles, cPosInfInterval.contains(cdate)));
    static assert(__traits(compiles, iPosInfInterval.contains(cdate)));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(Date(1994, 12, 24)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(Date(2000, 1, 5)));
}

//Test PosInfInterval's contains(Interval).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.contains(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(posInfInterval.contains(posInfInterval));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!posInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(posInfInterval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(posInfInterval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(posInfInterval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(posInfInterval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(posInfInterval.contains(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(posInfInterval.contains(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!posInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(posInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(posInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(posInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(posInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(posInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(PosInfInterval!Date(Date(2010, 7, 3)).contains(posInfInterval));
    assert(PosInfInterval!Date(Date(2010, 7, 4)).contains(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 5)).contains(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 6)).contains(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 7)).contains(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 8)).contains(posInfInterval));

    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.contains(interval)));
    static assert(__traits(compiles, posInfInterval.contains(cInterval)));
    static assert(__traits(compiles, posInfInterval.contains(iInterval)));
    static assert(__traits(compiles, posInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.contains(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(interval)));
    static assert(__traits(compiles, cPosInfInterval.contains(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.contains(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(interval)));
    static assert(__traits(compiles, iPosInfInterval.contains(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.contains(iNegInfInterval)));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(Interval!Date(Date(1998, 2, 28), Date(2013, 5, 1))));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).contains(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(PosInfInterval!Date(Date(1995, 7, 2))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).contains(NegInfInterval!Date(Date(1996, 5, 4))));
}

//Test PosInfInterval's isBefore(time point).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    assert(!posInfInterval.isBefore(Date(2009, 7, 3)));
    assert(!posInfInterval.isBefore(Date(2010, 7, 3)));
    assert(!posInfInterval.isBefore(Date(2010, 7, 4)));
    assert(!posInfInterval.isBefore(Date(2010, 7, 5)));
    assert(!posInfInterval.isBefore(Date(2011, 7, 1)));
    assert(!posInfInterval.isBefore(Date(2012, 1, 6)));
    assert(!posInfInterval.isBefore(Date(2012, 1, 7)));
    assert(!posInfInterval.isBefore(Date(2012, 1, 8)));
    assert(!posInfInterval.isBefore(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, posInfInterval.isBefore(cdate)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(cdate)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(cdate)));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Date(1994, 12, 24)));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Date(2000, 1, 5)));
}

//Test PosInfInterval's isBefore(Interval).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.isBefore(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!posInfInterval.isBefore(posInfInterval));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!posInfInterval.isBefore(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!PosInfInterval!Date(Date(2010, 7, 3)).isBefore(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 4)).isBefore(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 5)).isBefore(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 6)).isBefore(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 7)).isBefore(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 8)).isBefore(posInfInterval));

    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.isBefore(interval)));
    static assert(__traits(compiles, posInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(interval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(interval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isBefore(iNegInfInterval)));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(PosInfInterval!Date(Date(1992, 5, 4))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(PosInfInterval!Date(Date(2013, 3, 7))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isBefore(NegInfInterval!Date(Date(1996, 5, 4))));
}

//Test PosInfInterval's isAfter(time point).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    assert(posInfInterval.isAfter(Date(2009, 7, 3)));
    assert(posInfInterval.isAfter(Date(2010, 7, 3)));
    assert(!posInfInterval.isAfter(Date(2010, 7, 4)));
    assert(!posInfInterval.isAfter(Date(2010, 7, 5)));
    assert(!posInfInterval.isAfter(Date(2011, 7, 1)));
    assert(!posInfInterval.isAfter(Date(2012, 1, 6)));
    assert(!posInfInterval.isAfter(Date(2012, 1, 7)));
    assert(!posInfInterval.isAfter(Date(2012, 1, 8)));
    assert(!posInfInterval.isAfter(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, posInfInterval.isAfter(cdate)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(cdate)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(cdate)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Date(1994, 12, 24)));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Date(2000, 1, 5)));
}

//Test PosInfInterval's isAfter(Interval).
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.isAfter(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!posInfInterval.isAfter(posInfInterval));
    assert(posInfInterval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(posInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!posInfInterval.isAfter(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!PosInfInterval!Date(Date(2010, 7, 3)).isAfter(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 4)).isAfter(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 5)).isAfter(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 6)).isAfter(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 7)).isAfter(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 8)).isAfter(posInfInterval));

    assert(posInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(posInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.isAfter(interval)));
    static assert(__traits(compiles, posInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(interval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(interval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAfter(iNegInfInterval)));

    //Verify Examples.
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(PosInfInterval!Date(Date(1990, 1, 7))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(PosInfInterval!Date(Date(1999, 5, 4))));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).isAfter(NegInfInterval!Date(Date(1996, 1, 2))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAfter(NegInfInterval!Date(Date(2000, 7, 1))));
}

//Test PosInfInterval's intersects().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.intersects(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(posInfInterval.intersects(posInfInterval));
    assert(!posInfInterval.intersects(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!posInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(posInfInterval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(posInfInterval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(posInfInterval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(posInfInterval.intersects(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(posInfInterval.intersects(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(posInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(PosInfInterval!Date(Date(2010, 7, 3)).intersects(posInfInterval));
    assert(PosInfInterval!Date(Date(2010, 7, 4)).intersects(posInfInterval));
    assert(PosInfInterval!Date(Date(2010, 7, 5)).intersects(posInfInterval));
    assert(PosInfInterval!Date(Date(2012, 1, 6)).intersects(posInfInterval));
    assert(PosInfInterval!Date(Date(2012, 1, 7)).intersects(posInfInterval));
    assert(PosInfInterval!Date(Date(2012, 1, 8)).intersects(posInfInterval));

    assert(!posInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(posInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(posInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(posInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(posInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.intersects(interval)));
    static assert(__traits(compiles, posInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(interval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(interval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersects(iNegInfInterval)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).intersects(Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(PosInfInterval!Date(Date(1990, 1, 7))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(PosInfInterval!Date(Date(1999, 5, 4))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).intersects(NegInfInterval!Date(Date(1996, 1, 2))));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersects(NegInfInterval!Date(Date(2000, 7, 1))));
}

//Test PosInfInterval's intersection().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(I, J)(in I interval1, in J interval2)
    {
        interval1.intersection(interval2);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));

    assertThrown!DateTimeException(testInterval(posInfInterval, NegInfInterval!Date(Date(2010, 7, 3))));
    assertThrown!DateTimeException(testInterval(posInfInterval, NegInfInterval!Date(Date(2010, 7, 4))));

    assert(posInfInterval.intersection(posInfInterval) == posInfInterval);
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == Interval!Date(Date(2010, 7, 4), Date(2013, 7, 3)));
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)));
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)));
    assert(posInfInterval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)));
    assert(posInfInterval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));
    assert(posInfInterval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8)));
    assert(posInfInterval.intersection(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) == Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8)));
    assert(posInfInterval.intersection(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))) == Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9)));

    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 5)));
    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2012, 1, 6))) == PosInfInterval!Date(Date(2012, 1, 6)));
    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2012, 1, 7))) == PosInfInterval!Date(Date(2012, 1, 7)));
    assert(posInfInterval.intersection(PosInfInterval!Date(Date(2012, 1, 8))) == PosInfInterval!Date(Date(2012, 1, 8)));

    assert(PosInfInterval!Date(Date(2010, 7, 3)).intersection(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2010, 7, 4)).intersection(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2010, 7, 5)).intersection(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 5)));
    assert(PosInfInterval!Date(Date(2012, 1, 6)).intersection(posInfInterval) == PosInfInterval!Date(Date(2012, 1, 6)));
    assert(PosInfInterval!Date(Date(2012, 1, 7)).intersection(posInfInterval) == PosInfInterval!Date(Date(2012, 1, 7)));
    assert(PosInfInterval!Date(Date(2012, 1, 8)).intersection(posInfInterval) == PosInfInterval!Date(Date(2012, 1, 8)));

    assert(posInfInterval.intersection(NegInfInterval!Date(Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 4), Date(2010, 7, 5)));
    assert(posInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 6)));
    assert(posInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)));
    assert(posInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1, 8)));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.intersection(interval)));
    static assert(__traits(compiles, posInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(interval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(interval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.intersection(iNegInfInterval)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == Interval!Date(Date(1996, 1 , 2), Date(2000, 8, 2)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) == Interval!Date(Date(1999, 1 , 12), Date(2011, 9, 17)));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(PosInfInterval!Date(Date(1990, 7, 6))) == PosInfInterval!Date(Date(1996, 1 , 2)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(PosInfInterval!Date(Date(1999, 1, 12))) == PosInfInterval!Date(Date(1999, 1 , 12)));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(NegInfInterval!Date(Date(1999, 7, 6))) == Interval!Date(Date(1996, 1 , 2), Date(1999, 7, 6)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).intersection(NegInfInterval!Date(Date(2013, 1, 12))) == Interval!Date(Date(1996, 1 , 2), Date(2013, 1, 12)));
}

//Test PosInfInterval's isAdjacent().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.isAdjacent(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!posInfInterval.isAdjacent(posInfInterval));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!posInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 8))));

    assert(!PosInfInterval!Date(Date(2010, 7, 3)).isAdjacent(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 4)).isAdjacent(posInfInterval));
    assert(!PosInfInterval!Date(Date(2010, 7, 5)).isAdjacent(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 6)).isAdjacent(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 7)).isAdjacent(posInfInterval));
    assert(!PosInfInterval!Date(Date(2012, 1, 8)).isAdjacent(posInfInterval));

    assert(!posInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(posInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!posInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!posInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!posInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!posInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, posInfInterval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.isAdjacent(iNegInfInterval)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(Interval!Date(Date(1989, 3, 1), Date(1996, 1, 2))));
    assert(!PosInfInterval!Date(Date(1999, 1, 12)).isAdjacent(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(PosInfInterval!Date(Date(1990, 1, 7))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(PosInfInterval!Date(Date(1996, 1, 2))));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(NegInfInterval!Date(Date(1996, 1, 2))));
    assert(!PosInfInterval!Date(Date(1996, 1, 2)).isAdjacent(NegInfInterval!Date(Date(2000, 7, 1))));
}

//Test PosInfInterval's merge().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.merge(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));

    assert(posInfInterval.merge(posInfInterval) == posInfInterval);
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 1)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(posInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(PosInfInterval!Date(Date(2010, 7, 3)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(PosInfInterval!Date(Date(2010, 7, 4)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2010, 7, 5)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 6)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 7)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 8)).merge(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));

    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 3)))));
    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 4)))));
    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 5)))));
    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 6)))));
    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 7)))));
    static assert(!__traits(compiles, posInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 8)))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.merge(interval)));
    static assert(__traits(compiles, posInfInterval.merge(cInterval)));
    static assert(__traits(compiles, posInfInterval.merge(iInterval)));
    static assert(__traits(compiles, posInfInterval.merge(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.merge(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.merge(iPosInfInterval)));
    static assert(!__traits(compiles, posInfInterval.merge(negInfInterval)));
    static assert(!__traits(compiles, posInfInterval.merge(cNegInfInterval)));
    static assert(!__traits(compiles, posInfInterval.merge(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.merge(interval)));
    static assert(__traits(compiles, cPosInfInterval.merge(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.merge(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.merge(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.merge(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.merge(iPosInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.merge(negInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.merge(cNegInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.merge(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.merge(interval)));
    static assert(__traits(compiles, iPosInfInterval.merge(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.merge(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.merge(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.merge(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.merge(iPosInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.merge(negInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.merge(cNegInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.merge(iNegInfInterval)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) == PosInfInterval!Date(Date(1996, 1 , 2)));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(PosInfInterval!Date(Date(1990, 7, 6))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).merge(PosInfInterval!Date(Date(1999, 1, 12))) == PosInfInterval!Date(Date(1996, 1 , 2)));
}

//Test PosInfInterval's span().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(in PosInfInterval!Date posInfInterval, in Interval!Date interval)
    {
        posInfInterval.span(interval);
    }

    assertThrown!DateTimeException(testInterval(posInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(posInfInterval.span(posInfInterval) == posInfInterval);
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 1)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 1)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(posInfInterval.span(PosInfInterval!Date(Date(2010, 7, 3))) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(posInfInterval.span(PosInfInterval!Date(Date(2010, 7, 4))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(PosInfInterval!Date(Date(2010, 7, 5))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(PosInfInterval!Date(Date(2012, 1, 6))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(PosInfInterval!Date(Date(2012, 1, 7))) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(posInfInterval.span(PosInfInterval!Date(Date(2012, 1, 8))) == PosInfInterval!Date(Date(2010, 7, 4)));

    assert(PosInfInterval!Date(Date(2010, 7, 3)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 3)));
    assert(PosInfInterval!Date(Date(2010, 7, 4)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2010, 7, 5)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 6)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 7)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));
    assert(PosInfInterval!Date(Date(2012, 1, 8)).span(posInfInterval) == PosInfInterval!Date(Date(2010, 7, 4)));

    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2010, 7, 3)))));
    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2010, 7, 4)))));
    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2010, 7, 5)))));
    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2012, 1, 6)))));
    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2012, 1, 7)))));
    static assert(!__traits(compiles, posInfInterval.span(NegInfInterval!Date(Date(2012, 1, 8)))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, posInfInterval.span(interval)));
    static assert(__traits(compiles, posInfInterval.span(cInterval)));
    static assert(__traits(compiles, posInfInterval.span(iInterval)));
    static assert(__traits(compiles, posInfInterval.span(posInfInterval)));
    static assert(__traits(compiles, posInfInterval.span(cPosInfInterval)));
    static assert(__traits(compiles, posInfInterval.span(iPosInfInterval)));
    static assert(!__traits(compiles, posInfInterval.span(negInfInterval)));
    static assert(!__traits(compiles, posInfInterval.span(cNegInfInterval)));
    static assert(!__traits(compiles, posInfInterval.span(iNegInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.span(interval)));
    static assert(__traits(compiles, cPosInfInterval.span(cInterval)));
    static assert(__traits(compiles, cPosInfInterval.span(iInterval)));
    static assert(__traits(compiles, cPosInfInterval.span(posInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.span(cPosInfInterval)));
    static assert(__traits(compiles, cPosInfInterval.span(iPosInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.span(negInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.span(cNegInfInterval)));
    static assert(!__traits(compiles, cPosInfInterval.span(iNegInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.span(interval)));
    static assert(__traits(compiles, iPosInfInterval.span(cInterval)));
    static assert(__traits(compiles, iPosInfInterval.span(iInterval)));
    static assert(__traits(compiles, iPosInfInterval.span(posInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.span(cPosInfInterval)));
    static assert(__traits(compiles, iPosInfInterval.span(iPosInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.span(negInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.span(cNegInfInterval)));
    static assert(!__traits(compiles, iPosInfInterval.span(iNegInfInterval)));

    //Verify Examples.
    assert(PosInfInterval!Date(Date(1996, 1, 2)).span(Interval!Date(Date(500, 8, 9), Date(1602, 1, 31))) == PosInfInterval!Date(Date(500, 8, 9)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).span(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).span(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))) == PosInfInterval!Date(Date(1996, 1 , 2)));

    assert(PosInfInterval!Date(Date(1996, 1, 2)).span(PosInfInterval!Date(Date(1990, 7, 6))) == PosInfInterval!Date(Date(1990, 7 , 6)));
    assert(PosInfInterval!Date(Date(1996, 1, 2)).span(PosInfInterval!Date(Date(1999, 1, 12))) == PosInfInterval!Date(Date(1996, 1 , 2)));
}

//Test PosInfInterval's shift().
unittest
{
    auto interval = PosInfInterval!Date(Date(2010, 7, 4));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.shift(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), PosInfInterval!Date(Date(2010, 7, 26)));
    testInterval(interval, dur!"days"(-22), PosInfInterval!Date(Date(2010, 6, 12)));

    const cInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(!__traits(compiles, cInterval.shift(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.shift(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
    auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

    interval1.shift(dur!"days"(50));
    assert(interval1 == PosInfInterval!Date(Date(1996, 2, 21)));

    interval2.shift(dur!"days"(-50));
    assert(interval2 == PosInfInterval!Date(Date(1995, 11, 13)));
}

//Test PosInfInterval's shift(int, int, AllowDayOverflow).
unittest
{
    {
        auto interval = PosInfInterval!Date(Date(2010, 7, 4));

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, in I expected, size_t line = __LINE__)
        {
            interval.shift(years, months, allow);
            assert(interval == expected);
        }

        testInterval(interval, 5, 0, AllowDayOverflow.yes, PosInfInterval!Date(Date(2015, 7, 4)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, PosInfInterval!Date(Date(2005, 7, 4)));

        auto interval2 = PosInfInterval!Date(Date(2000, 1, 29));

        testInterval(interval2, 1, 1, AllowDayOverflow.yes, PosInfInterval!Date(Date(2001, 3, 1)));
        testInterval(interval2, 1, -1, AllowDayOverflow.yes, PosInfInterval!Date(Date(2000, 12, 29)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, PosInfInterval!Date(Date(1998, 12, 29)));
        testInterval(interval2, -1, 1, AllowDayOverflow.yes, PosInfInterval!Date(Date(1999, 3, 1)));

        testInterval(interval2, 1, 1, AllowDayOverflow.no, PosInfInterval!Date(Date(2001, 2, 28)));
        testInterval(interval2, 1, -1, AllowDayOverflow.no, PosInfInterval!Date(Date(2000, 12, 29)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, PosInfInterval!Date(Date(1998, 12, 29)));
        testInterval(interval2, -1, 1, AllowDayOverflow.no, PosInfInterval!Date(Date(1999, 2, 28)));
    }

    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(!__traits(compiles, cPosInfInterval.shift(1)));
    static assert(!__traits(compiles, iPosInfInterval.shift(1)));

    //Verify Examples.
    auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
    auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

    interval1.shift(2);
    assert(interval1 == PosInfInterval!Date(Date(1998, 1, 2)));

    interval2.shift(-2);
    assert(interval2 == PosInfInterval!Date(Date(1994, 1, 2)));
}

//Test PosInfInterval's expand().
unittest
{
    auto interval = PosInfInterval!Date(Date(2000, 7, 4));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.expand(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), PosInfInterval!Date(Date(2000, 6, 12)));
    testInterval(interval, dur!"days"(-22), PosInfInterval!Date(Date(2000, 7, 26)));

    const cInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(!__traits(compiles, cInterval.expand(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.expand(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
    auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

    interval1.expand(dur!"days"(2));
    assert(interval1 == PosInfInterval!Date(Date(1995, 12, 31)));

    interval2.expand(dur!"days"(-2));
    assert(interval2 == PosInfInterval!Date(Date(1996, 1, 4)));
}

//Test PosInfInterval's expand(int, int, AllowDayOverflow).
unittest
{
    {
        auto interval = PosInfInterval!Date(Date(2000, 7, 4));

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, in I expected, size_t line = __LINE__)
        {
            interval.expand(years, months, allow);
            assert(interval == expected);
        }

        testInterval(interval, 5, 0, AllowDayOverflow.yes, PosInfInterval!Date(Date(1995, 7, 4)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, PosInfInterval!Date(Date(2005, 7, 4)));

        auto interval2 = PosInfInterval!Date(Date(2000, 1, 29));

        testInterval(interval2, 1, 1, AllowDayOverflow.yes, PosInfInterval!Date(Date(1998, 12, 29)));
        testInterval(interval2, 1, -1, AllowDayOverflow.yes, PosInfInterval!Date(Date(1999, 3, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, PosInfInterval!Date(Date(2001, 3, 1)));
        testInterval(interval2, -1, 1, AllowDayOverflow.yes, PosInfInterval!Date(Date(2000, 12, 29)));

        testInterval(interval2, 1, 1, AllowDayOverflow.no, PosInfInterval!Date(Date(1998, 12, 29)));
        testInterval(interval2, 1, -1, AllowDayOverflow.no, PosInfInterval!Date(Date(1999, 2, 28)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, PosInfInterval!Date(Date(2001, 2, 28)));
        testInterval(interval2, -1, 1, AllowDayOverflow.no, PosInfInterval!Date(Date(2000, 12, 29)));
    }

    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(!__traits(compiles, cPosInfInterval.expand(1)));
    static assert(!__traits(compiles, iPosInfInterval.expand(1)));

    //Verify Examples.
    auto interval1 = PosInfInterval!Date(Date(1996, 1, 2));
    auto interval2 = PosInfInterval!Date(Date(1996, 1, 2));

    interval1.expand(2);
    assert(interval1 == PosInfInterval!Date(Date(1994, 1, 2)));

    interval2.expand(-2);
    assert(interval2 == PosInfInterval!Date(Date(1998, 1, 2)));
}

//Test PosInfInterval's fwdRange().
unittest
{
    auto posInfInterval = PosInfInterval!Date(Date(2010, 9, 19));

    static void testInterval(PosInfInterval!Date posInfInterval)
    {
        posInfInterval.fwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri)).popFront();
    }

    assertThrown!DateTimeException(testInterval(posInfInterval));

    assert(PosInfInterval!Date(Date(2010, 9, 12)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri)).front ==
                Date(2010, 9, 12));

    assert(PosInfInterval!Date(Date(2010, 9, 12)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri), PopFirst.yes).front ==
                Date(2010, 9, 17));

    //Verify Examples.
    auto interval = PosInfInterval!Date(Date(2010, 9, 1));
    auto func = delegate (in Date date)
                {
                    if ((date.day & 1) == 0)
                        return date + dur!"days"(2);

                    return date + dur!"days"(1);
                };
    auto range = interval.fwdRange(func);

    assert(range.front == Date(2010, 9, 1)); //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 2).

    range.popFront();
    assert(range.front == Date(2010, 9, 2));

    range.popFront();
    assert(range.front == Date(2010, 9, 4));

    range.popFront();
    assert(range.front == Date(2010, 9, 6));

    range.popFront();
    assert(range.front == Date(2010, 9, 8));

    range.popFront();
    assert(!range.empty);

    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, cPosInfInterval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
    static assert(__traits(compiles, iPosInfInterval.fwdRange(everyDayOfWeek!Date(DayOfWeek.fri))));
}

//Test PosInfInterval's toString().
unittest
{
    assert(PosInfInterval!Date(Date(2010, 7, 4)).toString() == "[2010-Jul-04 - ∞)");

    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    static assert(__traits(compiles, cPosInfInterval.toString()));
    static assert(__traits(compiles, iPosInfInterval.toString()));
}


/++
    Represents an interval of time which has negative infinity as its starting
    point.

    Any ranges which iterate over a $(D NegInfInterval) are infinite. So, the
    main purpose of using $(D NegInfInterval) is to create an infinite range
    which starts at negative infinity and goes to a fixed end point.
    Iterate over it in reverse.
  +/
struct NegInfInterval(TP)
{
    import std.exception : enforce;
    import std.format : format;

public:

    /++
        Params:
            end = The time point which ends the interval.

        Examples:
            --------------------
            auto interval = PosInfInterval!Date(Date(1996, 1, 2));
            --------------------
      +/
    this(in TP end) pure nothrow
    {
        _end = cast(TP)end;
    }


    /++
        Params:
            rhs = The $(D NegInfInterval) to assign to this one.
      +/
    ref NegInfInterval opAssign(const ref NegInfInterval rhs) pure nothrow
    {
        _end = cast(TP)rhs._end;
        return this;
    }


    /++
        Params:
            rhs = The $(D NegInfInterval) to assign to this one.
      +/
    ref NegInfInterval opAssign(NegInfInterval rhs) pure nothrow
    {
        _end = cast(TP)rhs._end;
        return this;
    }


    /++
        The end point of the interval. It is excluded from the interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).end == Date(2012, 3, 1));
--------------------
      +/
    @property TP end() const pure nothrow
    {
        return cast(TP)_end;
    }


    /++
        The end point of the interval. It is excluded from the interval.

        Params:
            timePoint = The time point to set end to.
      +/
    @property void end(TP timePoint) pure nothrow
    {
        _end = timePoint;
    }


    /++
        Whether the interval's length is 0. Always returns false.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(1996, 1, 2)).empty);
--------------------
      +/
    @property bool empty() const pure nothrow
    {
        return false;
    }


    /++
        Whether the given time point is within this interval.

        Params:
            timePoint = The time point to check for inclusion in this interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(1994, 12, 24)));
assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(2000, 1, 5)));
assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(2012, 3, 1)));
--------------------
      +/
    bool contains(TP timePoint) const pure nothrow
    {
        return timePoint < _end;
    }


    /++
        Whether the given interval is completely within this interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(
            Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(
            Interval!Date(Date(1998, 2, 28), Date(2013, 5, 1))));
--------------------
      +/
    bool contains(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return interval._end <= _end;
    }


    /++
        Whether the given interval is completely within this interval.

        Always returns false because an interval beginning at negative
        infinity can never contain an interval going to positive infinity.

        Params:
            interval = The interval to check for inclusion in this interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(
            PosInfInterval!Date(Date(1999, 5, 4))));
--------------------
      +/
    bool contains(in PosInfInterval!TP interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether the given interval is completely within this interval.

        Params:
            interval = The interval to check for inclusion in this interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(
            NegInfInterval!Date(Date(1996, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(
            NegInfInterval!Date(Date(2013, 7, 9))));
--------------------
      +/
    bool contains(in NegInfInterval interval) const pure nothrow
    {
        return interval._end <= _end;
    }


    /++
        Whether this interval is before the given time point.

        Params:
            timePoint = The time point to check whether this interval is
                        before it.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(1994, 12, 24)));
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(2000, 1, 5)));
assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(2012, 3, 1)));
--------------------
      +/
    bool isBefore(in TP timePoint) const pure nothrow
    {
        return timePoint >= _end;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Params:
            interval = The interval to check for against this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));
--------------------
      +/
    bool isBefore(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return _end <= interval._begin;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Params:
            interval = The interval to check for against this interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            PosInfInterval!Date(Date(1999, 5, 4))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            PosInfInterval!Date(Date(2012, 3, 1))));
--------------------
      +/
    bool isBefore(in PosInfInterval!TP interval) const pure nothrow
    {
        return _end <= interval._begin;
    }


    /++
        Whether this interval is before the given interval and does not
        intersect it.

        Always returns false because an interval beginning at negative
        infinity can never be before another interval beginning at negative
        infinity.

        Params:
            interval = The interval to check for against this interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            NegInfInterval!Date(Date(1996, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(
            NegInfInterval!Date(Date(2013, 7, 9))));
--------------------
      +/
    bool isBefore(in NegInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is after the given time point.

        Always returns false because an interval beginning at negative infinity
        can never be after any time point.

        Params:
            timePoint = The time point to check whether this interval is after
                        it.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(1994, 12, 24)));
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(2000, 1, 5)));
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(2012, 3, 1)));
--------------------
      +/
    bool isAfter(in TP timePoint) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is after the given interval and does not
        intersect it.

        Always returns false (unless the given interval is empty) because an
        interval beginning at negative infinity can never be after any other
        interval.

        Params:
            interval = The interval to check against this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));
--------------------
      +/
    bool isAfter(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return false;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Always returns false because an interval beginning at negative infinity
        can never be after any other interval.

        Params:
            interval = The interval to check against this interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            PosInfInterval!Date(Date(1999, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            PosInfInterval!Date(Date(2012, 3, 1))));
--------------------
      +/
    bool isAfter(in PosInfInterval!TP interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether this interval is after the given interval and does not intersect
        it.

        Always returns false because an interval beginning at negative infinity
        can never be after any other interval.

        Params:
            interval = The interval to check against this interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            NegInfInterval!Date(Date(1996, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(
            NegInfInterval!Date(Date(2013, 7, 9))));
--------------------
      +/
    bool isAfter(in NegInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));
--------------------
      +/
    bool intersects(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return interval._begin < _end;
    }


    /++
        Whether the given interval overlaps this interval.

        Params:
            interval = The interval to check for intersection with this
                       interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            PosInfInterval!Date(Date(1999, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            PosInfInterval!Date(Date(2012, 3, 1))));
--------------------
      +/
    bool intersects(in PosInfInterval!TP interval) const pure nothrow
    {
        return interval._begin < _end;
    }


    /++
        Whether the given interval overlaps this interval.

        Always returns true because two intervals beginning at negative infinity
        always overlap.

        Params:
            interval = The interval to check for intersection with this interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            NegInfInterval!Date(Date(1996, 5, 4))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(
            NegInfInterval!Date(Date(2013, 7, 9))));
--------------------
      +/
    bool intersects(in NegInfInterval!TP interval) const pure nothrow
    {
        return true;
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect or if
            the given interval is empty.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
       Interval!Date(Date(1990, 7 , 6), Date(2000, 8, 2)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) ==
       Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));
--------------------
      +/
    Interval!TP intersection(in Interval!TP interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        auto end = _end < interval._end ? _end : interval._end;

        return Interval!TP(interval._begin, end);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            PosInfInterval!Date(Date(1990, 7, 6))) ==
       Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            PosInfInterval!Date(Date(1999, 1, 12))) ==
       Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));
--------------------
      +/
    Interval!TP intersection(in PosInfInterval!TP interval) const
    {
        enforce(this.intersects(interval), new DateTimeException(format("%s and %s do not intersect.", this, interval)));

        return Interval!TP(interval._begin, _end);
    }


    /++
        Returns the intersection of two intervals

        Params:
            interval = The interval to intersect with this interval.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            NegInfInterval!Date(Date(1999, 7, 6))) ==
       NegInfInterval!Date(Date(1999, 7 , 6)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(
            NegInfInterval!Date(Date(2013, 1, 12))) ==
       NegInfInterval!Date(Date(2012, 3 , 1)));
--------------------
      +/
    NegInfInterval intersection(in NegInfInterval interval) const nothrow
    {
        return NegInfInterval(_end < interval._end ? _end : interval._end);
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            Interval!Date(Date(1999, 1, 12), Date(2012, 3, 1))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            Interval!Date(Date(2012, 3, 1), Date(2019, 2, 2))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));
--------------------
      +/
    bool isAdjacent(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return interval._begin == _end;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            PosInfInterval!Date(Date(1999, 5, 4))));

assert(NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            PosInfInterval!Date(Date(2012, 3, 1))));
--------------------
      +/
    bool isAdjacent(in PosInfInterval!TP interval) const pure nothrow
    {
        return interval._begin == _end;
    }


    /++
        Whether the given interval is adjacent to this interval.

        Always returns false because two intervals beginning at negative
        infinity can never be adjacent to one another.

        Params:
            interval = The interval to check whether its adjecent to this
                       interval.

        Examples:
--------------------
assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            NegInfInterval!Date(Date(1996, 5, 4))));

assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(
            NegInfInterval!Date(Date(2012, 3, 1))));
--------------------
      +/
    bool isAdjacent(in NegInfInterval interval) const pure nothrow
    {
        return false;
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Throws:
            $(LREF DateTimeException) if the two intervals do not intersect and are
            not adjacent or if the given interval is empty.

        Note:
            There is no overload for $(D merge) which takes a
            $(D PosInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
       NegInfInterval!Date(Date(2012, 3 , 1)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(
            Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) ==
       NegInfInterval!Date(Date(2015, 9 , 2)));
--------------------
      +/
    NegInfInterval merge(in Interval!TP interval) const
    {
        enforce(this.isAdjacent(interval) || this.intersects(interval),
                new DateTimeException(format("%s and %s are not adjacent and do not intersect.", this, interval)));

        return NegInfInterval(_end > interval._end ? _end : interval._end);
    }


    /++
        Returns the union of two intervals

        Params:
            interval = The interval to merge with this interval.

        Note:
            There is no overload for $(D merge) which takes a
            $(D PosInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(
            NegInfInterval!Date(Date(1999, 7, 6))) ==
       NegInfInterval!Date(Date(2012, 3 , 1)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(
            NegInfInterval!Date(Date(2013, 1, 12))) ==
       NegInfInterval!Date(Date(2013, 1 , 12)));
--------------------
      +/
    NegInfInterval merge(in NegInfInterval interval) const pure nothrow
    {
        return NegInfInterval(_end > interval._end ? _end : interval._end);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this
                       interval.

        Throws:
            $(LREF DateTimeException) if the given interval is empty.

        Note:
            There is no overload for $(D span) which takes a
            $(D PosInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).span(
            Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) ==
       NegInfInterval!Date(Date(2012, 3 , 1)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).span(
            Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) ==
       NegInfInterval!Date(Date(2015, 9 , 2)));

assert(NegInfInterval!Date(Date(1600, 1, 7)).span(
            Interval!Date(Date(2012, 3, 11), Date(2017, 7, 1))) ==
       NegInfInterval!Date(Date(2017, 7 , 1)));
--------------------
      +/
    NegInfInterval span(in Interval!TP interval) const pure
    {
        interval._enforceNotEmpty();

        return NegInfInterval(_end > interval._end ? _end : interval._end);
    }


    /++
        Returns an interval that covers from the earliest time point of two
        intervals up to (but not including) the latest time point of two
        intervals.

        Params:
            interval = The interval to create a span together with this
                       interval.

        Note:
            There is no overload for $(D span) which takes a
            $(D PosInfInterval), because an interval
            going from negative infinity to positive infinity
            is not possible.

        Examples:
--------------------
assert(NegInfInterval!Date(Date(2012, 3, 1)).span(
            NegInfInterval!Date(Date(1999, 7, 6))) ==
       NegInfInterval!Date(Date(2012, 3 , 1)));

assert(NegInfInterval!Date(Date(2012, 3, 1)).span(
            NegInfInterval!Date(Date(2013, 1, 12))) ==
       NegInfInterval!Date(Date(2013, 1 , 12)));
--------------------
      +/
    NegInfInterval span(in NegInfInterval interval) const pure nothrow
    {
        return NegInfInterval(_end > interval._end ? _end : interval._end);
    }


    /++
        Shifts the $(D end) of this interval forward or backwards in time by the
        given duration (a positive duration shifts the interval forward; a
        negative duration shifts it backward). Effectively, it does
        $(D end += duration).

        Params:
            duration = The duration to shift the interval by.

        Examples:
--------------------
auto interval1 = NegInfInterval!Date(Date(2012, 4, 5));
auto interval2 = NegInfInterval!Date(Date(2012, 4, 5));

interval1.shift(dur!"days"(50));
assert(interval1 == NegInfInterval!Date(Date(2012, 5, 25)));

interval2.shift(dur!"days"(-50));
assert(interval2 == NegInfInterval!Date( Date(2012, 2, 15)));
--------------------
      +/
    void shift(D)(D duration) pure nothrow
        if (__traits(compiles, end + duration))
    {
        _end += duration;
    }


    static if (__traits(compiles, end.add!"months"(1)) &&
              __traits(compiles, end.add!"years"(1)))
    {
        /++
            Shifts the $(D end) of this interval forward or backwards in time by
            the given number of years and/or months (a positive number of years
            and months shifts the interval forward; a negative number shifts it
            backward). It adds the years the given years and months to end. It
            effectively calls $(D add!"years"()) and then $(D add!"months"())
            on end with the given number of years and months.

            Params:
                years         = The number of years to shift the interval by.
                months        = The number of months to shift the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D end), causing its month to increment.

            Throws:
                $(LREF DateTimeException) if empty is true or if the resulting
                interval would be invalid.

            Examples:
--------------------
auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

interval1.shift(2);
assert(interval1 == NegInfInterval!Date(Date(2014, 3, 1)));

interval2.shift(-2);
assert(interval2 == NegInfInterval!Date(Date(2010, 3, 1)));
--------------------
          +/
        void shift(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes)
            if (isIntegral!T)
        {
            auto end = _end;

            end.add!"years"(years, allowOverflow);
            end.add!"months"(months, allowOverflow);

            _end = end;
        }
    }


    /++
        Expands the interval forwards in time. Effectively, it does
        $(D end += duration).

        Params:
            duration = The duration to expand the interval by.

        Examples:
--------------------
auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

interval1.expand(dur!"days"(2));
assert(interval1 == NegInfInterval!Date(Date(2012, 3, 3)));

interval2.expand(dur!"days"(-2));
assert(interval2 == NegInfInterval!Date(Date(2012, 2, 28)));
--------------------
      +/
    void expand(D)(D duration) pure nothrow
        if (__traits(compiles, end + duration))
    {
        _end += duration;
    }


    static if (__traits(compiles, end.add!"months"(1)) &&
              __traits(compiles, end.add!"years"(1)))
    {
        /++
            Expands the interval forwards and/or backwards in time. Effectively,
            it adds the given number of months/years to end.

            Params:
                years         = The number of years to expand the interval by.
                months        = The number of months to expand the interval by.
                allowOverflow = Whether the days should be allowed to overflow
                                on $(D end), causing their month to increment.

            Throws:
                $(LREF DateTimeException) if empty is true or if the resulting
                interval would be invalid.

            Examples:
--------------------
auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

interval1.expand(2);
assert(interval1 == NegInfInterval!Date(Date(2014, 3, 1)));

interval2.expand(-2);
assert(interval2 == NegInfInterval!Date(Date(2010, 3, 1)));
--------------------
          +/
        void expand(T)(T years, T months = 0, AllowDayOverflow allowOverflow = AllowDayOverflow.yes)
            if (isIntegral!T)
        {
            auto end = _end;

            end.add!"years"(years, allowOverflow);
            end.add!"months"(months, allowOverflow);

            _end = end;

            return;
        }
    }


    /++
        Returns a range which iterates backwards over the interval, starting
        at $(D end), using $(D_PARAM func) to generate each successive time
        point.

        The range's $(D front) is the interval's $(D end). $(D_PARAM func) is
        used to generate the next $(D front) when $(D popFront) is called. If
        $(D_PARAM popFirst) is $(D PopFirst.yes), then $(D popFront) is called
        before the range is returned (so that $(D front) is a time point which
        $(D_PARAM func) would generate).

        If $(D_PARAM func) ever generates a time point greater than or equal to
        the current $(D front) of the range, then a $(LREF DateTimeException) will
        be thrown.

        There are helper functions in this module which generate common
        delegates to pass to $(D bwdRange). Their documentation starts with
        "Range-generating function," to make them easily searchable.

        Params:
            func     = The function used to generate the time points of the
                       range over the interval.
            popFirst = Whether $(D popFront) should be called on the range
                       before returning it.

        Throws:
            $(LREF DateTimeException) if this interval is empty.

        Warning:
            $(D_PARAM func) must be logically pure. Ideally, $(D_PARAM func)
            would be a function pointer to a pure function, but forcing
            $(D_PARAM func) to be pure is far too restrictive to be useful, and
            in order to have the ease of use of having functions which generate
            functions to pass to $(D fwdRange), $(D_PARAM func) must be a
            delegate.

            If $(D_PARAM func) retains state which changes as it is called, then
            some algorithms will not work correctly, because the range's
            $(D save) will have failed to have really saved the range's state.
            To avoid such bugs, don't pass a delegate which is
            not logically pure to $(D fwdRange). If $(D_PARAM func) is given the
            same time point with two different calls, it must return the same
            result both times.

            Of course, none of the functions in this module have this problem,
            so it's only relevant for custom delegates.

        Examples:
--------------------
auto interval = NegInfInterval!Date(Date(2010, 9, 9));
auto func = (in Date date) //For iterating over even-numbered days.
            {
                if ((date.day & 1) == 0)
                    return date - dur!"days"(2);

                return date - dur!"days"(1);
            };
auto range = interval.bwdRange(func);

assert(range.front == Date(2010, 9, 9)); //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 8).

range.popFront();
assert(range.front == Date(2010, 9, 8));

range.popFront();
assert(range.front == Date(2010, 9, 6));

range.popFront();
assert(range.front == Date(2010, 9, 4));

range.popFront();
assert(range.front == Date(2010, 9, 2));

range.popFront();
assert(!range.empty);
--------------------
      +/
    NegInfIntervalRange!(TP) bwdRange(TP delegate(in TP) func, PopFirst popFirst = PopFirst.no) const
    {
        auto range = NegInfIntervalRange!(TP)(this, func);

        if (popFirst == PopFirst.yes)
            range.popFront();

        return range;
    }


    /+
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString()
    {
        return _toStringImpl();
    }


    /++
        Converts this interval to a string.
      +/
    //Due to bug http://d.puremagic.com/issues/show_bug.cgi?id=3715 , we can't
    //have versions of toString() with extra modifiers, so we define one version
    //with modifiers and one without.
    string toString() const nothrow
    {
        return _toStringImpl();
    }

private:

    /+
        Since we have two versions of toString(), we have _toStringImpl()
        so that they can share implementations.
      +/
    string _toStringImpl() const nothrow
    {
        try
            return format("[-∞ - %s)", _end);
        catch (Exception e)
            assert(0, "format() threw.");
    }


    TP _end;
}

//Test NegInfInterval's constructor.
unittest
{
    NegInfInterval!Date(Date.init);
    NegInfInterval!TimeOfDay(TimeOfDay.init);
    NegInfInterval!DateTime(DateTime.init);
    NegInfInterval!SysTime(SysTime(0));
}

//Test NegInfInterval's end.
unittest
{
    assert(NegInfInterval!Date(Date(2010, 1, 1)).end == Date(2010, 1, 1));
    assert(NegInfInterval!Date(Date(2010, 1, 1)).end == Date(2010, 1, 1));
    assert(NegInfInterval!Date(Date(1998, 1, 1)).end == Date(1998, 1, 1));

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, cNegInfInterval.end));
    static assert(__traits(compiles, iNegInfInterval.end));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).end == Date(2012, 3, 1));
}

//Test NegInfInterval's empty.
unittest
{
    assert(!NegInfInterval!Date(Date(2010, 1, 1)).empty);
    assert(!NegInfInterval!TimeOfDay(TimeOfDay(0, 30, 0)).empty);
    assert(!NegInfInterval!DateTime(DateTime(2010, 1, 1, 0, 30, 0)).empty);
    assert(!NegInfInterval!SysTime(SysTime(DateTime(2010, 1, 1, 0, 30, 0))).empty);

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, cNegInfInterval.empty));
    static assert(__traits(compiles, iNegInfInterval.empty));

    //Verify Examples.
    assert(!NegInfInterval!Date(Date(1996, 1, 2)).empty);
}

//Test NegInfInterval's contains(time point).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    assert(negInfInterval.contains(Date(2009, 7, 4)));
    assert(negInfInterval.contains(Date(2010, 7, 3)));
    assert(negInfInterval.contains(Date(2010, 7, 4)));
    assert(negInfInterval.contains(Date(2010, 7, 5)));
    assert(negInfInterval.contains(Date(2011, 7, 1)));
    assert(negInfInterval.contains(Date(2012, 1, 6)));
    assert(!negInfInterval.contains(Date(2012, 1, 7)));
    assert(!negInfInterval.contains(Date(2012, 1, 8)));
    assert(!negInfInterval.contains(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.contains(cdate)));
    static assert(__traits(compiles, cNegInfInterval.contains(cdate)));
    static assert(__traits(compiles, iNegInfInterval.contains(cdate)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(1994, 12, 24)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(2000, 1, 5)));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(Date(2012, 3, 1)));
}

//Test NegInfInterval's contains(Interval).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(in NegInfInterval!Date negInfInterval, in Interval!Date interval)
    {
        negInfInterval.contains(interval);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(negInfInterval.contains(negInfInterval));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!negInfInterval.contains(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!negInfInterval.contains(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(negInfInterval.contains(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(negInfInterval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!negInfInterval.contains(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!negInfInterval.contains(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!negInfInterval.contains(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(negInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(negInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(negInfInterval.contains(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(negInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(negInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.contains(NegInfInterval!Date(Date(2012, 1, 8))));

    assert(!NegInfInterval!Date(Date(2010, 7, 3)).contains(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 4)).contains(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 5)).contains(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 6)).contains(negInfInterval));
    assert(NegInfInterval!Date(Date(2012, 1, 7)).contains(negInfInterval));
    assert(NegInfInterval!Date(Date(2012, 1, 8)).contains(negInfInterval));

    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.contains(PosInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.contains(interval)));
    static assert(__traits(compiles, negInfInterval.contains(cInterval)));
    static assert(__traits(compiles, negInfInterval.contains(iInterval)));
    static assert(__traits(compiles, negInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.contains(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(interval)));
    static assert(__traits(compiles, cNegInfInterval.contains(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.contains(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(interval)));
    static assert(__traits(compiles, iNegInfInterval.contains(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.contains(iNegInfInterval)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(Interval!Date(Date(1998, 2, 28), Date(2013, 5, 1))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(PosInfInterval!Date(Date(1999, 5, 4))));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).contains(NegInfInterval!Date(Date(1996, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).contains(NegInfInterval!Date(Date(2013, 7, 9))));
}

//Test NegInfInterval's isBefore(time point).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    assert(!negInfInterval.isBefore(Date(2009, 7, 4)));
    assert(!negInfInterval.isBefore(Date(2010, 7, 3)));
    assert(!negInfInterval.isBefore(Date(2010, 7, 4)));
    assert(!negInfInterval.isBefore(Date(2010, 7, 5)));
    assert(!negInfInterval.isBefore(Date(2011, 7, 1)));
    assert(!negInfInterval.isBefore(Date(2012, 1, 6)));
    assert(negInfInterval.isBefore(Date(2012, 1, 7)));
    assert(negInfInterval.isBefore(Date(2012, 1, 8)));
    assert(negInfInterval.isBefore(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.isBefore(cdate)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(cdate)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(cdate)));

    //Verify Examples.
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(1994, 12, 24)));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(2000, 1, 5)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Date(2012, 3, 1)));
}

//Test NegInfInterval's isBefore(Interval).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(in NegInfInterval!Date negInfInterval, in Interval!Date interval)
    {
        negInfInterval.isBefore(interval);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!negInfInterval.isBefore(negInfInterval));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!negInfInterval.isBefore(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(negInfInterval.isBefore(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(negInfInterval.isBefore(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.isBefore(NegInfInterval!Date(Date(2012, 1, 8))));

    assert(!NegInfInterval!Date(Date(2010, 7, 3)).isBefore(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 4)).isBefore(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 5)).isBefore(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 6)).isBefore(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 7)).isBefore(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 8)).isBefore(negInfInterval));

    assert(!negInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isBefore(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(negInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(negInfInterval.isBefore(PosInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.isBefore(interval)));
    static assert(__traits(compiles, negInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(interval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isBefore(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(interval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isBefore(iNegInfInterval)));

    //Verify Examples.
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).isBefore(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(NegInfInterval!Date(Date(1996, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isBefore(NegInfInterval!Date(Date(2013, 7, 9))));
}

//Test NegInfInterval's isAfter(time point).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    assert(!negInfInterval.isAfter(Date(2009, 7, 4)));
    assert(!negInfInterval.isAfter(Date(2010, 7, 3)));
    assert(!negInfInterval.isAfter(Date(2010, 7, 4)));
    assert(!negInfInterval.isAfter(Date(2010, 7, 5)));
    assert(!negInfInterval.isAfter(Date(2011, 7, 1)));
    assert(!negInfInterval.isAfter(Date(2012, 1, 6)));
    assert(!negInfInterval.isAfter(Date(2012, 1, 7)));
    assert(!negInfInterval.isAfter(Date(2012, 1, 8)));
    assert(!negInfInterval.isAfter(Date(2013, 1, 7)));

    const cdate = Date(2010, 7, 6);
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.isAfter(cdate)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(cdate)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(cdate)));
}

//Test NegInfInterval's isAfter(Interval).
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(in NegInfInterval!Date negInfInterval, in Interval!Date interval)
    {
        negInfInterval.isAfter(interval);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!negInfInterval.isAfter(negInfInterval));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!negInfInterval.isAfter(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.isAfter(NegInfInterval!Date(Date(2012, 1, 8))));

    assert(!NegInfInterval!Date(Date(2010, 7, 3)).isAfter(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 4)).isAfter(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 5)).isAfter(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 6)).isAfter(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 7)).isAfter(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 8)).isAfter(negInfInterval));

    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.isAfter(PosInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.isAfter(interval)));
    static assert(__traits(compiles, negInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(interval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAfter(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(interval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAfter(iNegInfInterval)));

    //Verify Examples.
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(1994, 12, 24)));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(2000, 1, 5)));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Date(2012, 3, 1)));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(NegInfInterval!Date(Date(1996, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAfter(NegInfInterval!Date(Date(2013, 7, 9))));
}

//Test NegInfInterval's intersects().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(in NegInfInterval!Date negInfInterval, in Interval!Date interval)
    {
        negInfInterval.intersects(interval);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(negInfInterval.intersects(negInfInterval));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(negInfInterval.intersects(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(negInfInterval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(negInfInterval.intersects(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(!negInfInterval.intersects(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!negInfInterval.intersects(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(negInfInterval.intersects(NegInfInterval!Date(Date(2012, 1, 8))));

    assert(NegInfInterval!Date(Date(2010, 7, 3)).intersects(negInfInterval));
    assert(NegInfInterval!Date(Date(2010, 7, 4)).intersects(negInfInterval));
    assert(NegInfInterval!Date(Date(2010, 7, 5)).intersects(negInfInterval));
    assert(NegInfInterval!Date(Date(2012, 1, 6)).intersects(negInfInterval));
    assert(NegInfInterval!Date(Date(2012, 1, 7)).intersects(negInfInterval));
    assert(NegInfInterval!Date(Date(2012, 1, 8)).intersects(negInfInterval));

    assert(negInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(negInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(negInfInterval.intersects(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(negInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.intersects(PosInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.intersects(interval)));
    static assert(__traits(compiles, negInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(interval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersects(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(interval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersects(iNegInfInterval)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(Interval!Date(Date(1999, 1, 12), Date(2011, 9, 17))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).intersects(Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).intersects(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(NegInfInterval!Date(Date(1996, 5, 4))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersects(NegInfInterval!Date(Date(2013, 7, 9))));
}

//Test NegInfInterval's intersection().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(I, J)(in I interval1, in J interval2)
    {
        interval1.intersection(interval2);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assertThrown!DateTimeException(testInterval(negInfInterval, PosInfInterval!Date(Date(2012, 1, 7))));
    assertThrown!DateTimeException(testInterval(negInfInterval, PosInfInterval!Date(Date(2012, 1, 8))));

    assert(negInfInterval.intersection(negInfInterval) == negInfInterval);
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))) == Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) == Interval!Date(Date(2010, 7, 1), Date(2012, 1, 7)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) == Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6)));
    assert(negInfInterval.intersection(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7)));
    assert(negInfInterval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));
    assert(negInfInterval.intersection(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7)));

    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2010, 7, 3))) == NegInfInterval!Date(Date(2010, 7, 3)));
    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2010, 7, 4))) == NegInfInterval!Date(Date(2010, 7, 4)));
    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2010, 7, 5))) == NegInfInterval!Date(Date(2010, 7, 5)));
    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 6))) == NegInfInterval!Date(Date(2012, 1, 6)));
    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 7))) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.intersection(NegInfInterval!Date(Date(2012, 1, 8))) == NegInfInterval!Date(Date(2012, 1, 7)));

    assert(NegInfInterval!Date(Date(2010, 7, 3)).intersection(negInfInterval) == NegInfInterval!Date(Date(2010, 7, 3)));
    assert(NegInfInterval!Date(Date(2010, 7, 4)).intersection(negInfInterval) == NegInfInterval!Date(Date(2010, 7, 4)));
    assert(NegInfInterval!Date(Date(2010, 7, 5)).intersection(negInfInterval) == NegInfInterval!Date(Date(2010, 7, 5)));
    assert(NegInfInterval!Date(Date(2012, 1, 6)).intersection(negInfInterval) == NegInfInterval!Date(Date(2012, 1, 6)));
    assert(NegInfInterval!Date(Date(2012, 1, 7)).intersection(negInfInterval) == NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 8)).intersection(negInfInterval) == NegInfInterval!Date(Date(2012, 1, 7)));

    assert(negInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 3))) == Interval!Date(Date(2010, 7, 3), Date(2012, 1 ,7)));
    assert(negInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 4))) == Interval!Date(Date(2010, 7, 4), Date(2012, 1 ,7)));
    assert(negInfInterval.intersection(PosInfInterval!Date(Date(2010, 7, 5))) == Interval!Date(Date(2010, 7, 5), Date(2012, 1 ,7)));
    assert(negInfInterval.intersection(PosInfInterval!Date(Date(2012, 1, 6))) == Interval!Date(Date(2012, 1, 6), Date(2012, 1 ,7)));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.intersection(interval)));
    static assert(__traits(compiles, negInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(interval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.intersection(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(interval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.intersection(iNegInfInterval)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == Interval!Date(Date(1990, 7 , 6), Date(2000, 8, 2)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) == Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(PosInfInterval!Date(Date(1990, 7, 6))) == Interval!Date(Date(1990, 7 , 6), Date(2012, 3, 1)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(PosInfInterval!Date(Date(1999, 1, 12))) == Interval!Date(Date(1999, 1 , 12), Date(2012, 3, 1)));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(NegInfInterval!Date(Date(1999, 7, 6))) == NegInfInterval!Date(Date(1999, 7 , 6)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).intersection(NegInfInterval!Date(Date(2013, 1, 12))) == NegInfInterval!Date(Date(2012, 3 , 1)));
}

//Test NegInfInterval's isAdjacent().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(in NegInfInterval!Date negInfInterval, in Interval!Date interval)
    {
        negInfInterval.isAdjacent(interval);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(!negInfInterval.isAdjacent(negInfInterval));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))));
    assert(negInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))));
    assert(!negInfInterval.isAdjacent(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 6))));
    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.isAdjacent(NegInfInterval!Date(Date(2012, 1, 8))));

    assert(!NegInfInterval!Date(Date(2010, 7, 3)).isAdjacent(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 4)).isAdjacent(negInfInterval));
    assert(!NegInfInterval!Date(Date(2010, 7, 5)).isAdjacent(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 6)).isAdjacent(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 7)).isAdjacent(negInfInterval));
    assert(!NegInfInterval!Date(Date(2012, 1, 8)).isAdjacent(negInfInterval));

    assert(!negInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 3))));
    assert(!negInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 4))));
    assert(!negInfInterval.isAdjacent(PosInfInterval!Date(Date(2010, 7, 5))));
    assert(!negInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 6))));
    assert(negInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 7))));
    assert(!negInfInterval.isAdjacent(PosInfInterval!Date(Date(2012, 1, 8))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.isAdjacent(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(interval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(iInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(posInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(cPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.isAdjacent(iNegInfInterval)));

    //Verify Examples.
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(1999, 1, 12), Date(2012, 3, 1))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(2012, 3, 1), Date(2019, 2, 2))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(Interval!Date(Date(2022, 10, 19), Date(2027, 6, 3))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(PosInfInterval!Date(Date(1999, 5, 4))));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(PosInfInterval!Date(Date(2012, 3, 1))));

    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(NegInfInterval!Date(Date(1996, 5, 4))));
    assert(!NegInfInterval!Date(Date(2012, 3, 1)).isAdjacent(NegInfInterval!Date(Date(2012, 3, 1))));
}

//Test NegInfInterval's merge().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(I, J)(in I interval1, in J interval2)
    {
        interval1.merge(interval2);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))));

    assert(negInfInterval.merge(negInfInterval) ==
                negInfInterval);
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) ==
                NegInfInterval!Date(Date(2013, 7, 3)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));
    assert(negInfInterval.merge(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));

    assert(negInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 3))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 4))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(NegInfInterval!Date(Date(2010, 7, 5))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 6))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.merge(NegInfInterval!Date(Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));

    assert(NegInfInterval!Date(Date(2010, 7, 3)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2010, 7, 4)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2010, 7, 5)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 6)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 7)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 8)).merge(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 8)));

    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 3)))));
    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 4)))));
    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2010, 7, 5)))));
    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 6)))));
    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 7)))));
    static assert(!__traits(compiles, negInfInterval.merge(PosInfInterval!Date(Date(2012, 1, 8)))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.merge(interval)));
    static assert(__traits(compiles, negInfInterval.merge(cInterval)));
    static assert(__traits(compiles, negInfInterval.merge(iInterval)));
    static assert(!__traits(compiles, negInfInterval.merge(posInfInterval)));
    static assert(!__traits(compiles, negInfInterval.merge(cPosInfInterval)));
    static assert(!__traits(compiles, negInfInterval.merge(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.merge(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.merge(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.merge(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.merge(interval)));
    static assert(__traits(compiles, cNegInfInterval.merge(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.merge(iInterval)));
    static assert(!__traits(compiles, cNegInfInterval.merge(posInfInterval)));
    static assert(!__traits(compiles, cNegInfInterval.merge(cPosInfInterval)));
    static assert(!__traits(compiles, cNegInfInterval.merge(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.merge(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.merge(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.merge(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.merge(interval)));
    static assert(__traits(compiles, iNegInfInterval.merge(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.merge(iInterval)));
    static assert(!__traits(compiles, iNegInfInterval.merge(posInfInterval)));
    static assert(!__traits(compiles, iNegInfInterval.merge(cPosInfInterval)));
    static assert(!__traits(compiles, iNegInfInterval.merge(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.merge(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.merge(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.merge(iNegInfInterval)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) == NegInfInterval!Date(Date(2015, 9 , 2)));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(NegInfInterval!Date(Date(1999, 7, 6))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).merge(NegInfInterval!Date(Date(2013, 1, 12))) == NegInfInterval!Date(Date(2013, 1 , 12)));
}

//Test NegInfInterval's span().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(I, J)(in I interval1, in J interval2)
    {
        interval1.span(interval2);
    }

    assertThrown!DateTimeException(testInterval(negInfInterval, Interval!Date(Date(2010, 7, 4), dur!"days"(0))));

    assert(negInfInterval.span(negInfInterval) ==
                negInfInterval);
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 1), Date(2010, 7, 3))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 1), Date(2013, 7, 3))) ==
                NegInfInterval!Date(Date(2013, 7, 3)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 4))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2010, 7, 5))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 3), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 6))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2010, 7, 5), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(Interval!Date(Date(2012, 1, 6), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));
    assert(negInfInterval.span(Interval!Date(Date(2012, 1, 7), Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));
    assert(negInfInterval.span(Interval!Date(Date(2012, 1, 8), Date(2012, 1, 9))) ==
                NegInfInterval!Date(Date(2012, 1, 9)));

    assert(negInfInterval.span(NegInfInterval!Date(Date(2010, 7, 3))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(NegInfInterval!Date(Date(2010, 7, 4))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(NegInfInterval!Date(Date(2010, 7, 5))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(NegInfInterval!Date(Date(2012, 1, 6))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(NegInfInterval!Date(Date(2012, 1, 7))) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(negInfInterval.span(NegInfInterval!Date(Date(2012, 1, 8))) ==
                NegInfInterval!Date(Date(2012, 1, 8)));

    assert(NegInfInterval!Date(Date(2010, 7, 3)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2010, 7, 4)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2010, 7, 5)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 6)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 7)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 7)));
    assert(NegInfInterval!Date(Date(2012, 1, 8)).span(negInfInterval) ==
                NegInfInterval!Date(Date(2012, 1, 8)));

    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2010, 7, 3)))));
    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2010, 7, 4)))));
    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2010, 7, 5)))));
    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2012, 1, 6)))));
    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2012, 1, 7)))));
    static assert(!__traits(compiles, negInfInterval.span(PosInfInterval!Date(Date(2012, 1, 8)))));

    auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    const cInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    immutable iInterval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
    auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    immutable iPosInfInterval = PosInfInterval!Date(Date(2010, 7, 4));
    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, negInfInterval.span(interval)));
    static assert(__traits(compiles, negInfInterval.span(cInterval)));
    static assert(__traits(compiles, negInfInterval.span(iInterval)));
    static assert(!__traits(compiles, negInfInterval.span(posInfInterval)));
    static assert(!__traits(compiles, negInfInterval.span(cPosInfInterval)));
    static assert(!__traits(compiles, negInfInterval.span(iPosInfInterval)));
    static assert(__traits(compiles, negInfInterval.span(negInfInterval)));
    static assert(__traits(compiles, negInfInterval.span(cNegInfInterval)));
    static assert(__traits(compiles, negInfInterval.span(iNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.span(interval)));
    static assert(__traits(compiles, cNegInfInterval.span(cInterval)));
    static assert(__traits(compiles, cNegInfInterval.span(iInterval)));
    static assert(!__traits(compiles, cNegInfInterval.span(posInfInterval)));
    static assert(!__traits(compiles, cNegInfInterval.span(cPosInfInterval)));
    static assert(!__traits(compiles, cNegInfInterval.span(iPosInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.span(negInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.span(cNegInfInterval)));
    static assert(__traits(compiles, cNegInfInterval.span(iNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.span(interval)));
    static assert(__traits(compiles, iNegInfInterval.span(cInterval)));
    static assert(__traits(compiles, iNegInfInterval.span(iInterval)));
    static assert(!__traits(compiles, iNegInfInterval.span(posInfInterval)));
    static assert(!__traits(compiles, iNegInfInterval.span(cPosInfInterval)));
    static assert(!__traits(compiles, iNegInfInterval.span(iPosInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.span(negInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.span(cNegInfInterval)));
    static assert(__traits(compiles, iNegInfInterval.span(iNegInfInterval)));

    //Verify Examples.
    assert(NegInfInterval!Date(Date(2012, 3, 1)).span(Interval!Date(Date(1990, 7, 6), Date(2000, 8, 2))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).span(Interval!Date(Date(1999, 1, 12), Date(2015, 9, 2))) == NegInfInterval!Date(Date(2015, 9 , 2)));
    assert(NegInfInterval!Date(Date(1600, 1, 7)).span(Interval!Date(Date(2012, 3, 11), Date(2017, 7, 1))) == NegInfInterval!Date(Date(2017, 7 , 1)));

    assert(NegInfInterval!Date(Date(2012, 3, 1)).span(NegInfInterval!Date(Date(1999, 7, 6))) == NegInfInterval!Date(Date(2012, 3 , 1)));
    assert(NegInfInterval!Date(Date(2012, 3, 1)).span(NegInfInterval!Date(Date(2013, 1, 12))) == NegInfInterval!Date(Date(2013, 1 , 12)));
}

//Test NegInfInterval's shift().
unittest
{
    auto interval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.shift(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), NegInfInterval!Date(Date(2012, 1, 29)));
    testInterval(interval, dur!"days"(-22), NegInfInterval!Date(Date(2011, 12, 16)));

    const cInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.shift(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.shift(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = NegInfInterval!Date(Date(2012, 4, 5));
    auto interval2 = NegInfInterval!Date(Date(2012, 4, 5));

    interval1.shift(dur!"days"(50));
    assert(interval1 == NegInfInterval!Date(Date(2012, 5, 25)));

    interval2.shift(dur!"days"(-50));
    assert(interval2 == NegInfInterval!Date( Date(2012, 2, 15)));
}

//Test NegInfInterval's shift(int, int, AllowDayOverflow).
unittest
{
    {
        auto interval = NegInfInterval!Date(Date(2012, 1, 7));

        static void testIntervalFail(I)(I interval, int years, int months)
        {
            interval.shift(years, months);
        }

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, in I expected, size_t line = __LINE__)
        {
            interval.shift(years, months, allow);
            assert(interval == expected);
        }

        testInterval(interval, 5, 0, AllowDayOverflow.yes, NegInfInterval!Date(Date(2017, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, NegInfInterval!Date(Date(2007, 1, 7)));

        auto interval2 = NegInfInterval!Date(Date(2010, 5, 31));

        testInterval(interval2, 1, 1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2011, 7, 1)));
        testInterval(interval2, 1, -1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2011, 5, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2009, 5, 1)));
        testInterval(interval2, -1, 1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2009, 7, 1)));

        testInterval(interval2, 1, 1, AllowDayOverflow.no, NegInfInterval!Date(Date(2011, 6, 30)));
        testInterval(interval2, 1, -1, AllowDayOverflow.no, NegInfInterval!Date(Date(2011, 4, 30)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, NegInfInterval!Date(Date(2009, 4, 30)));
        testInterval(interval2, -1, 1, AllowDayOverflow.no, NegInfInterval!Date(Date(2009, 6, 30)));
    }

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(!__traits(compiles, cNegInfInterval.shift(1)));
    static assert(!__traits(compiles, iNegInfInterval.shift(1)));

    //Verify Examples.
    auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
    auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

    interval1.shift(2);
    assert(interval1 == NegInfInterval!Date(Date(2014, 3, 1)));

    interval2.shift(-2);
    assert(interval2 == NegInfInterval!Date(Date(2010, 3, 1)));
}

//Test NegInfInterval's expand().
unittest
{
    auto interval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(I)(I interval, in Duration duration, in I expected, size_t line = __LINE__)
    {
        interval.expand(duration);
        assert(interval == expected);
    }

    testInterval(interval, dur!"days"(22), NegInfInterval!Date(Date(2012, 1, 29)));
    testInterval(interval, dur!"days"(-22), NegInfInterval!Date(Date(2011, 12, 16)));

    const cInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(!__traits(compiles, cInterval.expand(dur!"days"(5))));
    static assert(!__traits(compiles, iInterval.expand(dur!"days"(5))));

    //Verify Examples.
    auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
    auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

    interval1.expand(dur!"days"(2));
    assert(interval1 == NegInfInterval!Date(Date(2012, 3, 3)));

    interval2.expand(dur!"days"(-2));
    assert(interval2 == NegInfInterval!Date(Date(2012, 2, 28)));
}

//Test NegInfInterval's expand(int, int, AllowDayOverflow).
unittest
{
    {
        auto interval = NegInfInterval!Date(Date(2012, 1, 7));

        static void testInterval(I)(I interval, int years, int months, AllowDayOverflow allow, in I expected, size_t line = __LINE__)
        {
            interval.expand(years, months, allow);
            assert(interval == expected);
        }

        testInterval(interval, 5, 0, AllowDayOverflow.yes, NegInfInterval!Date(Date(2017, 1, 7)));
        testInterval(interval, -5, 0, AllowDayOverflow.yes, NegInfInterval!Date(Date(2007, 1, 7)));

        auto interval2 = NegInfInterval!Date(Date(2010, 5, 31));

        testInterval(interval2, 1, 1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2011, 7, 1)));
        testInterval(interval2, 1, -1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2011, 5, 1)));
        testInterval(interval2, -1, -1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2009, 5, 1)));
        testInterval(interval2, -1, 1, AllowDayOverflow.yes, NegInfInterval!Date(Date(2009, 7, 1)));

        testInterval(interval2, 1, 1, AllowDayOverflow.no, NegInfInterval!Date(Date(2011, 6, 30)));
        testInterval(interval2, 1, -1, AllowDayOverflow.no, NegInfInterval!Date(Date(2011, 4, 30)));
        testInterval(interval2, -1, -1, AllowDayOverflow.no, NegInfInterval!Date(Date(2009, 4, 30)));
        testInterval(interval2, -1, 1, AllowDayOverflow.no, NegInfInterval!Date( Date(2009, 6, 30)));
    }

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(!__traits(compiles, cNegInfInterval.expand(1)));
    static assert(!__traits(compiles, iNegInfInterval.expand(1)));

    //Verify Examples.
    auto interval1 = NegInfInterval!Date(Date(2012, 3, 1));
    auto interval2 = NegInfInterval!Date(Date(2012, 3, 1));

    interval1.expand(2);
    assert(interval1 == NegInfInterval!Date(Date(2014, 3, 1)));

    interval2.expand(-2);
    assert(interval2 == NegInfInterval!Date(Date(2010, 3, 1)));
}

//Test NegInfInterval's bwdRange().
unittest
{
    auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

    static void testInterval(NegInfInterval!Date negInfInterval)
    {
        negInfInterval.bwdRange(everyDayOfWeek!(Date, Direction.fwd)(DayOfWeek.fri)).popFront();
    }

    assertThrown!DateTimeException(testInterval(negInfInterval));

    assert(NegInfInterval!Date(Date(2010, 10, 1)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri)).front ==
                Date(2010, 10, 1));

    assert(NegInfInterval!Date(Date(2010, 10, 1)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri), PopFirst.yes).front ==
                Date(2010, 9, 24));

    //Verify Examples.
    auto interval = NegInfInterval!Date(Date(2010, 9, 9));
    auto func = delegate (in Date date)
                {
                    if ((date.day & 1) == 0)
                        return date - dur!"days"(2);

                    return date - dur!"days"(1);
                };
    auto range = interval.bwdRange(func);

    //An odd day. Using PopFirst.yes would have made this Date(2010, 9, 8).
    assert(range.front == Date(2010, 9, 9));

    range.popFront();
    assert(range.front == Date(2010, 9, 8));

    range.popFront();
    assert(range.front == Date(2010, 9, 6));

    range.popFront();
    assert(range.front == Date(2010, 9, 4));

    range.popFront();
    assert(range.front == Date(2010, 9, 2));

    range.popFront();
    assert(!range.empty);

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, cNegInfInterval.bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri))));
    static assert(__traits(compiles, iNegInfInterval.bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri))));
}

//Test NegInfInterval's toString().
unittest
{
    assert(NegInfInterval!Date(Date(2012, 1, 7)).toString() == "[-∞ - 2012-Jan-07)");

    const cNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    immutable iNegInfInterval = NegInfInterval!Date(Date(2012, 1, 7));
    static assert(__traits(compiles, cNegInfInterval.toString()));
    static assert(__traits(compiles, iNegInfInterval.toString()));
}


/++
    Range-generating function.

    Returns a delegate which returns the next time point with the given
    $(D DayOfWeek) in a range.

    Using this delegate allows iteration over successive time points which
    are all the same day of the week. e.g. passing $(D DayOfWeek.mon) to
    $(D everyDayOfWeek) would result in a delegate which could be used to
    iterate over all of the Mondays in a range.

    Params:
        dir       = The direction to iterate in. If passing the return value to
                    $(D fwdRange), use $(D Direction.fwd). If passing it to
                    $(D bwdRange), use $(D Direction.bwd).
        dayOfWeek = The week that each time point in the range will be.
  +/
static TP delegate(in TP) everyDayOfWeek(TP, Direction dir = Direction.fwd)(DayOfWeek dayOfWeek) nothrow
    if (isTimePoint!TP &&
       (dir == Direction.fwd || dir == Direction.bwd) &&
       __traits(hasMember, TP, "dayOfWeek") &&
       !__traits(isStaticFunction, TP.dayOfWeek) &&
       is(typeof(TP.dayOfWeek) == DayOfWeek))
{
    TP func(in TP tp)
    {
        TP retval = cast(TP)tp;
        immutable days = daysToDayOfWeek(retval.dayOfWeek, dayOfWeek);

        static if (dir == Direction.fwd)
            immutable adjustedDays = days == 0 ? 7 : days;
        else
            immutable adjustedDays = days == 0 ? -7 : days - 7;

        return retval += dur!"days"(adjustedDays);
    }

    return &func;
}

///
unittest
{
    auto interval = Interval!Date(Date(2010, 9, 2), Date(2010, 9, 27));
    auto func = everyDayOfWeek!Date(DayOfWeek.mon);
    auto range = interval.fwdRange(func);

    //A Thursday. Using PopFirst.yes would have made this Date(2010, 9, 6).
    assert(range.front == Date(2010, 9, 2));

    range.popFront();
    assert(range.front == Date(2010, 9, 6));

    range.popFront();
    assert(range.front == Date(2010, 9, 13));

    range.popFront();
    assert(range.front == Date(2010, 9, 20));

    range.popFront();
    assert(range.empty);
}

unittest
{
    auto funcFwd = everyDayOfWeek!Date(DayOfWeek.mon);
    auto funcBwd = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.mon);

    assert(funcFwd(Date(2010, 8, 28)) == Date(2010, 8, 30));
    assert(funcFwd(Date(2010, 8, 29)) == Date(2010, 8, 30));
    assert(funcFwd(Date(2010, 8, 30)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 8, 31)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 1)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 2)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 3)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 4)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 5)) == Date(2010, 9, 6));
    assert(funcFwd(Date(2010, 9, 6)) == Date(2010, 9, 13));
    assert(funcFwd(Date(2010, 9, 7)) == Date(2010, 9, 13));

    assert(funcBwd(Date(2010, 8, 28)) == Date(2010, 8, 23));
    assert(funcBwd(Date(2010, 8, 29)) == Date(2010, 8, 23));
    assert(funcBwd(Date(2010, 8, 30)) == Date(2010, 8, 23));
    assert(funcBwd(Date(2010, 8, 31)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 1)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 2)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 3)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 4)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 5)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 6)) == Date(2010, 8, 30));
    assert(funcBwd(Date(2010, 9, 7)) == Date(2010, 9, 6));

    static assert(!__traits(compiles, everyDayOfWeek!(TimeOfDay)(DayOfWeek.mon)));
    static assert(__traits(compiles, everyDayOfWeek!(DateTime)(DayOfWeek.mon)));
    static assert(__traits(compiles, everyDayOfWeek!(SysTime)(DayOfWeek.mon)));
}


/++
    Range-generating function.

    Returns a delegate which returns the next time point with the given month
    which would be reached by adding months to the given time point.

    So, using this delegate allows iteration over successive time points
    which are in the same month but different years. For example,
    iterate over each successive December 25th in an interval by starting with a
    date which had the 25th as its day and passed $(D Month.dec) to
    $(D everyMonth) to create the delegate.

    Since it wouldn't really make sense to be iterating over a specific month
    and end up with some of the time points in the succeeding month or two years
    after the previous time point, $(D AllowDayOverflow.no) is always used when
    calculating the next time point.

    Params:
        dir   = The direction to iterate in. If passing the return value to
                $(D fwdRange), use $(D Direction.fwd). If passing it to
                $(D bwdRange), use $(D Direction.bwd).
        month = The month that each time point in the range will be in.
  +/
static TP delegate(in TP) everyMonth(TP, Direction dir = Direction.fwd)(int month)
    if (isTimePoint!TP &&
       (dir == Direction.fwd || dir == Direction.bwd) &&
       __traits(hasMember, TP, "month") &&
       !__traits(isStaticFunction, TP.month) &&
       is(typeof(TP.month) == Month))
{
    enforceValid!"months"(month);

    TP func(in TP tp)
    {
        TP retval = cast(TP)tp;
        immutable months = monthsToMonth(retval.month, month);

        static if (dir == Direction.fwd)
            immutable adjustedMonths = months == 0 ? 12 : months;
        else
            immutable adjustedMonths = months == 0 ? -12 : months - 12;

        retval.add!"months"(adjustedMonths, AllowDayOverflow.no);

        if (retval.month != month)
        {
            retval.add!"months"(-1);
            assert(retval.month == month);
        }

        return retval;
    }

    return &func;
}

///
unittest
{
    auto interval = Interval!Date(Date(2000, 1, 30), Date(2004, 8, 5));
    auto func = everyMonth!(Date)(Month.feb);
    auto range = interval.fwdRange(func);

    //Using PopFirst.yes would have made this Date(2010, 2, 29).
    assert(range.front == Date(2000, 1, 30));

    range.popFront();
    assert(range.front == Date(2000, 2, 29));

    range.popFront();
    assert(range.front == Date(2001, 2, 28));

    range.popFront();
    assert(range.front == Date(2002, 2, 28));

    range.popFront();
    assert(range.front == Date(2003, 2, 28));

    range.popFront();
    assert(range.front == Date(2004, 2, 28));

    range.popFront();
    assert(range.empty);
}

unittest
{
    auto funcFwd = everyMonth!Date(Month.jun);
    auto funcBwd = everyMonth!(Date, Direction.bwd)(Month.jun);

    assert(funcFwd(Date(2010, 5, 31)) == Date(2010, 6, 30));
    assert(funcFwd(Date(2010, 6, 30)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 7, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 8, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 9, 30)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 10, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 11, 30)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2010, 12, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2011, 1, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2011, 2, 28)) == Date(2011, 6, 28));
    assert(funcFwd(Date(2011, 3, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2011, 4, 30)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2011, 5, 31)) == Date(2011, 6, 30));
    assert(funcFwd(Date(2011, 6, 30)) == Date(2012, 6, 30));
    assert(funcFwd(Date(2011, 7, 31)) == Date(2012, 6, 30));

    assert(funcBwd(Date(2010, 5, 31)) == Date(2009, 6, 30));
    assert(funcBwd(Date(2010, 6, 30)) == Date(2009, 6, 30));
    assert(funcBwd(Date(2010, 7, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2010, 8, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2010, 9, 30)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2010, 10, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2010, 11, 30)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2010, 12, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 1, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 2, 28)) == Date(2010, 6, 28));
    assert(funcBwd(Date(2011, 3, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 4, 30)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 5, 31)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 6, 30)) == Date(2010, 6, 30));
    assert(funcBwd(Date(2011, 7, 30)) == Date(2011, 6, 30));

    static assert(!__traits(compiles, everyMonth!(TimeOfDay)(Month.jan)));
    static assert(__traits(compiles, everyMonth!(DateTime)(Month.jan)));
    static assert(__traits(compiles, everyMonth!(SysTime)(Month.jan)));
}


/++
    Range-generating function.

    Returns a delegate which returns the next time point which is the given
    duration later.

    Using this delegate allows iteration over successive time points which
    are apart by the given duration e.g. passing $(D dur!"days"(3)) to
    $(D everyDuration) would result in a delegate which could be used to iterate
    over a range of days which are each 3 days apart.

    Params:
        dir      = The direction to iterate in. If passing the return value to
                   $(D fwdRange), use $(D Direction.fwd). If passing it to
                   $(D bwdRange), use $(D Direction.bwd).
        duration = The duration which separates each successive time point in
                   the range.
  +/
static TP delegate(in TP) everyDuration(TP, Direction dir = Direction.fwd, D)
                                       (D duration) nothrow
    if (isTimePoint!TP &&
       __traits(compiles, TP.init + duration) &&
       (dir == Direction.fwd || dir == Direction.bwd))
{
    TP func(in TP tp)
    {
        static if (dir == Direction.fwd)
            return tp + duration;
        else
            return tp - duration;
    }

    return &func;
}

///
unittest
{
    auto interval = Interval!Date(Date(2010, 9, 2), Date(2010, 9, 27));
    auto func = everyDuration!Date(dur!"days"(8));
    auto range = interval.fwdRange(func);

    //Using PopFirst.yes would have made this Date(2010, 9, 10).
    assert(range.front == Date(2010, 9, 2));

    range.popFront();
    assert(range.front == Date(2010, 9, 10));

    range.popFront();
    assert(range.front == Date(2010, 9, 18));

    range.popFront();
    assert(range.front == Date(2010, 9, 26));

    range.popFront();
    assert(range.empty);
}

unittest
{
    auto funcFwd = everyDuration!Date(dur!"days"(27));
    auto funcBwd = everyDuration!(Date, Direction.bwd)(dur!"days"(27));

    assert(funcFwd(Date(2009, 12, 25)) == Date(2010, 1, 21));
    assert(funcFwd(Date(2009, 12, 26)) == Date(2010, 1, 22));
    assert(funcFwd(Date(2009, 12, 27)) == Date(2010, 1, 23));
    assert(funcFwd(Date(2009, 12, 28)) == Date(2010, 1, 24));

    assert(funcBwd(Date(2010, 1, 21)) == Date(2009, 12, 25));
    assert(funcBwd(Date(2010, 1, 22)) == Date(2009, 12, 26));
    assert(funcBwd(Date(2010, 1, 23)) == Date(2009, 12, 27));
    assert(funcBwd(Date(2010, 1, 24)) == Date(2009, 12, 28));

    static assert(__traits(compiles, everyDuration!Date(dur!"hnsecs"(1))));
    static assert(__traits(compiles, everyDuration!TimeOfDay(dur!"hnsecs"(1))));
    static assert(__traits(compiles, everyDuration!DateTime(dur!"hnsecs"(1))));
    static assert(__traits(compiles, everyDuration!SysTime(dur!"hnsecs"(1))));
}


/++
    Range-generating function.

    Returns a delegate which returns the next time point which is the given
    number of years, month, and duration later.

    The difference between this version of $(D everyDuration) and the version
    which just takes a $(CXREF time, Duration) is that this one also takes the number of
    years and months (along with an $(D AllowDayOverflow) to indicate whether
    adding years and months should allow the days to overflow).

    Note that if iterating forward, $(D add!"years"()) is called on the given
    time point, then $(D add!"months"()), and finally the duration is added
    to it. However, if iterating backwards, the duration is added first, then
    $(D add!"months"()) is called, and finally $(D add!"years"()) is called.
    That way, going backwards generates close to the same time points that
    iterating forward does, but since adding years and months is not entirely
    reversible (due to possible day overflow, regardless of whether
    $(D AllowDayOverflow.yes) or $(D AllowDayOverflow.no) is used), it can't be
    guaranteed that iterating backwards will give the same time points as
    iterating forward would have (even assuming that the end of the range is a
    time point which would be returned by the delegate when iterating forward
    from $(D begin)).

    Params:
        dir           = The direction to iterate in. If passing the return
                        value to $(D fwdRange), use $(D Direction.fwd). If
                        passing it to $(D bwdRange), use $(D Direction.bwd).
        years         = The number of years to add to the time point passed to
                        the delegate.
        months        = The number of months to add to the time point passed to
                        the delegate.
        allowOverflow = Whether the days should be allowed to overflow on
                        $(D begin) and $(D end), causing their month to
                        increment.
        duration      = The duration to add to the time point passed to the
                        delegate.
  +/
static TP delegate(in TP) everyDuration(TP, Direction dir = Direction.fwd, D)
                                       (int years,
                                        int months = 0,
                                        AllowDayOverflow allowOverflow = AllowDayOverflow.yes,
                                        D duration = dur!"days"(0)) nothrow
    if (isTimePoint!TP &&
       __traits(compiles, TP.init + duration) &&
       __traits(compiles, TP.init.add!"years"(years)) &&
       __traits(compiles, TP.init.add!"months"(months)) &&
       (dir == Direction.fwd || dir == Direction.bwd))
{
    TP func(in TP tp)
    {
        static if (dir == Direction.fwd)
        {
            TP retval = cast(TP)tp;

            retval.add!"years"(years, allowOverflow);
            retval.add!"months"(months, allowOverflow);

            return retval + duration;
        }
        else
        {
            TP retval = tp - duration;

            retval.add!"months"(-months, allowOverflow);
            retval.add!"years"(-years, allowOverflow);

            return retval;
        }
    }

    return &func;
}

///
unittest
{
    auto interval = Interval!Date(Date(2010, 9, 2), Date(2025, 9, 27));
    auto func = everyDuration!Date(4, 1, AllowDayOverflow.yes, dur!"days"(2));
    auto range = interval.fwdRange(func);

    //Using PopFirst.yes would have made this Date(2014, 10, 12).
    assert(range.front == Date(2010, 9, 2));

    range.popFront();
    assert(range.front == Date(2014, 10, 4));

    range.popFront();
    assert(range.front == Date(2018, 11, 6));

    range.popFront();
    assert(range.front == Date(2022, 12, 8));

    range.popFront();
    assert(range.empty);
}

unittest
{
    {
        auto funcFwd = everyDuration!Date(1, 2, AllowDayOverflow.yes, dur!"days"(3));
        auto funcBwd = everyDuration!(Date, Direction.bwd)(1, 2, AllowDayOverflow.yes, dur!"days"(3));

        assert(funcFwd(Date(2009, 12, 25)) == Date(2011, 2, 28));
        assert(funcFwd(Date(2009, 12, 26)) == Date(2011, 3, 1));
        assert(funcFwd(Date(2009, 12, 27)) == Date(2011, 3, 2));
        assert(funcFwd(Date(2009, 12, 28)) == Date(2011, 3, 3));
        assert(funcFwd(Date(2009, 12, 29)) == Date(2011, 3, 4));

        assert(funcBwd(Date(2011, 2, 28)) == Date(2009, 12, 25));
        assert(funcBwd(Date(2011, 3, 1)) == Date(2009, 12, 26));
        assert(funcBwd(Date(2011, 3, 2)) == Date(2009, 12, 27));
        assert(funcBwd(Date(2011, 3, 3)) == Date(2009, 12, 28));
        assert(funcBwd(Date(2011, 3, 4)) == Date(2010, 1, 1));
    }

    {
        auto funcFwd = everyDuration!Date(1, 2, AllowDayOverflow.no, dur!"days"(3));
        auto funcBwd = everyDuration!(Date, Direction.bwd)(1, 2, AllowDayOverflow.yes, dur!"days"(3));

        assert(funcFwd(Date(2009, 12, 25)) == Date(2011, 2, 28));
        assert(funcFwd(Date(2009, 12, 26)) == Date(2011, 3, 1));
        assert(funcFwd(Date(2009, 12, 27)) == Date(2011, 3, 2));
        assert(funcFwd(Date(2009, 12, 28)) == Date(2011, 3, 3));
        assert(funcFwd(Date(2009, 12, 29)) == Date(2011, 3, 3));

        assert(funcBwd(Date(2011, 2, 28)) == Date(2009, 12, 25));
        assert(funcBwd(Date(2011, 3, 1)) == Date(2009, 12, 26));
        assert(funcBwd(Date(2011, 3, 2)) == Date(2009, 12, 27));
        assert(funcBwd(Date(2011, 3, 3)) == Date(2009, 12, 28));
        assert(funcBwd(Date(2011, 3, 4)) == Date(2010, 1, 1));
    }

    static assert(__traits(compiles, everyDuration!Date(1, 2, AllowDayOverflow.yes, dur!"hnsecs"(1))));
    static assert(!__traits(compiles, everyDuration!TimeOfDay(1, 2, AllowDayOverflow.yes, dur!"hnsecs"(1))));
    static assert(__traits(compiles, everyDuration!DateTime(1, 2, AllowDayOverflow.yes, dur!"hnsecs"(1))));
    static assert(__traits(compiles, everyDuration!SysTime(1, 2, AllowDayOverflow.yes, dur!"hnsecs"(1))));
}


//TODO Add function to create a range generating function based on a date recurrence pattern string.
//     This may or may not involve creating a date recurrence pattern class of some sort - probably
//     yes if we want to make it easy to build them. However, there is a standard recurrence
//     pattern string format which we'd want to support with a range generator (though if we have
//     the class/struct, we'd probably want a version of the range generating function which took
//     that rather than a string).


//==============================================================================
// Section with ranges.
//==============================================================================


/++
    A range over an $(LREF2 .Interval, Interval).

    $(D IntervalRange) is only ever constructed by $(LREF2 .Interval, Interval). However, when
    it is constructed, it is given a function, $(D func), which is used to
    generate the time points which are iterated over. $(D func) takes a time
    point and returns a time point of the same type. For instance,
    to iterate over all of the days in
    the interval $(D Interval!Date), pass a function to $(LREF2 .Interval, Interval)'s $(D fwdRange)
    where that function took a $(LREF Date) and returned a $(LREF Date) which was one
    day later. That function would then be used by $(D IntervalRange)'s
    $(D popFront) to iterate over the $(LREF Date)s in the interval.

    If $(D dir == Direction.fwd), then a range iterates forward in time, whereas
    if $(D dir == Direction.bwd), then it iterates backwards in time. So, if
    $(D dir == Direction.fwd) then $(D front == interval.begin), whereas if
    $(D dir == Direction.bwd) then $(D front == interval.end). $(D func) must
    generate a time point going in the proper direction of iteration, or a
    $(LREF DateTimeException) will be thrown. So, to iterate forward in
    time, the time point that $(D func) generates must be later in time than the
    one passed to it. If it's either identical or earlier in time, then a
    $(LREF DateTimeException) will be thrown. To iterate backwards, then
    the generated time point must be before the time point which was passed in.

    If the generated time point is ever passed the edge of the range in the
    proper direction, then the edge of that range will be used instead. So, if
    iterating forward, and the generated time point is past the interval's
    $(D end), then $(D front) becomes $(D end). If iterating backwards, and the
    generated time point is before $(D begin), then $(D front) becomes
    $(D begin). In either case, the range would then be empty.

    Also note that while normally the $(D begin) of an interval is included in
    it and its $(D end) is excluded from it, if $(D dir == Direction.bwd), then
    $(D begin) is treated as excluded and $(D end) is treated as included. This
    allows for the same behavior in both directions. This works because none of
    $(LREF2 .Interval, Interval)'s functions which care about whether $(D begin) or $(D end) is
    included or excluded are ever called by $(D IntervalRange). $(D interval)
    returns a normal interval, regardless of whether $(D dir == Direction.fwd)
    or if $(D dir == Direction.bwd), so any $(LREF2 .Interval, Interval) functions which are
    called on it which care about whether $(D begin) or $(D end) are included or
    excluded will treat $(D begin) as included and $(D end) as excluded.
  +/
struct IntervalRange(TP, Direction dir)
    if (isTimePoint!TP && dir != Direction.both)
{
public:

    /++
        Params:
            rhs = The $(D IntervalRange) to assign to this one.
      +/
    ref IntervalRange opAssign(ref IntervalRange rhs) pure nothrow
    {
        _interval = rhs._interval;
        _func = rhs._func;
        return this;
    }


    /++ Ditto +/
    ref IntervalRange opAssign(IntervalRange rhs) pure nothrow
    {
        return this = rhs;
    }


    /++
        Whether this $(D IntervalRange) is empty.
      +/
    @property bool empty() const pure nothrow
    {
        return _interval.empty;
    }


    /++
        The first time point in the range.

        Throws:
            $(LREF DateTimeException) if the range is empty.
      +/
    @property TP front() const pure
    {
        _enforceNotEmpty();

        static if (dir == Direction.fwd)
            return _interval.begin;
        else
            return _interval.end;
    }


    /++
        Pops $(D front) from the range, using $(D func) to generate the next
        time point in the range. If the generated time point is beyond the edge
        of the range, then $(D front) is set to that edge, and the range is then
        empty. So, if iterating forwards, and the generated time point is
        greater than the interval's $(D end), then $(D front) is set to
        $(D end). If iterating backwards, and the generated time point is less
        than the interval's $(D begin), then $(D front) is set to $(D begin).

        Throws:
            $(LREF DateTimeException) if the range is empty or if the generated
            time point is in the wrong direction (i.e. if iterating
            forward and the generated time point is before $(D front), or if
            iterating backwards and the generated time point is after
            $(D front)).
      +/
    void popFront()
    {
        _enforceNotEmpty();

        static if (dir == Direction.fwd)
        {
            auto begin = _func(_interval.begin);

            if (begin > _interval.end)
                begin = _interval.end;

            _enforceCorrectDirection(begin);

            _interval.begin = begin;
        }
        else
        {
            auto end = _func(_interval.end);

            if (end < _interval.begin)
                end = _interval.begin;

            _enforceCorrectDirection(end);

            _interval.end = end;
        }
    }


    /++
        Returns a copy of $(D this).
      +/
    @property IntervalRange save() pure nothrow
    {
        return this;
    }


    /++
        The interval that this $(D IntervalRange) currently covers.
      +/
    @property Interval!TP interval() const pure nothrow
    {
        return cast(Interval!TP)_interval;
    }


    /++
        The function used to generate the next time point in the range.
      +/
    TP delegate(in TP) func() pure nothrow @property
    {
        return _func;
    }


    /++
        The $(D Direction) that this range iterates in.
      +/
    @property Direction direction() const pure nothrow
    {
        return dir;
    }


private:

    /+
        Params:
            interval = The interval that this range covers.
            func     = The function used to generate the time points which are
                       iterated over.
      +/
    this(in Interval!TP interval, TP delegate(in TP) func) pure nothrow
    {
        _func = func;
        _interval = interval;
    }


    /+
        Throws:
            $(LREF DateTimeException) if this interval is empty.
      +/
    void _enforceNotEmpty(size_t line = __LINE__) const pure
    {
        if (empty)
            throw new DateTimeException("Invalid operation for an empty IntervalRange.", __FILE__, line);
    }


    /+
        Throws:
            $(LREF DateTimeException) if $(D_PARAM newTP) is in the wrong
            direction.
      +/
    void _enforceCorrectDirection(in TP newTP, size_t line = __LINE__) const
    {
        import std.format : format;
        import std.exception : enforce;

        static if (dir == Direction.fwd)
        {
            enforce(newTP > _interval._begin,
                    new DateTimeException(format("Generated time point is before previous begin: prev [%s] new [%s]",
                                                 interval._begin,
                                                 newTP),
                                                 __FILE__,
                                                 line));
        }
        else
        {
            enforce(newTP < _interval._end,
                    new DateTimeException(format("Generated time point is after previous end: prev [%s] new [%s]",
                                                 interval._end,
                                                 newTP),
                                                 __FILE__,
                                                 line));
        }
    }


    Interval!TP        _interval;
    TP delegate(in TP) _func;
}

//Test that IntervalRange satisfies the range predicates that it's supposed to satisfy.
unittest
{
    static assert(isInputRange!(IntervalRange!(Date, Direction.fwd)));
    static assert(isForwardRange!(IntervalRange!(Date, Direction.fwd)));

    //Commented out due to bug http://d.puremagic.com/issues/show_bug.cgi?id=4895
    //static assert(!isOutputRange!(IntervalRange!(Date, Direction.fwd), Date));

    static assert(!isBidirectionalRange!(IntervalRange!(Date, Direction.fwd)));
    static assert(!isRandomAccessRange!(IntervalRange!(Date, Direction.fwd)));
    static assert(!hasSwappableElements!(IntervalRange!(Date, Direction.fwd)));
    static assert(!hasAssignableElements!(IntervalRange!(Date, Direction.fwd)));
    static assert(!hasLength!(IntervalRange!(Date, Direction.fwd)));
    static assert(!isInfinite!(IntervalRange!(Date, Direction.fwd)));
    static assert(!hasSlicing!(IntervalRange!(Date, Direction.fwd)));

    static assert(is(ElementType!(IntervalRange!(Date, Direction.fwd)) == Date));
    static assert(is(ElementType!(IntervalRange!(TimeOfDay, Direction.fwd)) == TimeOfDay));
    static assert(is(ElementType!(IntervalRange!(DateTime, Direction.fwd)) == DateTime));
    static assert(is(ElementType!(IntervalRange!(SysTime, Direction.fwd)) == SysTime));
}

//Test construction of IntervalRange.
unittest
{
    {
        Date dateFunc(in Date date)
        {
            return date;
        }

        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));

        auto ir = IntervalRange!(Date, Direction.fwd)(interval, &dateFunc);
    }

    {
        TimeOfDay todFunc(in TimeOfDay tod)
        {
            return tod;
        }

        auto interval = Interval!TimeOfDay(TimeOfDay(12, 1, 7), TimeOfDay(14, 0, 0));

        auto ir = IntervalRange!(TimeOfDay, Direction.fwd)(interval, &todFunc);
    }

    {
        DateTime dtFunc(in DateTime dt)
        {
            return dt;
        }

        auto interval = Interval!DateTime(DateTime(2010, 7, 4, 12, 1, 7), DateTime(2012, 1, 7, 14, 0, 0));

        auto ir = IntervalRange!(DateTime, Direction.fwd)(interval, &dtFunc);
    }

    {
        SysTime stFunc(in SysTime st)
        {
            return cast(SysTime)st;
        }

        auto interval = Interval!SysTime(SysTime(DateTime(2010, 7, 4, 12, 1, 7)), SysTime(DateTime(2012, 1, 7, 14, 0, 0)));

        auto ir = IntervalRange!(SysTime, Direction.fwd)(interval, &stFunc);
    }
}

//Test IntervalRange's empty().
unittest
{
    //fwd
    {
        auto range = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 21)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));

        assert(!range.empty);
        range.popFront();
        assert(range.empty);

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
        static assert(__traits(compiles, cRange.empty));

        //Apparently, creating an immutable IntervalRange!Date doesn't work, so we can't test if
        //empty works with it. However, since an immutable range is pretty useless, it's no great loss.
    }

    //bwd
    {
        auto range = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 21)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));

        assert(!range.empty);
        range.popFront();
        assert(range.empty);

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
        static assert(__traits(compiles, cRange.empty));

        //Apparently, creating an immutable IntervalRange!Date doesn't work, so we can't test if
        //empty works with it. However, since an immutable range is pretty useless, it's no great loss.
    }
}

//Test IntervalRange's front.
unittest
{
    //fwd
    {
        auto emptyRange = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 20)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
        assertThrown!DateTimeException((in IntervalRange!(Date, Direction.fwd) range){range.front;}(emptyRange));

        auto range = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed));
        assert(range.front == Date(2010, 7, 4));

        auto poppedRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
        assert(poppedRange.front == Date(2010, 7, 7));

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
        static assert(__traits(compiles, cRange.front));
    }

    //bwd
    {
        auto emptyRange = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 20)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
        assertThrown!DateTimeException((in IntervalRange!(Date, Direction.bwd) range){range.front;}(emptyRange));

        auto range = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed));
        assert(range.front == Date(2012, 1, 7));

        auto poppedRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
        assert(poppedRange.front == Date(2012, 1, 4));

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
        static assert(__traits(compiles, cRange.front));
    }
}

//Test IntervalRange's popFront().
unittest
{
    //fwd
    {
        auto emptyRange = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 20)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
        assertThrown!DateTimeException((IntervalRange!(Date, Direction.fwd) range){range.popFront();}(emptyRange));

        auto range = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
        auto expected = range.front;

        foreach (date; range)
        {
            assert(date == expected);
            expected += dur!"days"(7);
        }

        assert(walkLength(range) == 79);

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
        static assert(__traits(compiles, cRange.front));
    }

    //bwd
    {
        auto emptyRange = Interval!Date(Date(2010, 9, 19), Date(2010, 9, 20)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
        assertThrown!DateTimeException((IntervalRange!(Date, Direction.bwd) range){range.popFront();}(emptyRange));

        auto range = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
        auto expected = range.front;

        foreach (date; range)
        {
            assert(date == expected);
            expected += dur!"days"(-7);
        }

        assert(walkLength(range) == 79);

        const cRange = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
        static assert(!__traits(compiles, cRange.popFront()));
    }
}

//Test IntervalRange's save.
unittest
{
    //fwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!Date(DayOfWeek.fri);
        auto range = interval.fwdRange(func);

        assert(range.save == range);
    }

    //bwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
        auto range = interval.bwdRange(func);

        assert(range.save == range);
    }
}

//Test IntervalRange's interval.
unittest
{
    //fwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!Date(DayOfWeek.fri);
        auto range = interval.fwdRange(func);

        assert(range.interval == interval);

        const cRange = range;
        static assert(__traits(compiles, cRange.interval));
    }

    //bwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
        auto range = interval.bwdRange(func);

        assert(range.interval == interval);

        const cRange = range;
        static assert(__traits(compiles, cRange.interval));
    }
}

//Test IntervalRange's func.
unittest
{
    //fwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!Date(DayOfWeek.fri);
        auto range = interval.fwdRange(func);

        assert(range.func == func);
    }

    //bwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
        auto range = interval.bwdRange(func);

        assert(range.func == func);
    }
}

//Test IntervalRange's direction.
unittest
{
    //fwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!Date(DayOfWeek.fri);
        auto range = interval.fwdRange(func);

        assert(range.direction == Direction.fwd);

        const cRange = range;
        static assert(__traits(compiles, cRange.direction));
    }

    //bwd
    {
        auto interval = Interval!Date(Date(2010, 7, 4), Date(2012, 1, 7));
        auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
        auto range = interval.bwdRange(func);

        assert(range.direction == Direction.bwd);

        const cRange = range;
        static assert(__traits(compiles, cRange.direction));
    }
}


/++
    A range over a $(D PosInfInterval). It is an infinite range.

    $(D PosInfIntervalRange) is only ever constructed by $(D PosInfInterval).
    However, when it is constructed, it is given a function, $(D func), which
    is used to generate the time points which are iterated over. $(D func)
    takes a time point and returns a time point of the same type. For
    instance, to iterate
    over all of the days in the interval $(D PosInfInterval!Date), pass a function to
    $(D PosInfInterval)'s $(D fwdRange) where that function took a $(LREF Date) and
    returned a $(LREF Date) which was one day later. That function would then be
    used by $(D PosInfIntervalRange)'s $(D popFront) to iterate over the
    $(LREF Date)s in the interval - though obviously, since the range is infinite,
    use a function such as $(D std.range.take) with it rather than
    iterating over $(I all) of the dates.

    As the interval goes to positive infinity, the range is always iterated over
    forwards, never backwards. $(D func) must generate a time point going in
    the proper direction of iteration, or a $(LREF DateTimeException) will be
    thrown. So, the time points that $(D func) generates must be later in time
    than the one passed to it. If it's either identical or earlier in time, then
    a $(LREF DateTimeException) will be thrown.
  +/
struct PosInfIntervalRange(TP)
    if (isTimePoint!TP)
{
public:

    /++
        Params:
            rhs = The $(D PosInfIntervalRange) to assign to this one.
      +/
    ref PosInfIntervalRange opAssign(ref PosInfIntervalRange rhs) pure nothrow
    {
        _interval = rhs._interval;
        _func = rhs._func;

        return this;
    }


    /++ Ditto +/
    ref PosInfIntervalRange opAssign(PosInfIntervalRange rhs) pure nothrow
    {
        return this = rhs;
    }


    /++
        This is an infinite range, so it is never empty.
      +/
    enum bool empty = false;


    /++
        The first time point in the range.
      +/
    @property TP front() const pure nothrow
    {
        return _interval.begin;
    }


    /++
        Pops $(D front) from the range, using $(D func) to generate the next
        time point in the range.

        Throws:
            $(LREF DateTimeException) if the generated time point is less than
            $(D front).
      +/
    void popFront()
    {
        auto begin = _func(_interval.begin);

        _enforceCorrectDirection(begin);

        _interval.begin = begin;
    }


    /++
        Returns a copy of $(D this).
      +/
    @property PosInfIntervalRange save() pure nothrow
    {
        return this;
    }


    /++
        The interval that this range currently covers.
      +/
    @property PosInfInterval!TP interval() const pure nothrow
    {
        return cast(PosInfInterval!TP)_interval;
    }


    /++
        The function used to generate the next time point in the range.
      +/
    TP delegate(in TP) func() pure nothrow @property
    {
        return _func;
    }


private:

    /+
        Params:
            interval = The interval that this range covers.
            func     = The function used to generate the time points which are
                       iterated over.
      +/
    this(in PosInfInterval!TP interval, TP delegate(in TP) func) pure nothrow
    {
        _func = func;
        _interval = interval;
    }


    /+
        Throws:
            $(LREF DateTimeException) if $(D_PARAME newTP) is in the wrong
            direction.
      +/
    void _enforceCorrectDirection(in TP newTP, size_t line = __LINE__) const
    {
        import std.format : format;
        import std.exception : enforce;

        enforce(newTP > _interval._begin,
                new DateTimeException(format("Generated time point is before previous begin: prev [%s] new [%s]",
                                             interval._begin,
                                             newTP),
                                             __FILE__,
                                             line));
    }


    PosInfInterval!TP  _interval;
    TP delegate(in TP) _func;
}

//Test that PosInfIntervalRange satisfies the range predicates that it's supposed to satisfy.
unittest
{
    static assert(isInputRange!(PosInfIntervalRange!Date));
    static assert(isForwardRange!(PosInfIntervalRange!Date));
    static assert(isInfinite!(PosInfIntervalRange!Date));

    //Commented out due to bug http://d.puremagic.com/issues/show_bug.cgi?id=4895
    //static assert(!isOutputRange!(PosInfIntervalRange!Date, Date));
    static assert(!isBidirectionalRange!(PosInfIntervalRange!Date));
    static assert(!isRandomAccessRange!(PosInfIntervalRange!Date));
    static assert(!hasSwappableElements!(PosInfIntervalRange!Date));
    static assert(!hasAssignableElements!(PosInfIntervalRange!Date));
    static assert(!hasLength!(PosInfIntervalRange!Date));
    static assert(!hasSlicing!(PosInfIntervalRange!Date));

    static assert(is(ElementType!(PosInfIntervalRange!Date) == Date));
    static assert(is(ElementType!(PosInfIntervalRange!TimeOfDay) == TimeOfDay));
    static assert(is(ElementType!(PosInfIntervalRange!DateTime) == DateTime));
    static assert(is(ElementType!(PosInfIntervalRange!SysTime) == SysTime));
}

//Test construction of PosInfIntervalRange.
unittest
{
    {
        Date dateFunc(in Date date)
        {
            return date;
        }

        auto posInfInterval = PosInfInterval!Date(Date(2010, 7, 4));

        auto ir = PosInfIntervalRange!Date(posInfInterval, &dateFunc);
    }

    {
        TimeOfDay todFunc(in TimeOfDay tod)
        {
            return tod;
        }

        auto posInfInterval = PosInfInterval!TimeOfDay(TimeOfDay(12, 1, 7));

        auto ir = PosInfIntervalRange!(TimeOfDay)(posInfInterval, &todFunc);
    }

    {
        DateTime dtFunc(in DateTime dt)
        {
            return dt;
        }

        auto posInfInterval = PosInfInterval!DateTime(DateTime(2010, 7, 4, 12, 1, 7));

        auto ir = PosInfIntervalRange!(DateTime)(posInfInterval, &dtFunc);
    }

    {
        SysTime stFunc(in SysTime st)
        {
            return cast(SysTime)st;
        }

        auto posInfInterval = PosInfInterval!SysTime(SysTime(DateTime(2010, 7, 4, 12, 1, 7)));

        auto ir = PosInfIntervalRange!(SysTime)(posInfInterval, &stFunc);
    }
}

//Test PosInfIntervalRange's front.
unittest
{
    auto range = PosInfInterval!Date(Date(2010, 7, 4)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed));
    assert(range.front == Date(2010, 7, 4));

    auto poppedRange = PosInfInterval!Date(Date(2010, 7, 4)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
    assert(poppedRange.front == Date(2010, 7, 7));

    const cRange = PosInfInterval!Date(Date(2010, 7, 4)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
    static assert(__traits(compiles, cRange.front));
}

//Test PosInfIntervalRange's popFront().
unittest
{
    import std.range;

    auto range = PosInfInterval!Date(Date(2010, 7, 4)).fwdRange(everyDayOfWeek!Date(DayOfWeek.wed), PopFirst.yes);
    auto expected = range.front;

    foreach (date; take(range, 79))
    {
        assert(date == expected);
        expected += dur!"days"(7);
    }

    const cRange = PosInfInterval!Date(Date(2010, 7, 4)).fwdRange(everyDayOfWeek!Date(DayOfWeek.fri));
    static assert(!__traits(compiles, cRange.popFront()));
}

//Test PosInfIntervalRange's save.
unittest
{
    auto interval = PosInfInterval!Date(Date(2010, 7, 4));
    auto func = everyDayOfWeek!Date(DayOfWeek.fri);
    auto range = interval.fwdRange(func);

    assert(range.save == range);
}

//Test PosInfIntervalRange's interval.
unittest
{
    auto interval = PosInfInterval!Date(Date(2010, 7, 4));
    auto func = everyDayOfWeek!Date(DayOfWeek.fri);
    auto range = interval.fwdRange(func);

    assert(range.interval == interval);

    const cRange = range;
    static assert(__traits(compiles, cRange.interval));
}

//Test PosInfIntervalRange's func.
unittest
{
    auto interval = PosInfInterval!Date(Date(2010, 7, 4));
    auto func = everyDayOfWeek!Date(DayOfWeek.fri);
    auto range = interval.fwdRange(func);

    assert(range.func == func);
}


/++
    A range over a $(D NegInfInterval). It is an infinite range.

    $(D NegInfIntervalRange) is only ever constructed by $(D NegInfInterval).
    However, when it is constructed, it is given a function, $(D func), which
    is used to generate the time points which are iterated over. $(D func)
    takes a time point and returns a time point of the same type. For
    instance, to iterate
    over all of the days in the interval $(D NegInfInterval!Date), pass a function to
    $(D NegInfInterval)'s $(D bwdRange) where that function took a $(LREF Date) and
    returned a $(LREF Date) which was one day earlier. That function would then be
    used by $(D NegInfIntervalRange)'s $(D popFront) to iterate over the
    $(LREF Date)s in the interval - though obviously, since the range is infinite,
    use a function such as $(D std.range.take) with it rather than
    iterating over $(I all) of the dates.

    As the interval goes to negative infinity, the range is always iterated over
    backwards, never forwards. $(D func) must generate a time point going in
    the proper direction of iteration, or a $(LREF DateTimeException) will be
    thrown. So, the time points that $(D func) generates must be earlier in time
    than the one passed to it. If it's either identical or later in time, then a
    $(LREF DateTimeException) will be thrown.

    Also note that while normally the $(D end) of an interval is excluded from
    it, $(D NegInfIntervalRange) treats it as if it were included. This allows
    for the same behavior as with $(D PosInfIntervalRange). This works
    because none of $(D NegInfInterval)'s functions which care about whether
    $(D end) is included or excluded are ever called by
    $(D NegInfIntervalRange). $(D interval) returns a normal interval, so any
    $(D NegInfInterval) functions which are called on it which care about
    whether $(D end) is included or excluded will treat $(D end) as excluded.
  +/
struct NegInfIntervalRange(TP)
    if (isTimePoint!TP)
{
public:

    /++
        Params:
            rhs = The $(D NegInfIntervalRange) to assign to this one.
      +/
    ref NegInfIntervalRange opAssign(ref NegInfIntervalRange rhs) pure nothrow
    {
        _interval = rhs._interval;
        _func = rhs._func;

        return this;
    }


    /++ Ditto +/
    ref NegInfIntervalRange opAssign(NegInfIntervalRange rhs) pure nothrow
    {
        return this = rhs;
    }


    /++
        This is an infinite range, so it is never empty.
      +/
    enum bool empty = false;


    /++
        The first time point in the range.
      +/
    @property TP front() const pure nothrow
    {
        return _interval.end;
    }


    /++
        Pops $(D front) from the range, using $(D func) to generate the next
        time point in the range.

        Throws:
            $(LREF DateTimeException) if the generated time point is greater than
            $(D front).
      +/
    void popFront()
    {
        auto end = _func(_interval.end);

        _enforceCorrectDirection(end);

        _interval.end = end;
    }


    /++
        Returns a copy of $(D this).
      +/
    @property NegInfIntervalRange save() pure nothrow
    {
        return this;
    }


    /++
        The interval that this range currently covers.
      +/
    @property NegInfInterval!TP interval() const pure nothrow
    {
        return cast(NegInfInterval!TP)_interval;
    }


    /++
        The function used to generate the next time point in the range.
      +/
    TP delegate(in TP) func() pure nothrow @property
    {
        return _func;
    }


private:

    /+
        Params:
            interval = The interval that this range covers.
            func     = The function used to generate the time points which are
                       iterated over.
      +/
    this(in NegInfInterval!TP interval, TP delegate(in TP) func) pure nothrow
    {
        _func = func;
        _interval = interval;
    }


    /+
        Throws:
            $(LREF DateTimeException) if $(D_PARAM newTP) is in the wrong
            direction.
      +/
    void _enforceCorrectDirection(in TP newTP, size_t line = __LINE__) const
    {
        import std.format : format;
        import std.exception : enforce;

        enforce(newTP < _interval._end,
                new DateTimeException(format("Generated time point is before previous end: prev [%s] new [%s]",
                                             interval._end,
                                             newTP),
                                             __FILE__,
                                             line));
    }


    NegInfInterval!TP  _interval;
    TP delegate(in TP) _func;
}

//Test that NegInfIntervalRange satisfies the range predicates that it's supposed to satisfy.
unittest
{
    static assert(isInputRange!(NegInfIntervalRange!Date));
    static assert(isForwardRange!(NegInfIntervalRange!Date));
    static assert(isInfinite!(NegInfIntervalRange!Date));

    //Commented out due to bug http://d.puremagic.com/issues/show_bug.cgi?id=4895
    //static assert(!isOutputRange!(NegInfIntervalRange!Date, Date));
    static assert(!isBidirectionalRange!(NegInfIntervalRange!Date));
    static assert(!isRandomAccessRange!(NegInfIntervalRange!Date));
    static assert(!hasSwappableElements!(NegInfIntervalRange!Date));
    static assert(!hasAssignableElements!(NegInfIntervalRange!Date));
    static assert(!hasLength!(NegInfIntervalRange!Date));
    static assert(!hasSlicing!(NegInfIntervalRange!Date));

    static assert(is(ElementType!(NegInfIntervalRange!Date) == Date));
    static assert(is(ElementType!(NegInfIntervalRange!TimeOfDay) == TimeOfDay));
    static assert(is(ElementType!(NegInfIntervalRange!DateTime) == DateTime));
}

//Test construction of NegInfIntervalRange.
unittest
{
    {
        Date dateFunc(in Date date)
        {
            return date;
        }

        auto negInfInterval = NegInfInterval!Date(Date(2012, 1, 7));

        auto ir = NegInfIntervalRange!Date(negInfInterval, &dateFunc);
    }

    {
        TimeOfDay todFunc(in TimeOfDay tod)
        {
            return tod;
        }

        auto negInfInterval = NegInfInterval!TimeOfDay(TimeOfDay(14, 0, 0));

        auto ir = NegInfIntervalRange!(TimeOfDay)(negInfInterval, &todFunc);
    }

    {
        DateTime dtFunc(in DateTime dt)
        {
            return dt;
        }

        auto negInfInterval = NegInfInterval!DateTime(DateTime(2012, 1, 7, 14, 0, 0));

        auto ir = NegInfIntervalRange!(DateTime)(negInfInterval, &dtFunc);
    }

    {
        SysTime stFunc(in SysTime st)
        {
            return cast(SysTime)(st);
        }

        auto negInfInterval = NegInfInterval!SysTime(SysTime(DateTime(2012, 1, 7, 14, 0, 0)));

        auto ir = NegInfIntervalRange!(SysTime)(negInfInterval, &stFunc);
    }
}

//Test NegInfIntervalRange's front.
unittest
{
    auto range = NegInfInterval!Date(Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed));
    assert(range.front == Date(2012, 1, 7));

    auto poppedRange = NegInfInterval!Date(Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
    assert(poppedRange.front == Date(2012, 1, 4));

    const cRange = NegInfInterval!Date(Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
    static assert(__traits(compiles, cRange.front));
}

//Test NegInfIntervalRange's popFront().
unittest
{
    import std.range;

    auto range = NegInfInterval!Date(Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.wed), PopFirst.yes);
    auto expected = range.front;

    foreach (date; take(range, 79))
    {
        assert(date == expected);
        expected += dur!"days"(-7);
    }

    const cRange = NegInfInterval!Date(Date(2012, 1, 7)).bwdRange(everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri));
    static assert(!__traits(compiles, cRange.popFront()));
}

//Test NegInfIntervalRange's save.
unittest
{
    auto interval = NegInfInterval!Date(Date(2012, 1, 7));
    auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
    auto range = interval.bwdRange(func);

    assert(range.save == range);
}

//Test NegInfIntervalRange's interval.
unittest
{
    auto interval = NegInfInterval!Date(Date(2012, 1, 7));
    auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
    auto range = interval.bwdRange(func);

    assert(range.interval == interval);

    const cRange = range;
    static assert(__traits(compiles, cRange.interval));
}

//Test NegInfIntervalRange's func.
unittest
{
    auto interval = NegInfInterval!Date(Date(2012, 1, 7));
    auto func = everyDayOfWeek!(Date, Direction.bwd)(DayOfWeek.fri);
    auto range = interval.bwdRange(func);

    assert(range.func == func);
}
