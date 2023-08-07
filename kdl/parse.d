/++
 + kdl.parse
 +
 + See_Also: The [KDL Specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md)
 +/

module kdl.parse;

import std.algorithm;
import std.conv;
import std.range;
import std.range.primitives;
import std.traits;
import std.utf;
import std.uni;

bool isKdlVisitor(T)()
{
    return hasMember!(T, "visitIdentifier");
}

byte hexLookup(T)(T c)
{
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
    if (input.empty() == false && input.startsWith(content))
    {
        static if (isArray!U)
        {
            for (auto i = 0; i < content.length; i++)
                input.popfront();
        }
        else static if (isForwardRange!U)
        {
            for (auto i = 0; i < walkLength(content); i++)
                input.popfront();
        }
        else static if (isScalarType!U)
        {
            input.popFront();
        }
        return true;
    }
    else
        return false;
}

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
 + KDL parsing utilities are templated at the top level according to:
 + Params:
 +   V = the Visitor type.
 +/
template KdlParser(V)
{
    void parse(R)(V visitor, R input)
    {
        parseBareIdentifier(visitor, input);
    }

    auto parseNode(R)(V visitor, R input)
    {
        bool slashdash = false;
        if (input.tryConsume("/-"))
        {
            slashdash = true;
            input.popFront();
            input.popFront();
        }
        return slashdash;
    }

    auto parseIdentifier(R)(R input)
    {

    }

    /++ 
     + Parses a bare identifier. Note, will parse reserved keywords like "true", "false", or "null". It
     + is up to the caller to handle those cases.
     + Params:
     +   input = Forward Range of the current location in the KDL document
     + Returns:
     +   Empty range if no valid identifier was found
     +   Forward Range of the bare identifier, if found
     +/
    auto parseBareIdentifier(R)(R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        if (input.front().isNonInitial())
            return input.take(0);

        auto start = input.save();
        size_t n = 0;

        // Leading sign characters are fine, as long as the next characters are not integers
        if (input.front() == '-' || input.front() == '+')
        {
            input.popFront();
            n++;
            if (input.front().isDigit())
                return input.take(0);
        }

        while (input.empty() == false && input.front().isNonIdentifier() == false)
        {
            input.popFront();
            n++;
        }

        return start.take(n);
    }

    unittest
    {
        assert(parseBareIdentifier("nodeName").equal("nodeName"));
        assert(parseBareIdentifier("nodeName attrib=3").equal("nodeName"));
        assert(parseBareIdentifier("😀789 node").equal("😀789"));
        assert(parseBareIdentifier("+myNode").equal("+myNode"));
        assert(parseBareIdentifier("+78node").equal(""));
    }

    /++ 
     + Parses an "Escaped String", i.e. a string literal between two double quotes.
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Decoded string literal, omitting the enclosing quotes; Empty range if there is not a valid
     +   string literal on input.
     +/
    auto parseEscapedString(R)(R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        /// A ForwardRange wrapper which processes escape codes on-the-fly. The range will appear empty
        /// once the string literal has been terminated by an unescaped double quote.
        struct StringEscapeRange
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
                return (src.empty() && escaped == false)
                    || (front() == '"' && escaped == false);
            }

            auto save()
            {
                return StringEscapeRange(this.src.save(), escaped, escaped_char);
            }
        }

        auto string = StringEscapeRange(input);
        if (string.front() != '"')
            return string.take(0);
        else
            string.popFront();

        size_t n = 0;
        auto start = string.save();

        while (string.empty() == false)
        {
            string.popFront();
            n++;
        }
        string.popFront();
        return start.take(n);
    }

    unittest
    {
        assert(parseEscapedString(`"Just a string."`).equal(`Just a string.`));
        assert(parseEscapedString(`"A string with \"several\" \u{005C}escape codes. \u{00B5}"`)
                .equal(`A string with "several" \escape codes. µ`));
    }

    /++ 
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Raw contents between opening and closing tags; Empty range if there was no valid raw string
     +   literal on input.
     + Throws:
     +   Exception if a raw string is not closed before end-of-input.
     +/
    auto parseRawString(R)(R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        if (input.tryConsume('r') == false)
            return input.take(0);

        // Parse the hash-plus-quote tag used to open the raw string, then reverse it to make the
        // closing pattern
        auto closeTag = to!(dchar[])(input.until('"', No.openRight));
        reverse(closeTag);
        for (auto i = 0; i < closeTag.length; i++)
            input.popFront();

        auto start = input.save();
        size_t n = 0;

        // Read until the closing tag is seen.
        // todo: std.algorithm.searching.boyerMooreFinder requires a random-access haystack, so it
        //       cannot be used out of the box here. A custom implementation of the algorithm should
        //       be implemented to operate on ForwardRange haystacks in chunks.
        while (input.empty() == false && input.startsWith(closeTag) == false)
        {
            input.popFront();
            n++;
        }

        if (input.empty())
            throw new Exception("Unterminated raw string literal");
        else
            for (auto i = 0; i < closeTag.length; i++)
                input.popFront();

        // Return the unprocessed contents between the opening and closing tags
        return start.take(n);
    }

    unittest
    {
        assert(parseRawString(`r#"Just a "raw" string \with\no\escapes"# and more values`)
                .equal(`Just a "raw" string \with\no\escapes`));
    }

    /++ 
     + 
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     +/
    auto parseNumber(R)(R input) if (isForwardRange!R && is(ElementType!R == dchar))
    {
        bool sign_pos = true;

        if (input.front() == '-')
        {
            sign_pos = false;
            input.popFront();
        }
        else if (input.front() == '+')
            input.popFront();

        auto prefix = input.take(2);
        if (prefix.equal("0b"))
        {
            input.popFront();
            input.popFront();

            ulong bin = 0;
            while (true)
            {
                if (input.front() == '0')
                {
                    bin <<= 1;
                }
                else if (input.front() == '1')
                {
                    bin <<= 1;
                    bin |= 1;
                }
                else if (input.front() == '_')
                    continue;
                else
                    break;
            }

            import std.stdio;

            writeln("Binary literal: ", bin);
        }
        else if (prefix.equal("0o"))
        {
            input.popFront();
            input.popFront();

            ulong oct = 0;

            while (true)
            {
                if (input.front().isOctal())
                {
                    oct <<= 3;
                    oct |= hexLookup(input.front());
                }
                else if (input.front() == '_')
                    continue;
                else
                    break;
            }

            import std.stdio;

            writeln("Octal literal: ", bin);
        }
        else if (prefix.equal("0x"))
        {
            input.popFront();
            input.popFront();
            ulong hex = 0;
            while (true)
            {
                if (input.front().isHex())
                {
                    hex <<= 3;
                    hex |= hexLookup(input.front());
                }
                else if (input.front() == '_')
                    continue;
                else
                    break;
            }

            import std.stdio;

            writeln("Octal literal: ", bin);
        }
        else
        {
            ulong integral = 0;
            ulong fractional = 0;
            ulong exponent = 0;

            while (input.front().isDigit())
            {
                integral *= 10;
                integral += hexLookup(input.front());
                input.popFront();
            }

            if (input.front() == '.')
            {
                input.popFront();
                while (input.front().isDigit())
                {
                    fractional *= 10;
                    fractional += hexLookup(input.front());
                    input.popFront();
                }
            }

            if (input.front().toUpper() == 'E')
            {
                bool exponent_pos = true;
                if (input.front() == '+')
                    input.popFront();
                else if (input.front() == '-')
                {
                    exponent_pos = false;
                    input.popFront();
                }

                while (input.front().isDigit())
                {
                    exponent += hexLookup(input.front());
                    input.popFront();
                }

                if (exponent_pos == false)
                    exponent = -exponent;
            }
        }
    }

    unittest
    {
    }
}
