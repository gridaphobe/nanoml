{-# language FlexibleContexts #-}
{-# language DeriveGeneric #-}
{-# language MultiWayIf #-}
{-# language OverloadedStrings #-}
module Main where

-- import Control.Concurrent.Async.Pool
import Control.DeepSeq
import Control.Exception
import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.State
import Data.Char
import Data.List
import Data.Maybe
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics
import Options.Generic hiding (All(..))
import System.FilePath
import System.FilePath.Glob
import System.IO
import System.IO.Temp
import System.Process
import qualified System.Timeout as Timeout
import Text.Printf
import Text.Regex.TDFA

import NanoML.Types

main :: IO ()
main = do
  run =<< getRecord "Evaluate type-error localizations"

data Mode
  = Gather Tool FilePath
  | Evaluate String FilePath (Maybe Prune) (Maybe All)
  deriving (Generic, Show)
instance ParseRecord Mode

data Tool
  = Ocaml
  | Mycroft
  | Sherrloc
  | SherrlocTop
  | Nanomaly
  deriving (Generic, Show, Read, Eq)
instance ParseField Tool
instance ParseFields Tool
instance ParseRecord Tool

data Prune
  = DoPrune
  | NoPrune
  deriving (Generic, Show, Read, Eq)
instance ParseField Prune
instance ParseFields Prune
instance ParseRecord Prune

data All
  = DoAll
  | NoAll
  deriving (Generic, Show, Read, Eq)
instance ParseField All
instance ParseFields All
instance ParseRecord All

run :: Mode -> IO ()
run (Gather tool dir) = do
  mls <- glob (dir </> "*.ml")
  forM_ mls $ \ml -> do
    putStrLn $ "Processing " ++ ml ++ "..."
    spans <- fromMaybe mempty . join . e2m <$> try (timeout 60 (runTool tool ml))
    let n = takeFileName ml
    writeFile (dir </> toolName tool </> n <.> "out")
              (unlines . map show $ spans)
run (Evaluate "baseline" dir prune _) = do
  doBaseline dir (fromMaybe NoPrune prune)
run (Evaluate tool dir prune all) = do
  doEval tool dir (fromMaybe NoPrune prune) (fromMaybe NoAll all)


e2m :: Either SomeException b -> Maybe b
e2m e = case e of
  Left _ -> Nothing
  Right x -> Just x

runTool :: Tool -> FilePath -> IO [SrcSpan]
runTool t = case t of
  Ocaml -> runOcaml
  Mycroft -> runMycroft
  Sherrloc -> runSherrloc Sherrloc
  SherrlocTop -> runSherrloc SherrlocTop
  Nanomaly -> runNanomaly

toolName :: Tool -> String
toolName t = map toLower (show t)

data Spans = Spans
  { sourceFile :: FilePath
  , allSpans :: !(Set SrcSpan)
  , diffSpans :: !(Set SrcSpan)
  , errSpans :: !(Set SrcSpan)
  } deriving (Generic, Show)
instance NFData Spans

loadSpans :: FilePath -> IO Spans
loadSpans ml = do
  ls <- lines.force <$> readFile ml
  let all  = Set.fromList $! extractSrcSpans $ slice "(* all spans"        "*)" ls
  let diff = Set.fromList $! extractSrcSpans $ slice "(* changed spans"    "*)" ls
  let err  = Set.fromList $! extractSrcSpans $ slice "(* type error slice" "*)" ls
  return $! Spans ml all diff err

loadToolSpans :: FilePath -> IO [SrcSpan]
loadToolSpans f = do
  ls <- lines.force <$> readFile f
  return $! map read $ {-take 3 $-} nub ls

data ProcessState = ProcessState
  { good1Progs :: !Int
  , good2Progs :: !Int
  , good3Progs :: !Int
  , allProgs  :: !Int
  , recalls   :: [Double]
  } deriving (Show)

doEval
  :: String -> FilePath -> Prune -> All -> IO ()
doEval t dir prune all = do
  let year = takeFileName dir
  let features = takeDirectory t
  let model = takeFileName t
  mls <- glob (dir </> "*.ml")
  mls <- case prune of
    NoPrune -> return mls
    DoPrune -> flip filterM mls $ \ml -> do
      let (dir, f) = splitFileName ml
      oracle <- loadSpans ml
      let sh = if all == DoAll then "sherrloctop" else "sherrloc"
      ocs <- loadToolSpans (dir </> "ocaml"    </> f <.> "out")
      mys <- loadToolSpans (dir </> "mycroft"  </> f <.> "out")
      shs <- loadToolSpans (dir </> sh         </> f <.> "out")
      nms <- loadToolSpans (dir </> "nanomaly" </> f <.> "out")
      return $! not (null ocs || null mys || null shs || null nms)
             && Set.fromList ocs `Set.isSubsetOf` allSpans oracle
             && Set.fromList mys `Set.isSubsetOf` allSpans oracle
             && Set.fromList shs `Set.isSubsetOf` allSpans oracle
             && Set.fromList nms `Set.isSubsetOf` allSpans oracle

  let init = ProcessState { good1Progs = 0, good2Progs = 0, good3Progs = 0
                          , allProgs = 0, recalls = []
                          }
  final <- execStateT (mapM_ (processOne all t) mls) init
  -- print final
  let top1 = fromIntegral (good1Progs final) / fromIntegral (allProgs final) :: Double
      top2 = fromIntegral (good2Progs final) / fromIntegral (allProgs final) :: Double
      top3 = fromIntegral (good3Progs final) / fromIntegral (allProgs final) :: Double
      recall = avg (recalls final)
      total = allProgs final
  printf "top 1/2/3 (total): %.3f / %.3f / %.3f (%d)\n"
    top1 top2 top3 total
  printf "recall: %.3f\n" recall
  let csv = case prune of
        NoPrune -> dir </> t </> "results.csv"
        DoPrune -> dir </> t </> "results.pruned.csv"
  writeFile csv $ unlines
    [ "tool,year,features,model,top-1,top-2,top-3,recall,total"
    , printf "%s,%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%d"
             t year features model top1 top2 top3 recall total
    ]

processOne :: (MonadState ProcessState m, MonadIO m)
           => All -> String -> FilePath -> m ()
processOne all t f = do
  let (dir, ml) = splitFileName f
  oracle <- liftIO $ loadSpans f
  let out = dir </> t </> ml <.> "out"
  sps <- liftIO $ loadToolSpans out
  -- ocs <- liftIO $ loadToolSpans (dir </> "ocaml" </> ml <.> "out")
  -- mys <- liftIO $ loadToolSpans (dir </> "mycroft" </> ml <.> "out")
  -- shs <- liftIO $ loadToolSpans (dir </> "sherrloc" </> ml <.> "out")
  if
    | null sps -> do
        liftIO . putStrLn . unlines $
          [ "WARN: no blamed spans in"
          , "  " ++ out
          ]
    | not (Set.fromList sps `Set.isSubsetOf` allSpans oracle) -> do
        liftIO . putStrLn . unlines $
          [ "WARN: blamed spans not subset of all spans in"
          , "  " ++ out
          ]
    | otherwise -> do
        let r = fromIntegral (Set.size (Set.intersection
                                        (Set.fromList sps)
                                         (Set.intersection (errSpans oracle) (diffSpans oracle))))
                / fromIntegral (Set.size (Set.intersection (errSpans oracle) (diffSpans oracle)))
        modify' $ \s -> s { recalls = r : recalls s}
        when (any (`Set.member` diffSpans oracle) $ take 1 sps) $ do
          bumpGood1 (+1)
          --unless (or [any (`Set.member` diffSpans oracle) $ take 3 ocs
          --           ,any (`Set.member` diffSpans oracle) $ take 3 mys
          --           ,any (`Set.member` diffSpans oracle) $ take 3 shs]) $ do
          --  liftIO $ printf "WIN: %s\n" f
        when (any (`Set.member` diffSpans oracle) $ take 2 sps) $ do
          bumpGood2 (+1)
        let tk = if all == DoAll then id else take 3
        when (any (`Set.member` diffSpans oracle) $ tk sps) $ do
          bumpGood3 (+1)
        -- unless (any (`Set.member` diffSpans oracle) $ take 3 sps) $ do
        --   liftIO $ printf "FAIL: %s\n" f
        bumpAll (+1)

bumpAll, bumpGood1, bumpGood2, bumpGood3
  :: MonadState ProcessState m
  => (Int -> Int) -> m ()
bumpAll f = modify' $ \s -> s {allProgs = f (allProgs s)}
bumpGood1 f = modify' $ \s -> s {good1Progs = f (good1Progs s)}
bumpGood2 f = modify' $ \s -> s {good2Progs = f (good2Progs s)}
bumpGood3 f = modify' $ \s -> s {good3Progs = f (good3Progs s)}

data BaselineState = BaselineState
  { top1s :: ![Double]
  , top2s  :: ![Double]
  , top3s  :: ![Double]
  } deriving (Show)

doBaseline
  :: FilePath -> Prune -> IO ()
doBaseline dir prune = do
  let year = takeFileName dir
  mls <- glob (dir </> "*.ml")
  mls <- case prune of
    NoPrune -> return mls
    DoPrune -> flip filterM mls $ \ml -> do
      let (dir, f) = splitFileName ml
      oracle <- loadSpans ml
      -- mys <- loadToolSpans (dir </> "mycroft" </> f <.> "out")
      shs <- loadToolSpans (dir </> "sherrloc" </> f <.> "out")
      -- return $! not (null mys || null shs) &&
      --           Set.fromList mys `Set.isSubsetOf` allSpans oracle &&
      --           Set.fromList shs `Set.isSubsetOf` allSpans oracle
      return $! not (null shs) &&
                Set.fromList shs `Set.isSubsetOf` allSpans oracle
  let init = BaselineState {top1s = [], top2s = [], top3s = []}
  final <- flip execStateT init $ forM_ mls $ \ml -> do
    oracle <- liftIO $ loadSpans ml
    let n_dif = fromIntegral $ Set.size (diffSpans oracle `Set.intersection` errSpans oracle)
    let n_err = fromIntegral $ Set.size (errSpans oracle)
    let topk k = 1 - ((1-(n_dif/n_err))^k)
    let top1 = topk 1
    let top2 = topk 2
    let top3 = topk 3
    -- liftIO $ printf "n_dif / n_err / n_tot: %.0f / %.0f / %d\n" n_dif n_err (Set.size (allSpans oracle))
    -- liftIO $ printf "top 1/2/3: %.3f / %.3f / %.3f\n" top1 top2 top3
    -- liftIO $ printf "----------------------------------\n"
    modify' $ \s -> s { top1s = top1 : top1s s
                      , top2s = top2 : top2s s
                      , top3s = top3 : top3s s
                      }
  let top1 = avg (top1s final)
  let top2 = avg (top2s final)
  let top3 = avg (top3s final)
  printf "top 1/2/3: %.3f / %.3f / %.3f\n" top1 top2 top3
  let csv = case prune of
        NoPrune -> dir </> "baseline.csv"
        DoPrune -> dir </> "baseline.pruned.csv"
  writeFile csv $ unlines
    [ "tool,year,top-1,top-2,top-3,total"
    , printf "baseline,%s,%.3f,%.3f,%.3f,%d" year top1 top2 top3 (length (top1s final))
    ]
  -- printf "good / total = %d / %d = %.3f\n" (goodProgs final) (allProgs final)
  --   (fromIntegral (goodProgs final) / fromIntegral (allProgs final) :: Double)


slice :: Eq a => a -> a -> [a] -> [a]
slice start stop = takeWhile (/=stop) . dropWhile (/=start)

-- computeSpans :: FilePath -> String -> (FilePath -> IO ([SrcSpan])) -> IO ()
-- computeSpans dir toolname runTool = do
--   mls <- glob (dir </> "*.ml")
--   forM_ mls $ \ml -> do
--     spans <- runTool ml
--     let n = takeFileName ml
--     writeFile (dir </> toolname </> n <.> "out") (unlines . map show $ spans)

runOcaml :: FilePath -> IO ([SrcSpan])
runOcaml ml = do
  (_, _, err) <- readCreateProcessWithExitCode (proc "eval/bin/ocamlc" [ml]) ""
  return $! map read . take 1 $ lines err

runMycroft :: FilePath -> IO ([SrcSpan])
runMycroft ml = do
  out <- readCreateProcess (proc "eval/mycroft/build/bin/cgen-unif" [ml]){ std_err = CreatePipe } ""
  out <- readCreateProcess (proc "eval/mycroft/build/bin/unif" ["-e"]) out
  -- return $! extractSrcSpans (dropWhile (/="Generated report:")
  --                             (lines out))
  return $! extractSrcSpans (lines out)

runSherrloc :: Tool -> FilePath -> IO ([SrcSpan])
runSherrloc sh ml = withSystemTempDirectory "sherrloc" $ \tmpDir -> do
  let tmp = tmpDir </> "error.con"
  out <- readCreateProcess (proc "eval/bin/ecamlc" [ml]) ""
  writeFile tmp out
  let args
          | Sherrloc <- sh
          = ["-e", "-n2", tmp]
          | otherwise
          = ["-e", tmp]
  out <- readCreateProcess (proc "eval/bin/sherrloc" args) ""
  return $! extractSrcSpans (lines out)

runNanomaly :: FilePath -> IO ([SrcSpan])
runNanomaly ml = do
  out <- readCreateProcess (proc "stack" ["exec", "--", "nano-check", ml]) ""
  return $! extractSrcSpans (lines out)

extractSrcSpans :: [String] -> [SrcSpan]
extractSrcSpans strs =
  [ read x | str <- strs
           , x <- getAllTextMatches (str =~ srcSpanRE)
           ]

srcSpanRE :: String
srcSpanRE = "\\([0-9]+,[0-9]+\\)-\\([0-9]+,[0-9]+\\)"

-- | Like 'Timeout.timeout', but in seconds.
timeout :: Int -> IO a -> IO (Maybe a)
timeout sec = Timeout.timeout (sec * 10^6)

avg :: Fractional a => [a] -> a
avg xs = sum xs / genericLength xs
