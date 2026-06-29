package paopao.toml;

@:analyzer(optimize, local_dce, fusion, user_var_fusion)
final class Lexer {
	private final source:String;

	private var pos:Int = 0;
	private var line:Int = 1;
	private var column:Int = 1;

	public function new(source:String) {
		this.source = source;
	}

	public dynamic function tokenize():Array<Token> {
		var tokens:Array<Token> = [];

		while (!isAtEnd()) {
			var c = peek();

			switch (c) {
				case " " | "\t" | "\r":
					advance();

				case "\n":
					tokens.push(new Token(TokenType.NEWLINE, "\\n", line, column));
					advance();

				case "#":
					skipComment();

				case "=":
					tokens.push(makeToken(TokenType.EQUALS, "="));
					advance();

				case ".":
					tokens.push(makeToken(TokenType.DOT, "."));
					advance();

				case ",":
					tokens.push(makeToken(TokenType.COMMA, ","));
					advance();

				case "[":
					tokens.push(makeToken(TokenType.LBRACKET, "["));
					advance();

				case "]":
					tokens.push(makeToken(TokenType.RBRACKET, "]"));
					advance();

				case "{":
					tokens.push(makeToken(TokenType.LBRACE, "{"));
					advance();

				case "}":
					tokens.push(makeToken(TokenType.RBRACE, "}"));
					advance();

				case "\"", "'":
					tokens.push(readString());

				default:
					if (!isAtEnd() && isIdentifierStartCode(source.charCodeAt(pos))) {
						for (token in readIdentifierOrValue())
							tokens.push(token);
					} else
						throw error('Unexpected character "$c"');
			}
		}

		tokens.push(new Token(TokenType.EOF, "", line, column));

		return tokens;
	}

	// Avoid the charAt -> 1-char String -> charCodeAt round trip in the hot check.
	private inline function isIdentifierStartCode(code:Int):Bool {
		return (code >= 65 && code <= 90) // A-Z
			|| (code >= 97 && code <= 122) // a-z
			|| code == 95 // _
			|| code == 45 // -
			|| code == 43 // +
			|| (code >= 48 && code <= 57); // 0-9
	}

	private inline function isAtEnd():Bool {
		return pos >= source.length;
	}

	private inline function peek():String {
		if (isAtEnd())
			return "\x00";

		return source.charAt(pos);
	}

	private inline function peekNext():String {
		if (pos + 1 >= source.length)
			return "\x00";

		return source.charAt(pos + 1);
	}

	private function advance():String {
		var c = source.charAt(pos);

		pos++;

		if (c == "\n") {
			line++;
			column = 1;
		} else {
			column++;
		}

		return c;
	}

	private inline function makeToken(type:TokenType, value:String):Token
		return new Token(type, value, line, column);

	private inline function error(message:String):TomlError
		return new TomlError(message, line, column);

	private function skipComment():Void
		while (!isAtEnd() && peek() != "\n")
			advance();

	private function isIdentifierStart(c:String):Bool {
		if (c.length == 0)
			return false;

		var code = c.charCodeAt(0);

		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| c == "_"
			|| c == "-"
			|| (code >= "0".code && code <= "9".code);
	}

	private function readUnicodeEscape(length:Int):String {
		var hex = "";

		for (i in 0...length) {
			if (isAtEnd())
				throw new TomlError("Unexpected end of unicode escape", line, column);

			var c = advance();

			if (!~/^[0-9A-Fa-f]$/.match(c))
				throw new TomlError('Invalid hex digit "$c"', line, column);

			hex += c;
		}

		var codepoint = Std.parseInt("0x" + hex);

		return String.fromCharCode(codepoint);
	}

	private function readString():Token {
		var quote = peek();
		var startLine = line;
		var startColumn = column;

		advance(); // opening quote

		var multiline = false;
		var literal = quote == "'";

		// """ or '''
		if (peek() == quote && peekNext() == quote) {
			multiline = true;
			advance();
			advance();

			// Ignore one immediate newline after opening delimiter.
			if (peek() == "\n")
				advance();
		}

		var buf = new StringBuf();

		while (!isAtEnd()) {
			var c = advance();

			// Closing delimiter
			if (multiline) {
				if (c == quote && peek() == quote && peekNext() == quote) {
					advance();
					advance();

					return new Token(TokenType.STRING, buf.toString(), startLine, startColumn);
				}
			} else {
				if (c == quote)
					return new Token(TokenType.STRING, buf.toString(), startLine, startColumn);

				if (c == "\n")
					throw new TomlError("Newline in string", line, column);
			}

			// Literal strings have no escaping.
			if (literal) {
				buf.add(c);
				continue;
			}

			// Escape sequences
			if (c == "\\") {
				if (isAtEnd())
					throw new TomlError("Unexpected end of string", line, column);

				// Multiline string line continuation:
				// backslash + newline + following whitespace are removed.
				if (multiline && peek() == "\n") {
					advance();

					while (!isAtEnd()) {
						var p = peek();

						if (p == " " || p == "\t" || p == "\r" || p == "\n")
							advance();
						else
							break;
					}

					continue;
				}

				var escaped = advance();

				switch (escaped) {
					case "b":
						buf.addChar(0x08);

					case "t":
						buf.addChar(0x09);

					case "n":
						buf.addChar(0x0A);

					case "f":
						buf.addChar(0x0C);

					case "r":
						buf.addChar(0x0D);

					case "e":
						buf.addChar(0x1B);

					case "\"":
						buf.add("\"");

					case "\\":
						buf.add("\\");

					case "x":
						buf.add(readUnicodeEscape(2));

					case "u":
						buf.add(readUnicodeEscape(4));

					case "U":
						buf.add(readUnicodeEscape(8));

					default:
						throw new TomlError('Invalid escape sequence \\$escaped', line, column);
				}

				continue;
			}

			buf.add(c);
		}

		throw new TomlError("Unterminated string", startLine, startColumn);
	}

	private static final INT_RE = ~/^[+-]?[0-9](?:_?[0-9])*$/;
	private static final FLOAT_RE = ~/^[+-]?[0-9](?:_?[0-9])*\.[0-9](?:_?[0-9])*$/;
	private static final DATETIME_RE = ~/^[0-9]{4}-[0-9]{2}-[0-9]{2}/;

	private function isInteger(value:String):Bool
		return INT_RE.match(value);

	private function isFloat(value:String):Bool
		return FLOAT_RE.match(value);

	private function isDateTime(value:String):Bool
		return DATETIME_RE.match(value);

	private function readIdentifierOrValue():Array<Token> {
		var startLine = line;
		var startColumn = column;

		var buf = new StringBuf();

		while (!isAtEnd()) {
			var c = peek();

			switch (c) {
				case " " | "\t" | "\r" | "\n":
					break;

				case "," | "=" | "[" | "]" | "{" | "}" | "\"" | "'":
					break;

				case ".":
					// A dot right before a quote belongs to the outer
					// tokenizer (DOT token, then a fresh STRING token for
					// the quoted segment) rather than this buffer — e.g.
					// the "." in dog."tater.man" must not be swallowed
					// here, or the quoted segment gets merged into a
					// garbled bare key. A dot followed by anything else
					// (a digit, in a float; another bare key char) stays
					// buffered as before.
					if (peekNext() == "\"" || peekNext() == "'") {
						break;
					}

					buf.add(c);
					advance();

				case "#":
					break;

				default:
					buf.add(c);
					advance();
			}
		}

		var value = buf.toString();

		if (value == "true" || value == "false")
			return [new Token(TokenType.BOOLEAN, value, startLine, startColumn)];

		if (isDateTime(value))
			return [new Token(TokenType.DATETIME, value, startLine, startColumn)];

		if (isInteger(value))
			return [new Token(TokenType.INTEGER, value, startLine, startColumn)];

		if (isFloat(value))
			return [new Token(TokenType.FLOAT, value, startLine, startColumn)];

		// Not a recognized literal: treat as a bare key, possibly dotted
		// (e.g. "database.replica" in [database.replica] or a.b = 1).
		// Split it into IDENTIFIER/DOT/IDENTIFIER... so the parser sees
		// the same token shape it gets for quoted/spaced dotted keys.
		if (value.indexOf(".") >= 0) {
			var result:Array<Token> = [];
			var parts = value.split(".");

			for (i in 0...parts.length) {
				result.push(new Token(TokenType.IDENTIFIER, parts[i], startLine, startColumn));

				if (i < parts.length - 1)
					result.push(new Token(TokenType.DOT, ".", startLine, startColumn));
			}

			return result;
		}

		return [new Token(TokenType.IDENTIFIER, value, startLine, startColumn)];
	}
}
