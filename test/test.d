module test.test;

import kdl;
import std.file;
import std.stdio;
import std.path;

void main(string[] args)
{
    // Make sure the KDL test cases are here
    auto testInputDir = buildNormalizedPath(getcwd(), "test/kdl/tests/test_cases/input");
    auto testExpectedDir = buildNormalizedPath(getcwd(), "test/kdl/tests/test_cases/expected_kdl");
    if (isDir(testInputDir) == false || isDir(testExpectedDir) == false)
    {
        writeln("Cannot locate tests. Please make sure 'test/kdl' submodule exists");
        return;
    }

    // Go file-by-file and make sure our output matches the input
    foreach (inFile; testInputDir.dirEntries(SpanMode.shallow))
    {
        auto outFile = buildNormalizedPath(testExpectedDir, baseName(inFile));

        bool expectParseFailure = false;
        if (isFile(outFile) == false)
        {
            expectParseFailure = true;
        }

        writeln("Test ", baseName(inFile));
        if (expectParseFailure)
            writeln("    Expect parse failure");
        else
            writeln("    Expect match with ", baseName(outFile));
        
        // Parse input file
        auto input = readText(inFile);
        DomVisitor vis;
        try
        {
            KdlParser!vis.parse(input);
        }
        catch (Exception e)
        {
            if (expectParseFailure)
            {
                writeln("  PASS");
                continue;
            }
            else
                throw e;
        }

        // Check that output matches input
        auto expected = readText(outFile);
        auto output = vis.root.toString();

        if (output != expected)
        {
            writeln("  FAIL\n");
            writeln("More information:");
            writeln(inFile, " (source):");
            writeln("----------------");
            writeln(readText(inFile));
            writeln();
            writeln(outFile, " (expected):");
            writeln("----------------");
            writeln(expected);
            writeln();
            writeln("Actual output:");
            writeln("----------------");
            writeln(output);
            writeln("\n\n");
        }
        else
        {
            writeln("  PASS");
        }
    }
}
