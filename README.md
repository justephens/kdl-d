# KDL-d

A D library for parsing and operating on [KDL](kdl.dev) documents.

KDL is a markup language inspired by the DLang Community's own [SDLang](sdlang.org), but with some
design tweaks to make it more broadly appealing. KDL appears to have gained wider traction than
SDLang (and in my view rightly taken the crown for "friendliest markup language"), so I figured
it's time to bring it to D.

## Example

```D
import kdl;

import std.file : readText;
import std.stdio : writeln;

void main(string[] args)
{
    // Read file into memory, create a range to lazily decode the UTF-8 into codepoints
    auto input = readText(args[1]);

    // Parse into DOM
    DomVisitor vis;
    KdlParser!vis.parse(input);

    // vis.root is the document root

    // Print DOM
    writeln(vis.root);
}

```

## Features

- Range-based parser will parse any [Forward Range](https://dlang.org/phobos/std_range_primitives.html#isForwardRange) of `dchar`.
- Visitor pattern means parser backend can by easily customized.
  - See [doc/VisitorInterface.md] for more information.
- Parse documents into a DOM tree

### Planned features

- Parser Improvements
  - [ ] Emit comments
  - [ ] Emit indent level for each line (to allow multi-line strings to remove indents)
- Document Improvements
  - [ ] Basic DOM model
  - [ ] Automatically convert common type hints to `std` types
  - [ ] Support for [KDL Query Language](https://github.com/kdl-org/kdl/blob/main/QUERY-SPEC.md)
- Stretch Goals:
  - [ ] Support for [KDL Schema](https://github.com/kdl-org/kdl/blob/main/SCHEMA-SPEC.md)
    - [ ] Validate DOM after parsing
    - [ ] Bake validation into parser at compile time

## Build
1. To build library, run `dub`
2. To build example code, run `dub --config=example -- path/to/test/document.kdl`
3. To run test cases, run `dub test`
