import Control.Applicative ((*>))
import Control.Monad (forever, unless, void)
import Control.Concurrent (forkIO, getNumCapabilities)
import Control.Concurrent.Chan (newChan, readChan, writeChan)
import System.Environment (getArgs)
import System.IO (stdout, BufferMode (LineBuffering), hSetBuffering)
import System.FilePath ((</>))
import System.Directory (doesDirectoryExist)

import qualified Path
import ProblemSet (ProblemFile, runProblemFile)
import qualified ProblemSet as ProbSet
import TraceEncoder (writeTraceFile)
import Model (readModel)
import qualified Model
import NaiveBot (getAssembleTrace, getDisassembleTrace, getReassembleTrace)
import TraceOptimizer (optimize)


newLog :: IO (String -> IO ())
newLog = do
  hSetBuffering stdout LineBuffering
  c <- newChan
  void . forkIO . forever $ putStrLn =<< readChan c
  return $ writeChan c

concurrent :: Int     -- ^ num of threads
           -> [IO a]  -- ^ tasks
           -> IO ()
concurrent n as = do
  tq <- newChan
  wq <- newChan
  let thread = do
        mayT <- readChan tq
        case mayT of
          Nothing  ->  writeChan wq ()  -- end of thread
          Just t   ->  t *> thread      -- next task
  sequence_ . replicate n $ forkIO thread
  mapM_ (writeChan tq) $ map Just as ++ replicate n Nothing  -- enqueue tasks and end-marks
  sequence_ . replicate n $ readChan wq                      -- waiting finish

data Mode
  = NoOpt
  | Opt
  --- | TOpt
  deriving (Eq, Show)

descMode :: Mode -> String
descMode NoOpt = "no-optimize"
descMode Opt   = "optimize"
--- descMode TOpt  = "optimize (may timeoute)"

timeoutAD :: Int
timeoutAD = 7 * 60 * 1000 * 1000

timeoutR :: Int
timeoutR = 12 * 60 * 1000 * 1000

assemble :: Mode -> FilePath -> Int -> FilePath -> IO ()
assemble mode nbt _n tgt_ = do
  tgt <- readModel $ Path.problems </> tgt_
  let trs0 = getAssembleTrace tgt
      optimized = optimize (Model.emptyR tgt) tgt trs0
      trs NoOpt  =  return trs0
      trs Opt    =  return optimized
  writeTraceFile nbt =<< trs mode

disassemble :: Mode -> FilePath -> Int -> FilePath -> IO ()
disassemble mode nbt _n src_ = do
  src <- readModel $ Path.problems </> src_
  let trs0 = getDisassembleTrace src
      optimized = optimize src (Model.emptyR src) trs0
      trs NoOpt  =  return trs0
      trs Opt    =  return optimized
  writeTraceFile nbt =<< trs mode

reassemble :: Mode -> FilePath -> Int -> FilePath -> FilePath -> IO ()
reassemble mode nbt _n src_ tgt_ = do
  src <- readModel $ Path.problems </> src_
  tgt <- readModel $ Path.problems </> tgt_
  let trs0 = getReassembleTrace src tgt
      optimized = optimize src tgt trs0
      trs NoOpt  =  return trs0
      trs Opt    =  return optimized
  writeTraceFile nbt =<< trs mode

run :: (String -> IO ())
    -> FilePath
    -> Mode
    -> ProblemFile
    -> IO ()
run putLog dst mode pf = do
  let nbtPath = dst </> ProbSet.traceFile pf
      label = nbtPath
  putLog $ "running: " ++ label
  runProblemFile
    (assemble    mode nbtPath)
    (disassemble mode nbtPath)
    (reassemble  mode nbtPath)
    pf
  putLog $ "done   : " ++ label

runAll :: FilePath -> Mode -> IO ()
runAll dst mode = do
  putStrLn $ "dest-dir: " ++ dst
  putStrLn $ "mode: " ++ descMode mode
  do e <- doesDirectoryExist dst
     unless e . fail $ dst ++ " does not exist!"
  putStrLn "processing FA*, FD*, FR* files ..."
  putLog <- newLog
  n <- getNumCapabilities
  let orderedP Opt    =  reverse ProbSet.problemsL  -- opt は高コストなので小さい順
      orderedP NoOpt  =  ProbSet.problemsL
  concurrent (n - 1) $ map (run putLog dst mode) $ orderedP mode

main :: IO ()
main = do
  args <- getArgs
  (dst, doOpt) <- case args of
    d:"opt":_  ->  return (d, Opt)
    d:_        ->  return (d, NoOpt)
    _   -> fail "DEST_DIRECTORY is required."
  runAll dst doOpt
