package paopao.toml;

enum abstract TokenType(Int) {
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
