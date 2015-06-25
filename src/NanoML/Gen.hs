{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards  #-}
module NanoML.Gen where

import           Data.Map        (Map)
import qualified Data.Map        as Map
import           Data.Maybe
import           Test.QuickCheck

import           NanoML.Types

type TypeEnv = Map TCon TypeDecl

genArgs :: Type -> TypeEnv -> Gen [Expr]
genArgs ty e = mapM (`genExpr` e) (argTys ty)

genExpr :: Type -> TypeEnv -> Gen Expr
genExpr ty e = case ty of
  -- NOTE: instantiate all tyvars indescriminately with `int`
  TVar _ -> Lit . LI <$> arbitrary
  TCon t
    | t == tINT
      -> Lit . LI <$> arbitrary
    | t == tFLOAT
      -> Lit . LD <$> arbitrary
    | t == tCHAR
      -> Lit . LC <$> arbitrary
    | t == tSTRING
      -> Lit . LS <$> arbitrary
    | t == tBOOL
      -> Lit . LB <$> arbitrary
    | t == tUNIT
      -> return (Var "()")
    | otherwise
      -> sized (genADT t [] e)
--  TApp "list" [t] -> sized (genList t e)
  TApp c ts -> sized (genADT c ts e)
  TTup ts -> Tuple <$> mapM (`genExpr` e) ts
  _ :-> to -> Lam WildPat <$> (`genExpr` e) to

genADT :: TCon -> [Type] -> TypeEnv -> Int -> Gen Expr
genADT c ts e n = do
  let Just TypeDecl {..} = Map.lookup c e
  case tyRhs of
    Alias ty -> genExpr ty e
    Alg dds  -> oneof (mapMaybe (genDataDecl tyVars) dds)
  where
  genDataDecl tvs DataDecl {..}
    | n <= 0 && not (null dArgs) && any isRec dArgs
    = Nothing
    | otherwise
    = Just $ ConApp dCon <$> mapM (resize (n-1) . (`genExpr` e) . subst (zip tvs ts))
                                  dArgs
  isRec (TCon t)   = t == c
  isRec (TApp t _) = t == c
  isRec _          = False

-- genList :: Type -> TypeEnv -> Int -> Gen Expr
-- genList _ e 0 = return (mkConApp "[]" [])
-- genList t e n = do x  <- genExpr t e
--                    xs <- genList t e (n-1)
--                    return (mkConApp "::" [x,xs])
