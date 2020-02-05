--
-- Copyright 2018, Data61
-- Commonwealth Scientific and Industrial Research Organisation (CSIRO)
-- ABN 41 687 119 230.
--
-- This software may be distributed and modified according to the terms of
-- the GNU General Public License version 2. Note that NO WARRANTY is provided.
-- See "LICENSE_GPLv2.txt" for details.
--
-- @TAG(DATA61_GPL)
--


{-# LANGUAGE LambdaCase, PatternGuards #-}
{-# OPTIONS_GHC -Wwarn #-}

module Cogent.Reorganizer where

import qualified Cogent.Common.Syntax as Syn
import Cogent.Compiler (__impossible)
import Cogent.Surface
import Cogent.Util
import Cogent.Common.Types

import Control.Arrow
import Control.Monad (forM, forM_)
import Control.Monad.Trans.State
import Data.Char (isUpper)
-- import Data.Foldable hiding (notElem)
import Data.Functor.Compose
import qualified Data.Graph.Wrapper as G
import Data.List as L
import qualified Data.Map as M
import qualified Data.Maybe as Maybe
import Text.Parsec.Pos

import Debug.Trace

data ReorganizeError = CyclicDependency
                     | DuplicateTypeDefinition
                     | DuplicateValueDefinition
                     | DuplicateRepDefinition

data SourceObject = TypeName  Syn.TypeName
                  | ValName   Syn.VarName
                  | RepName   Syn.RepName
                  | DocBlock' String
                  deriving (Eq, Ord)

instance Show SourceObject where
  show (TypeName  n) = n
  show (ValName   n) = n
  show (RepName   n) = n
  show (DocBlock' s) = s

dependencies :: TopLevel LocType LocPatn LocExpr -> [SourceObject]
dependencies (Include _) = __impossible "dependencies"
dependencies (IncludeStd _) = __impossible "dependencies"
dependencies (TypeDec _ _ t) = map TypeName (fcT (stripLocT t))
                            ++ map ValName  (fvT (stripLocT t))
                            ++ map RepName  (dvT (stripLocT t))
dependencies (AbsTypeDec _ _ ts) = map TypeName (foldMap (fcT . stripLocT) ts)
                                ++ map ValName  (foldMap (fvT . stripLocT) ts)
                                ++ map RepName  (foldMap (dvT . stripLocT) ts)
dependencies (DocBlock _) = []
dependencies (RepDef (DataLayoutDecl _ _ e)) = map RepName (allRepRefs e)
dependencies (AbsDec _ pt) = map TypeName (foldMap (fcT . stripLocT) pt)
                          ++ map ValName  (foldMap (fvT . stripLocT) pt)
                          ++ map RepName  (foldMap (dvT . stripLocT) pt)
dependencies (FunDef _ pt as) = map TypeName (foldMap (fcT . stripLocT) pt
                                           ++ foldMap (fcA . fmap stripLocE) as)
                             ++ map ValName  (foldMap (fvT . stripLocT) pt
                                           ++ foldMap (fvA . ffmap stripLocP . fmap stripLocE) as)
                             ++ map RepName  (foldMap (dvT . stripLocT) pt
                                           ++ foldMap (dvA . fmap stripLocE) as)
dependencies (ConstDef _ t e) = map TypeName (fcT (stripLocT t) ++ fcE (stripLocE e))
                             ++ map ValName  (fvT (stripLocT t) ++ fvE (stripLocE e))
                             ++ map RepName  (dvT (stripLocT t) ++ dvE (stripLocE e))

classify :: [(SourcePos, DocString, TopLevel LocType LocPatn LocExpr)]
         -> [(SourceObject, (SourcePos, DocString, TopLevel LocType LocPatn LocExpr))]
classify = map (\px -> (sourceObject (thd3 px), px))

sourceObject :: TopLevel LocType LocPatn LocExpr -> SourceObject
sourceObject (Include _)        = __impossible "sourceObject (in classify)"
sourceObject (IncludeStd _)     = __impossible "sourceObject (in classify)"
sourceObject (DocBlock s)       = DocBlock' s
sourceObject (TypeDec n _ _)    = TypeName n
sourceObject (AbsTypeDec n _ _) = TypeName n
sourceObject (AbsDec n _)       = ValName n
sourceObject (FunDef v _ _)     = ValName v
sourceObject (ConstDef v _ _)   = ValName v
sourceObject (RepDef (DataLayoutDecl _ n _))    = RepName n

prune :: [SourceObject]  -- a list of entry-points
      -> [(SourceObject, v, [SourceObject])]
      -> [SourceObject]  -- a list of 'k's that will be included
prune es m = flip execState builtins $ forM_ es
                                     $ flip go
                                     $ map (\(k,_,ks) -> (k,ks)) m
  where
    builtins = [ TypeName "U8"
               , TypeName "U16"
               , TypeName "U32"
               , TypeName "U64"
               , TypeName "Bool"
               , TypeName "String"
               ]
    go :: SourceObject -> [(SourceObject, [SourceObject])] -> State [SourceObject] ()
    go k m = do s <- get
                case k `elem` s of
                  True  -> return ()  -- visited
                  False -> case L.lookup k m of
                    Nothing -> error $ show k ++ " is not defined"
                    Just ds -> do put $ k:s
                                  forM_ ds $ flip go m

graphOf :: Ord a => (b -> [a]) -> [(a, b)] -> G.Graph a b
graphOf f = G.fromListLenient . map (\(k,v) -> (k, v, f v))


dependencyGraph_ :: [(SourceObject, (SourcePos, DocString, TopLevel LocType LocPatn LocExpr))]
                 -> G.Graph SourceObject (SourcePos, DocString, TopLevel LocType LocPatn LocExpr)
dependencyGraph_ = graphOf (dependencies . thd3)

-- With prune
dependencyGraph :: [SourceObject]
                -> [(SourceObject, (SourcePos, DocString, TopLevel LocType LocPatn LocExpr))]
                -> G.Graph SourceObject (SourcePos, DocString, TopLevel LocType LocPatn LocExpr)
dependencyGraph es m =
  let edges = map (\(k,v) -> (k, v, dependencies $ thd3 v)) m
      included = prune es edges
      trimmed = filter (\(k,_,_) -> k `elem` included) edges
   in G.fromListLenient trimmed

checkNoNameClashes :: [(SourceObject, SourcePos)]
                   -> M.Map SourceObject SourcePos
                   -> Either (ReorganizeError, [(SourceObject, SourcePos)]) ()
checkNoNameClashes [] bindings = return ()
checkNoNameClashes ((s,d):xs) bindings
  | Just x <- M.lookup s bindings = Left (msg, [(s, x), (s, d)])
  | otherwise = let bindings' = case s of DocBlock' _ -> bindings; _ -> M.insert s d bindings
                 in checkNoNameClashes xs bindings'
  where msg = case s of TypeName  _ -> DuplicateTypeDefinition
                        ValName   _ -> DuplicateValueDefinition
                        RepName   _ -> DuplicateRepDefinition
                        DocBlock' _ -> __impossible "checkNoNameClashes"

embedRecPars :: [TopLevel LocType LocPatn LocExpr] -> [TopLevel LocType LocPatn LocExpr]
embedRecPars = map check
  where
    -- We need to check: Type definitions, function polytypes
    check :: TopLevel LocType LocPatn LocExpr -> TopLevel LocType LocPatn LocExpr
    check (TypeDec n tvs t) =
      TypeDec n tvs (embedRecPar tvs t)
    check (FunDef  n (PT tvs t) y) =
      FunDef n (PT tvs (embedRecPar (map fst tvs) t)) y
    -- TODO: Consts?
    check t = t

embedRecPar :: [Syn.TyVarName] -> LocType -> LocType
embedRecPar tvs t = erp M.empty t
  where
    erp :: RecContext LocType -> LocType -> LocType 
    erp ctxt orig@(LocType p ty) =
      LocType p $ case ty of
    -- If we find a type variable that is in our context, we replace it with a recursive parameter
      (TVar n _ _) | M.member n ctxt -> TRPar n ctxt
      -- If we find a record, add it's recursive parameter to the context if it exists and recurse
      (TRecord rp fs s) -> 
        let ctxt' = case rp of 
                      Rec v -> M.insert v orig ctxt
                      _     -> ctxt
        in TRecord rp (map (\(n,(x, y)) -> (n, (erp ctxt' x, y))) fs) s

      (TFun t1 t2)  -> TFun (erp ctxt t1) (erp ctxt t2) 
      (TVariant ts) -> TVariant $ M.map (\(ts', x) -> (map (erp ctxt) ts', x)) ts
      (TTuple ts)   -> TTuple (map (erp ctxt) ts)
#ifdef BUILTIN_ARRAYS
      (TArray t e)  -> TArray (erp ctxt t) e
#endif
      (TUnbox t)    -> TUnbox (erp ctxt t)
      (TBang t)     -> TBang (erp ctxt t)
      (TTake fs t)  -> TTake fs (erp ctxt t)
      (TPut fs t)   -> TPut fs (erp ctxt t)
      t             -> t

-- Note: it doesn't make much sense to check for unused definitions as they may be used
-- by the FFI. / zilinc
reorganize :: Maybe [String]
           -> [(SourcePos, DocString, TopLevel LocType LocPatn LocExpr)]
           -> Either (ReorganizeError, [(SourceObject, SourcePos)]) [(SourcePos, DocString, TopLevel LocType LocPatn LocExpr)]
reorganize mes bs = do let m = classify bs
                           cs = G.stronglyConnectedComponents $ case mes of
                                   Nothing -> dependencyGraph_ m
                                   Just es -> dependencyGraph (map parseSourceObject es) m
                       checkNoNameClashes (map (second fst3) m) M.empty
                       -- FIXME: it might be good to preserve the original order as much as possible
                       -- see file `tests/pass_wf-take-put-tc-2.cogent` as a bad-ish example / zilinc

                       -- TODO: Strictly positive check and recPar embedding

                       forM cs $ \case
                         G.AcyclicSCC i -> Right $ case lookup i m of
                                                     Nothing -> __impossible $ "reorganize: " ++ show i
                                                     Just x  -> x
                         G.CyclicSCC is -> Left  $ (CyclicDependency, map (id &&& getSourcePos m) is)
  where getSourcePos m i | Just (p,_,_) <- lookup i m = p
                         | otherwise = __impossible "getSourcePos (in reorganize)"
        -- FIXME: proper parsing / zilinc
        parseSourceObject :: String -> SourceObject
        parseSourceObject (c:cs) | isUpper c = TypeName (c:cs)
                                 | otherwise = ValName  (c:cs)

