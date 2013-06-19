module std.algorithm.distance;

import std.algorithm;
import std.range, std.functional, std.traits;

version(unittest)
{
}

/**
Encodes $(WEB realityinteractive.com/rgrzywinski/archives/000249.html,
edit operations) necessary to transform one sequence into
another. Given sequences $(D s) (source) and $(D t) (target), a
sequence of $(D EditOp) encodes the steps that need to be taken to
convert $(D s) into $(D t). For example, if $(D s = "cat") and $(D
"cars"), the minimal sequence that transforms $(D s) into $(D t) is:
skip two characters, replace 't' with 'r', and insert an 's'. Working
with edit operations is useful in applications such as spell-checkers
(to find the closest word to a given misspelled word), approximate
searches, diff-style programs that compute the difference between
files, efficient encoding of patches, DNA sequence analysis, and
plagiarism detection.
*/

enum EditOp : char
{
    /** Current items are equal; no editing is necessary. */
    none = 'n',
    /** Substitute current item in target with current item in source. */
    substitute = 's',
    /** Insert current item from the source into the target. */
    insert = 'i',
    /** Remove current item from the target. */
    remove = 'r'
}

struct Levenshtein(Range, alias equals, CostType = size_t)
{
    void deletionIncrement(CostType n)
    {
        _deletionIncrement = n;
        InitMatrix();
    }

    void insertionIncrement(CostType n)
    {
        _insertionIncrement = n;
        InitMatrix();
    }

    CostType distance(Range s, Range t)
    {
        auto slen = walkLength(s.save);
        auto tlen = walkLength(t.save);

        allocMatrix(slen + 1, tlen + 1);
        foreach (i; 1 .. rows)
        {
            auto sfront = s.front;
            s.popFront();
            auto tt = t;
            foreach (j; 1 .. cols)
            {
                auto cSub = _matrix[i - 1][j - 1]
                    + (equals(sfront, tt.front) ? 0 : _substitutionIncrement);
                tt.popFront();
                auto cIns = _matrix[i][j - 1] + _insertionIncrement;
                auto cDel = _matrix[i - 1][j] + _deletionIncrement;
                switch (min_index(cSub, cIns, cDel))
                {
                case 0:
                    _matrix[i][j] = cSub;
                    break;
                case 1:
                    _matrix[i][j] = cIns;
                    break;
                default:
                    _matrix[i][j] = cDel;
                    break;
                }
            }
        }
        return _matrix[slen][tlen];
    }

    EditOp[] path(Range s, Range t)
    {
        distance(s, t);
        return path();
    }

    EditOp[] path()
    {
        EditOp[] result;
        size_t i = rows - 1, j = cols - 1;
        // restore the path
        while (i || j)
        {
            auto cIns = j == 0 ? CostType.max : _matrix[i][j - 1];
            auto cDel = i == 0 ? CostType.max : _matrix[i - 1][j];
            auto cSub = i == 0 || j == 0
                ? CostType.max
                : _matrix[i - 1][j - 1];
            switch (min_index(cSub, cIns, cDel))
            {
            case 0:
                result ~= _matrix[i - 1][j - 1] == _matrix[i][j]
                    ? EditOp.none
                    : EditOp.substitute;
                --i;
                --j;
                break;
            case 1:
                result ~= EditOp.insert;
                --j;
                break;
            default:
                result ~= EditOp.remove;
                --i;
                break;
            }
        }
        reverse(result);
        return result;
    }

private:
    CostType _deletionIncrement = 1,
             _insertionIncrement = 1,
             _substitutionIncrement = 1;
    CostType[][] _matrix;
    size_t rows, cols;

    void allocMatrix(size_t r, size_t c)
    {
        rows = r;
        cols = c;
        if (!_matrix || _matrix.length < r || _matrix[0].length < c)
        {
            delete _matrix;
            _matrix = new CostType[][](r, c);
            InitMatrix();
        }
    }

    void InitMatrix()
    {
        foreach (i, row; _matrix)
        {
            row[0] = i * _deletionIncrement;
        }
        if (!_matrix)
            return;
        for (auto i = 0u; i != _matrix[0].length; ++i)
        {
            _matrix[0][i] = i * _insertionIncrement;
        }
    }

    static uint min_index(CostType i0, CostType i1, CostType i2)
    {
        if (i0 <= i1)
        {
            return i0 <= i2 ? 0 : 2;
        }
        else
        {
            return i1 <= i2 ? 1 : 2;
        }
    }
}

/**
 * Returns the $(WEB wikipedia.org/wiki/Levenshtein_distance, Levenshtein
 * distance) between $(D s) and $(D t). The Levenshtein distance computes
 * the minimal amount of edit operations necessary to transform $(D s)
 * into $(D t).  Performs $(BIGOH s.length * t.length) evaluations of $(D
 * equals) and occupies $(BIGOH s.length * t.length) storage.
 */
size_t levenshteinDistance(alias equals = "a == b", Range1, Range2)(Range1 s, Range2 t)
if (isForwardRange!Range1 && isForwardRange!Range2)
{
    Levenshtein!(Range1, binaryFun!equals, size_t) lev;
    return lev.distance(s, t);
}

///
unittest
{
    assert(levenshteinDistance("cat", "rat") == 1);
    assert(levenshteinDistance("parks", "spark") == 2);
    assert(levenshteinDistance("kitten", "sitting") == 3);
    assert(levenshteinDistance!("std.uni.toUpper(a) == std.uni.toUpper(b)")
        ("parks", "SPARK") == 2);
}

/**
 * Returns the Levenshtein distance and the edit path between $(D s) and
 * $(D t).
 */
Tuple!(size_t, EditOp[])
levenshteinDistanceAndPath(alias equals = "a == b", Range1, Range2)(Range1 s, Range2 t)
if (isForwardRange!Range1 && isForwardRange!Range2)
{
    Levenshtein!(Range1, binaryFun!(equals)) lev;
    auto d = lev.distance(s, t);
    return tuple(d, lev.path());
}

///
unittest
{
    string a = "Saturday", b = "Sunday";
    auto p = levenshteinDistanceAndPath(a, b);
    assert(p[0] == 3);
    assert(equal(p[1], "nrrnsnnn"));
}

unittest
{
    debug(std_algorithm) scope(success)
        writeln("unittest @", __FILE__, ":", __LINE__, " done.");
    assert(levenshteinDistance("a", "a") == 0);
    assert(levenshteinDistance("a", "b") == 1);
    assert(levenshteinDistance("aa", "ab") == 1);
    assert(levenshteinDistance("aa", "abc") == 2);
    assert(levenshteinDistance("Saturday", "Sunday") == 3);
    assert(levenshteinDistance("kitten", "sitting") == 3);
    //lev.deletionIncrement = 2;
    //lev.insertionIncrement = 100;
    string a = "Saturday", b = "Sunday";
    auto p = levenshteinDistanceAndPath(a, b);
    assert(cast(string) p[1] == "nrrnsnnn");
}
