package paopao.toml;

import Reflect;
import Type;
import paopao.toml.TomlDateTime;

using StringTools;

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

			if (match(TokenType.DOT)) {
				if (check(TokenType.RBRACKET))
					throw error(previous(), "Trailing dot in table name");
				continue;
			}

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
			current = descend(current, parts[i], partTokens[i], parts.slice(0, i + 1));

		var finalName = parts[parts.length - 1];
		var finalToken = partTokens[partTokens.length - 1];
		var path = parts.join(".");

		if (definedTables.exists(pathKey(parts)))
			throw error(finalToken, '"$path" is already defined as a table');

		var arr:Array<Dynamic>;

		if (!Reflect.hasField(current, finalName)) {
			arr = [];

			Reflect.setField(current, finalName, arr);
		} else {
			var existing = Reflect.field(current, finalName);

			if (!Std.isOfType(existing, Array) || !arrayTables.exists(pathKey(parts)))
				throw error(finalToken, 'Cannot define "$finalName" as an array of tables; it is already defined as a different type');

			arr = cast existing;
		}

		arrayTables.set(pathKey(parts), true);

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

			if (match(TokenType.DOT)) {
				if (check(TokenType.RBRACKET))
					throw error(previous(), "Trailing dot in table name");
				continue;
			}

			break;
		}

		consume(TokenType.RBRACKET, "Expected ']'");
		consumeLineEnd("Expected newline after table header");

		if (parts.length == 0)
			throw error(previous(), "Expected table name");

		var path = parts.join(".");
		var pkey = pathKey(parts);

		// Check if this exact path was already defined as a table.
		// Skip the check if parent is an array table (sub-tables within
		// array elements are scoped to that element).
		var parentKey = parts.length > 1 ? pathKey(parts.slice(0, parts.length - 1)) : "";
		var isInArrayTable = parentKey != "" && arrayTables.exists(parentKey);

		if (!isInArrayTable && (definedTables.exists(pkey) || sealedTables.exists(pkey) || arrayTables.exists(pkey)))
			throw error(partTokens[partTokens.length - 1], 'Table "$path" already defined');

		if (!isInArrayTable)
			definedTables.set(pkey, true);

		var current:Dynamic = root;

		for (i in 0...parts.length)
			current = descend(current, parts[i], partTokens[i], parts.slice(0, i + 1));

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

		for (i in 0...parts.length - 1) {
			var segParts = splitPath(basePath).concat(parts.slice(0, i + 1));
			var segPkey = pathKey(segParts);
			var checkPath = joinPath(basePath, parts.slice(0, i + 1));

			if (definedTables.exists(segPkey))
				throw error(partTokens[i], 'Cannot append to explicitly defined table "$checkPath" with a dotted key');

			if (arrayTables.exists(segPkey) && basePath != checkPath && !basePath.startsWith(checkPath + "."))
				throw error(partTokens[i], 'Cannot append to array of tables "$checkPath" from "$basePath"');

			current = descend(current, parts[i], partTokens[i], segParts);
			sealedTables.set(segPkey, "dotted");
		}

		var finalKey = parts[parts.length - 1];

		if (Reflect.hasField(current, finalKey))
			throw error(partTokens[partTokens.length - 1], 'Duplicate key "$finalKey"');

		var existing = Reflect.field(current, finalKey);

		if (existing != null && isTableLike(existing))
			throw error(partTokens[partTokens.length - 1], 'Cannot redefine table "$finalKey" as a value');

		Reflect.setField(current, finalKey, value);

		if (isTableLike(value)) {
			var allParts = splitPath(basePath).concat(parts);
			sealedTables.set(pathKey(allParts), "inline");
		}
	}

	// Datetime parsing patterns (capturing groups). Compiled once and
	// reused across calls instead of being rebuilt on every parseDateTime
	// invocation, which previously recompiled 4 regexes per datetime value.
	private static final DT_FULL_RE = ~/^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(?:Z|([+-])(\d{2}):(\d{2}))?$/;
	private static final DT_LOCAL_RE = ~/^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?([Zz])?$/;
	private static final DT_TIME_RE = ~/^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(?:Z|([+-])(\d{2}):(\d{2}))?$/;
	private static final DT_LOCAL_TIME_RE = ~/^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?$/;
	private static final DT_DATE_ONLY_RE = ~/^(\d{4})-(\d{2})-(\d{2})$/;

	// Value-classification patterns (validation only). Mirrors the
	// equivalent static finals already hoisted in Lexer.hx.
	private static final INT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)$/;
	private static final HEX_INT_RE = ~/^0x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*$/;
	private static final OCT_INT_RE = ~/^0o[0-7](?:_?[0-7])*$/;
	private static final BIN_INT_RE = ~/^0b[01](?:_?[01])*$/;

	private static final FLOAT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)\.[0-9](?:_?[0-9])*(?:[eE][+-]?[0-9](?:_?[0-9])*)?$/;
	private static final EXPONENT_RE = ~/^[+-]?(?:0|[1-9](?:_?[0-9])*)[eE][+-]?[0-9](?:_?[0-9])*$/;
	private static final INF_NAN_RE = ~/^[+-]?(?:inf|nan)$/;

	private static final DATE_ONLY_RE = ~/^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
	private static final DATETIME_VALUE_RE = ~/^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?(?:Z|[+-][0-9]{2}:[0-9]{2})?$/;
	private static final TIME_VALUE_RE = ~/^([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?(?:Z|[+-][0-9]{2}:[0-9]{2})?$/;

	private static function parseDateTime(value:String):TomlDateTime {
		var dt = new TomlDateTime();

		// Full datetime with date and time
		if (DT_FULL_RE.match(value)) {
			dt.year = Std.parseInt(DT_FULL_RE.matched(1));
			dt.month = Std.parseInt(DT_FULL_RE.matched(2));
			dt.day = Std.parseInt(DT_FULL_RE.matched(3));
			dt.hour = Std.parseInt(DT_FULL_RE.matched(4));
			dt.minute = Std.parseInt(DT_FULL_RE.matched(5));

			if (DT_FULL_RE.matched(6) != null)
				dt.second = Std.parseInt(DT_FULL_RE.matched(6));

			var frac = DT_FULL_RE.matched(7);
			if (frac != null) {
				while (frac.length < 9)
					frac += "0";
				if (frac.length > 9)
					frac = frac.substr(0, 9);
				dt.nanosecond = Std.parseInt(frac);
			}

			if (DT_FULL_RE.matched(8) != null) {
				var sign = DT_FULL_RE.matched(8) == "+" ? 1 : -1;
				var hours = Std.parseInt(DT_FULL_RE.matched(9));
				var mins = Std.parseInt(DT_FULL_RE.matched(10));
				if (hours < 0 || hours > 23)
					throw 'Invalid offset hours: $hours';
				if (mins < 0 || mins > 59)
					throw 'Invalid offset minutes: $mins';
				dt.offsetMinutes = sign * (hours * 60 + mins);
			}
			return dt;
		}

		// Local datetime (same as full but with lowercase z or without timezone)
		if (DT_LOCAL_RE.match(value)) {
			dt.year = Std.parseInt(DT_LOCAL_RE.matched(1));
			dt.month = Std.parseInt(DT_LOCAL_RE.matched(2));
			dt.day = Std.parseInt(DT_LOCAL_RE.matched(3));
			dt.hour = Std.parseInt(DT_LOCAL_RE.matched(4));
			dt.minute = Std.parseInt(DT_LOCAL_RE.matched(5));

			if (DT_LOCAL_RE.matched(6) != null)
				dt.second = Std.parseInt(DT_LOCAL_RE.matched(6));

			var frac = DT_LOCAL_RE.matched(7);
			if (frac != null) {
				while (frac.length < 9)
					frac += "0";
				if (frac.length > 9)
					frac = frac.substr(0, 9);
				dt.nanosecond = Std.parseInt(frac);
			}

			if (DT_LOCAL_RE.matched(8) != null)
				dt.offsetMinutes = 0;

			return dt;
		}

		// Time only with optional timezone
		if (DT_TIME_RE.match(value)) {
			dt.hour = Std.parseInt(DT_TIME_RE.matched(1));
			dt.minute = Std.parseInt(DT_TIME_RE.matched(2));

			if (DT_TIME_RE.matched(3) != null)
				dt.second = Std.parseInt(DT_TIME_RE.matched(3));

			var frac = DT_TIME_RE.matched(4);
			if (frac != null) {
				while (frac.length < 9)
					frac += "0";
				if (frac.length > 9)
					frac = frac.substr(0, 9);
				dt.nanosecond = Std.parseInt(frac);
			}

			if (DT_TIME_RE.matched(5) != null) {
				var sign = DT_TIME_RE.matched(5) == "+" ? 1 : -1;
				var hours = Std.parseInt(DT_TIME_RE.matched(6));
				var mins = Std.parseInt(DT_TIME_RE.matched(7));
				dt.offsetMinutes = sign * (hours * 60 + mins);
			}
			return dt;
		}

		// Local time only (without timezone)
		if (DT_LOCAL_TIME_RE.match(value)) {
			dt.hour = Std.parseInt(DT_LOCAL_TIME_RE.matched(1));
			dt.minute = Std.parseInt(DT_LOCAL_TIME_RE.matched(2));

			if (DT_LOCAL_TIME_RE.matched(3) != null)
				dt.second = Std.parseInt(DT_LOCAL_TIME_RE.matched(3));

			var frac = DT_LOCAL_TIME_RE.matched(4);
			if (frac != null) {
				while (frac.length < 9)
					frac += "0";
				if (frac.length > 9)
					frac = frac.substr(0, 9);
				dt.nanosecond = Std.parseInt(frac);
			}
			return dt;
		}

		// Date only
		if (DT_DATE_ONLY_RE.match(value)) {
			dt.year = Std.parseInt(DT_DATE_ONLY_RE.matched(1));
			dt.month = Std.parseInt(DT_DATE_ONLY_RE.matched(2));
			dt.day = Std.parseInt(DT_DATE_ONLY_RE.matched(3));
			return dt;
		}

		throw 'Invalid TOML datetime: $value';
	}

	private function parseValue():Dynamic {
		if (match(TokenType.STRING))
			return previous().value;

		if (match(TokenType.MULTILINE_STRING))
			return previous().value;

		if (match(TokenType.INTEGER))
			return Std.parseInt((previous().value).replace("_", ""));

		if (match(TokenType.FLOAT))
			return parseFloatValue(previous().value);

		if (match(TokenType.BOOLEAN))
			return previous().value == "true";

		if (match(TokenType.DATETIME))
			return parseDateTime(previous().value);

		// IDENTIFIER in value position: try to interpret as typed value
		if (match(TokenType.IDENTIFIER)) {
			var v = previous().value;
			if (v == "true")
				return true;
			if (v == "false")
				return false;

			if (isIntegerValue(v))
				return Std.parseInt(v.replace("_", ""));

			if (isFloatValue(v))
				return parseFloatValue(v);

			if (isDateTimeValue(v))
				return parseDateTime(v);

			throw error(previous(), 'Expected value');
		}

		if (match(TokenType.LBRACKET))
			return parseArray();

		if (match(TokenType.LBRACE))
			return parseInlineTable();

		throw error(peek(), "Expected value");
	}

	private static function parseFloatValue(value:String):Float {
		// Handle inf and nan
		switch (value.toLowerCase()) {
			case "inf", "+inf":
				return Math.POSITIVE_INFINITY;
			case "-inf":
				return Math.NEGATIVE_INFINITY;
			case "nan", "+nan", "-nan":
				return Math.NaN;
		}
		return Std.parseFloat(value.replace("_", ""));
	}

	private static function isIntegerValue(value:String):Bool {
		if (value == "+0" || value == "-0")
			return true;
		if (INT_RE.match(value))
			return true;
		if (HEX_INT_RE.match(value))
			return true;
		if (OCT_INT_RE.match(value))
			return true;
		if (BIN_INT_RE.match(value))
			return true;
		return false;
	}

	private static function isFloatValue(value:String):Bool {
		if (FLOAT_RE.match(value))
			return true;
		if (EXPONENT_RE.match(value))
			return true;
		if (INF_NAN_RE.match(value))
			return true;
		return false;
	}

	private static function isDateTimeValue(value:String):Bool {
		if (DATE_ONLY_RE.match(value))
			return isValidDate(Std.parseInt(DATE_ONLY_RE.matched(1)), Std.parseInt(DATE_ONLY_RE.matched(2)), Std.parseInt(DATE_ONLY_RE.matched(3)));

		if (DATETIME_VALUE_RE.match(value))
			return isValidDateTime(Std.parseInt(DATETIME_VALUE_RE.matched(1)), Std.parseInt(DATETIME_VALUE_RE.matched(2)),
				Std.parseInt(DATETIME_VALUE_RE.matched(3)), Std.parseInt(DATETIME_VALUE_RE.matched(4)), Std.parseInt(DATETIME_VALUE_RE.matched(5)),
				DATETIME_VALUE_RE.matched(6) != null ? Std.parseInt(DATETIME_VALUE_RE.matched(6)) : 0);

		if (TIME_VALUE_RE.match(value))
			return isValidTime(Std.parseInt(TIME_VALUE_RE.matched(1)), Std.parseInt(TIME_VALUE_RE.matched(2)),
				TIME_VALUE_RE.matched(3) != null ? Std.parseInt(TIME_VALUE_RE.matched(3)) : 0);

		return false;
	}

	private static inline function isLeapYear(year:Int):Bool
		return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

	private static function isValidDate(year:Int, month:Int, day:Int):Bool {
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

	private static function isValidDateTime(year:Int, month:Int, day:Int, hour:Int, minute:Int, second:Int):Bool {
		return isValidDate(year, month, day) && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 59;
	}

	private static function isValidTime(hour:Int, minute:Int, second:Int):Bool {
		return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 59;
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
		var sealedKeys:Map<String, Bool> = [];

		skipNewlines();

		while (!check(TokenType.RBRACE)) {
			// Parse dotted key in inline table
			var keyParts:Array<String> = [];
			var keyTokens:Array<Token> = [];

			var first = consumeKey("Expected inline table key");
			keyParts.push(first.value);
			keyTokens.push(first);

			while (match(TokenType.DOT)) {
				var part = consumeKey("Expected key after '.'");
				keyParts.push(part.value);
				keyTokens.push(part);
			}

			consume(TokenType.EQUALS, "Expected '='");

			var value = parseValue();

			// Assign nested value
			if (keyParts.length == 1) {
				var key = keyParts[0];
				if (Reflect.hasField(obj, key))
					throw error(keyTokens[0], 'Duplicate key "$key"');
				Reflect.setField(obj, key, value);
				sealedKeys.set(key, true);
			} else {
				// Dotted key in inline table: create or verify intermediate tables
				var current = obj;
				for (i in 0...keyParts.length - 1) {
					var part = keyParts[i];
					if (sealedKeys.exists(part))
						throw error(keyTokens[i], 'Cannot extend "$part" with dotted key');
					if (!Reflect.hasField(current, part)) {
						Reflect.setField(current, part, {});
					}
					current = Reflect.field(current, part);
				}
				var finalKey = keyParts[keyParts.length - 1];
				if (Reflect.hasField(current, finalKey))
					throw error(keyTokens[keyTokens.length - 1], 'Duplicate key "$finalKey"');
				Reflect.setField(current, finalKey, value);
			}

			skipNewlines();

			if (match(TokenType.COMMA)) {
				skipNewlines();
				continue;
			}

			skipNewlines();
			break;
		}

		consume(TokenType.RBRACE, "Expected '}'");

		return obj;
	}

	private function descend(parent:Dynamic, part:String, token:Token, parts:Array<String>):Dynamic {
		if (!Reflect.hasField(parent, part)) {
			var table:Dynamic = {};
			Reflect.setField(parent, part, table);
			return table;
		}

		var value = Reflect.field(parent, part);
		var pkey = pathKey(parts);

		if (Std.isOfType(value, Array)) {
			if (!arrayTables.exists(pkey))
				throw error(token, 'Cannot use "${part}" as a table: it is an array, not an array of tables');

			var arr:Array<Dynamic> = cast value;

			if (arr.length == 0 || !isTableLike(arr[arr.length - 1]))
				throw error(token, 'Cannot use "${part}" as a table: it is an array, not an array of tables');

			return arr[arr.length - 1];
		}

		if (!isTableLike(value))
			throw error(token, 'Cannot redefine "${part}" as a table: it is already defined as a different type');

		if (sealedTables.get(pkey) == "inline")
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
		if (check(TokenType.IDENTIFIER) || check(TokenType.STRING) || check(TokenType.INTEGER) || check(TokenType.FLOAT) || check(TokenType.BOOLEAN)
			|| check(TokenType.DATETIME))
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

	private inline function check(type:TokenType):Bool
		return peek().type == type;

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

	private inline function skipNewlines():Void
		while (check(TokenType.NEWLINE))
			advance();

	private function consumeLineEnd(message:String):Void
		if (!check(TokenType.NEWLINE) && !check(TokenType.EOF))
			throw error(peek(), message);

	private static inline function pathKey(parts:Array<String>):String
		return parts.join("\x00");

	private static inline function joinPath(basePath:String, subParts:Array<String>):String {
		var suffix = subParts.join(".");
		return basePath == "" ? suffix : basePath + "." + suffix;
	}

	private static function splitPath(path:String):Array<String>
		return path == "" ? [] : path.split(".");

	private function error(token:Token, message:String):TomlError
		return (new TomlError(message, token.line, token.column));
}
