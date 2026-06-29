package paopao.toml;

import Reflect;
import Type;
import Date;

@:analyzer(optimize, local_dce, fusion, user_var_fusion)
final class Parser {
	private final tokens:Array<Token>;
	private final definedTables:Map<String, Bool> = [];
	private final arrayTables:Map<String, Bool> = [];
	private final sealedTables:Map<String, String> = [];
	private var current:Int = 0;
	private var currentTablePath:String = "";

	public function new(tokens:Array<Token>) {
		this.tokens = tokens;
	}

	public dynamic function parse():Dynamic {
		var root:Dynamic = {};
		var currentTable:Dynamic = root;

		while (!isAtEnd()) {
			skipNewlines();

			if (isAtEnd())
				break;

			if (check(TokenType.LBRACKET)) {
				advance();

				if (match(TokenType.LBRACKET)) {
					if (previous().column != tokens[current - 2].column + 1)
						throw error(previous(), "Expected contiguous '[['");

					currentTable = parseArrayTable(root);
				} else
					currentTable = parseTable(root);

				continue;
			}

			parseKeyValue(currentTable, currentTablePath);
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

		if (previous().column != tokens[current - 2].column + 1)
			throw error(previous(), "Expected contiguous ']]'");

		consumeLineEnd("Expected newline after array table header");

		if (parts.length == 0)
			throw error(previous(), "Expected table name");

		var current:Dynamic = root;

		for (i in 0...parts.length - 1)
			current = descend(current, parts[i], partTokens[i], parts.slice(0, i + 1).join("."));

		var finalName = parts[parts.length - 1];
		var finalToken = partTokens[partTokens.length - 1];
		var path = parts.join(".");

		if (definedTables.exists(path))
			throw error(finalToken, '"$path" is already defined as a table');

		var arr:Array<Dynamic>;

		if (!Reflect.hasField(current, finalName)) {
			arr = [];

			Reflect.setField(current, finalName, arr);
		} else {
			var existing = Reflect.field(current, finalName);

			if (!Std.isOfType(existing, Array) || !arrayTables.exists(path))
				throw error(finalToken, 'Cannot define "$finalName" as an array of tables; it is already defined as a different type');

			arr = cast existing;
		}

		arrayTables.set(path, true);

		var obj:Dynamic = {};

		arr.push(obj);

		skipNewlines();
		currentTablePath = path;

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
		consumeLineEnd("Expected newline after table header");

		if (parts.length == 0)
			throw error(previous(), "Expected table name");

		var path = parts.join(".");

		if (definedTables.exists(path) || sealedTables.exists(path) || arrayTables.exists(path))
			throw error(partTokens[partTokens.length - 1], 'Table "$path" already defined');

		definedTables.set(path, true);

		var current:Dynamic = root;

		for (i in 0...parts.length)
			current = descend(current, parts[i], partTokens[i], parts.slice(0, i + 1).join("."));

		skipNewlines();
		currentTablePath = path;

		return current;
	}

	private function parseKeyValue(table:Dynamic, basePath:String):Void {
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

		assignDottedKey(table, keyParts, keyTokens, value, basePath);

		if (!check(TokenType.NEWLINE) && !check(TokenType.EOF))
			throw error(peek(), "Expected newline after key/value pair");

		skipNewlines();
	}

	private function assignDottedKey(root:Dynamic, parts:Array<String>, partTokens:Array<Token>, value:Dynamic, basePath:String):Void {
		var current = root;

		// Same rule as table headers: if an earlier segment of a dotted
		// key already resolves to an array of tables, the assignment
		// belongs to that array's most recently defined element.
		for (i in 0...parts.length - 1) {
			var path = joinPath(basePath, parts.slice(0, i + 1));

			if (definedTables.exists(path))
				throw error(partTokens[i], 'Cannot append to explicitly defined table "$path" with a dotted key');

			if (arrayTables.exists(path) && basePath != path && !StringTools.startsWith(basePath, path + "."))
				throw error(partTokens[i], 'Cannot append to array of tables "$path" from "$basePath"');

			current = descend(current, parts[i], partTokens[i], path);
			sealedTables.set(path, "dotted");
		}

		var finalKey = parts[parts.length - 1];

		if (Reflect.hasField(current, finalKey))
			throw error(partTokens[partTokens.length - 1], 'Duplicate key "$finalKey"');

		var existing = Reflect.field(current, finalKey);

		if (existing != null && isTableLike(existing))
			throw error(partTokens[partTokens.length - 1], 'Cannot redefine table "$finalKey" as a value');

		Reflect.setField(current, finalKey, value);

		if (isTableLike(value))
			sealedTables.set(joinPath(basePath, parts), "inline");
	}

	private static function dateTimeToDate(value:String):Date {
		var result = value;

		result = StringTools.replace(result, "T", " ");

		// remove fractional seconds
		var dot = result.indexOf(".");
		if (dot != -1) {
			var tz = result.indexOf("Z", dot);

			if (tz == -1) {
				var plus = result.indexOf("+", dot);
				var minus = result.lastIndexOf("-");

				tz = plus != -1 ? plus : minus;
			}

			if (tz != -1)
				result = result.substr(0, dot) + result.substr(tz);
			else
				result = result.substr(0, dot);
		}

		// remove timezone
		if (StringTools.endsWith(result, "Z"))
			result = result.substr(0, result.length - 1);

		var plus = result.lastIndexOf("+");

		if (plus > 10)
			result = result.substr(0, plus);

		var minus = result.lastIndexOf("-");

		if (minus > 10)
			result = result.substr(0, minus);

		return Date.fromString(result);
	}

	private function parseValue():Dynamic {
		if (match(TokenType.STRING))
			return previous().value;

		if (match(TokenType.MULTILINE_STRING))
			return previous().value;

		if (match(TokenType.INTEGER))
			return Std.parseInt(StringTools.replace(previous().value, "_", ""));

		if (match(TokenType.FLOAT))
			return Std.parseFloat(StringTools.replace(previous().value, "_", ""));

		if (match(TokenType.BOOLEAN))
			return previous().value == "true";

		if (match(TokenType.DATETIME))
			return dateTimeToDate(previous().value);

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

		while (!check(TokenType.RBRACE)) {
			if (check(TokenType.NEWLINE))
				throw error(peek(), "Newline in inline table");

			var key = consumeKey("Expected inline table key");

			if (Reflect.hasField(obj, key.value))
				throw error(key, 'Duplicate key "${key.value}"');

			consume(TokenType.EQUALS, "Expected '='");

			var value = parseValue();

			Reflect.setField(obj, key.value, value);

			if (check(TokenType.NEWLINE))
				throw error(peek(), "Newline in inline table");

			if (match(TokenType.COMMA)) {
				if (check(TokenType.RBRACE))
					throw error(peek(), "Trailing comma in inline table");

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
	private function descend(parent:Dynamic, part:String, token:Token, path:String):Dynamic {
		if (!Reflect.hasField(parent, part)) {
			var table:Dynamic = {};

			Reflect.setField(parent, part, table);

			return table;
		}

		var value = Reflect.field(parent, part);

		if (Std.isOfType(value, Array)) {
			if (!arrayTables.exists(path))
				throw error(token, 'Cannot use "${part}" as a table: it is an array, not an array of tables');

			var arr:Array<Dynamic> = cast value;

			if (arr.length == 0 || !isTableLike(arr[arr.length - 1]))
				throw error(token, 'Cannot use "${part}" as a table: it is an array, not an array of tables');

			return arr[arr.length - 1];
		}

		if (!isTableLike(value))
			throw error(token, 'Cannot redefine "${part}" as a table: it is already defined as a different type');

		if (sealedTables.get(path) == "inline")
			throw error(token, 'Cannot extend "${part}": it was defined by a dotted key or inline table');

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

	private inline function isAtEnd():Bool
		return peek().type == TokenType.EOF;

	private inline function peek():Token
		return tokens[current];

	private inline function previous():Token
		return tokens[current - 1];

	private function advance():Token {
		if (!isAtEnd())
			current++;

		return previous();
	}

	private function check(type:TokenType):Bool {
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
		while (check(TokenType.NEWLINE))
			advance();
	}

	private function consumeLineEnd(message:String):Void {
		if (!check(TokenType.NEWLINE) && !check(TokenType.EOF))
			throw error(peek(), message);
	}

	private function joinPath(basePath:String, parts:Array<String>):String {
		var suffix = parts.join(".");

		if (basePath == "")
			return suffix;

		return basePath + "." + suffix;
	}

	private function error(token:Token, message:String):TomlError {
		return new TomlError(message, token.line, token.column);
	}
}
