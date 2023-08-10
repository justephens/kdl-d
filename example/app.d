import kdl.dom;
import kdl.parse;

import std.file : readText;
import std.stdio : writeln;

void main(string[] args)
{
    if (args.length != 2) {
        writeln("Must provide exactly one argument - the path to KDL document to parse");
        return;
    }

    // Read file into memory
    auto input = readText(args[1]);

    // Parse
    writeln(input);
    writeln("========");
    DomVisitor vis;
    KdlParser!vis.parse(input);
    writeln(vis.root);
}
