package paopao.toml;

using StringTools;

@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class Writer {
	static var SIMPLE_KEY = ~/^[-A-Za-z0-9_]+$/;

	public static function write(value:Dynamic):String {
		var out = new StringBuf();
		writeTable(out, "", value);
		return out.toString();
	}

	static function isTableArray(value:Dynamic):Bool {
		if (!Std.isOfType(value, Array))
			return false;

		var arr:Array<Dynamic> = cast value;

		if (arr.length == 0)
			return false;

		for (item in arr) {
			if (!isTable(item))
				return false;
		}

		return true;
	}

	static function getSortedFields(obj:Dynamic):Array<String> {
		var fields = Reflect.fields(obj);
		fields.sort(Reflect.compare);
		return fields;
	}

	static function writeKey(key:String):String {
		if (SIMPLE_KEY.match(key))
			return key;

		return '"' + key.replace('"', '\\"') + '"';
	}

	static function writeArrayTable(out:StringBuf, path:String, tables:Array<Dynamic>):Void {
		var first = true;

		for (table in tables) {
			if (!first)
				out.add("\n");

			first = false;

			out.add('[[$path]]\n');
			var fields = getSortedFields(table);

			for (field in fields) {
				var value = Reflect.field(table, field);

				if (isTable(value) || isTableArray(value))
					continue;

				out.add('${writeKey(field)} = ${writeValue(value)}\n');
			}

			var hasChildren = false;

			for (field in fields) {
				var value = Reflect.field(table, field);

				if (isTable(value) || isTableArray(value)) {
					hasChildren = true;
					break;
				}
			}

			if (hasChildren)
				out.add("\n");

			for (field in fields) {
				var value = Reflect.field(table, field);
				var childPath = path + "." + field;

				if (isTableArray(value))
					writeArrayTable(out, childPath, cast value);
				else if (isTable(value))
					writeTable(out, childPath, value);
			}
		}
	}

	static function writeTable(out:StringBuf, path:String, obj:Dynamic):Void {
		var fields = getSortedFields(obj);
		var childTables:Array<String> = [];
		var hasValues = false;

		for (field in fields) {
			var value = Reflect.field(obj, field);

			if (isEmptyObject(value)) {
				hasValues = true;
				continue;
			}

			if (isTable(value) || isTableArray(value)) {
				childTables.push(field);
				continue;
			}

			hasValues = true;
		}

		if (path != "" && hasValues)
			out.add('[$path]\n');

		for (field in fields) {
			var value = Reflect.field(obj, field);

			if (isEmptyObject(value)) {
				out.add('${writeKey(field)} = { }\n');
				continue;
			}

			if (isTable(value) || isTableArray(value))
				continue;

			out.add('${writeKey(field)} = ${writeValue(value)}\n');
		}

		if (childTables.length > 0)
			out.add("\n");

		var first = true;

		for (field in childTables) {
			if (!first)
				out.add("\n");

			first = false;

			var child = Reflect.field(obj, field);
			var childPath = path == "" ? field : '$path.$field';

			if (isTableArray(child))
				writeArrayTable(out, childPath, cast child);
			else
				writeTable(out, childPath, child);
		}
	}

	static function isEmptyObject(value:Dynamic):Bool {
		return Reflect.isObject(value) && !Std.isOfType(value, Array) && Reflect.fields(value).length == 0;
	}

	static function formatInteger(value:Int):String {
		var s = Std.string(value);
		var result = "";
		var count = 0;

		for (i in 0...s.length) {
			var idx = s.length - 1 - i;

			if (count == 3) {
				result = "_" + result;
				count = 0;
			}

			result = s.charAt(idx) + result;
			count++;
		}

		return result;
	}

	static function writeValue(value:Dynamic):String {
		if (value == null)
			return '""';

		if (Std.isOfType(value, String))
			return writeString(cast value);

		if (Std.isOfType(value, Bool))
			return Std.string(value);

		if (Std.isOfType(value, Int))
			return formatInteger(cast value);

		if (Std.isOfType(value, Float)) {
			var f:Float = cast value;

			if (Math.isNaN(f))
				return "nan";

			if (f == Math.POSITIVE_INFINITY)
				return "inf";

			if (f == Math.NEGATIVE_INFINITY)
				return "-inf";

			return Std.string(f);
		}

		if (Std.isOfType(value, Array))
			return writeArray(cast value);

		if (Std.isOfType(value, Date) || Std.isOfType(value, TomlDateTime))
			return writeDate(cast value);

		if (isEmptyObject(value))
			return "{ }";

		return writeInlineTable(value);
	}

	static function writeDate(date:Dynamic):String {
		if (Std.isOfType(date, Date)) {
			inline function pad(n:Int):String
				return n < 10 ? "0" + n : Std.string(n);

			return '"' + date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + "T" + pad(date.getHours()) + ":"
				+ pad(date.getMinutes()) + ":" + pad(date.getSeconds()) + 'Z"';
		} else if (Std.isOfType(date, TomlDateTime))
			return cast(date, TomlDateTime).toString();

		throw new TomlError("Expected Date or TomlDateTime", 0, 0);
	}

	static function writeString(value:String):String {
		if (value.indexOf("\n") != -1) {
			return '"""\n' + value + '"""';
		}

		var out = new StringBuf();
		out.add('"');

		for (i in 0...value.length) {
			var c = value.charAt(i);

			if (c == "\\")
				out.add("\\\\");
			else if (c == '"')
				out.add('\\"');
			else if (c == "\n")
				out.add("\\n");
			else if (c == "\r")
				out.add("\\r");
			else if (c == "\t")
				out.add("\\t");
			else if (c == "\x08")
				out.add("\\b");
			else if (c == "\x0C")
				out.add("\\f");
			else
				out.add(c);
		}

		out.add('"');
		return out.toString();
	}

	static function writeArray(arr:Array<Dynamic>):String {
		var parts = [for (v in arr) writeValue(v)];

		var oneLine = "[ " + parts.join(", ") + " ]";

		if (oneLine.length <= 60)
			return oneLine;

		return "[\n  " + parts.join(",\n  ") + "\n]";
	}

	static function writeInlineTable(obj:Dynamic):String {
		var fields = getSortedFields(obj);

		if (fields.length == 0)
			return "{ }";

		var parts = new Array<String>();

		for (field in fields) {
			parts.push('${writeKey(field)} = ${writeValue(Reflect.field(obj, field))}');
		}

		return "{ " + parts.join(", ") + " }";
	}

	static function isTable(value:Dynamic):Bool {
		if (value == null)
			return false;

		if (Std.isOfType(value, String))
			return false;

		if (Std.isOfType(value, Array))
			return false;

		return Reflect.isObject(value);
	}
}
