package paopao.toml;

import Reflect;
import Type;
import Date;

class Parser {
	private final tokens:Array<Token>;
	private final definedTables:Map<String, Bool> = [];
	private var current:Int = 0;

	public function new(tokens:Array<Token>) {
		this.tokens = tokens;
	}

	public function parse():Dynamic {
		var root:Dynamic = {};
		var currentTable:Dynamic = root;

		while (!isAtEnd()) {
			skipNewlines();

			if (isAtEnd())
				break;

			if (check(TokenType.LBRACKET)) {
				advance();

				if (match(TokenType.LBRACKET)) {
					currentTable = parseArrayTable(root);
				} else {
					currentTable = parseTable(root);
				}

				continue;
			}

			parseKeyValue(currentTable);
		}

		return root;
	}

	private function parseArrayTable(root:Dynamic):Dynamic {
		var parts:Array<String> = [];
		var partTokens:Array<Token> = [];

		while (!check(TokenType.RBRACKET)) {
			var token = consumeKey("Expected table name");

			parts.push(token.value);
			partTokens.push(token);

			if (match(TokenType.DOT))
				continue;

			break;
		}

		consume(TokenType.RBRACKET, "Expected ']'");

		consume(TokenType.RBRACKET, "Expected second ']'");

		if (parts.length == 0) {
			throw error(previous(), "Expected table name");
		}

		var current:Dynamic = root;

		// Walk every segment except the last. If an ancestor is itself an
		// array of tables (e.g. [[fruits]] before [[fruits.varieties]]),
		// new headers always refer to that array's most recently defined
		// element, never to the array itself.
		for (i in 0...parts.length - 1) {
			current = descend(current, parts[i], partTokens[i]);
		}

		var finalName = parts[parts.length - 1];
		var finalToken = partTokens[partTokens.length - 1];

		if (definedTables.exists(parts.join("."))) {
			throw error(finalToken, '"${parts.join(".")}" is already defined as a table');
		}

		var arr:Array<Dynamic>;

		if (!Reflect.hasField(current, finalName)) {
			arr = [];

			Reflect.setField(current, finalName, arr);
		} else {
			var existing = Reflect.field(current, finalName);

			if (!Std.isOfType(existing, Array)) {
				throw error(finalToken, 'Cannot define "$finalName" as an array of tables; it is already defined as a different type');
			}

			arr = cast existing;
		}

		var obj:Dynamic = {};

		arr.push(obj);

		skipNewlines();

		return obj;
	}

	private function parseTable(root:Dynamic):Dynamic {
		var parts:Array<String> = [];
		var partTokens:Array<Token> = [];

		while (!check(TokenType.RBRACKET)) {
			var token = consumeKey("Expected table name");

			parts.push(token.value);
			partTokens.push(token);

			if (match(TokenType.DOT))
				continue;

			break;
		}

		consume(TokenType.RBRACKET, "Expected ']'");

		if (parts.length == 0) {
			throw error(previous(), "Expected table name");
		}

		var path = parts.join(".");

		if (definedTables.exists(path)) {
			throw error(partTokens[partTokens.length - 1], 'Table "$path" already defined');
		}

		definedTables.set(path, true);

		var current:Dynamic = root;

		for (i in 0...parts.length) {
			current = descend(current, parts[i], partTokens[i]);
		}

		skipNewlines();

		return current;
	}

	private function parseKeyValue(table:Dynamic):Void {
		var keyParts:Array<String> = [];
		var keyTokens:Array<Token> = [];

		var first = consumeKey("Expected key");

		keyParts.push(first.value);
		keyTokens.push(first);

		while (match(TokenType.DOT)) {
			var part = consumeKey("Expected key after '.'");

			keyParts.push(part.value);
			keyTokens.push(part);
		}

		consume(TokenType.EQUALS, "Expected '='");

		var value = parseValue();

		assignDottedKey(table, keyParts, keyTokens, value);

		if (!check(TokenType.NEWLINE) && !check(TokenType.EOF)) {
			throw error(peek(), "Expected newline after key/value pair");
		}

		skipNewlines();
	}

	private function assignDottedKey(root:Dynamic, parts:Array<String>, partTokens:Array<Token>, value:Dynamic):Void {
		var current = root;

		// Same rule as table headers: if an earlier segment of a dotted
		// key already resolves to an array of tables, the assignment
		// belongs to that array's most recently defined element.
		for (i in 0...parts.length - 1) {
			current = descend(current, parts[i], partTokens[i]);
		}

		var finalKey = parts[parts.length - 1];

		if (Reflect.hasField(current, finalKey)) {
			throw error(partTokens[partTokens.length - 1], 'Duplicate key "$finalKey"');
		}

		var existing = Reflect.field(current, finalKey);

		if (existing != null && isTableLike(existing)) {
			throw error(partTokens[partTokens.length - 1], 'Cannot redefine table "$finalKey" as a value');
		}

		Reflect.setField(current, finalKey, value);
	}

	private function parseValue():Dynamic {
		if (match(TokenType.STRING))
			return previous().value;

		if (match(TokenType.INTEGER))
			return Std.parseInt(previous().value);

		if (match(TokenType.FLOAT))
			return Std.parseFloat(previous().value);

		if (match(TokenType.BOOLEAN))
			return previous().value == "true";

		if (match(TokenType.DATETIME))
			return previous().value;

		if (match(TokenType.LBRACKET))
			return parseArray();

		if (match(TokenType.LBRACE))
			return parseInlineTable();

		throw error(peek(), "Expected value");
	}

	private function parseArray():Array<Dynamic> {
		var result:Array<Dynamic> = [];

		skipNewlines();

		while (!check(TokenType.RBRACKET)) {
			result.push(parseValue());

			skipNewlines();

			if (match(TokenType.COMMA)) {
				skipNewlines();
				continue;
			}

			break;
		}

		consume(TokenType.RBRACKET, "Expected ']' after array");

		return result;
	}

	private function parseInlineTable():Dynamic {
		var obj:Dynamic = {};

		skipNewlines();

		while (!check(TokenType.RBRACE)) {
			var key = consumeKey("Expected inline table key");

			if (Reflect.hasField(obj, key.value)) {
				throw error(key, 'Duplicate key "${key.value}"');
			}

			consume(TokenType.EQUALS, "Expected '='");

			var value = parseValue();

			Reflect.setField(obj, key.value, value);

			skipNewlines();

			if (match(TokenType.COMMA)) {
				skipNewlines();
				continue;
			}

			break;
		}

		consume(TokenType.RBRACE, "Expected '}'");

		return obj;
	}

	/**
	 * Resolve one segment of a dotted path (table header or dotted key)
	 * against `parent`, creating an intermediate table if it doesn't exist
	 * yet. If the segment already resolves to an array of tables, descend
	 * into that array's most recently defined element rather than the
	 * array itself — this is what makes `[fruits.physical]` attach to the
	 * last `[[fruits]]` entry, and likewise for nested `[[fruits.varieties]]`.
	 * Throws a clean TomlError (instead of an opaque cast failure) if the
	 * segment already holds a non-table value.
	 */
	private function descend(parent:Dynamic, part:String, token:Token):Dynamic {
		if (!Reflect.hasField(parent, part)) {
			var table:Dynamic = {};

			Reflect.setField(parent, part, table);

			return table;
		}

		var value = Reflect.field(parent, part);

		if (Std.isOfType(value, Array)) {
			var arr:Array<Dynamic> = cast value;

			if (arr.length == 0 || !isTableLike(arr[arr.length - 1])) {
				throw error(token, 'Cannot use "${part}" as a table: it is an array, not an array of tables');
			}

			return arr[arr.length - 1];
		}

		if (!isTableLike(value)) {
			throw error(token, 'Cannot redefine "${part}" as a table: it is already defined as a different type');
		}

		return value;
	}

	private function isTableLike(value:Dynamic):Bool {
		if (value == null)
			return false;

		if (Std.isOfType(value, String))
			return false;

		if (Std.isOfType(value, Bool))
			return false;

		if (Std.isOfType(value, Int))
			return false;

		if (Std.isOfType(value, Float))
			return false;

		if (Std.isOfType(value, Array))
			return false;

		return Type.typeof(value) == TObject;
	}

	private function consumeKey(message:String):Token {
		if (check(TokenType.IDENTIFIER) || check(TokenType.STRING))
			return advance();

		throw error(peek(), message);
	}

	private inline function isAtEnd():Bool {
		return peek().type == TokenType.EOF;
	}

	private inline function peek():Token {
		return tokens[current];
	}

	private inline function previous():Token {
		return tokens[current - 1];
	}

	private function advance():Token {
		if (!isAtEnd())
			current++;

		return previous();
	}

	private function check(type:TokenType):Bool {
		if (isAtEnd())
			return false;

		return peek().type == type;
	}

	private function match(type:TokenType):Bool {
		if (!check(type))
			return false;

		advance();
		return true;
	}

	private function consume(type:TokenType, message:String):Token {
		if (check(type))
			return advance();

		throw error(peek(), message);
	}

	private function skipNewlines():Void {
		while (check(TokenType.NEWLINE)) {
			advance();
		}
	}

	private function error(token:Token, message:String):TomlError {
		return new TomlError(message, token.line, token.column);
	}
}
