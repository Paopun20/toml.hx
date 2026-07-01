package paopao.toml;

/*
PInt8 is Platform Int8
*/

#if cpp
typedef PInt8 = cpp.Int8;
#elseif cs
typedef PInt8 = cs.StdTypes.Int8;
#elseif java
typedef PInt8 = java.StdTypes.Int8;
#else
typedef PInt8 = Int;
#end

enum abstract TokenType(PInt8) {
	var EOF;

	// literals
	var STRING;
	var MULTILINE_STRING;
	var INTEGER;
	var FLOAT;
	var BOOLEAN;
	var DATETIME;

	// identifiers / keys
	var IDENTIFIER;

	// punctuation
	var DOT;
	var COMMA;
	var EQUALS;

	// brackets
	var LBRACKET;
	var RBRACKET;

	// braces
	var LBRACE;
	var RBRACE;

	// special
	var NEWLINE;
}
