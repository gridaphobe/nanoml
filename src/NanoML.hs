{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE PackageImports    #-}
{-# LANGUAGE RecordWildCards   #-}
module NanoML
  ( module NanoML.Parser
  , module NanoML.Types
  , module NanoML.Eval
  , module NanoML.Step
  , check, checkAll, checkAllFrom, runProg, checkDecl
  ) where

import           Control.Exception
import           Control.Monad
import           Control.Monad.Except
import           Control.Monad.Random
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Writer
import qualified Data.IntMap              as IntMap
import           Data.List
import qualified Data.Map                 as Map
import           Data.Maybe
import           Data.Typeable (Typeable)
import qualified Data.Vector              as Vector
import           System.IO.Unsafe
import           System.Timeout
-- import           Test.QuickCheck
-- import           Test.QuickCheck.Monadic
-- import           Test.QuickCheck.Property hiding (Result)
import           Text.Printf
import "regex-tdfa" Text.Regex.TDFA ( (=~~) )

import           NanoML.Eval
import           NanoML.Gen
import           NanoML.Misc
import           NanoML.Parser hiding (read)
import           NanoML.Pretty
import           NanoML.Step
import           NanoML.Types

import Debug.Trace


check :: Maybe Err -> Prog -> IO (Maybe Result)
check err prog =
  case last prog of
    -- NOTE: it's crucial that we prioritize the case where ocaml has
    -- told us where the type error is
    _ | Just err <- err
      , Just (_,_,_,[l,c])
        <- err =~~ "line ([0-9]+), characters ([0-9]+)"
           :: Maybe (String,String,String,[String])
      , Just (f,d,p) <- traceShow (l,c) findDecl prog (read l) (read c)
--      , Just t <- Map.lookup f knownFuncs
        -> do r <- checkDecl f p
              -- printResult r
              return $ Just r
    DFun _ _ [(VarPat _ f, Lam {})]
      -- Just t <- Map.lookup f knownFuncs
        -> do r <- checkDecl f prog
              -- printResult r
              return $ Just r
    DFun _ _ [(WildPat _, _)]
        -> do r <- runProg prog
              -- printResult r
              return $ Just r
    DFun _ _ [(VarPat _ _, _)]
        -> do r <- runProg prog
              -- printResult r
              return $ Just r
    DEvl _ _
        -> do r <- runProg prog
              -- printResult r
              return $ Just r
    _ -> do -- printf "I don't (yet) know how to check this program!\n" -- (show $ prettyProg prog)
            return Nothing

printResult Failure {..} = do
  printf "*** Failed after %d tests: %s\n" numTests (show errorMsg)
  print counterExample
printResult Success {..} =
  printf "+++ OK, passed %d tests.\n" numTests

findDecl :: Prog -> Int -> Int -> Maybe (Var,Decl,Prog)
findDecl prog l c = do
  d <- find (surrounds l c . getSrcSpan) prog
  case d of
    DFun _ _ [(VarPat _ f, Lam {})] -> Just (f,d, takeWhile (before l c . getSrcSpan) prog)
    _                               -> Nothing

before l c (SrcSpan sl sc el ec)
  = l >= sl

surrounds l c (SrcSpan sl sc el ec)
  = sl <= l && l < el

safeTail [] = []
safeTail (x:xs) = xs

runProg :: Prog -> IO Result
runProg prog = nanoCheck 0 0 stdOpts $ do
                 prog <- mapM refreshDecl prog
                 stepAllProg prog

checkDecl :: Var -> Prog -> IO Result
checkDecl f prog = go (Success 0 initState) 0
  where
  go r@(Failure {}) _    = return r
  go (Success 1000 st) _ = return (Success 1000 st)
  go (Success n _st) !m  = do
    r <- nanoCheck n m stdOpts $ do
      -- mapM_ evalDecl prog
      prog <- mapM refreshDecl prog
      stepAllProg prog
      to (Var Nothing f) []
    go r ((m+1) `mod` 5)

  to f args = do
    rememberArgs (f:args)
    let x = mkApps Nothing f args
    addSubTerms x
    v <- stepAll x
    case v of
      Lam {} -> do
        arg <- (\r -> Hole Nothing r Nothing) <$> fresh
        -- let x = mkApps Nothing e (args ++ [arg])
        -- addSubTerms x
        to f (args ++ [arg])
      _ -> return ()

sec = 1000000 * 60

-- within n s x = do
--   m <- timeout s x
--   return $ fromMaybe (Failure (n+1) 0 0 (text "<<timeout>>") []) m

nanoCheck :: Int -> Int -> NanoOpts -> Eval () -> IO Result
nanoCheck numSuccess maxSize opts x = do
  seed <- getRandom
  let opts' = opts { seed = seed, size = maxSize }
  x <- evaluate $ runEvalFull opts' x
  return $ case x of
    (Left (MLException e), st, _) -> Success (numSuccess + 1) st
    (Left e, st, tr) ->
                  -- NOTE: don't forget to fill in holes with generated values
      let -- paths = map (map (fillHoles st)) $ unsafePerformIO $ makePaths st
          invoc = case map (fetchArg' (stStore st)) (stArgs st) of
            [] -> mempty
            f:args -> pretty (fillHoles st $ mkApps Nothing f args)
      in Failure (numSuccess + 1) seed maxSize
                 invoc
                 (pretty e)
                 st
--                 (vcat (text (show e) : invoc : []))
    (Right _, st, _) -> Success (numSuccess + 1) st

-- fetchArg' st (Val v) = Val (fetchArg st v)
fetchArg' st e = e

fetchArg st (Hole _ r _)
  | Just (_,v) <- IntMap.lookup r st
  = fetchArg st v
fetchArg st (VL ms vs)
  = VL ms (map (fetchArg st) vs)
fetchArg st (VT ms vs)
  = VT ms (map (fetchArg st) vs)
fetchArg st (VA ms c (Just v) t)
  = VA ms c (Just (fetchArg st v)) t
--  TODO: fetchArg st (VR )
fetchArg st (VV ms vs)
  = VV ms (map (fetchArg st) vs)
fetchArg st v
  = v

checkAll = checkAllFrom "../yunounderstand/data/sp14/prog/unify"

checkAllFrom dir = parseAllIn dir >>= mapM (\(f,e,p) -> putStrLn ("\n" ++ f) >> check e p >>= \r -> maybe (return Nothing) (\r -> printResult r >> return (Just (f,r))) r)

checkType :: MonadEval m => Value -> Type -> m Bool
checkType v t = unify t (typeOf v) >> return True
