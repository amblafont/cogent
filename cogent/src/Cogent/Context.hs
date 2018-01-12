--
-- Copyright 2016, NICTA
--
-- This software may be distributed and modified according to the terms of
-- the GNU General Public License version 2. Note that NO WARRANTY is provided.
-- See "LICENSE_GPLv2.txt" for details.
--
-- @TAG(NICTA_GPL)
--

module Cogent.Context
  ( Context
  , Row
  , addScope
  , contains
  , dropScope
  , empty
  , lookup
  , merge
  , mode
  , use
) where

import Cogent.Common.Syntax
import Cogent.Compiler (__impossible)

import Control.Lens hiding (Context, contains, use)
import Data.List (foldl', partition)
import qualified Data.Sequence as Seq
import qualified Data.Map.Strict as M
import Prelude hiding (lookup)
import Text.Parsec.Pos

type Row t = (t, SourcePos, Seq.Seq SourcePos)
--                            ^------ the locations where it's used; serves as an use count
newtype Context t = Context [M.Map VarName (Row t)]

empty :: Context t
empty = Context []

lookup :: VarName -> Context t -> Maybe (t, SourcePos, Seq.Seq SourcePos)
lookup v (Context (x:xs)) | Just r <- M.lookup v x = Just r
                          | otherwise              = lookup v (Context xs)
lookup v (Context []) = Nothing

contains :: Context t -> VarName -> Bool
contains (Context xs) v = any (M.member v) xs

use :: VarName -> SourcePos -> Context t -> Context t
use v loc (Context xs) = Context (go xs)
  where go (x:xs) | M.member v x = M.adjust (\(t, p, us) -> (t, p, us Seq.|> loc)) v x:xs
                  | otherwise    = x:go xs
        go [] = []

addScope :: M.Map VarName (Row t) -> Context t -> Context t
addScope m (Context ms) = Context (m:ms)

dropScope :: Context t -> (M.Map VarName (Row t), Context t)
dropScope (Context (m:ms)) = (m, Context ms)
dropScope (Context [])     = error "dropScope of empty context!"

mode' :: M.Map VarName x -> [VarName] -> (x -> x) -> (M.Map VarName x, M.Map VarName x -> M.Map VarName x)
mode' c vs f =
  let c' = c & itraversed.indices (`elem` vs) %~ f
      undo d = foldl' (\x v -> x & at v .~ M.lookup v c) d vs
  in (c', undo)

mode :: Context t -> [VarName]
     -> ((t, SourcePos, Seq.Seq SourcePos) -> (t, SourcePos, Seq.Seq SourcePos))
     -> (Context t, Context t -> Context t)
mode (Context ms) vs f = let (c', f') = go ms vs
                         in (Context c', \(Context x) -> Context (f' x))
  where
    go [] vs     = ([], id)
    go (m:ms) vs = let
        (as, bs) = partition (`M.member` m) vs
        (m', um) = mode' m as f
        (ms', ums) = go ms bs
        undo (n:ns) = (um n : ums ns)
        undo []     = []
      in (m':ms', undo)


data UnionHelper x = First x | Second x | Both x

unhelp :: UnionHelper x -> x
unhelp (First x) = x
unhelp (Second x) = x
unhelp (Both x) = x

isFirst :: UnionHelper x -> Bool
isFirst (First x) = True
isFirst _ = False

isSecond :: UnionHelper x -> Bool
isSecond (Second x) = True
isSecond _ = False

merge' :: M.Map VarName (Row x) -> M.Map VarName (Row x) -> (M.Map VarName (Row x), [(VarName, Row x)], [(VarName, Row x)])
merge' a b = let a' = fmap First a
                 b' = fmap Second b
                 m  = M.unionWithKey f a' b'
                 f k (First (t, p, Seq.Empty)) (Second (_, _, Seq.Empty)) = Both (t, p, Seq.empty)
                 f k (First (t, p, us)) (Second (_, _, Seq.Empty)) = First  (t, p, us)
                 f k (First (_, _, Seq.Empty)) (Second (t, p, us)) = Second (t, p, us)
                 f k (First (t, p, us)) (Second (_, _, vs)) = Both (t, p, us Seq.>< vs)
                 f k _ _ = __impossible "merge'"
                 newM = fmap unhelp m
                 ls = M.toList $ unhelp <$> M.filter isFirst m
                 rs = M.toList $ unhelp <$> M.filter isSecond m
              in (newM, ls, rs)

merge :: Context t -> Context t -> (Context t, [(VarName, Row t)], [(VarName, Row t)])
merge (Context a) (Context b) = let (c, l, r) = go a b in (Context c, l, r)
  where
    go [] [] = ([], [], [])
    go [] _  = __impossible "merge"
    go _ []  = __impossible "merge"
    go (a:as) (b:bs) = let
      (cs, ls, rs) = go as bs
      (c,  l,  r ) = merge' a b
      in (c:cs, l ++ ls, r ++ rs)
