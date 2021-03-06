{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | A simple model of abstract (mathematical) sets.
module Data.Set.Abstract (Set, enumerate, elimSet, emptySet, isEmpty, union, 
  Enumerable(..), setToMS, smap, adjoin, injectionMap) where

import           Control.Lens
import           Data.BFunctor
import           Data.Fin
import           Data.Finite
import           Data.Type.Nat
import qualified Data.MultiSet as MS

-- | A set is an unordered collection of elements in which each
--   element occurs at most once.
newtype Set a = Set [a]
  deriving Show

-- Set is not a Functor (unless f is required to be injective).
-- so map on Set produces a MultiSet
-- we ignore efficiency for now, so the generated MultiSet might be
-- totally out of whack.  We ought to implement our own instead, to make
-- that clearer still.
smap :: (a -> b) -> Set a -> MS.MultiSet b
smap f (Set l) = MS.mapMonotonic f $ MS.fromDistinctAscList l

-- adjoin the value of a function to the set.  Since the a's are unique,
-- the result is guaranteed to be as well.
adjoin :: (a -> b) -> Set a -> Set (a,b)
adjoin f (Set l) = Set $ map (\x -> (x, f x)) l

-- Map an injective function onto a Set.  This one can be mis-used
injectionMap :: (a -> b) -> Set a -> Set b
injectionMap f (Set l) = Set $ map f l

instance BFunctor Set where
  bmap i = iso (\(Set as) -> Set (map (view i) as))
               (\(Set as) -> Set (map (view (from i)) as))

-- | The set of elements of a 'Finite' type.
enumerate :: forall l. Finite l -> Set l
enumerate f@(F finite) = Set $ map (view finite) (fins (size f))

-- | The empty set
emptySet = Set []

-- | Check if the set is empty
isEmpty :: Set l -> Bool
isEmpty (Set []) = True
isEmpty (Set _)  = False

-- | Convert from an abstract set to a MultiSet
setToMS :: Set a -> MS.MultiSet a
setToMS (Set l) = MS.fromDistinctAscList l

-- | Union
union :: Set a -> Set b -> Set (Either a b)
union (Set la) (Set lb) = Set (map Left la ++ map Right lb)

-- | Generic eliminator for 'Set'. Note that using @elimSet@ incurs a
--   proof obligation, namely, the first argument must be a function
--   which yields the same result for any permutation of a given input
--   list.
elimSet :: ([a] -> b) -> Set a -> b
elimSet f (Set xs) = f xs

-- Probably need to move this to its own file
-- Rather than requiring Finite, which isn't alawys what we want
-- as it 'implies' an ordering, we can get away with abstract enumerability

class Enumerable l where
  enumS :: Set l

instance Enumerable () where
  enumS = Set [()]

instance Natural n => Enumerable (Fin n) where
  enumS = Set (fins toSNat)
