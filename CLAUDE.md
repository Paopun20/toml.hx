# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building and Running Tests

- **Run all tests**: `haxe test.hxml`
- **Run Main.hx**: `haxe haxe.hxml`
- **Build in cpp**: `haxe build.hxml`

## Project Architecture

### Core Structure

- `src/`: Main source code implementing TOML parser/writer with `paopao.toml` package
- `test/`: Unit tests for TOML functionality with `TestMain.hx` as entry point
- `haxelib.json`: Haxe library configuration with metadata

### Key Components

1. **TOML Parser**: Implements parsing of TOML format according to the TOML v1.1.0 specification
2. **Data Types**: Supports all TOML types including:
   - Primitive values (strings, integers, floats, booleans)
   - Tables and nested tables
   - Arrays and arrays of tables
   - Inline tables
   - Dotted key-value pairs
3. **TOML Serializer**: Converts Haxe data structures to TOML format
4. **File I/O**: Provides `parseFile()` and `save()` functions for file operations

### Key Files

- `src/paopao/toml/Toml.hx`: Main TOML implementation class with `parse()`, `parseFile()`, `stringify()`, and `save()` methods
- `test/TestMain.hx`: Comprehensive test suite covering all TOML features including:
  - Primitive types
  - Tables and nested tables
  - Arrays and arrays of tables
  - Inline tables
  - Dotted keys and key-value pairs
  - Complex edge cases (hyphen/underscore keys, float parsing, table state isolation)

## Development Workflow

1. **Add new features**: Modify files in `src/paopao/toml/`
2. **Update tests**: Add test cases in `test/TestMain.hx` using the existing `assert()` pattern
3. **Run tests**: Use `haxe test.hxml` for fast feedback during development
4. **Package**: When ready for release, run `update.ps1` to create and submit the haxelib package (ask owmer only to do this)
5. **Documentation**: Nope

## Testing Strategy

The test suite follows a comprehensive approach:

- Each test function covers a specific TOML feature
- Tests verify both successful parsing and edge cases
- Use of `trace("✓ feature")` for visual feedback during test execution
- Full test coverage of TOML v1.1.0 specification features

## Package Distribution

- Distributed via haxelib using the provided `update.ps1` script
- Package name: `toml.hx`
- Version: Defined in haxelib.json
- Built as a zip file containing src/, haxelib.json, and README.md
- Published to the haxelib registry for use with `haxelib install toml.hx`

## Key Design Decisions

1. **Haxe for Cross-platform**: Leverages Haxe's ability to target multiple platforms while maintaining a single codebase
2. **Dynamic Data Structures**: Uses Haxe's Dynamic type for flexible TOML parsing returning nested objects
3. **Full Specification Compliance**: Implements all features of TOML v1.1.0 including complex cases
4. **Error Handling**: Throws exceptions on parsing errors rather than returning null values
5. **Memory Efficient**: Uses streaming parser design for large files
