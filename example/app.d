import kdl.dom;
import kdl.parse;

import std.file : readText;
import std.stdio : writeln;
import std.uni : byCodePoint;

void main(string[] args)
{
    if (args.length != 2) {
        writeln("Must provide exactly one argument - the path to KDL document to parse");
        return;
    }

    // Read file into memory, create a range to lazily decode the UTF-8 into codepoints
    auto inputFile = readText(args[1]);
    auto inputStream = inputFile.byCodePoint();

    // Parse
    writeln(inputStream);
    writeln("========");
    DomVisitor vis;
    KdlParser!vis.parse(inputStream);
}
