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

module Cogent.TypeCheck.Solver.Normalise where

import Cogent.Common.Types
import Cogent.Compiler
import Cogent.Surface
import Cogent.TypeCheck.Base
import Cogent.TypeCheck.Solver.Goal
import Cogent.TypeCheck.Solver.Monad
import Cogent.TypeCheck.Solver.Rewrite
import qualified Cogent.TypeCheck.Row as Row

import Control.Applicative
import Data.Maybe
import Control.Monad.Reader
import Control.Monad.Trans.Maybe
import Lens.Micro.Mtl
import Lens.Micro

normaliseRW :: RewriteT TcSolvM TCType
normaliseRW = rewrite' $ \t -> case t of
    T (TBang (T (TCon t ts s))) -> pure (T (TCon t (fmap (T . TBang) ts) (bangSigil s)))
    T (TBang (T (TVar v b u))) -> pure (T (TVar v True u))
    T (TBang (T (TFun x y))) -> pure (T (TFun x y))
    T (TBang (R row (Left s))) 
      | isNothing (Row.var row) -> pure (R (fmap (T . TBang) row) (Left (bangSigil s)))
    T (TBang (V row)) 
      | isNothing (Row.var row) -> pure (V (fmap (T . TBang) row))
    T (TBang (T (TTuple ts))) -> pure (T (TTuple (map (T . TBang) ts)))
    T (TBang (T TUnit)) -> pure (T TUnit)
#ifdef BUILTIN_ARRAYS
    T (TBang (T (TArray t e s))) -> pure (T (TArray (T (TBang t)) e (bangSigil s)))
#endif

    T (TUnbox (T (TVar v b u))) -> pure (T (TVar v b True))
    T (TUnbox (T (TCon t ts s))) -> pure (T (TCon t ts Unboxed))
    T (TUnbox (R row _)) -> pure (R row (Left Unboxed))
#ifdef BUILTIN_ARRAYS
    T (TUnbox (T (TArray t l _))) -> pure (T (TArray t l Unboxed))
    T (TUnbox (A t l _)) -> pure (A t l (Left Unboxed))
#endif

    Synonym n as -> do 
        table <- view knownTypes
        case lookup n table of 
            Just (as', Just b) -> pure (substType (zip as' as) b)
            _ -> __impossible "normaliseRW: missing synonym"

    T (TTake fs (R row s)) 
      | isNothing (Row.var row) -> case fs of 
        Nothing -> pure $ R (Row.takeAll row) s
        Just fs -> pure $ R (Row.takeMany fs row) s 
    T (TTake fs (V row)) 
      | isNothing (Row.var row) -> case fs of 
        Nothing -> pure $ V (Row.takeAll row)
        Just fs -> pure $ V (Row.takeMany fs row)
    T (TTake fs t) | __cogent_flax_take_put -> return t
    T (TPut fs (R row s)) 
      | isNothing (Row.var row) -> case fs of 
        Nothing -> pure $ R (Row.putAll row) s
        Just fs -> pure $ R (Row.putMany fs row) s 
    T (TPut fs (V row)) 
      | isNothing (Row.var row) -> case fs of 
        Nothing -> pure $ V (Row.putAll row)
        Just fs -> pure $ V (Row.putMany fs row)
    T (TPut fs t) | __cogent_flax_take_put -> return t
    T (TLayout l (R row (Left (Boxed p _)))) ->
      pure $ R row $ Left $ Boxed p (Just l)
    T (TLayout l (R row (Right i))) ->
      __impossible "normaliseRW: TLayout over a sigil variable (R)" 
#ifdef BUILTIN_ARRAYS
    T (TLayout l (A t n (Left (Boxed p _)))) ->
      pure $ A t n $ Left $ Boxed p (Just (Layout l))
    T (TLayout l (A t n (Right i))) -> 
      __impossible "normaliseRW: TLayout over a sigil variable (A)"
#endif
    T (TLayout l _) -> -- TODO(dargent): maybe handle this later
      empty
    _ -> empty 

  where
    bangSigil (Boxed _ r) = Boxed True r
    bangSigil x           = x

whnf :: TCType -> TcSolvM TCType
whnf input = do 
    step <- case input of 
        T (TTake fs t') -> T . TTake fs <$> whnf t'
        T (TPut  fs t') -> T . TPut  fs <$> whnf t'
        T (TBang    t') -> T . TBang    <$> whnf t'
        T (TUnbox   t') -> T . TUnbox   <$> whnf t'
        T (TLayout l t') -> T . TLayout l <$> whnf t'
        _               -> pure input
    fromMaybe step <$> runMaybeT (run' (untilFixedPoint normaliseRW) step)

-- | Normalise all types within a set of constraints
normaliseTypes :: [Goal] -> TcSolvM [Goal]
normaliseTypes = mapM $ \g -> do
   c' <- traverse whnf (g ^. goal)
   pure $ set goal c' g

