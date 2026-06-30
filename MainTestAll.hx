import haxe.Log;
import sys.io.File;
import paopao.toml.Toml;
import haxe.io.Bytes;
import Sys;

class Main {
	static function main() {
		var root = "toml-test/tests";
		var manifest = File.getContent('$root/files-toml-1.1.0').split("\n");

		var pass = [];
		var error = [];

		Log.trace = function(v, ?infos) {
			Sys.stdout().writeString(v + "\n");
			Sys.stdout().flush();
		}

		for (entry in manifest) {
			entry = StringTools.trim(entry);

			if (!StringTools.endsWith(entry, ".toml"))
				continue;

			var isValid = StringTools.startsWith(entry, "valid/");
			var isInvalid = StringTools.startsWith(entry, "invalid/");

			if (!isValid && !isInvalid)
				continue;

			var path = '$root/$entry';
			var bytes = File.getBytes(path);

			if (!isValidUtf8(bytes))
				continue;

			var ok = true;
			var errMsg = "";

			try {
				Toml.parse(bytes.toString());

				if (isInvalid)
					ok = false;
			} catch (e:Any) {
				if (isValid) {
					ok = false;
					errMsg = Std.string(e);
				}
			}

			if (!ok && isValid)
				trace('FAIL $entry -> $errMsg');

			if (ok) {
				pass.push(entry);
			} else {
				error.push(entry);
			}
		}

		trace("pass");

		for (x in pass)
			trace("- " + x);

		trace("");

		trace("error");

		for (x in error)
			trace("- " + x);
	}

	static function isValidUtf8(bytes:Bytes):Bool {
		var i = 0;

		while (i < bytes.length) {
			var b = bytes.get(i++);
			var codepoint:Int;

			if (b < 0x80) {
				codepoint = b;
			} else if (b >= 0xC2 && b <= 0xDF) {
				if (i >= bytes.length)
					return false;

				var b2 = bytes.get(i++);

				if (!isContinuation(b2))
					return false;

				codepoint = ((b & 0x1F) << 6) | (b2 & 0x3F);
			} else if (b >= 0xE0 && b <= 0xEF) {
				if (i + 1 >= bytes.length)
					return false;

				var b2 = bytes.get(i++);
				var b3 = bytes.get(i++);

				if (!isContinuation(b2) || !isContinuation(b3))
					return false;

				if (b == 0xE0 && b2 < 0xA0)
					return false;

				if (b == 0xED && b2 >= 0xA0)
					return false;

				codepoint = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
			} else if (b >= 0xF0 && b <= 0xF4) {
				if (i + 2 >= bytes.length)
					return false;

				var b2 = bytes.get(i++);
				var b3 = bytes.get(i++);
				var b4 = bytes.get(i++);

				if (!isContinuation(b2) || !isContinuation(b3) || !isContinuation(b4))
					return false;

				if (b == 0xF0 && b2 < 0x90)
					return false;

				if (b == 0xF4 && b2 > 0x8F)
					return false;

				codepoint = ((b & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F);
			} else {
				return false;
			}

			if (codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
				return false;
		}

		return true;
	}

	static inline function isContinuation(byte:Int):Bool
		return byte >= 0x80 && byte <= 0xBF;
}
