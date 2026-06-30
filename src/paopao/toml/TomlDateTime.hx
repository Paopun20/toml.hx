package paopao.toml;

@:allow(paopao.toml.Parser)
@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class TomlDateTime {
	public var year(default, null):Null<Int>;
	public var month(default, null):Null<Int>;
	public var day(default, null):Null<Int>;

	public var hour(default, null):Null<Int>;
	public var minute(default, null):Null<Int>;
	public var second(default, null):Null<Int>;
	public var nanosecond(default, null):Null<Int>;

	/** UTC offset in minutes. Null = local/no offset */
	public var offsetMinutes(default, null):Null<Int>;

	private function new() {}

	public static function localDate(year:Int, month:Int, day:Int):TomlDateTime {
		var dt = new TomlDateTime();
		dt.year = year;
		dt.month = month;
		dt.day = day;
		return dt;
	}

	public static function localTime(hour:Int, minute:Int, second:Int, nanosecond:Int = 0):TomlDateTime {
		var dt = new TomlDateTime();
		dt.hour = hour;
		dt.minute = minute;
		dt.second = second;
		dt.nanosecond = nanosecond;
		return dt;
	}

	public static function localDateTime(year:Int, month:Int, day:Int, hour:Int, minute:Int, second:Int, nanosecond:Int = 0):TomlDateTime {
		var dt = localDate(year, month, day);
		dt.hour = hour;
		dt.minute = minute;
		dt.second = second;
		dt.nanosecond = nanosecond;
		return dt;
	}

	public static function offsetDateTime(year:Int, month:Int, day:Int, hour:Int, minute:Int, second:Int, offsetMinutes:Int, nanosecond:Int = 0):TomlDateTime {
		var dt = localDateTime(year, month, day, hour, minute, second, nanosecond);
		dt.offsetMinutes = offsetMinutes;
		return dt;
	}

	public inline function hasDate():Bool
		return year != null;

	public inline function hasTime():Bool
		return hour != null;

	public inline function hasOffset():Bool
		return offsetMinutes != null;

	public inline function isLocalDate():Bool
		return hasDate() && !hasTime();

	public inline function isLocalTime():Bool
		return !hasDate() && hasTime();

	public inline function isLocalDateTime():Bool
		return hasDate() && hasTime() && !hasOffset();

	public inline function isOffsetDateTime():Bool
		return hasDate() && hasTime() && hasOffset();

	public function clone():TomlDateTime {
		var dt = new TomlDateTime();

		dt.year = year;
		dt.month = month;
		dt.day = day;

		dt.hour = hour;
		dt.minute = minute;
		dt.second = second;
		dt.nanosecond = nanosecond;

		dt.offsetMinutes = offsetMinutes;

		return dt;
	}

	public function equals(other:TomlDateTime):Bool {
		return year == other.year && month == other.month && day == other.day && hour == other.hour && minute == other.minute && second == other.second
			&& nanosecond == other.nanosecond && offsetMinutes == other.offsetMinutes;
	}

	public function toString():String {
		var buf = new StringBuf();

		if (hasDate()) {
			buf.add(pad(year, 4));
			buf.add("-");
			buf.add(pad(month, 2));
			buf.add("-");
			buf.add(pad(day, 2));
		}

		if (hasDate() && hasTime()) {
			buf.add("T");
		}

		if (hasTime()) {
			buf.add(pad(hour, 2));
			buf.add(":");
			buf.add(pad(minute, 2));
			buf.add(":");
			buf.add(pad(second, 2));

			if (nanosecond != null && nanosecond != 0) {
				buf.add(".");
				buf.add(formatNanosecond(nanosecond));
			}

			if (hasOffset()) {
				if (offsetMinutes == 0) {
					buf.add("Z");
				} else {
					var sign = offsetMinutes < 0 ? "-" : "+";
					var abs = offsetMinutes < 0 ? -offsetMinutes : offsetMinutes;
					var oh = Std.int(abs / 60);
					var om = abs % 60;
					buf.add(sign);
					buf.add(pad(oh, 2));
					buf.add(":");
					buf.add(pad(om, 2));
				}
			}
		}

		return buf.toString();
	}

	public static function parse(text:String):TomlDateTime {
		text = StringTools.trim(text);

		var fullRe = ~/^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|z|[+-]\d{2}:\d{2})?)?$/;
		var timeRe = ~/^(\d{2}):(\d{2}):(\d{2})(\.\d+)?$/;

		if (fullRe.match(text)) {
			var year = Std.parseInt(fullRe.matched(1));
			var month = Std.parseInt(fullRe.matched(2));
			var day = Std.parseInt(fullRe.matched(3));

			var hourStr = fullRe.matched(4);
			if (hourStr == null) {
				return localDate(year, month, day);
			}

			var hour = Std.parseInt(hourStr);
			var minute = Std.parseInt(fullRe.matched(5));
			var second = Std.parseInt(fullRe.matched(6));
			var nanosecond = parseFraction(fullRe.matched(7));
			var offsetStr = fullRe.matched(8);

			if (offsetStr == null) {
				return localDateTime(year, month, day, hour, minute, second, nanosecond);
			}

			var offsetMinutes = parseOffset(offsetStr);
			return offsetDateTime(year, month, day, hour, minute, second, offsetMinutes, nanosecond);
		}

		if (timeRe.match(text)) {
			var hour = Std.parseInt(timeRe.matched(1));
			var minute = Std.parseInt(timeRe.matched(2));
			var second = Std.parseInt(timeRe.matched(3));
			var nanosecond = parseFraction(timeRe.matched(4));
			return localTime(hour, minute, second, nanosecond);
		}

		throw 'Invalid TOML datetime: $text';
	}

	private static function pad(n:Int, len:Int):String {
		var s = Std.string(n);
		while (s.length < len)
			s = "0" + s;
		return s;
	}

	private static function formatNanosecond(ns:Int):String {
		var s = pad(ns, 9);
		while (s.length > 1 && StringTools.endsWith(s, "0")) {
			s = s.substr(0, s.length - 1);
		}
		return s;
	}

	private static function parseFraction(frac:Null<String>):Int {
		if (frac == null)
			return 0;
		var digits = frac.substr(1); // drop leading "."
		digits = (digits + "000000000").substr(0, 9);
		return Std.parseInt(digits);
	}

	private static function parseOffset(offsetStr:String):Int {
		if (offsetStr == "Z" || offsetStr == "z")
			return 0;
		var sign = offsetStr.charAt(0) == "-" ? -1 : 1;
		var oh = Std.parseInt(offsetStr.substr(1, 2));
		var om = Std.parseInt(offsetStr.substr(4, 2));
		return sign * (oh * 60 + om);
	}
}
