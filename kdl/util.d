module kdl.util;

/++
 + kdl.util
 + 
 + Authors: Justin Stephens
 + Copyright: 2023 Justin Stephens
 + License: MIT
 +/

import std.algorithm : startsWith;
import std.range;
import std.range.primitives;
import std.traits;
import std.utf;
import std.uni : CodepointSet;

enum IdentifierType
{
    Illegal,
    String,
    Bare,
}

/// Decodes a hex character 
byte hexLookup(T)(T c) if (isSomeChar!T)
{
    import std.ascii : toUpper;

    switch (c.toUpper)
    {
    case '0':
        return 0;
    case '1':
        return 1;
    case '2':
        return 2;
    case '3':
        return 3;
    case '4':
        return 4;
    case '5':
        return 5;
    case '6':
        return 6;
    case '7':
        return 7;
    case '8':
        return 8;
    case '9':
        return 9;
    case 'A':
        return 10;
    case 'B':
        return 11;
    case 'C':
        return 12;
    case 'D':
        return 13;
    case 'E':
        return 14;
    case 'F':
        return 15;
    default:
        assert(0);
    }
}

char hexEncode(T)(T i) if (isIntegral!T && isUnsigned!T)
{
    enum lookup = "0123456789ABCDEF";
    assert(i <= 15);
    return lookup[i];
}

/// Add a single character to a std.uni.CodepointSet
auto addChar(T)(CodepointSet set, T b)
{
    return set.add(b, cast(uint)(b + 1));
}

enum whiteSpaceSet = CodepointSet()
        .addChar('\u0009').addChar('\u0020').addChar('\u00A0')
        .addChar('\u1680').addChar('\u2000').addChar('\u2001')
        .addChar('\u2002').addChar('\u2003').addChar('\u2004')
        .addChar('\u2005').addChar('\u2006').addChar('\u2007')
        .addChar('\u2008').addChar('\u2009').addChar('\u200A')
        .addChar('\u202F').addChar('\u205F').addChar('\u3000');
enum newlineSet = CodepointSet()
        .addChar('\u000D').addChar('\u000A').addChar('\u0085')
        .addChar('\u000C').addChar('\u2028').addChar('\u2029');
enum nonIdentifierSet = CodepointSet(0x20, 0x10FFFF).inverted()
        .addChar('\\').addChar('/').addChar('(').addChar(')').addChar('{')
        .addChar('}').addChar('<').addChar('>').addChar(';').addChar('[')
        .addChar(']').addChar('=').addChar(',').addChar('"')
        .add(whiteSpaceSet).add(newlineSet);
enum octalSet = CodepointSet('0', '7' + 1);
enum digitSet = CodepointSet('0', '9' + 1);
enum hexSet = CodepointSet(digitSet).add('a', 'f' + 1).add('A', 'F' + 1);
enum nonInitialSet = nonIdentifierSet.add(digitSet);

// Generate functions to test for character types
mixin(whiteSpaceSet.toSourceCode("isWhitespace"));
mixin(newlineSet.toSourceCode("isNewline"));
mixin(nonIdentifierSet.toSourceCode("isNonIdentifier"));
mixin(octalSet.toSourceCode("isOctal"));
mixin(digitSet.toSourceCode("isDigit"));
mixin(hexSet.toSourceCode("isHex"));
mixin(nonInitialSet.toSourceCode("isNonInitial"));

/++ 
 + Chooses the first range which is not empty. All ranges must have the same element type.
 + Arguments are lazily evaluated, so any expressions will only evaluate if all prior ranges
 + are empty.
 + Params:
 +   ranges = Ranges to choose from
 +/
auto chooseFirstNonEmpty(R...)(lazy R ranges)
{
    static if (ranges.length > 1)
    {
        auto res = ranges[0]();
        return choose(res.empty() == false, res, chooseFirstNonEmpty(ranges[1 .. $]));
    }
    else
    {
        auto res = ranges[0]();
        return res;
    }
}

/++ 
 + Tries to consume the `content` string from the front of the `input` range.
 + Params:
 +   input = Input range to try and consume from
 +   content = The string to consume
 + Returns:
 +   true if `content` was matched and consumed from `input`
 +/
bool tryConsume(R, U)(ref R input, U content) if (isInputRange!R)
{
    if (input.empty() == false)
    {
        static if (isArray!U)
        {
            auto s = input.save;
            if (s.startsWith(content))
            {
                input.popFrontN(content.length);
                return true;
            }
            else
            {
                return false;
            }
        }
        else static if (isForwardRange!U)
        {
            auto s = input.save;
            if (s.startsWith(content))
            {
                for (auto i = 0; i < walkLength(content); i++)
                    input.popFront();
                return true;
            }
            else
            {
                return false;
            }
        }
        else static if (isScalarType!U)
        {
            if (input.front() == content)
            {
                input.popFront();
                return true;
            }
        }
    }
    return false;
}

/++
 + Given a string, returns the format / type of identifier that must be used in order to produce
 + valid KDL output.
 +/
IdentifierType classifyIdentifier(R)(R ident) if (isInputRange!R)
{
    if (ident.empty())
        return IdentifierType.Illegal;
    if (ident.front().isNonInitial())
        return IdentifierType.String;
    ident.popFront();

    while (ident.empty() == false)
    {
        if (ident.front().isNonIdentifier() || ident.front().isWhitespace()
            || ident.front().isNewline())
            return IdentifierType.String;
        ident.popFront();
    }
    return IdentifierType.Bare;
}

/++ 
 + Writes to an output stream, expanding illegal characters to escape codes.
 + Params:
 +   outStream = Output Stream to write to
 +   contents = contents to write to `outStream`
 +/
void writeEscaped(T, R)(scope ref T outStream, R contents)
        if (isOutputRange!(T, ElementType!R) && isInputRange!R && isSomeChar!(ElementType!R))
{
    foreach (c; contents)
    {
        switch (c)
        {
        case '\u000A':
            put(outStream, `\n`);
            break;
        case '\u000D':
            put(outStream, `\r`);
            break;
        case '\u0009':
            put(outStream, `\t`);
            break;
        case '\u005C':
            put(outStream, `\\`);
            break;
            // todo: verify the escape behavior of the solidus:
            // case '\u002F':
            //     str.put(`\/`);
            //     break;
        case '\u0022':
            put(outStream, `\"`);
            break;
        case '\u0008':
            put(outStream, `\b`);
            break;
        case '\u000C':
            put(outStream, `\f`);
            break;
        default:
            put(outStream, c);
            break;
        }
    }
}

/++
 + A ForwardRange wrapper which processes escape codes on-the-fly. The range will appear empty
 + once the string literal has been terminated by an unescaped double quote.
 +/
struct StringEscapeReader(R) if (isInputRange!R && is(ElementType!R == dchar))
{
    R src;
    bool escaped = false;
    dchar escaped_char = 0;

    this(R src, bool esc = false, dchar c = 0)
    {
        this.src = src;
        this.escaped = esc;
        this.escaped_char = c;
    }

    dchar front()
    {
        if (escaped)
        {
            return escaped_char;
        }
        else if (src.front() == '\\')
        {
            escaped = true;
            src.popFront();
            switch (src.front())
            {
            case 'n':
                src.popFront();
                escaped_char = '\u000A';
                break;
            case 'r':
                src.popFront();
                escaped_char = '\u000D';
                break;
            case 't':
                src.popFront();
                escaped_char = '\u0009';
                break;
            case '\\':
                src.popFront();
                escaped_char = '\u005C';
                break;
            case '/':
                src.popFront();
                escaped_char = '\u002F';
                break;
            case '"':
                src.popFront();
                escaped_char = '\u0022';
                break;
            case 'b':
                src.popFront();
                escaped_char = '\u0008';
                break;
            case 'f':
                src.popFront();
                escaped_char = '\u000C';
                break;
            case 'u':
                // pop 'u' and '{'
                src.popFront();
                src.popFront();

                // decode the hex code between the brackets into a dchar
                escaped_char = 0;
                while (src.front() != '}')
                {
                    if (src.front().isHex() == false)
                        throw new Exception("Invalid unicode escape sequence");
                    escaped_char <<= 4;
                    escaped_char |= hexLookup(src.front());
                    src.popFront();
                }
                src.popFront();
                break;
            default:
                throw new Exception("Invalid escape sequence");
            }
            return escaped_char;
        }
        else
        {
            return src.front();
        }
    }

    void popFront()
    {
        if (escaped)
            escaped = false;
        else
            src.popFront();
    }

    bool empty()
    {
        if (src.empty())
            return true;
        if (front() == '"' && escaped == false)
        {
            popFront();
            escaped_char = '"';
            return true;
        }
        if (escaped_char == '"' && escaped == false)
            return true;
        return false;
    }

    auto save()
    {
        return StringEscapeReader(this.src.save(), escaped, escaped_char);
    }
}
