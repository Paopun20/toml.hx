import sys.io.File;
import paopao.toml.TomlError;
import paopao.toml.Toml;

class Main {
	static function main() {
		var text = File.getContent("Example.toml");
		var data = Toml.parse(text);
		trace(data);

		trace(Toml.stringify(data));
		trace(data);
	}
}
