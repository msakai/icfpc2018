{-# OPTIONS_GHC -Wall #-}
module Sim
  ( execAll
  , execOneStep
  , execOneStepCommands
  ) where

import Control.Monad
import Control.Monad.State
import qualified Data.IntMap as IntMap
import qualified Data.IntSet as IntSet
import Data.List
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
-- import Data.Tuple.Extra (fst3,snd3,thd3)

import Coordinate
import Matrix as MX
import State


execAll :: SystemState -> SystemState
execAll = execState execAll'

execAll' :: State SystemState ()
execAll' = do
  s <- get
  if noActiveNanobots s || noCommands s then
    return ()
  else do
    execOneStep'
    execAll'


execOneStep :: SystemState -> SystemState
execOneStep = execState execOneStep'

execOneStep' :: State SystemState ()
execOneStep' = do
  s <- get
  unless (stateIsWellformed s) $ error "state is not wellformed"
  let n = IntMap.size (stBots s)
  case splitAt n (stTrace s) of
    (xs, traces') -> do
      unless (length xs == n) $ error "trace is short"
      execOneStepCommands' $ zip (map fst (IntMap.toAscList (stBots s))) xs
      modify (\s -> s{ stTrace = traces' })


addCost :: Int -> State SystemState ()
addCost cost = modify (\s -> s{ stEnergy = stEnergy s + fromIntegral cost })


execOneStepCommands :: [(BotId, Command)] -> SystemState -> SystemState
execOneStepCommands xs = execState (execOneStepCommands' xs)

execOneStepCommands' :: [(BotId, Command)] -> State SystemState ()
execOneStepCommands' xs = do
  s <- get
  let n = IntMap.size (stBots s)

  let fusionPs = Map.fromList [(c, (bid, c `add` nd)) | (bid,FusionP nd) <- xs, let c = botPos (stBots s IntMap.! bid)]
      fusionSs = Map.fromList [(c, (bid, c `add` nd)) | (bid,FusionS nd) <- xs, let c = botPos (stBots s IntMap.! bid)]
  unless (Map.size fusionPs == Map.size fusionSs) $ error "failed to create a pair for fusion"
  let fusionPairs = do
        (c1,(bid1,c2)) <- Map.toList fusionPs
        case Map.lookup c2 fusionSs of
          Just (bid2,c1') | c1==c1' -> return (bid1,bid2)
          _ -> error "failed to create a pair for fusion"
  let update (r,bid) = Map.insertWith Set.union r (Set.singleton bid)
  let groupFills =
        foldr update Map.empty [ (region c1 c2,bid)
                               | (bid,GFill nd fd) <- xs
                               , let (c,c1,c2) = (botPos (stBots s IntMap.! bid), c `add` nd, c1 `add` fd)]
  let groupVoids =
        foldr update Map.empty [ (region c1 c2,bid)
                               | (bid,GVoid nd fd) <- xs
                               , let (c,c1,c2) = (botPos (stBots s IntMap.! bid), c `add` nd, c1 `add` fd)]
  let mat = stMatrix s
  forM_ xs $ \(bid,cmd) -> do
    case cmd of
      FusionP _ -> return ()
      FusionS _ -> return ()
      GFill _ _ -> return ()
      GVoid _ _ -> return ()
      _ -> execSingleNanobotCommand mat bid cmd
  forM_ fusionPairs $ uncurry execFusion
  forM_ (Map.keys groupFills) (execGroupFill <*> (groupFills Map.!))
  forM_ (Map.keys groupVoids) (execGroupVoid <*> (groupVoids Map.!))

  -- コスト計算は実行前の状態に基づく
  case stHarmonics s of
    High -> addCost $ 30 * stResolution s ^ (3 :: Int)
    Low  -> addCost $  3 * stResolution s ^ (3 :: Int)
  addCost $ 20 * n

  -- stGroundedTable の情報の更新
  let fillCoords =
        [add (botPos (stBots s IntMap.! bid)) nd | (bid, Fill nd) <- xs] ++
        concat [membersOfRegion r | r <- Map.keys groupFills]
      voidCoords =
        [add (botPos (stBots s IntMap.! bid)) nd | (bid, Void nd) <- xs] ++
        concat [membersOfRegion r | r <- Map.keys groupVoids]
  modify $ \s ->
    s{ stGroundedTable =
         voidGroundedTable voidCoords $
         foldl' (flip fillGroundedTable) (stGroundedTable s) fillCoords
     }

  modify $ \s -> s{ stTime = stTime s + 1, stCommands = stCommands s + n }

  return ()


-- 事前条件のチェックは他のボットのコマンドの実行前のmatrixに対して行う必要があるので、
-- そのMatrixを受け取っている。
execSingleNanobotCommand :: Matrix -> BotId -> Command -> State SystemState ()
execSingleNanobotCommand _mat _bid (FusionP _) = error "execSingleNanobotCommand: FusionP should not be passed"
execSingleNanobotCommand _mat _bid (FusionS _) = error "execSingleNanobotCommand: FusionS should not be passed"
execSingleNanobotCommand _mat _bid (GFill _ _) = error "execSingleNanobotCommand: GFill should not be passed"
execSingleNanobotCommand _mat _bid (GVoid _ _) = error "execSingleNanobotCommand: GVoid should not be passed"
execSingleNanobotCommand _mat _bid Halt = do
  s <- get
  case IntMap.elems (stBots s) of
    [bot] -> do
      unless (botPos bot == Coord (0,0,0)) $ error "Halt pre-condition is violated"
      put $ s{ stBots = IntMap.empty }
    _ -> error "Halt pre-condition is violated"
execSingleNanobotCommand _mat _bid Wait = return ()
execSingleNanobotCommand _mat _bid Flip = do
  s <- get
  put $ s{ stHarmonics = flipHarmonics (stHarmonics s) }
execSingleNanobotCommand mat bid (SMove lld) = do
  s <- get
  case IntMap.lookup bid (stBots s) of
    Just bot -> do
      let c  = botPos bot
          c' = add c lld
      unless (checkEmptyRegion mat (region c c')) $ error "SMove pre-condition is violated"
      put $
        s{ stBots   = IntMap.insert bid bot{ botPos = c' } (stBots s)
         , stEnergy = stEnergy s + fromIntegral (2 * mlen lld)
         }
execSingleNanobotCommand mat bid (LMove sld1 sld2) = do
  s <- get
  case IntMap.lookup bid (stBots s) of
    Just bot -> do
      let c   = botPos bot
          c'  = add c sld1
          c'' = add c' sld2
      unless (checkEmptyRegion mat (region c  c' )) $ error "LMove pre-condition is violated"
      unless (checkEmptyRegion mat (region c' c'')) $ error "LMove pre-condition is violated"
      put $
        s{ stBots   = IntMap.insert bid bot{ botPos = c'' } (stBots s)
         , stEnergy = stEnergy s + fromIntegral (2 * mlen sld1 + 2 + mlen sld2)
         }
execSingleNanobotCommand mat bid (Fission nd m) = do
  s <- get
  case IntMap.lookup bid (stBots s) of
    Just bot -> do
      when (IntSet.null (botSeeds bot)) $ error "Fission pre-condition is violated"
      let c = botPos bot
          c' = add c nd
      unless (isEmpty mat c') $ error "Fission pre-condition is violated"
      case splitAt (m+1) (IntSet.toAscList (botSeeds bot)) of
        (bid':seeds1, seeds2) -> do
          put $
            s{ stBots =
                 IntMap.insert bid  bot{ botSeeds = IntSet.fromAscList seeds2 } $
                 IntMap.insert bid' Bot{ botId = bid', botPos = c', botSeeds = IntSet.fromAscList seeds1 } $
                 stBots s
             , stEnergy = stEnergy s + 24
             }
execSingleNanobotCommand _mat bid (Fill nd) = do
  s <- get
  case IntMap.lookup bid (stBots s) of
    Just bot -> do
      let c = botPos bot
          c' = add c nd
          mat = stMatrix s
      case voxel mat c' of
        Empty -> do
          put $ s{ stMatrix = MX.fill c' mat, stEnergy = stEnergy s + 12 }
        Full -> do
          put $ s{ stEnergy = stEnergy s + 6 }

execSingleNanobotCommand _mat bid (Void nd) = do
  s <- get
  case IntMap.lookup bid (stBots s) of
    Just bot -> do
      let c = botPos bot
          c' = add c nd
          mat = stMatrix s
      case voxel mat c' of
        Full -> do
          put $ s{ stMatrix = MX.void c' mat, stEnergy = stEnergy s - 12 }
        Empty -> do
          put $ s{ stEnergy = stEnergy s + 3 }


execFusion :: BotId -> BotId -> State SystemState ()
execFusion bidP bidS = do
  s <- get
  case IntMap.lookup bidP (stBots s) of
    Just botP ->
      case IntMap.lookup bidS (stBots s) of
        Just botS -> do
          put $
            s{ stBots =
                 IntMap.insert bidP botP{ botSeeds = IntSet.insert bidS $ botSeeds botS `IntSet.union` botSeeds botP } $
                 IntMap.delete bidS $
                 stBots s
             , stEnergy = stEnergy s - 24
             }

execGroupFill :: Region -> Set BotId -> State SystemState ()
execGroupFill r bs = do
  forM_ (membersOfRegion r) $ \c -> do
    s <- get
    let mat = stMatrix s
    case voxel mat c of
      Empty -> do
        put $ s{ stMatrix = MX.fill c mat, stEnergy = stEnergy s + 12 }
      Full -> do
        put $ s{ stEnergy = stEnergy s + 6 }

execGroupVoid :: Region -> Set BotId -> State SystemState ()
execGroupVoid r bs = do
  forM_ (membersOfRegion r) $ \c -> do
    s <- get
    let mat = stMatrix s
    case voxel mat c of
      Full -> do
        put $ s{ stMatrix = MX.void c mat, stEnergy = stEnergy s - 12 }
      Empty -> do
        put $ s{ stEnergy = stEnergy s + 3 }

checkEmptyRegion :: Matrix -> Region -> Bool
checkEmptyRegion mat r = all (isEmpty mat) (membersOfRegion r)
