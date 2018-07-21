{-# OPTIONS_GHC -Wno-missing-fields #-}

module OgaBot where

import qualified Control.Monad.State.Lazy as St
import qualified Data.IntMap as IntMap
import qualified Data.Set as Set

import Coordinate
import Model
import State

type OgaBot = (Bot, Trace)
type OgaBotSt a = St.State OgaBot a

sMoveDx :: Int -> OgaBotSt ()
sMoveDx 0 = return ()
sMoveDx n = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (Bot{botPos=Coord(x,y,z)}, trs) =
      (Bot{botPos=Coord(x+n,y,z)}, SMove (n,0,0):trs)

sMoveDy :: Int -> OgaBotSt ()
sMoveDy 0 = return ()
sMoveDy n = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (Bot{botPos=Coord(x,y,z)}, trs) =
      (Bot{botPos=Coord(x,y+n,z)}, SMove (0,n,0):trs)

sMoveDz:: Int -> OgaBotSt ()
sMoveDz 0 = return ()
sMoveDz n = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (Bot{botPos=Coord(x,y,z)}, trs) =
      (Bot{botPos=Coord(x,y,z+n)}, SMove (0,0,n):trs)

-- absolute coord
sMoveAbs :: (Int,Int,Int) -> OgaBotSt ()
sMoveAbs (x,y,z) = do
  (Bot{botPos=Coord(cx,cy,cz)},trs) <- St.get
  if abs (x-cx) <= 15
    then sMoveDx (x-cx)
    else sMoveDx (15*signum(x-cx)) >> sMoveDx ((x-cx)-(15*signum(x-cx)))
  if abs (y-cy) <= 15
    then sMoveDy (y-cy)
    else sMoveDy (15*signum(y-cy)) >> sMoveDy ((y-cy)-(15*signum(y-cy)))
  if abs (z-cz) <= 15
    then sMoveDz (z-cz)
    else sMoveDz (15*signum(z-cz)) >> sMoveDz ((z-cz)-(15*signum(z-cz)))  

fillBottom :: OgaBotSt ()
fillBottom = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (bot, trs) =
      (bot, Fill (0,-1,0):trs)

cFlip :: OgaBotSt ()
cFlip = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (bot, trs) =
      (bot, Flip:trs)


cHalt :: OgaBotSt ()
cHalt = do
  St.modify f
  where
    f :: OgaBot -> OgaBot
    f (bot, trs) =
      (bot, Halt:trs)

-------------------------------------------------------

getOgaBotTrace :: Model -> Trace
getOgaBotTrace m =
  reverse $ snd $ St.execState (ogaBot m) (Bot{botPos=Coord(0,0,0)}, [])

ogaBot :: Model -> OgaBotSt ()
ogaBot (Model r mtx) = do
  cFlip
  sequence_
    [ fillFloor i (maybe [] Set.toList mset)
    | i<-[0..r-2]
    , let mset = IntMap.lookup i mtx
    ]
  cFlip
  sMoveAbs (r-1,r-1,r-1)
  sMoveAbs (r-1,0,r-1)
  sMoveAbs (r-1,0,0)
  sMoveAbs (0,0,0)
  cHalt

fillFloor :: Int -> [(Int,Int)] -> OgaBotSt ()
fillFloor fno xs =
  sequence_ (sMoveDy 1 : map (fillFloor1 fno) xs)

fillFloor1 :: Int -> (Int,Int) -> OgaBotSt ()
fillFloor1 y (x,z) = do
  sMoveAbs (x,y+1,z)
  fillBottom

    