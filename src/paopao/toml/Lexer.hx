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

		skipBOM();

		while (!isAtEnd()) {
			var c = peek();

			switch (c) {
				case " " | "\t":
					advance();

				case "\r":
					if (peekNext() != "\n")
						throw error("Bare carriage return");

					tokens.push(new Token(TokenType.NEWLINE, "\\n", line, column));
					advance();
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

	private function skipBOM():Void {
		if (source.length >= 1 && source.charCodeAt(0) == 0xFEFF) {
			pos = 1;
			column = 2;
		}
	}

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

	private function skipComment():Void {
		while (!isAtEnd()) {
			var c = peek();

			if (c == "\n" || (c == "\r" && peekNext() == "\n"))
				break;

			var code = source.charCodeAt(pos);

			if (!isUnicodeScalarValue(code))
				throw error("Invalid unicode scalar");

			if (isDisallowedControlCode(code))
				throw error("Control character in comment");

			advance();
		}
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

		if (!isUnicodeScalarValue(codepoint))
			throw new TomlError('Invalid unicode scalar U+$hex', line, column);

		if (codepoint <= 0xFFFF)
			return String.fromCharCode(codepoint);

		var value = codepoint - 0x10000;
		var high = 0xD800 + (value >> 10);
		var low = 0xDC00 + (value & 0x3FF);

		return String.fromCharCode(high) + String.fromCharCode(low);
	}

	private inline function isUnicodeScalarValue(codepoint:Null<Int>):Bool
		return codepoint != null && codepoint >= 0 && codepoint <= 0x10FFFF && !(codepoint >= 0xD800 && codepoint <= 0xDFFF);

	private inline function isDisallowedControlCode(code:Int):Bool
		return (code >= 0 && code < 0x20 && code != 0x09) || code == 0x7F;

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

			// Closing delimiter for multiline strings
			if (multiline && c == quote) {
				var qCount = 1;
				while (!isAtEnd() && peek() == quote) {
					advance();
					qCount++;
				}
				if (qCount >= 3) {
					var extra = qCount - 3;
					if (extra <= 2) {
						for (i in 0...extra)
							buf.add(quote);
						return new Token(TokenType.MULTILINE_STRING, buf.toString(), startLine, startColumn);
					}
				}
				// Not a close: all quotes are content
				for (i in 0...qCount)
					buf.add(quote);
				continue;
			}

			// Single-line string closing
			if (!multiline && c == quote)
				return new Token(TokenType.STRING, buf.toString(), startLine, startColumn);

			if (!multiline && c == "\n")
				throw new TomlError("Newline in string", line, column);

			// Literal strings have no escaping.
			if (literal) {
				if (c == "\r" && multiline && peek() == "\n") {
					advance();
					buf.add("\n");
					continue;
				}

				var code = source.charCodeAt(pos - 1);

				if (!isUnicodeScalarValue(code))
					throw new TomlError("Invalid unicode scalar", line, column);

				if (isDisallowedControlCode(code) && !(multiline && c == "\n"))
					throw new TomlError("Control character in string", line, column);

				buf.add(c);
				continue;
			}

			// Escape sequences
			if (c == "\\") {
				if (isAtEnd())
					throw new TomlError("Unexpected end of string", line, column);

				// Multiline string line continuation:
				// backslash followed only by whitespace before a newline
				// strips all whitespace (including newlines) up to the
				// next non-whitespace character.
				if (multiline) {
					var savedPos = pos;
					var savedLine = line;
					var savedColumn = column;
					while (!isAtEnd() && (peek() == " " || peek() == "\t"))
						advance();
					if (!isAtEnd() && (peek() == "\n" || peek() == "\r")) {
						if (peek() == "\r" && peekNext() == "\n")
							advance();
						advance();
						while (!isAtEnd()) {
							var p = peek();
							if (p == " " || p == "\t" || p == "\n" || p == "\r")
								advance();
							else
								break;
						}
						continue;
					}
					pos = savedPos;
					line = savedLine;
					column = savedColumn;
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

			if (c == "\r" && multiline && peek() == "\n") {
				advance();
				buf.add("\n");
				continue;
			}

			var code = source.charCodeAt(pos - 1);

			if (!isUnicodeScalarValue(code))
				throw new TomlError("Invalid unicode scalar", line, column);

			if (isDisallowedControlCode(code) && !(multiline && c == "\n"))
				throw new TomlError("Control character in string", line, column);

			buf.add(c);
		}

		throw new TomlError("Unterminated string", startLine, startColumn);
	}

	// Integer: decimal with optional underscores, +0, -0
	private static final INT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)$/;

	// Float with decimal point (optional exponent)
	private static final FLOAT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)\.[0-9](?:_?[0-9])*(?:[eE][+-]?[0-9](?:_?[0-9])*)?$/;

	// Float without decimal point (exponent only, e.g. 3e2, 3e+2)
	private static final EXPONENT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)[eE][+-]?[0-9](?:_?[0-9])*$/;

	// Special float values: inf, nan, with optional sign
	private static final INF_NAN_RE = ~/^[+-]?(?:inf|nan)$/;

	// Integer: hex, octal, binary (lowercase prefix only per TOML spec)
	private static final HEX_INT_RE = ~/^0x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*$/;
	private static final OCT_INT_RE = ~/^0o[0-7](?:_?[0-7])*$/;
	private static final BIN_INT_RE = ~/^0b[01](?:_?[01])*$/;

	// Full date: YYYY-MM-DD
	private static final DATE_RE = ~/^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;

	// Full datetime with timezone (Z/z or offset), T/t or space separator,
	// seconds optional, fraction optional.
	private static final DATETIME_RE = ~/^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})?$/;

	// Local datetime without timezone, seconds optional
	private static final LOCAL_DATETIME_RE = ~/^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?$/;

	// Local time: HH:MM:SS, HH:MM, with optional fraction
	private static final LOCAL_TIME_RE = ~/^([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?$/;

	// Time with optional timezone
	private static final TIME_RE = ~/^([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})?$/;

	private function readIdentifierOrValue():Array<Token> {
		var startLine = line;
		var startColumn = column;

		var buf = new StringBuf();

		while (!isAtEnd()) {
			var c = peek();

			switch (c) {
				case "\t" | "\r" | "\n":
					break;

				case " ":
					// Allow space in datetime values: YYYY-MM-DD HH:MM:SS
					if (looksLikeDatePrefix(buf.toString()) && !isAtEnd() && peekNext() >= "0" && peekNext() <= "9") {
						buf.add(c);
						advance();
						continue;
					}
					break;

				case "," | "=" | "[" | "]" | "{" | "}" | "\"" | "'":
					break;

				case ".":
					// If next char is a quote, or not a valid bare key char,
					// emit the dot as a separate DOT token
					var next = peekNext();
					if (next == "\"" || next == "'" || !isBareKeyChar(next.charCodeAt(0))) {
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

		if (value == "" || value == "+")
			throw new TomlError('Invalid bare key "$value"', startLine, startColumn);

		// Values with dots could be floats, datetimes, or dotted bare keys.
		// Check typed patterns first so that e.g. 3.14 is recognized as
		// FLOAT rather than split into IDENTIFIER(3), DOT, IDENTIFIER(14).
		if (value.indexOf(".") >= 0 && (isFloat(value) || isDateTime(value))) {
			if (isDateTime(value))
				return [new Token(TokenType.DATETIME, value, startLine, startColumn)];

			if (isFloat(value))
				return [new Token(TokenType.FLOAT, value, startLine, startColumn)];
		}

		// Dotted bare key (e.g. a.b): split into parts
		if (value.indexOf(".") >= 0) {
			var parts = value.split(".");
			var allValid = true;
			for (i in 0...parts.length) {
				if (!isValidBareKey(parts[i])) {
					allValid = false;
					break;
				}
			}
			if (allValid) {
				var result:Array<Token> = [];
				for (i in 0...parts.length) {
					result.push(new Token(TokenType.IDENTIFIER, parts[i], startLine, startColumn));
					if (i < parts.length - 1)
						result.push(new Token(TokenType.DOT, ".", startLine, startColumn));
				}
				return result;
			}
			// Not a valid dotted bare key — fall through to typed value check
		}

		// Check for special float-like values that are NOT valid bare keys
		// (inf, nan, exponent-only floats like 3e+2). These must be
		// recognized here since they won't parse as bare keys.
		if (!isValidBareKey(value)) {
			if (isDateTime(value))
				return [new Token(TokenType.DATETIME, value, startLine, startColumn)];

			if (isFloat(value))
				return [new Token(TokenType.FLOAT, value, startLine, startColumn)];

			if (isInteger(value))
				return [new Token(TokenType.INTEGER, value, startLine, startColumn)];

			throw new TomlError('Invalid bare key "$value"', startLine, startColumn);
		}

		// The value IS a valid bare key, but might also be a typed literal.
		// In TOML, bare keys that look like integers, floats, booleans, or
		// dates are still keys, not values. We produce an IDENTIFIER token
		// and let the parser reinterpret when in value context.
		return [new Token(TokenType.IDENTIFIER, value, startLine, startColumn)];
	}

	private function isBareKeyChar(code:Int):Bool {
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95 || code == 45;
	}

	private function isValidBareKey(value:String):Bool {
		if (value.length == 0)
			return false;

		for (i in 0...value.length) {
			if (!isBareKeyChar(value.charCodeAt(i)))
				return false;
		}

		return true;
	}

	private function isInteger(value:String):Bool {
		if (value == "+0" || value == "-0")
			return true;

		return INT_RE.match(value) || HEX_INT_RE.match(value) || OCT_INT_RE.match(value) || BIN_INT_RE.match(value);
	}

	private function isFloat(value:String):Bool {
		return FLOAT_RE.match(value) || EXPONENT_RE.match(value) || INF_NAN_RE.match(value);
	}

	private function isDateTime(value:String):Bool {
		if (DATE_RE.match(value))
			return isValidDate(Std.parseInt(DATE_RE.matched(1)), Std.parseInt(DATE_RE.matched(2)), Std.parseInt(DATE_RE.matched(3)));

		if (LOCAL_DATETIME_RE.match(value))
			return isValidDateTime(Std.parseInt(LOCAL_DATETIME_RE.matched(1)), Std.parseInt(LOCAL_DATETIME_RE.matched(2)),
				Std.parseInt(LOCAL_DATETIME_RE.matched(3)), Std.parseInt(LOCAL_DATETIME_RE.matched(4)), Std.parseInt(LOCAL_DATETIME_RE.matched(5)),
				LOCAL_DATETIME_RE.matched(6) != null ? Std.parseInt(LOCAL_DATETIME_RE.matched(6)) : 0);

		if (DATETIME_RE.match(value))
			return isValidDateTime(Std.parseInt(DATETIME_RE.matched(1)), Std.parseInt(DATETIME_RE.matched(2)), Std.parseInt(DATETIME_RE.matched(3)),
				Std.parseInt(DATETIME_RE.matched(4)), Std.parseInt(DATETIME_RE.matched(5)),
				DATETIME_RE.matched(6) != null ? Std.parseInt(DATETIME_RE.matched(6)) : 0);

		if (TIME_RE.match(value))
			return isValidTime(Std.parseInt(TIME_RE.matched(1)), Std.parseInt(TIME_RE.matched(2)),
				TIME_RE.matched(3) != null ? Std.parseInt(TIME_RE.matched(3)) : 0);

		if (LOCAL_TIME_RE.match(value))
			return isValidTime(Std.parseInt(LOCAL_TIME_RE.matched(1)), Std.parseInt(LOCAL_TIME_RE.matched(2)),
				LOCAL_TIME_RE.matched(3) != null ? Std.parseInt(LOCAL_TIME_RE.matched(3)) : 0);

		return false;
	}

	private inline function isLeapYear(year:Int):Bool
		return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

	private function isValidDate(year:Int, month:Int, day:Int):Bool {
		if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1)
			return false;

		var days = switch (month) {
			case 1 | 3 | 5 | 7 | 8 | 10 | 12: 31;
			case 4 | 6 | 9 | 11: 30;
			case 2: isLeapYear(year) ? 29 : 28;
			default: 0;
		}

		return day <= days;
	}

	private function isValidDateTime(year:Int, month:Int, day:Int, hour:Int, minute:Int, second:Int):Bool {
		return isValidDate(year, month, day) && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 59;
	}

	private function isValidTime(hour:Int, minute:Int, second:Int):Bool {
		return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 59;
	}

	private static function looksLikeDatePrefix(s:String):Bool {
		return s.length >= 10
			&& s.charCodeAt(4) == 45 // '-'
			&& s.charCodeAt(7) == 45 // '-'
			&& (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57);
	}
}
