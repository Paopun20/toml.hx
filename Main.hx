import sys.io.File;
import paopao.toml.Toml;
import haxe.Timer;

class Memory {
	public static function used():Float {
		#if cpp
		return cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
		#elseif js
		var perf = untyped js.Browser.window.performance;
		return (perf != null && perf.memory != null) ? perf.memory.usedJSHeapSize : -1;
		#elseif hl
		return hl.Gc.stats().currentMemory;
		#else
		return -1;
		#end
	}

	public static function freeup():Void {
		#if cpp
		cpp.vm.Gc.run(true);
		#elseif hl
		hl.Gc.major();
		#end
	}
}

class Main {
	static function main() {
		var text:String = File.getContent("Example-Tester.toml");

		// Warm-up
		var data:Dynamic = Toml.parse(text);
		Toml.stringify(data);

		var iterations = 1000;

		// Parse
		var start = Timer.stamp();
		var parseMemory:Float = 0;

		for (i in 0...iterations) {
			Toml.parse(text);

			var mem = Memory.used();
			if (mem >= 0)
				parseMemory += mem;

			Memory.freeup();
		}

		trace('Average Parse: ${((Timer.stamp() - start) / iterations) * 1000} ms');
		trace('Average Parse Memory: ${(parseMemory / iterations) / 1024} KB');


		// Stringify
		start = Timer.stamp();
		var stringifyMemory:Float = 0;

		for (i in 0...iterations) {
			Toml.stringify(data);

			var mem = Memory.used();
			if (mem >= 0)
				stringifyMemory += mem;

			Memory.freeup();
		}

		trace('Average Stringify: ${((Timer.stamp() - start) / iterations) * 1000} ms');
		trace('Average Stringify Memory: ${(stringifyMemory / iterations) / 1024} KB');


		// Final memory
		var memoryUsage = Memory.used();

		if (memoryUsage < 0)
			trace('Memory Usage: Not available on this platform');
		else
			trace('Current Memory Usage: ${memoryUsage / 1024} KB');
	}
}