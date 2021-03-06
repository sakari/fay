{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}

-- | All Fay types and instances.

module Language.Fay.Types
  (JsStmt(..)
  ,JsExp(..)
  ,JsLit(..)
  ,JsParam
  ,JsName
  ,CompileError(..)
  ,Compile(..)
  ,CompilesTo(..)
  ,Printable(..)
  ,Fay
  ,CompileConfig(..)
  ,CompileState(..)
  ,FayReturnType(..)
  ,ArgType(..))
  where

import           Control.Applicative
import           Control.Exception
import           Control.Monad.Error    (Error, ErrorT, MonadError)
import           Control.Monad.Identity (Identity)
import           Control.Monad.State
import           Data.Data
import           Data.Default
import           Language.Haskell.Exts

--------------------------------------------------------------------------------
-- Compiler types

-- | Configuration of the compiler.
data CompileConfig = CompileConfig
  { configTCO            :: Bool
  , configInlineForce    :: Bool
  , configFlattenApps    :: Bool
  , configExportBuiltins :: Bool
  } deriving (Show)

-- | Default configuration.
instance Default CompileConfig where
  def = CompileConfig False False False True

-- | State of the compiler.
data CompileState = CompileState
  { stateConfig     :: CompileConfig
  , stateExports    :: [Name]
  , stateExportAll  :: Bool
  , stateModuleName :: ModuleName
  } deriving (Show)

-- | Compile monad.
newtype Compile a = Compile { unCompile :: StateT CompileState (ErrorT CompileError IO) a }
  deriving (MonadState CompileState
           ,MonadError CompileError
           ,MonadIO
           ,Monad
           ,Functor
           ,Applicative)

-- | Convenience type for function parameters.
type JsParam = JsName

-- | To be used to force name sanitization eventually.
type JsName = QName -- FIXME: Force sanitization at this point.

-- | Just a convenience class to generalize the parsing/printing of
-- various types of syntax.
class (Parseable from,Printable to) => CompilesTo from to | from -> to where
  compileTo :: from -> Compile to

-- | Print some value.
class Printable a where
  printJS :: a -> String

-- | Error type.
data CompileError
  = ParseError SrcLoc String
  | UnsupportedDeclaration Decl
  | UnsupportedExportSpec ExportSpec
  | UnsupportedMatchSyntax Match
  | UnsupportedWhereInMatch Match
  | UnsupportedExpression Exp
  | UnsupportedLiteral Literal
  | UnsupportedLetBinding Decl
  | UnsupportedOperator QOp
  | UnsupportedPattern Pat
  | UnsupportedRhs Rhs
  | UnsupportedGuardedAlts GuardedAlts
  | EmptyDoBlock
  | UnsupportedModuleSyntax Module
  | LetUnsupported
  | InvalidDoBlock
  | RecursiveDoUnsupported
  | FfiNeedsTypeSig Decl
  | FfiFormatBadChars String
  | FfiFormatNoSuchArg Int
  | FfiFormatIncompleteArg
  | FfiFormatInvalidJavaScript String String
  deriving (Show,Eq,Data,Typeable)
instance Error CompileError
instance Exception CompileError

-- | The JavaScript FFI interfacing monad.
newtype Fay a = Fay (Identity a)
  deriving Monad

--------------------------------------------------------------------------------
-- JS AST types

-- | Statement type.
data JsStmt
  = JsVar JsName JsExp
  | JsIf JsExp [JsStmt] [JsStmt]
  | JsEarlyReturn JsExp
  | JsThrow JsExp
  | JsWhile JsExp [JsStmt]
  | JsUpdate JsName JsExp
  | JsSetProp JsName JsName JsExp
  | JsContinue
  deriving (Show,Eq)

-- | Expression type.
data JsExp
  = JsName JsName
  | JsRawExp String
  | JsFun [JsParam] [JsStmt] (Maybe JsExp)
  | JsLit JsLit
  | JsApp JsExp [JsExp]
  | JsTernaryIf JsExp JsExp JsExp
  | JsNull
  | JsSequence [JsExp]
  | JsParen JsExp
  | JsGetProp JsExp JsName
  | JsUpdateProp JsExp JsName JsExp
  | JsGetPropExtern JsExp JsName
  | JsUpdatePropExtern JsExp JsName JsExp
  | JsList [JsExp]
  | JsNew JsName [JsExp]
  | JsThrowExp JsExp
  | JsInstanceOf JsExp JsName
  | JsIndex Int JsExp
  | JsEq JsExp JsExp
  | JsInfix String JsExp JsExp -- Used to optimize *, /, +, etc
  deriving (Show,Eq)

-- | Literal value type.
data JsLit
  = JsChar Char
  | JsStr String
  | JsInt Int
  | JsFloating Double
  | JsBool Bool
  deriving (Show,Eq)

data FayReturnType = FayArray | FayList | FayString | FayBool | FayNone
  deriving (Read,Show,Eq)

-- | These are the data types that are serializable directly to native
-- JS data types. Strings, floating points and arrays. The others are:
-- actiosn in the JS monad, which are thunks that shouldn't be forced
-- when serialized but wrapped up as JS zero-arg functions, and
-- unknown types can't be converted but should at least be forced.
data ArgType = FunctionType | JsType | StringType | DoubleType | ListType | BoolType | UnknownType
  deriving (Show,Eq)
