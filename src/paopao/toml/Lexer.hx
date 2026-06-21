package paopao.toml;

class Lexer {
	private final source:String;

	private var pos:Int = 0;
	private var line:Int = 1;
	private var column:Int = 1;

	public function new(source:String) {
		this.source = source;
	}

	public function tokenize():Array<Token> {
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

				case "\"":
					tokens.push(readString());

				default:
					if (isIdentifierStart(c)) {
						for (token in readIdentifierOrValue()) {
							tokens.push(token);
						}
					} else {
						throw error('Unexpected character "$c"');
					}
			}
		}

		tokens.push(new Token(TokenType.EOF, "", line, column));

		return tokens;
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

	private inline function makeToken(type:TokenType, value:String):Token {
		return new Token(type, value, line, column);
	}

	private inline function error(message:String):TomlError {
		return new TomlError(message, line, column);
	}

	private function skipComment():Void {
		while (!isAtEnd() && peek() != "\n") {
			advance();
		}
	}

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

	private function readString():Token {
		var startLine = line;
		var startColumn = column;

		advance(); // opening "

		var buf = new StringBuf();

		while (!isAtEnd()) {
			var c = advance();

			if (c == "\"") {
				return new Token(TokenType.STRING, buf.toString(), startLine, startColumn);
			}

			if (c == "\\") {
				if (isAtEnd()) {
					throw new TomlError("Unexpected end of string", line, column);
				}

				var escaped = advance();

				switch (escaped) {
					case "n":
						buf.add("\n");

					case "r":
						buf.add("\r");

					case "t":
						buf.add("\t");

					case "\"":
						buf.add("\"");

					case "\\":
						buf.add("\\");

					default:
						throw new TomlError('Invalid escape sequence \\$escaped', line, column);
				}

				continue;
			}

			buf.add(c);
		}

		throw new TomlError("Unterminated string", startLine, startColumn);
	}

	private function isInteger(value:String):Bool {
		var regex = ~/^[+-]?[0-9]+$/;
		return regex.match(value);
	}

	private function isFloat(value:String):Bool {
		var regex = ~/^[+-]?[0-9]+\.[0-9]+$/;

		return regex.match(value);
	}

	private function isDateTime(value:String):Bool {
		var regex = ~/^[0-9]{4}-[0-9]{2}-[0-9]{2}/;

		return regex.match(value);
	}

	private function readIdentifierOrValue():Array<Token> {
		var startLine = line;
		var startColumn = column;

		var buf = new StringBuf();

		while (!isAtEnd()) {
			var c = peek();

			switch (c) {
				case " " | "\t" | "\r" | "\n":
					break;

				case "," | "=" | "[" | "]" | "{" | "}":
					break;

				case "#":
					break;

				default:
					buf.add(c);
					advance();
			}
		}

		var value = buf.toString();

		if (value == "true" || value == "false") {
			return [new Token(TokenType.BOOLEAN, value, startLine, startColumn)];
		}

		if (isDateTime(value)) {
			return [new Token(TokenType.DATETIME, value, startLine, startColumn)];
		}

		if (isInteger(value)) {
			return [new Token(TokenType.INTEGER, value, startLine, startColumn)];
		}

		if (isFloat(value)) {
			return [new Token(TokenType.FLOAT, value, startLine, startColumn)];
		}

		if (value.indexOf(".") >= 0) {
			var result:Array<Token> = [];
			var parts = value.split(".");

			for (i in 0...parts.length) {
				result.push(new Token(TokenType.IDENTIFIER, parts[i], startLine, startColumn));

				if (i < parts.length - 1) {
					result.push(new Token(TokenType.DOT, ".", startLine, startColumn));
				}
			}

			return result;
		}

		return [new Token(TokenType.IDENTIFIER, value, startLine, startColumn)];
	}
}
