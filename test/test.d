module test.test;

import kdl;
import std.file;
import std.stdio;
import std.path;
import std.getopt;

bool verbose = false;

void main(string[] args)
{
    getopt(args,
        "verbose", &verbose);

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
        if (exists(outFile) == false || isFile(outFile) == false)
        {
            expectParseFailure = true;
        }

        write("Test ", baseName(inFile), " ... ");
        if (expectParseFailure)
            write("(expect parse failure) ");

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
                writeln("PASS");
                continue;
            }
            else
                throw e;
        }

        // Read in expected results
        string expected;
        if (expectParseFailure)
            expected = "";
        else
            expected = readText(outFile);

        // Output what we parsed
        auto output = vis.root.toString();

        // Check that output matches expected results
        if (output != expected)
            writeln("FAIL");
        else
            writeln("PASS");

        if (output != expected || verbose)
        {
            writeln("\nMore information:");
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
    }
}
