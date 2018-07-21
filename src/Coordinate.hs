{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

module Coordinate where

import Control.Applicative (pure, (*>), Alternative)
import Control.Monad (guard)
import Data.Bool (bool)
import Data.Function (on)
import Data.Tuple.Extra (fst3, snd3, thd3)

type R = Int

isValidR :: R -> Bool
isValidR = (&&) . (0 <) <*> (<= 250)

newtype Coord = Coord (Int, Int, Int) deriving (Eq, Ord, Show)
type CDiff = (Int, Int, Int)
type LD = CDiff
type SLD = CDiff
type LLD = CDiff
type ND = CDiff

coord :: Alternative f
      => Int -> (Int, Int, Int) -> f Coord
coord r (x, y, z) =
  guard (0 <= x && x <= r - 1) *>
  guard (0 <= y && y <= r - 1) *>
  guard (0 <= z && z <= r - 1) *>
  pure (Coord (x, y, z))

add :: Coord -> CDiff -> Coord
add (Coord (x,y,z)) (dx,dy,dz) = Coord (x+dx,y+dy,z+dz)

sub :: Coord -> Coord -> CDiff
sub (Coord (x,y,z)) (Coord (x',y',z')) = (x-x',y-y',z-z')

-- Manhattan length (or L1 norm)
mlen :: CDiff -> Int
mlen (dx, dy, dz) = abs dx + abs dy + abs dz

-- Chessboard length (or Chebyshev distance or L∞ norm)
clen :: CDiff -> Int
clen (dx, dy, dz) = max (max (abs dx) (abs dy)) (abs dz)

adjacent :: Coord -> Coord -> Bool
adjacent c c' = mlen (sub c c') == 1

pAND :: (a -> Bool) -> (a -> Bool) -> (a -> Bool)
pAND p q x = p x && q x

-- requirement to define linear coordinate difference
ld :: CDiff -> Bool
ld (dx,dy,dz) = length (filter (/= 0) [dx,dy,dz]) == 1

-- requirement to define short linear coordinate difference
sld :: CDiff -> Bool
sld = ld `pAND` ((<= 5) . mlen)

-- requirement to define long linear coordinate difference
lld :: CDiff -> Bool
lld = ld `pAND` ((<= 15) . mlen)

nd :: CDiff -> Bool
nd d = 0 < ml && ml <= 2 && cl == 1
  where
    ml = mlen d
    cl = clen d

type Region = (Coord, Coord)

instance {-# Overlapping #-} Eq Region where
  (==) = (==) `on` normRegion

memOfRegion :: Coord -> Region -> Bool
memOfRegion (Coord (x,y,z)) (Coord (x1,y1,z1), Coord (x2,y2,z2))
  = and [ min x1 x2 <= x && x <= max x1 x2
        , min y1 y2 <= y && x <= max y1 y2
        , min z1 z2 <= z && z <= max z1 z2
        ]

normRegion :: Region -> Region
normRegion (Coord (x1,y1,z1), Coord (x2,y2,z2)) =
  (Coord (min x1 x2, min y1 y2, min z1 z2), Coord (max x1 x2, max y1 y2, max z1 z2))

type Dimension = Int

dim :: Region -> Dimension
dim (Coord c1, Coord c2) = dim' fst3 + dim' snd3 + dim' thd3
  where
    dim' acc = bool 1 0 $ ((==) `on` acc) c1 c2

data Shape = Point | Line | Plane | Box deriving (Show, Eq, Ord, Enum)

shape :: Region -> Shape
shape = toEnum . dim