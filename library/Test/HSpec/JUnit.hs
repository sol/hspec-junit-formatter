module Test.HSpec.JUnit
  ( runJUnitSpec
  , configWith
  ) where

import Prelude

import Control.Monad.Trans.Resource (runResourceT)
import Data.Conduit (runConduit, (.|))
import Data.Conduit.Combinators (sinkFile)
import Data.Foldable (traverse_)
import Data.Text (Text)
import qualified Data.Text as T
import System.IO.Temp (emptySystemTempFile)
import System.Directory (createDirectoryIfMissing)
import Test.Hspec (Spec)
import Test.Hspec.Formatters (Formatter(..), writeLine, FailureReason(..), FormatM)
import Test.HSpec.JUnit.Parse (parseJUnit, denormalize)
import Test.HSpec.JUnit.Render (renderJUnit)
import Test.Hspec.Runner (Config(..), Summary, runSpec)
import Text.XML.Stream.Parse (parseFile)
import Text.XML.Stream.Render (def, renderBytes)

runJUnitSpec :: Spec -> (FilePath, String) -> Config -> IO Summary
runJUnitSpec spec (path, name) config = do
  tempFile <- emptySystemTempFile $ "hspec-junit-" <> name
  summary <- spec `runSpec` configWith tempFile name config
  createDirectoryIfMissing True dirPath
  runResourceT
    . runConduit
    $ parseFile def tempFile
    .| parseJUnit
    -- HSpec's formatter cannot correctly output JUnit, so we must denormalize
    -- nested <testsuite /> elements.
    .| denormalize
    .| renderJUnit
    .| renderBytes def
    .| sinkFile (dirPath <> "/test_results.xml")
  pure summary
  where dirPath = path <> "/" <> name

configWith :: FilePath -> String -> Config -> Config
configWith filePath name config = config
  { configFormatter = Just $ junitFormatter name
  , configOutputFile = Right filePath
  }

junitFormatter :: String -> Formatter
junitFormatter suiteName = Formatter
  { headerFormatter = do
    writeLine "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"
    writeLine $ "<testsuites name=" <> show suiteName <> ">"
  -- TODO needs: package, id, timestamp, hostname, tests, failures, errors, time
  , exampleGroupStarted = \_paths name ->
    writeLine $ "<testsuite name=" <> show (fixBrackets (T.pack name)) <> ">"
  , exampleGroupDone = writeLine "</testsuite>"
  , exampleProgress = \_ _ -> pure ()
  , exampleSucceeded = \path _info ->
    writeLine $ "<testcase name=" <> mkName path <> "/>"
  , exampleFailed = \path info reason -> do
    writeLine $ "<testcase name=" <> mkName path <> ">"
    writeLine $ "<failure type=\"error\">"
    traverse_ (writeLine . fixReason) $ lines info
    case reason of
      Error _ err -> writeLine . fixReason $ show err
      NoReason -> writeLine "no reason"
      Reason err -> traverse_ (writeLine . fixReason) $ lines err
      ExpectedButGot preface expected actual -> do
        traverse_ writeLine preface
        writeFound "expected" expected
        writeFound " but got" actual
    writeLine "</failure>"
    writeLine "</testcase>"
  , examplePending = \path info reason -> do
    writeLine $ "<testcase name=" <> mkName path <> ">"
    writeLine $ "<skipped>"
    traverse_ (writeLine . fixReason) $ lines info
    writeLine $ maybe "No reason given" fixReason reason
    writeLine "</skipped>"
    writeLine "</testcase>"
  , failedFormatter = pure ()
  , footerFormatter = writeLine "</testsuites>"
  }

mkName :: (a, String) -> String
mkName = show . fixBrackets . T.pack . snd

fixBrackets :: Text -> Text
fixBrackets =
  T.replace "\"" "&quot;"
    . T.replace "<" "&lt;"
    . T.replace ">" "&gt;"
    . T.replace "&" "&amp;"

fixReason :: String -> String
fixReason = T.unpack . fixBrackets . T.pack

writeFound :: Show a => Text -> a -> FormatM ()
writeFound msg found = case lines' of
  [] -> pure ()
  first : rest -> do
    writeLine . T.unpack $ msg <> ": " <> first
    traverse_ writeLine $ map (T.unpack . (T.replicate 9 " " <>)) rest
  where lines' = map fixBrackets . T.lines . T.pack $ show found
