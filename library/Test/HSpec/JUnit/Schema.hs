module Test.HSpec.JUnit.Schema
  ( Suites(..)
  , Suite(..)
  , TestCase(..)
  , Result(..)
  ) where

import Prelude

import Data.Text (Text)

data Suites = Suites Text [Suite]
  deriving (Show)

data Suite = Suite Text [Either Suite TestCase]
  deriving (Show)

data TestCase = TestCase Text (Maybe Result)
  deriving (Show)

data Result = Failure Text Text | Skipped Text
  deriving (Show)