module kdl.parse;

/++
 + kdl.parse
 +
 + See_Also: The [KDL Specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md)
 +/

import std.algorithm;
import std.conv;
import std.range;
import std.range.primitives;
import std.traits;
import std.utf;
import std.uni;

enum SlashDash : string
{
    Yes = "/-",
    No = ""
}

enum VisitType
{
    DocumentBegin,
    DocumentEnd,
    Node,
    NodeEnd,
    Property,
    Value,
    ChildrenBegin,
    ChildrenEnd,
}

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
 + Run a sequences of parsers until a non-empty result is returned
 + Params:
 +   parse = Variadic sequence of lazy parsing expressions. These will be evaluated in order, and
 +           the first to return a valid match returned.
 +/
private auto chooseFirstNonEmptyParse(R, S...)(R input, lazy S parse)
{
    static if (parse.length > 1)
    {
        auto res = parse[0]();
        return choose(res.empty() == false, res, chooseFirstNonEmptyParse(input, parse[1 .. $]));
    }
    else
    {
        auto res = parse[0]();
        return choose(res.empty() == false, res, input.take(0));
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
private bool tryConsume(R, U)(ref R input, U content) if (isInputRange!R)
{
    if (input.empty() == false && input.startsWith(content))
    {
        static if (isArray!U)
        {
            for (auto i = 0; i < content.length; i++)
                input.popFront();
        }
        else static if (isForwardRange!U)
        {
            for (auto i = 0; i < walkLength(content); i++)
                input.popFront();
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

/++
 + KDL parsing utilities are templated at the top level to allow control over parser behavior.
 +
 + Params:
 +   visitor = the visitor which is informed of parser outputs.
 +/
template KdlParser(alias visitor)
{
    void parse(R)(ref R input) if (isForwardRange!R && is(ElementType!R == dchar))
    {
        visitor.visit!(VisitType.DocumentBegin)();

        parseNodes(input);

        visitor.visit!(VisitType.DocumentEnd)();
    }

    void parseNodes(R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        while (true)
        {
            readLineSpacing(input);

            if (parseNode(input))
                continue;

            break;
        }

        readLineSpacing(input);
    }

    bool parseNode(R)(ref R input)
    {
        SlashDash slashdash = SlashDash.No;
        if (input.tryConsume("/-"))
            slashdash = SlashDash.Yes;

        auto typeHint = readTypeHint(input);

        auto identifier = readIdentifier(input);

        if (identifier.empty())
            return false;

        visitor.visit!(VisitType.Node)(slashdash, typeHint, identifier);

        // Read properties and values as long as possible
        while (true)
        {
            readNodeSpacing(input);

            if (parseProperty(input))
                continue;
            if (parseValue(input))
                continue;
            break;
        }

        // Check for children
        readNodeSpacing(input);
        SlashDash children_slashdash = SlashDash.No;
        if (input.tryConsume("/-"))
        {
            children_slashdash = SlashDash.Yes;
            readNodeSpacing(input);
        }
        if (input.tryConsume("{"))
        {
            visitor.visit!(VisitType.ChildrenBegin)(children_slashdash);

            parseNodes(input);

            if (input.tryConsume("}") == false)
                throw new Exception("Expected closing } after node children");

            visitor.visit!(VisitType.ChildrenEnd)();
        }

        visitor.visit!(VisitType.NodeEnd)();

        return true;
    }

    /++ 
     + Parses a value, i.e. "some string" or 123.3284E10
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     + Returns:
     +   True if parsing was successful in any branch of the grammar, and a call was made to the
     +   visitor. False if parsing failed.
     +/
    bool parseValue(R)(ref R input)
    {
        auto start = input.save;

        SlashDash slashdash = SlashDash.No;
        if (input.tryConsume("/-"))
            slashdash = SlashDash.Yes;

        auto typeHint = readTypeHint(input);

        auto value = input.chooseFirstNonEmptyParse(
            readRawString(input),
            readEscapedString(input),
            readNumber(input),
            readKeyword(input)
        );

        if (value.empty)
        {
            input = start;
            return false;
        }
        else
        {
            visitor.visit!(VisitType.Value)(slashdash, typeHint, value);
            return true;
        }
    }

    /++ 
     + Parses a property, i.e. someKey="someVal"
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     + Returns:
     +   True if parsing was successful in any branch of the grammar, and a call was made to the
     +   visitor. False if parsing failed.
     +/
    bool parseProperty(R)(ref R input)
    {
        auto start = input.save;

        SlashDash slashdash = SlashDash.No;
        if (input.tryConsume("/-"))
            slashdash = SlashDash.Yes;

        auto ident = readIdentifier(input);
        if (ident.empty())
        {
            input = start;
            return false;
        }

        if (input.tryConsume('=') == false)
        {
            input = start;
            return false;
        }

        visitor.visit!(VisitType.Property)(slashdash, ident);

        if (parseValue(input) == false)
            throw new Exception("Property assignment has invalid or missing value");

        return true;
    }

    bool readNewLine(R)(ref R input)
    {
        if (input.tryConsume("\r\n"))
            return true;
        if (input.empty() == false && input.front().isNewline())
        {
            input.popFront();
            return true;
        }
        return false;
    }

    void readLineSpacing(R)(ref R input)
    {
        while (true)
        {
            if (readNewLine(input))
                continue;
            if (readWhiteSpaces(input))
                continue;
            if (readSingleLineComment(input))
                continue;
            break;
        }
    }

    bool readNodeSpacing(R)(ref R input)
    {
        bool pass = false;
        pass |= readWhiteSpaces(input);

        if (input.front() == '\\')
        {
            input.popFront();
            readWhiteSpaces(input);
            readSingleLineComment(input);
            readNewLine(input);
            pass = true;
        }

        pass |= readWhiteSpaces(input);

        return pass;
    }

    bool readWhiteSpaces(R)(ref R input)
    {
        bool seen = false;
        while (true)
        {
            if (input.empty() == false && input.front().isWhitespace())
            {
                input.popFront();
                seen = true;
                continue;
            }
            if (readMultiLineComment(input))
            {
                seen = true;
                continue;
            }
            return seen;
        }
    }

    bool readSingleLineComment(R)(ref R input)
    {
        if (input.tryConsume("//"))
        {
            while (true)
            {
                if (input.tryConsume("\r\n"))
                    break;
                if (input.front().isNewline())
                {
                    input.popFront();
                    break;
                }
                input.popFront();
            }
            return true;
        }
        else
            return false;
    }

    bool readMultiLineComment(R)(ref R input)
    {
        size_t depth = 1;
        if (input.tryConsume("/*"))
        {
            while (input.empty() == false)
            {
                if (input.tryConsume("/*"))
                    depth++;
                if (input.tryConsume("*/") && --depth == 0)
                    return true;
                input.popFront();
            }
            return false;
        }
        return false;
    }

    auto readIdentifier(R)(ref R input)
    {
        return input.chooseFirstNonEmptyParse(
            readRawString(input),
            readEscapedString(input),
            readBareIdentifier(input)
        );
    }

    /++ 
     + Reads a bare identifier. Note, will parse reserved keywords like "true", "false", or "null". It
     + is up to the caller to handle those cases.
     + Params:
     +   input = Forward Range of the current location in the KDL document
     + Returns:
     +   Empty range if no valid identifier was found
     +   Forward Range of the bare identifier, if found
     +/
    auto readBareIdentifier(R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        auto start = input.save();

        if (input.empty() || input.front().isNonInitial())
            return input.take(0);

        size_t n = 0;

        // Leading sign characters are fine, as long as the next characters are not integers
        if (input.front() == '-' || input.front() == '+')
        {
            input.popFront();
            n++;
            if (input.front().isDigit())
            {
                input = start;
                return input.take(0);
            }
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
        string nodeNames = "nodeName 😀789 +myNode +78node";
        assert(readBareIdentifier(nodeNames).equal("nodeName"));
        nodeNames.skipOver(" ");
        assert(readBareIdentifier(nodeNames).equal("😀789"));
        nodeNames.skipOver(" ");
        assert(readBareIdentifier(nodeNames).equal("+myNode"));
        nodeNames.skipOver(" ");
        assert(readBareIdentifier(nodeNames).equal(""));
    }

    /++ 
     + Reads a type hint e.g. "(i32)" or "(timestamp)"
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     + Returns:
     +   Contents between the parentheses, or empty range if no type hint present.
     +/
    auto readTypeHint(R)(ref R input)
    {
        auto start = input.save();
        if (input.tryConsume('(') == false)
            return start.take(0);

        auto hint = readIdentifier(input);
        if (hint.empty())
            return start.take(0);

        if (input.tryConsume(')') == false)
        {
            throw new Exception(
                "Type hint closing parenthesis missing or not adjacent to type identifier");
        }

        // todo: how to return `hint` directly without messing up return type inference
        return start.drop(1).take(walkLength(hint));
    }

    /++ 
     + Reads an "Escaped String", i.e. a string literal between two double quotes.
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Decoded string literal, omitting the enclosing quotes; Empty range if there is not a valid
     +   string literal on input.
     +/
    auto readEscapedString(R)(ref R input)
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
                return StringEscapeRange(this.src.save(), escaped, escaped_char);
            }
        }

        auto es = StringEscapeRange(input);
        if (input.empty() || es.front() != '"')
            return es.take(0);
        else
            es.popFront();

        size_t n = 0;
        auto start = es.save();

        while (es.empty() == false)
        {
            es.popFront();
            n++;
        }

        input = es.src;
        return start.take(n);
    }

    unittest
    {
        string str1 = `"Just a string."`;
        assert(readEscapedString(str1).equal(`Just a string.`));

        string str2 = `"A string with \"several\" \u{005C}escape codes. \u{00B5}"`;
        assert(readEscapedString(str2)
                .equal(`A string with "several" \escape codes. µ`));
    }

    /++ 
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Raw contents between opening and closing tags; Empty range if there was no valid raw string
     +   literal on input.
     +/
    auto readRawString(R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        if (input.tryConsume('r') == false)
            return input.take(0);

        // Parse the hash-plus-quote tag used to open the raw string, then reverse it to make the
        // closing pattern
        size_t delimiter_len = 0;
        while (input.tryConsume('#'))
            delimiter_len++;
        if (input.tryConsume('"') == false)
            return input.take(0);
        auto closeTag = to!(dchar[])(chain("\"", '#'.repeat(delimiter_len)));

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
        string str = `r#"Just a "raw" string \with\no\escapes"# and more values`;
        assert(readRawString(str).equal(`Just a "raw" string \with\no\escapes`));
    }

    /++ 
     + 
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     +/
    auto readNumber(R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
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

            writeln("Octal literal: ", oct);
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

            writeln("Hex literal: ", hex);
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

        return "";
    }

    auto readKeyword(R)(ref R input)
    {
        auto start = input.save;
        if (input.tryConsume("true"))
            return start.take(4);
        else if (input.tryConsume("false"))
            return start.take(5);
        else if (input.tryConsume("null"))
            return start.take(4);
        else
            return start.take(0);
    }

    unittest
    {
    }
}

// Need to instantiate the template for unit tests to compile and run
version (unittest)
{
    import kdl.dom : DomVisitor;

    DomVisitor vis;
    alias DomParser = KdlParser!vis;
}
