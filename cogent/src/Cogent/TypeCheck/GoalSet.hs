--
-- Copyright 2016, NICTA
--
-- This software may be distributed and modified according to the terms of
-- the GNU General Public License version 2. Note that NO WARRANTY is provided.
-- See "LICENSE_GPLv2.txt" for details.
--
-- @TAG(NICTA_GPL)
--

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ViewPatterns #-}

module Cogent.TypeCheck.GoalSet where

import           Control.Lens hiding ((:<))
import qualified Data.Map as M
import           Cogent.TypeCheck.Base
import           Cogent.PrettyPrint
import qualified Text.PrettyPrint.ANSI.Leijen as P
import           Text.PrettyPrint.ANSI.Leijen hiding ((<$>), (<>))
import qualified Data.Foldable as F

-- A more efficient implementation would be a term net

data Goal = Goal { _goalContext :: [ErrorContext]
                 , _goal :: Constraint
                 }  -- high-level context at the end of _goalContext

instance Show Goal where
  show (Goal c g) = const (show big) big
    where big = (small P.<$> (P.vcat $ map (flip prettyCtx True) c))
          small = pretty g

makeLenses ''Goal

newtype GoalSet = GS (M.Map Constraint Goal) deriving (Show)

insert :: GoalSet -> Goal -> GoalSet
insert (GS x) g = (GS (M.insert (g ^. goal) g x))

toList :: GoalSet -> [Goal]
toList (GS x) = F.toList x

instance Monoid GoalSet where
  mempty = GS mempty
  mappend (GS a) (GS b) = GS (mappend a b)

singleton :: Goal -> GoalSet
singleton = insert mempty
