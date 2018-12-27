{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}

-- orphans for OnlineTex Mainable instances
{-# OPTIONS_GHC -fno-warn-orphans #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Diagrams.Backend.PGF.Surface
-- Copyright   :  (c) 2015 Christopher Chalmers
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  diagrams-discuss@googlegroups.com
--
-- A 'Surface' defines how a pgfpicture should be placed and compiled. Surfaces
-- are used for rendering a @.tex@ or @.pdf@ using functions from
-- 'Diagrams.Backend.PGF'.
--
-- Surfaces are also used in 'Diagrams.Backend.PGF.Hbox' for querying
-- envelopes of text.
--
-- Surfaces for Latex, Context and plain Tex are provided and reexported by
-- Diagrams.Backend.PGF. Lenses here allow these to be adjusted as required.
-----------------------------------------------------------------------------

module Diagrams.Backend.PGF.Surface
  ( -- * Surface definition
    Surface(..)
  , TexFormat(..)

    -- * Online rendering with surfaces
  , surfOnlineTex
  , surfOnlineTexIO

    -- * Predefined surfaces
  , latexSurface
  , contextSurface
  , plaintexSurface
  , sampleSurfaceOutput
  , runPageSizeTemplate

    -- * Lenses
  , texFormat
  , command
  , arguments
  , pageSizeTemplate
  , preamble
  , beginDoc
  , endDoc

    -- * Parsers
  , texFormatParser
  , surfaceParser
  ) where

import           Data.ByteString.Builder
import           Data.Hashable            (Hashable (..))
import           Data.Typeable            (Typeable)
import           System.IO.Unsafe
import           System.Texrunner.Online

import           Control.Applicative
import           Control.Lens
import           Data.Default.Class
import           Data.Semigroup
import           Options.Applicative      (eitherReader, help, long, metavar,
                                           short, showDefault, strOption)
import qualified Options.Applicative      as OP

import           Diagrams.Backend.CmdLine
import           Diagrams.Types (Diagram)
import           Geometry.TwoD.Types      (V2 (..))

-- | The 'TexFormat' is used to choose the different PGF commands nessesary for
--   that format.
data TexFormat = LaTeX | ConTeXt | PlainTeX
  deriving (Show, Read, Eq, Typeable)
  -- These names are only captialised so Context doesn't conflict with
  -- lens's Context.

-- instance Parseable TexFormat where
texFormatParser :: OP.Parser TexFormat
texFormatParser = OP.option (eitherReader parseFormat) $ mconcat
  [ short 'f', long "format", OP.value LaTeX, showDefault
  , help "l for LaTeX, c for ConTeXt, p for plain TeX"
  , metavar "FORMAT"]

parseFormat :: String -> Either String TexFormat
parseFormat ('l':_) = Right LaTeX
parseFormat ('c':_) = Right ConTeXt
parseFormat ('p':_) = Right PlainTeX
parseFormat ('t':_) = Right PlainTeX
parseFormat x       = Left $ "Unknown format" ++ x

-- | The surface defines how a tex file (latex, context or plain tex) is
--   generated.
data Surface = Surface
  { _texFormat :: TexFormat -- ^ Format for the PGF commands
  , _command   :: String    -- ^ System command to be called.
  , _arguments :: [String]  -- ^ Auguments for command.
  , _pageSizeTemplate :: String
    -- ^ Template to specify the page size. See 'pageSizeTemplate' for
    --   details.
  , _preamble  :: String    -- ^ Preamble for document, should import pgfcore.
  , _beginDoc  :: String    -- ^ Begin document.
  , _endDoc    :: String    -- ^ End document.
  } deriving Show

makeLensesWith (lensRules & generateSignatures .~ False) ''Surface

-- | Run a page size template, interpolating @${w}@ and @${h}@ with the
--   width and height of the input vector.
runPageSizeTemplate :: V2 Int -> String -> String
runPageSizeTemplate (V2 w h) = go where
  go ('$':'{':'w':'}':xs) = show w ++ go xs
  go ('$':'{':'h':'}':xs) = show h ++ go xs
  go (x:xs)               = x : go xs
  go []                   = []

surfaceParser :: OP.Parser Surface
surfaceParser = modCommand <*> surf where
  surf = texFormatParser <&> \case
    LaTeX    -> latexSurface
    ConTeXt  -> contextSurface
    PlainTeX -> plaintexSurface
  modCommand = maybe id (set command) <$> commandP
  commandP = optional . strOption $ mconcat
    [ short 'c', long "command", metavar "PATH"
    , help "tex command to use" ]

-- | Format for the PGF commands.
texFormat :: Lens' Surface TexFormat

-- | System command to call for rendering PDFs for 'OnlineTex'.
command :: Lens' Surface String

-- | List of arguments for the 'command'.
arguments :: Lens' Surface [String]

-- | Preamble for the tex document. This should at least import
--   @pgfcore@.
preamble :: Lens' Surface String

-- | Specify the page size template for the tex file. The width and
--   height of the diagram (in bp) is interpolated using @${w}@ and
--   @${h}@. See the source of 'latexSurface' for an example.
pageSizeTemplate :: Lens' Surface String

-- | Command to begin the document. (This normally doesn't need to
--   change)
beginDoc :: Lens' Surface String

-- | Command to end the document. (This normally doesn't need to
--   change)
endDoc :: Lens' Surface String

-- Predefined surfaces -------------------------------------------------

-- | Default surface for latex files by calling @pdflatex@.
--
-- ==== __Sample output__
--
-- @
-- 'command': pdflatex
--
-- % 'preamble'
-- \documentclass{article}
-- \usepackage{pgfcore}
-- \usepackage{iftex}
-- \pagenumbering{gobble}
--
-- % 'pageSizeTemplate'
-- \ifLuaTeX
--   \edef\pdfhorigin{\pdfvariable horigin}
--   \edef\pdfvorigin{\pdfvariable vorigin}
-- \fi
-- \usepackage[paperwidth=${w}bp,paperheight=${h}bp,margin=0bp]{geometry}
-- \pdfhorigin=57.0bp
-- \pdfvorigin=73.0bp
--
--
-- % 'beginDoc'
-- \begin{document}
--
-- \<LaTeX pgf code\>
--
-- % 'endDoc'
-- \end{document}
-- @
--
latexSurface :: Surface
latexSurface = Surface
  { _texFormat = LaTeX
  , _command   = "pdflatex"
  , _arguments = []
  , _pageSizeTemplate  = unlines
      [ "\\ifLuaTeX"
      , "  \\edef\\pdfhorigin{\\pdfvariable horigin}"
      , "  \\edef\\pdfvorigin{\\pdfvariable vorigin}"
      , "\\fi"
      , "\\usepackage[paperwidth=${w}bp,paperheight=${h}bp,margin=0bp]{geometry}"
      , "\\pdfhorigin=57.0bp"
      , "\\pdfvorigin=72.0bp"
      ]
  , _preamble  = "\\documentclass{article}\n"
              ++ "\\usepackage{pgfcore}\n"
              ++ "\\usepackage{iftex}\n"
              ++ "\\pagenumbering{gobble}"
  , _beginDoc  = "\\begin{document}"
  , _endDoc    = "\\end{document}"
  }

-- | Default surface for latex files by calling @pdflatex@.
--
-- ==== __Sample output__
--
-- @
-- 'command': context --pipe --once
--
-- % 'preamble'
-- \usemodule[pgf]
-- \setuppagenumbering[location=]
--
-- % 'pageSizeTemplate'
-- \definepapersize[diagram][width=${w}bp,height=${h}bp]
-- \setuppapersize[diagram][diagram]
-- \setuplayout
--   [ topspace=0bp
--   , backspace=0bp
--   , header=0bp
--   , footer=0bp
--   , width=${w}bp
--   , height=${h}bp
--   ]
--
-- % 'beginDoc'
-- \starttext
--
-- \<Context pgf code\>
--
-- % 'endDoc'
-- \stoptext
-- @
--
contextSurface :: Surface
contextSurface = Surface
  { _texFormat = ConTeXt
  , _command   = "context"
  , _arguments = ["--pipe", "--once"]
  , _pageSizeTemplate  = unlines
      [ "\\definepapersize[diagram][width=${w}bp,height=${h}bp]\n"
      , "\\setuppapersize[diagram][diagram]\n"
      , "\\setuplayout\n"
      , "  [ topspace=0bp\n"
      , "  , backspace=0bp\n"
      , "  , header=0bp\n"
      , "  , footer=0bp\n"
      , "  , width=${w}bp\n"
      , "  , height=${h}bp\n"
      , "  ]"
      ]
  , _preamble  = "\\usemodule[pgf]\n" -- pgfcore doesn't work
              ++ "\\setuppagenumbering[location=]"
  , _beginDoc  = "\\starttext"
  , _endDoc    = "\\stoptext"
  }

-- | Default surface for latex files by calling @pdflatex@.
--
-- ==== __Sample output__
--
-- @
-- 'command': pdftex
--
-- % 'preamble'
-- \input eplain
-- \beginpackages
-- \usepackage{color}
-- \endpackages
-- \input pgfcore
-- \def\frac#1#2{{\begingroup #1\endgroup\over #2}}\nopagenumbers
--
-- % 'pageSizeTemplate'
-- \pdfpagewidth=${w}bp
-- \pdfpageheight=${h}bp
-- \pdfhorigin=-20bp
-- \pdfvorigin=0bp
--
-- % 'beginDoc'
--
--
-- <PlainTex pgf code>
--
-- % 'endDoc'
-- \bye
-- @
--
plaintexSurface :: Surface
plaintexSurface = Surface
  { _texFormat = PlainTeX
  , _command   = "pdftex"
  , _arguments = []
  , _pageSizeTemplate  = unlines
      [ "\\pdfpagewidth=${w}bp"
      , "\\pdfpageheight=${h}bp"
      , "\\pdfhorigin=-20bp"
      , "\\pdfvorigin=0bp"
      ]
  , _preamble  = "\\input eplain\n"
              ++ "\\beginpackages\n\\usepackage{color}\n\\endpackages\n"
              ++ "\\input pgfcore\n"
              ++ "\\def\\frac#1#2{{\\begingroup #1\\endgroup\\over #2}}"
              ++ "\\nopagenumbers"
  , _beginDoc  = ""
  , _endDoc    = "\\bye"
  }

-- | Latex is the default surface.
instance Default Surface where
  def = latexSurface

sampleSurfaceOutput :: Surface -> String
sampleSurfaceOutput surf = unlines
  [ "command: " ++ surf ^. command ++ " " ++ unwords (surf ^. arguments)
  , "\n% preamble"
  , surf ^. preamble
  , "\n% pageSizeTemplate"
  , surf ^. pageSizeTemplate
  , "\n% beginDoc"
  , surf ^. beginDoc
  , "\n<" ++ show (surf ^. texFormat) ++ " pgf code>"
  , "\n% endDoc"
  , surf ^. endDoc
  ]

-- OnlineTex functions -------------------------------------------------

instance WithOutcome (OnlineTex (Diagram V2))

-- | Get the result of an OnlineTex using the given surface.
surfOnlineTex :: Surface -> OnlineTex a -> a
surfOnlineTex surf a = unsafePerformIO (surfOnlineTexIO surf a)
{-# NOINLINE surfOnlineTex #-}

-- | Get the result of an OnlineTex using the given surface.
surfOnlineTexIO :: Surface -> OnlineTex a -> IO a
surfOnlineTexIO surf = runOnlineTex (surf^.command) (surf^.arguments) begin
  where
    begin = view strict . toLazyByteString . stringUtf8
          $ surf ^. (preamble <> beginDoc)

-- Hashable instances --------------------------------------------------

instance Hashable TexFormat where
  hashWithSalt s LaTeX    = s `hashWithSalt` (1::Int)
  hashWithSalt s ConTeXt  = s `hashWithSalt` (2::Int)
  hashWithSalt s PlainTeX = s `hashWithSalt` (3::Int)

instance Hashable Surface where
  hashWithSalt s (Surface tf cm ar ps p bd ed)
    = s  `hashWithSalt`
      tf `hashWithSalt`
      cm `hashWithSalt`
      ar `hashWithSalt`
      ps `hashWithSalt`
      p  `hashWithSalt`
      bd `hashWithSalt`
      ed

