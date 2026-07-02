package paopao.toml;

final class Token {
	public final type:TokenType;

	/**
	 * Raw value associated with token
	 */
	public final value:String;

	public final line:Int;
	public final column:Int;

	public function new(type:TokenType, value:String, line:Int, column:Int) {
		this.type = type;
		this.value = value;
		this.line = line;
		this.column = column;
	}

	public function toString():String
		return 'Token($type, "$value", $line:$column)';
}