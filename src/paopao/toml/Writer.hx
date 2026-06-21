package paopao.toml;

using StringTools;

class Writer {
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

	static function writeArrayTable(out:StringBuf, path:String, tables:Array<Dynamic>):Void {
		for (table in tables) {
			out.add('[[$path]]\n');

			// Write simple fields first
			for (field in Reflect.fields(table)) {
				var value = Reflect.field(table, field);
				if (isTable(value) || isTableArray(value))
					continue;
				out.add('$field = ${writeValue(value)}\n');
			}

			out.add("\n");

			// Write nested table and array-of-table fields
			for (field in Reflect.fields(table)) {
				var value = Reflect.field(table, field);
				var childPath = path == "" ? field : '$path.$field';

				if (isTableArray(value)) {
					writeArrayTable(out, childPath, cast value);
				} else if (isTable(value)) {
					writeTable(out, childPath, value);
				}
			}
		}
	}

	static function writeTable(out:StringBuf, path:String, obj:Dynamic):Void {
		if (path != "") {
			out.add('[$path]\n');
		}

		var childTables:Array<String> = [];

		for (field in Reflect.fields(obj)) {
			var value = Reflect.field(obj, field);

			if (isTable(value) || isTableArray(value)) {
				childTables.push(field);
				continue;
			}

			out.add('$field = ${writeValue(value)}\n');
		}

		if (childTables.length > 0)
			out.add("\n");

		for (table in childTables) {
			var child = Reflect.field(obj, table);
			var childPath = path == "" ? table : '$path.$table';

			if (isTableArray(child)) {
				writeArrayTable(out, childPath, cast child);
			} else {
				writeTable(out, childPath, child);
			}
		}
	}

	static function writeValue(value:Dynamic):String {
		if (value == null)
			return "\"\"";

		if (Std.isOfType(value, String))
			return writeString(cast value);
		if (Std.isOfType(value, Bool))
			return Std.string(value);
		if (Std.isOfType(value, Int))
			return Std.string(value);

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
		if (Std.isOfType(value, Date))
			return writeDate(cast value);

		return writeInlineTable(value);
	}

	static function writeDate(date:Date):String {
		// Formats Date to RFC 3339 (TOML standard)
		function pad(n:Int)
			return n < 10 ? "0" + n : "" + n;
		var y = date.getFullYear();
		var m = pad(date.getMonth() + 1);
		var d = pad(date.getDate());
		var h = pad(date.getHours());
		var i = pad(date.getMinutes());
		var s = pad(date.getSeconds());
		return '"$y-$m-${d}T$h:$i:${s}Z"';
	}

	static function writeString(value:String):String {
		var escaped = value;
		escaped = escaped.replace("\\", "\\\\");
		escaped = escaped.replace("\"", "\\\"");
		escaped = escaped.replace("\n", "\\n");
		escaped = escaped.replace("\r", "\\r");
		escaped = escaped.replace("\t", "\\t");
		escaped = escaped.replace("\x08", "\\b"); // Backspace
		escaped = escaped.replace("\x0C", "\\f"); // Form feed
		return '"' + escaped + '"';
	}

	static function writeArray(arr:Array<Dynamic>):String {
		var parts = new Array<String>();
		for (v in arr)
			parts.push(writeValue(v));
		return "[" + parts.join(", ") + "]";
	}

	static function writeInlineTable(obj:Dynamic):String {
		var parts = new Array<String>();
		for (field in Reflect.fields(obj)) {
			parts.push('$field = ${writeValue(Reflect.field(obj, field))}');
		}
		return "{ " + parts.join(", ") + " }";
	}

	static function isTable(value:Dynamic):Bool {
		if (value == null)
			return false;
		if (Std.isOfType(value, String) || Std.isOfType(value, Array))
			return false;
		// Reflect.isObject correctly identifies both anonymous structures and class instances
		return Reflect.isObject(value);
	}
}
