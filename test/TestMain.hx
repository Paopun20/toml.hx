package;

import paopao.toml.Toml;

class TestMain {
	static function main() {
		testPrimitives();
		testArrays();
		testTables();
		testNestedTables();
		testInlineTables();
		testArrayOfTables();

		testDottedKeyValue();
		testDeepDottedTableHeader();
		testDottedArrayOfTables();
		testHyphenUnderscoreDottedKeys();
		testFloatsStillWorkWithDottedKeys();
		testDottedKeysDontLeakBetweenTables();
		testMultipleDottedAssignmentsSameParent();

		trace("All tests passed!");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function testPrimitives():Void {
		var data = Toml.parse('
title = "Hello"
count = 42
pi = 3.14
enabled = true
');

		assert(data.title == "Hello", "string");
		assert(data.count == 42, "int");
		assert(data.pi == 3.14, "float");
		assert(data.enabled == true, "bool");

		trace("✓ primitives");
	}

	static function testArrays():Void {
		var data = Toml.parse('
ports = [8000, 8001, 8002]
');

		assert(data.ports.length == 3, "array len");
		assert(data.ports[0] == 8000, "array value");

		trace("✓ arrays");
	}

	static function testTables():Void {
		var data = Toml.parse('
[database]
server = "localhost"
');

		assert(data.database.server == "localhost", "table");

		trace("✓ tables");
	}

	static function testNestedTables():Void {
		var data = Toml.parse('
[database.replica]
enabled = true
');

		assert(data.database.replica.enabled, "nested table");

		trace("✓ nested tables");
	}

	static function testInlineTables():Void {
		var data = Toml.parse('
point = { x = 1, y = 2 }
');

		assert(data.point.x == 1, "inline table x");
		assert(data.point.y == 2, "inline table y");

		trace("✓ inline tables");
	}

	static function testArrayOfTables():Void {
		var data = Toml.parse('
[[products]]
name = "Hammer"

[[products]]
name = "Nail"
');

		assert(data.products.length == 2, "array table len");
		assert(data.products[0].name == "Hammer", "product1");
		assert(data.products[1].name == "Nail", "product2");

		trace("✓ array of tables");
	} // Classic TOML dotted key-value, not just table headers:

	// physical.color = "orange"
	static function testDottedKeyValue():Void {
		var data = Toml.parse('
a.b.c = 1
');

		assert(data.a.b.c == 1, "dotted key-value c");

		trace("✓ dotted key-value");
	}

	static function testDeepDottedTableHeader():Void {
		var data = Toml.parse('
[a.b.c]
x = 1
');

		assert(data.a.b.c.x == 1, "deep dotted table header");

		trace("✓ deep dotted table header (3 levels)");
	}

	// Array-of-tables whose name itself is dotted: [[fruit.variety]]
	static function testDottedArrayOfTables():Void {
		var data = Toml.parse('
[[fruit.variety]]
name = "plantain"

[[fruit.variety]]
name = "rambutan"
');

		assert(data.fruit.variety.length == 2, "dotted array table len");
		assert(data.fruit.variety[0].name == "plantain", "dotted array table 0");
		assert(data.fruit.variety[1].name == "rambutan", "dotted array table 1");

		trace("✓ dotted array of tables");
	}

	// Bare keys can contain hyphens/underscores AND be dotted at the same time.
	// Use Reflect since "my-key" isn't valid Haxe field-access syntax.
	static function testHyphenUnderscoreDottedKeys():Void {
		var data = Toml.parse('
my-key.other_key = "value"
');

		var myKey = Reflect.field(data, "my-key");

		assert(myKey != null, "hyphenated parent exists");
		assert(Reflect.field(myKey, "other_key") == "value", "underscored child value");

		trace("✓ hyphen/underscore mixed with dots");
	}

	// Regression: the lexer buffers dots for number classification BEFORE
	// deciding whether to split as a key path. Make sure floats next to
	// dotted keys in the same doc still parse as numbers, not identifiers.
	static function testFloatsStillWorkWithDottedKeys():Void {
		var data = Toml.parse('
pi = 3.14
[a.b]
ratio = 2.5
');

		assert(data.pi == 3.14, "top-level float");
		assert(data.a.b.ratio == 2.5, "nested float under dotted table");

		trace("✓ floats unaffected by dotted-key split");
	}

	// Make sure splitting a dotted header into multiple IDENTIFIER/DOT
	// tokens doesn't accidentally carry state into the next table.
	static function testDottedKeysDontLeakBetweenTables():Void {
		var data = Toml.parse('
[a.b]
x = 1

[c.d]
y = 2
');

		assert(data.a.b.x == 1, "first dotted table");
		assert(data.c.d.y == 2, "second dotted table");
		assert(!Reflect.hasField(data.a, "d"), "no cross-contamination");

		trace("✓ no state leakage between dotted tables");
	}

	// Two separate dotted key-value lines sharing the same parent should
	// merge into one object rather than overwrite each other.
	static function testMultipleDottedAssignmentsSameParent():Void {
		var data = Toml.parse('
physical.color = "orange"
physical.shape = "round"
');

		assert(data.physical.color == "orange", "shared parent color");
		assert(data.physical.shape == "round", "shared parent shape");

		trace("✓ multiple dotted assignments share parent");
	}
}
