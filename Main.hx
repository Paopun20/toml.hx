import sys.io.File;
import paopao.toml.Toml;
import haxe.Timer;

class Main {
	static function main() {
		var text = File.getContent("Example-Tester.toml");

		// Warm-up
		var data = Toml.parse(text);
		Toml.stringify(data);

		var iterations = 1000;

		// Parse
		var start = Timer.stamp();
		for (i in 0...iterations)
			Toml.parse(text);

		trace('Average Parse: ${((Timer.stamp() - start) / iterations) * 1000} ms');

		// Stringify
		start = Timer.stamp();
		for (i in 0...iterations)
			Toml.stringify(data);

		trace('Average Stringify: ${((Timer.stamp() - start) / iterations) * 1000} ms');
	}
}
