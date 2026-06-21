class TestFeatures {
    static function main() {
        var content = sys.io.File.getContent("test_toml_features.toml");
        try {
            var data = paopao.toml.Toml.parse(content);
            trace("Parse succeeded!");
        } catch (e:Dynamic) {
            trace("Parse failed: " + e);
        }
    }
}
