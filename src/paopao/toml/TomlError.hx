package paopao.toml;

import haxe.Exception;

/**
 * TOML parsing/lexing exception.
 */
class TomlError extends Exception {
	public final line:Int;
	public final column:Int;

	public function new(message:String, line:Int, column:Int) {
		super(format(message, line, column));

		this.line = line;
		this.column = column;
	}

	static function format(message:String, line:Int, column:Int):String {
		return message + " at line " + line + ", column " + column;
	}
}
