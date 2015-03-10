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
module std.datetime.util;

public import core.time;

import std.datetime : Clock;
import std.traits;
// FIXME
import std.functional; //: unaryFun;


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
   $(D StopWatch) measures time as precisely as possible.

   This class uses a high-performance counter. On Windows systems, it uses
   $(D QueryPerformanceCounter), and on Posix systems, it uses
   $(D clock_gettime) if available, and $(D gettimeofday) otherwise.

   But the precision of $(D StopWatch) differs from system to system. It is
   impossible to for it to be the same from system to system since the precision
   of the system clock varies from system to system, and other system-dependent
   and situation-dependent stuff (such as the overhead of a context switch
   between threads) can also affect $(D StopWatch)'s accuracy.
  +/
@safe struct StopWatch
{
public:
    /++
       Auto start with constructor.
      +/
    this(AutoStart autostart)
    {
        if (autostart)
            start();
    }

    @safe unittest
    {
        auto sw = StopWatch(AutoStart.yes);
        sw.stop();
    }


    ///
    bool opEquals(const StopWatch rhs) const pure nothrow
    {
        return opEquals(rhs);
    }

    /// ditto
    bool opEquals(const ref StopWatch rhs) const pure nothrow
    {
        return _timeStart == rhs._timeStart &&
               _timeMeasured == rhs._timeMeasured;
    }


    /++
       Resets the stop watch.
      +/
    void reset()
    {
        if (_flagStarted)
        {
            // Set current system time if StopWatch is measuring.
            _timeStart = Clock.currSystemTick;
        }
        else
        {
            // Set zero if StopWatch is not measuring.
            _timeStart.length = 0;
        }

        _timeMeasured.length = 0;
    }

    @safe unittest
    {
        StopWatch sw;
        sw.start();
        sw.stop();
        sw.reset();
        assert(sw.peek().to!("seconds", real)() == 0);
    }


    /++
       Starts the stop watch.
      +/
    void start()
    {
        assert(!_flagStarted);
        _flagStarted = true;
        _timeStart = Clock.currSystemTick;
    }

    @trusted unittest
    {
        import core.exception : AssertError;

        StopWatch sw;
        sw.start();
        auto t1 = sw.peek();
        bool doublestart = true;
        try
            sw.start();
        catch (AssertError e)
            doublestart = false;
        assert(!doublestart);
        sw.stop();
        assert((t1 - sw.peek()).to!("seconds", real)() <= 0);
    }


    /++
       Stops the stop watch.
      +/
    void stop()
    {
        assert(_flagStarted);
        _flagStarted = false;
        _timeMeasured += Clock.currSystemTick - _timeStart;
    }

    @trusted unittest
    {
        import core.exception : AssertError;

        StopWatch sw;
        sw.start();
        sw.stop();
        auto t1 = sw.peek();
        bool doublestop = true;
        try
            sw.stop();
        catch (AssertError e)
            doublestop = false;
        assert(!doublestop);
        assert((t1 - sw.peek()).to!("seconds", real)() == 0);
    }


    /++
       Peek at the amount of time which has passed since the stop watch was
       started.
      +/
    TickDuration peek() const
    {
        if (_flagStarted)
            return Clock.currSystemTick - _timeStart + _timeMeasured;

        return _timeMeasured;
    }

    @safe unittest
    {
        StopWatch sw;
        sw.start();
        auto t1 = sw.peek();
        sw.stop();
        auto t2 = sw.peek();
        auto t3 = sw.peek();
        assert(t1 <= t2);
        assert(t2 == t3);
    }


    /++
       Set the amount of time which has been measured since the stop watch was
       started.
      +/
    void setMeasured(TickDuration d)
    {
        reset();
        _timeMeasured = d;
    }

     @safe unittest
    {
        StopWatch sw;
        TickDuration t0;
        t0.length = 100;
        sw.setMeasured(t0);
        auto t1 = sw.peek();
        assert(t0 == t1);
    }


    /++
       Confirm whether this stopwatch is measuring time.
      +/
    bool running() @property const pure nothrow
    {
        return _flagStarted;
    }

    @safe unittest
    {
        StopWatch sw1;
        assert(!sw1.running);
        sw1.start();
        assert(sw1.running);
        sw1.stop();
        assert(!sw1.running);
        StopWatch sw2 = AutoStart.yes;
        assert(sw2.running);
        sw2.stop();
        assert(!sw2.running);
        sw2.start();
        assert(sw2.running);
    }

private:

    // true if observing.
    bool _flagStarted = false;

    // TickDuration at the time of StopWatch starting measurement.
    TickDuration _timeStart;

    // Total time that StopWatch ran.
    TickDuration _timeMeasured;
}

///
@safe unittest
{
    void writeln(S...)(S args){}
    static void bar() {}

    StopWatch sw;
    enum n = 100;
    TickDuration[n] times;
    TickDuration last = TickDuration.from!"seconds"(0);
    foreach (i; 0..n)
    {
       sw.start(); //start/resume mesuring.
       foreach (unused; 0..1_000_000)
           bar();
       sw.stop();  //stop/pause measuring.
       //Return value of peek() after having stopped are the always same.
       writeln((i + 1) * 1_000_000, " times done, lap time: ",
               sw.peek().msecs, "[ms]");
       times[i] = sw.peek() - last;
       last = sw.peek();
    }
    real sum = 0;
    // To get the number of seconds,
    // use properties of TickDuration.
    // (seconds, msecs, usecs, hnsecs)
    foreach (t; times)
       sum += t.hnsecs;
    writeln("Average time: ", sum/n, " hnsecs");
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
        if (isSafe!({ StopWatch sw; unaryFun!func(sw.peek()); }))
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
                unaryFun!func(_sw.peek());
            }
        }
        return Result(AutoStart.yes);
    }

    auto measureTime(alias func)()
        if (!isSafe!({ StopWatch sw; unaryFun!func(sw.peek()); }))
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
                unaryFun!func(_sw.peek());
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


/++
    Benchmarks code for speed assessment and comparison.

    Params:
        fun = aliases of callable objects (e.g. function names). Each should
              take no arguments.
        n   = The number of times each function is to be executed.

    Returns:
        The amount of time (as a $(CXREF time, TickDuration)) that it took to
        call each function $(D n) times. The first value is the length of time
        that it took to call $(D fun[0]) $(D n) times. The second value is the
        length of time it took to call $(D fun[1]) $(D n) times. Etc.

    Note that casting the TickDurations to $(CXREF time, Duration)s will make
    the results easier to deal with (and it may change in the future that
    benchmark will return an array of Durations rather than TickDurations).

    See_Also:
        $(LREF measureTime)
  +/
TickDuration[fun.length] benchmark(fun...)(uint n)
{
    TickDuration[fun.length] result;
    StopWatch sw;
    sw.start();

    foreach (i, unused; fun)
    {
        sw.reset();
        foreach (j; 0 .. n)
            fun[i]();
        result[i] = sw.peek();
    }

    return result;
}

///
unittest
{
    import std.conv : to;
    int a;
    void f0() {}
    void f1() {auto b = a;}
    void f2() {auto b = to!string(a);}
    auto r = benchmark!(f0, f1, f2)(10_000);
    auto f0Result = to!Duration(r[0]); // time f0 took to run 10,000 times
    auto f1Result = to!Duration(r[1]); // time f1 took to run 10,000 times
    auto f2Result = to!Duration(r[2]); // time f2 took to run 10,000 times
}

@safe unittest
{
    int a;
    void f0() {}
    //void f1() {auto b = to!(string)(a);}
    void f2() {auto b = (a);}
    auto r = benchmark!(f0, f2)(100);
}


/++
   Return value of benchmark with two functions comparing.
  +/
@safe struct ComparingBenchmarkResult
{
    /++
       Evaluation value

       This returns the evaluation value of performance as the ratio of
       baseFunc's time over targetFunc's time. If performance is high, this
       returns a high value.
      +/
    @property real point() const pure nothrow
    {
        return _baseTime.length / cast(const real)_targetTime.length;
    }


    /++
       The time required of the base function
      +/
    @property public TickDuration baseTime() const pure nothrow
    {
        return _baseTime;
    }


    /++
       The time required of the target function
      +/
    @property public TickDuration targetTime() const pure nothrow
    {
        return _targetTime;
    }

private:

    this(TickDuration baseTime, TickDuration targetTime) pure nothrow
    {
        _baseTime = baseTime;
        _targetTime = targetTime;
    }

    TickDuration _baseTime;
    TickDuration _targetTime;
}


/++
   Benchmark with two functions comparing.

   Params:
       baseFunc   = The function to become the base of the speed.
       targetFunc = The function that wants to measure speed.
       times      = The number of times each function is to be executed.

   Examples:
        --------------------
        void f1() { /* ... */ }
        void f2() { /* ... */ }
        void main()
        {
           auto b = comparingBenchmark!(f1, f2, 0x80);
           writeln(b.point);
        }
        --------------------
  +/
ComparingBenchmarkResult comparingBenchmark(alias baseFunc,
                                            alias targetFunc,
                                            int times = 0xfff)()
{
    auto t = benchmark!(baseFunc, targetFunc)(times);
    return ComparingBenchmarkResult(t[0], t[1]);
}

@safe unittest
{
    void f1x() {}
    void f2x() {}
    @safe void f1o() {}
    @safe void f2o() {}
    auto b1 = comparingBenchmark!(f1o, f2o, 1)(); // OK
    //static auto b2 = comparingBenchmark!(f1x, f2x, 1); // NG
}

unittest
{
    void f1x() {}
    void f2x() {}
    @safe void f1o() {}
    @safe void f2o() {}
    auto b1 = comparingBenchmark!(f1o, f2o, 1)(); // OK
    auto b2 = comparingBenchmark!(f1x, f2x, 1)(); // OK
}

//Bug# 8450
unittest
{
    @safe    void safeFunc() {}
    @trusted void trustFunc() {}
    @system  void sysFunc() {}
    auto   safeResult = comparingBenchmark!((){ safeFunc();  }, (){ safeFunc();  })();
    auto  trustResult = comparingBenchmark!((){ trustFunc(); }, (){ trustFunc(); })();
    auto    sysResult = comparingBenchmark!((){ sysFunc();   }, (){ sysFunc();   })();
    auto mixedResult1 = comparingBenchmark!((){ safeFunc();  }, (){ trustFunc(); })();
    auto mixedResult2 = comparingBenchmark!((){ trustFunc(); }, (){ sysFunc();   })();
    auto mixedResult3 = comparingBenchmark!((){ safeFunc();  }, (){ sysFunc();   })();
}
