# Toml.hx

A Haxe implementation of the [TOML](https://toml.io/) configuration language.

## Features

- TOML parser
- TOML serializer
- Tables
- Nested tables
- Arrays
- Nested arrays
- Inline tables
- Dotted keys
- Array of tables (`[[table]]`)
- File loading and saving
- Haxe `Dynamic` object support
- Cross-platform

## Installation

### Haxelib

```bash
haxelib install toml
```

### Development

```bash
git clone https://github.com/yourname/toml-hx.git
```

## Usage

### Parsing

```haxe
import paopao.toml.Toml;

var config = Toml.parse('
title = "Example"

[database]
host = "localhost"
port = 5432
');

trace(config.database.host);
```

### Loading a File

```haxe
import paopao.toml.Toml;

var config = Toml.parseFile(
    "config.toml"
);

trace(config.database.port);
```

### Writing

```haxe
import paopao.toml.Toml;

var config = {
    title: "Example",

    database: {
        host: "localhost",
        port: 5432
    }
};

var toml = Toml.stringify(config);

trace(toml);
```

Output:

```toml
title = "Example"

[database]
host = "localhost"
port = 5432
```

### Saving

```haxe
Toml.save(
    "config.toml",
    config
);
```

## API

```haxe
Toml.parse(text:String):Dynamic;

Toml.parseFile(path:String):Dynamic;

Toml.stringify(value:Dynamic):String;

Toml.save(path:String, value:Dynamic):Void;
```

## Example TOML

```toml
title = "TOML Example"

[owner]
name = "Tom Preston-Werner"

[database]
server = "192.168.1.1"
ports = [8000, 8001, 8002]
enabled = true
```

## License

[License](./License.md)