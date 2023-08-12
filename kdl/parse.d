module kdl.parse;

/++
 + kdl.parse
 + 
 + Authors: Justin Stephens
 + Copyright: 2023 Justin Stephens
 + License: MIT
 +
 + See_Also: The [KDL Specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md)
 +/

import kdl.util;

import std.algorithm;
import std.conv;
import std.range;
import std.range.primitives;
import std.traits;
import std.typecons;
import std.meta;
import std.utf;
import std.uni;

enum Token : uint
{
    DocumentBegin,
    DocumentEnd,
    SlashDash,
    TypeHint,
    Node,
    NodeEnd,
    ChildrenBegin,
    ChildrenEnd,
    Property,
    RawString,
    EscapedString,
    BasedNumber,
    DecimalNumber,
    Keyword,
}

enum Keyword
{
    None,
    Null,
    True,
    False,
}

enum Radix
{
    Unknown,
    Decimal,
    Hex,
    Octal,
    Binary,
}

struct BasedNumber
{
    Radix radix;
    ulong value;

    string toString() const @safe pure
    {
        enum bases = AliasSeq!(
                tuple(Radix.Binary, 1, "0b"),
                tuple(Radix.Octal, 3, "0o"),
                tuple(Radix.Hex, 4, "0x")
            );
        auto str = appender!(char[])();

        static foreach (t; bases)
        {
            if (radix == t[0])
            {
                ulong v = value;
                while (v > 0)
                {
                    str.put(hexEncode(v & 0b1));
                    v >>= t[1];
                }

                str.put(t[2].retro());
            }
        }

        return str[].reverse;
    }
}

struct DecimalNumber
{
    bool sign;
    ulong integral;
    ulong fractional;
    ubyte fractionalDigits;
    bool exponentSign;
    ulong exponent;
}

alias EmitFlag = Flag!"emit";

/++
 + KDL parsing utilities are templated at the top level to allow control over parser behavior.
 +
 + Params:
 +   visitor = the visitor which is informed of parser outputs.
 +/
template KdlParser(alias visitor)
{
    void parse(R)(ref R input) if (isForwardRange!R && !is(ElementType!R == dchar))
    {
        parse(input.byCodePoint());
    }

    void parse(R)(ref R input) if (isForwardRange!R && is(ElementType!R == dchar))
    {
        visitor.visit!(Token.DocumentBegin)();
        parseNodes(input);
        visitor.visit!(Token.DocumentEnd)();
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

    bool parseSlashDash(R)(ref R input)
    {
        if (input.tryConsume("/-"))
        {
            visitor.visit!(Token.SlashDash)();
            readNodeSpacing(input);
            return true;
        }
        else
            return false;
    }

    bool parseTypeHint(R)(ref R input)
    {
        auto start = input.save();
        if (input.tryConsume('(') == false)
            return false;

        auto hint = readIdentifier(input);
        if (hint.empty())
            return false;

        if (input.tryConsume(')') == false)
        {
            throw new Exception(
                "Type hint closing parenthesis missing or not adjacent to type identifier");
        }

        visitor.visit!(Token.TypeHint)(hint);
        return true;
    }

    bool parseNode(R)(ref R input)
    {
        parseSlashDash(input);
        parseTypeHint(input);

        auto identifier = readIdentifier(input);

        if (identifier.empty())
            return false;
        if (readNodeSpacing(input) == false && input.empty() == false)
            return false;

        visitor.visit!(Token.Node)(identifier);

        // Read properties and values as long as possible
        while (true)
        {
            parseSlashDash(input);

            readNodeSpacing(input);

            if (parseProperty(input))
                continue;
            if (parseValue(input))
                continue;
            break;
        }

        // Check for children
        readNodeSpacing(input);
        parseSlashDash(input);
        if (input.tryConsume("{"))
        {
            visitor.visit!(Token.ChildrenBegin)();

            parseNodes(input);

            if (input.tryConsume("}") == false)
                return false;

            visitor.visit!(Token.ChildrenEnd)();
        }

        visitor.visit!(Token.NodeEnd)();

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

        // Parse optional prefixes
        parseTypeHint(input);

        // Try to parse each of the value-literal options
        if (parseRawString(input))
            return true;
        if (parseEscapedString(input))
            return true;
        if (parseBasedLiteral(input))
            return true;
        if (parseDecimalNumber(input))
            return true;
        if (parseKeyword(input))
            return true;

        input = start;
        return false;
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

        visitor.visit!(Token.Property)(ident);

        if (parseValue(input) == false)
            return false;

        return true;
    }

    /++ 
     + Reads an "Escaped String", i.e. a string literal between two double quotes.
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Decoded string literal, omitting the enclosing quotes; Empty range if there is not a valid
     +   string literal on input.
     +/
    auto parseEscapedString(EmitFlag emit = Yes.emit, R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        auto es = StringEscapeReader!R(input);
        if (input.empty() || es.front() != '"')
        {
            static if (emit)
                return false;
            else
                return es.take(0);
        }
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

        static if (emit)
        {
            visitor.visit!(Token.EscapedString)(start.take(n));
            return true;
        }
        else
            return start.take(n);
    }

    unittest
    {
        string str1 = `"Just a string."`;
        assert(parseEscapedString(str1).equal(`Just a string.`));

        string str2 = `"A string with \"several\" \u{005C}escape codes. \u{00B5}"`;
        assert(parseEscapedString(str2)
                .equal(`A string with "several" \escape codes. µ`));
    }

    /++ 
     + Params:
     +   input = Forward Range of current parse location in the KDL document
     + Returns:
     +   Raw contents between opening and closing tags; Empty range if there was no valid raw string
     +   literal on input.
     +/

    /++ 
     + 
     + Params:
     +      input = Forward Range of the KDL document
     + Returns:
     +      If `emit`, returns a boolean status flag
     +      If not `emit`, returns a range over the contents of the string; range is empty to
     +      indicate failure.
     +/
    auto parseRawString(EmitFlag emit = Yes.emit, R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        auto start = input.save;

        if (input.tryConsume('r') == false)
        {
            input = start;
            static if (emit)
                return false;
            else
                return input.take(0);
        }

        // Parse the hash-plus-quote tag used to open the raw string, then reverse it to make the
        // closing pattern
        size_t delimiter_len = 0;
        while (input.tryConsume('#'))
            delimiter_len++;
        if (input.tryConsume('"') == false)
        {
            input = start;
            static if (emit)
                return false;
            else
                return input.take(0);
        }
        auto closeTag = to!(dchar[])(chain("\"", '#'.repeat(delimiter_len)));

        auto contents = input.save();
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
        static if (emit)
        {
            visitor.visit!(Token.RawString)(contents.take(n));
            return true;
        }
        else
        {
            return contents.take(n);
        }
    }

    unittest
    {
        string str = `r#"Just a "raw" string \with\no\escapes"# and more values`;
        assert(parseRawString(str).equal(`Just a "raw" string \with\no\escapes`));
    }

    /++ 
     + Reads a based literal (0b, 0o, or 0x prefix).
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     + Returns:
     +   Tuple (BasedNumber, Range) where element 0 is the extracted and decoded literal, and
     +   element 1 is the input the literal was extracted from.
     +/
    bool parseBasedLiteral(R)(ref R input)
    {
        import std.meta : AliasSeq, Alias;
        import std.typecons : tuple;

        auto start = input.save;
        BasedNumber num;
        ulong n = 0;

        enum bases = AliasSeq!(
                tuple(Radix.Binary, 1, "0b", (dchar a) => a == '0' || a == '1'),
                tuple(Radix.Octal, 3, "0o", (dchar a) => a.isOctal()),
                tuple(Radix.Hex, 4, "0x", (dchar a) => a.isHex())
            );
        static foreach (t; bases)
        {
            {
                alias rad = Alias!(t[0]);
                alias pwr2 = Alias!(t[1]);
                alias prefix = Alias!(t[2]);
                alias isBaseChar = Alias!(t[3]);

                if (input.tryConsume(prefix))
                {
                    n += prefix.length;
                    num.value = 0;

                    if (input.empty() == false && isBaseChar(input.front()))
                    {
                        while (input.empty() == false)
                        {
                            if (isBaseChar(input.front()))
                            {
                                num.value <<= pwr2;
                                num.value |= hexLookup(input.front());
                                input.popFront();
                                n++;
                            }
                            else if (input.front() == '_')
                            {
                                input.popFront();
                                n++;
                            }
                            else
                                break;
                        }
                    }
                    else
                        throw new Exception("Based Literal prefix followed by invalid character");

                    num.radix = rad;

                    visitor.visit!(Token.BasedNumber)(num, start.take(n));
                    return true;
                }
            }
        }

        input = start;
        return false;
    }

    /++ 
     + 
     + Params:
     +   input = Forward Range of the current parse location in the KDL document
     +/
    bool parseDecimalNumber(R)(ref R input)
            if (isForwardRange!R && is(ElementType!R == dchar))
    {
        auto start = input;
        DecimalNumber num;
        ulong n = 0;

        if (input.tryConsume('-'))
        {
            num.sign = false;
            n++;
        }
        else if (input.tryConsume('+'))
        {
            num.sign = true;
            n++;
        }

        // Parse integer component
        if (input.empty() == false && input.front().isDigit())
        {
            while (input.empty() == false)
            {
                if (input.front().isDigit())
                {
                    num.integral *= 10;
                    num.integral += hexLookup(input.front());
                    n++;
                    input.popFront();
                }
                else if (input.front() == '_')
                {
                    n++;
                    input.popFront();
                }
                else
                    break;
            }
        }
        else
        {
            input = start;
            return false;
        }

        // Check if a fractional component is present, parse if it is
        if (input.empty() == false && input.front() == '.')
        {
            input.popFront();
            n++;

            if (input.empty() == false && input.front().isDigit())
            {
                while (input.empty() == false)
                {
                    if (input.front().isDigit())
                    {
                        num.fractional *= 10;
                        num.fractional += hexLookup(input.front());
                        num.fractionalDigits++;
                        n++;
                        input.popFront();
                    }
                    else if (input.front() == '_')
                    {
                        n++;
                        input.popFront();
                    }
                    else
                        break;
                }
            }
            else
                throw new Exception("Ill-formed decimal numeric");
        }

        // Check if an exponent component is present, parse if it is
        if (input.empty() == false && input.front().toUpper() == 'E')
        {
            input.popFront();
            n++;

            num.exponentSign = true;
            if (input.front() == '+')
            {
                n++;
                input.popFront();
            }
            else if (input.front() == '-')
            {
                num.exponentSign = false;
                n++;
                input.popFront();
            }

            if (input.empty() == false && input.front().isDigit())
            {
                while (input.empty() == false)
                {
                    if (input.front().isDigit())
                    {
                        num.exponent *= 10;
                        num.exponent += hexLookup(input.front());
                        n++;
                        input.popFront();
                    }
                    else if (input.front() == '_')
                    {
                        n++;
                        input.popFront();
                    }
                    else
                        break;
                }
            }
            else
                throw new Exception("Ill-formed exponent");
        }

        // Return struct
        visitor.visit!(Token.DecimalNumber)(num, input.take(n));
        return true;
    }

    /++ 
     + Parse out a keyword ("null", "false", or "true") from the input.
     + Params:
     +   input = Forward Range of the KDL document to read from
     + Returns:
     +      If emit == Yes, returns a boolean status flag (true: matched & emitted, false: no match)
     +      If emit == No, returns a Keyword enum of the keyword match (Keyword.None if no match)
     +/
    auto parseKeyword(EmitFlag emit = Yes.emit, R)(ref R input)
    {
        static if (emit)
        {
            if (input.tryConsume("true"))
                visitor.visit!(Token.Keyword)(Keyword.True);
            else if (input.tryConsume("false"))
                visitor.visit!(Token.Keyword)(Keyword.False);
            else if (input.tryConsume("null"))
                visitor.visit!(Token.Keyword)(Keyword.Null);
            else
                return false;
            return true;
        }
        else
        {
            if (input.tryConsume("true"))
                return Keyword.True;
            else if (input.tryConsume("false"))
                return Keyword.False;
            else if (input.tryConsume("null"))
                return Keyword.Null;
            else
                return Keyword.None;
        }
    }

    unittest
    {
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

        if (input.empty() == false && input.front() == '\\')
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
            while (input.empty() == false)
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
        return chooseFirstNonEmpty(
            parseRawString!(No.emit)(input),
            parseEscapedString!(No.emit)(input),
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

        // If the matched identifier is a reserved keyword, the parsing rule should fail
        if (start.take(n).equal("null") || start.take(n).equal("true")
            || start.take(n).equal("false"))
        {
            input = start;
            return start.take(0);
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
}

// Need to instantiate the template for unit tests to compile and run
version (unittest)
{
    import kdl.dom : DomVisitor;

    DomVisitor vis;
    alias DomParser = KdlParser!vis;
}
