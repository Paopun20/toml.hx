import sys.io.File;
import paopao.toml.Toml;
import haxe.Timer;

class Main {
	static function main() {
		var text = File.getContent("Example-Tester.toml");
        var st = Timer.stamp();
		var data = Toml.parse(text);
		var stringifyTime = Timer.stamp() - st;
		trace('Parse: ${Std.int(stringifyTime * 1000)} ms');

        var st = Timer.stamp();
		File.saveContent("Example-TDone.toml", Toml.stringify(data));
		var stringifyTime = Timer.stamp() - st;
		trace('Stringify: ${Std.int(stringifyTime * 1000)} ms');
	}
}
