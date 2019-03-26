# hspec-junit-formatter

A `JUnit` XML runner/formatter for [`hspec`](http://hspec.github.io/).

```hs
main :: IO ()
main = do
  config <- readConfig defaultConfig =<< getArgs
  spec `runJUnitSpec` ("output-dir", "my-tests") $ config
```
