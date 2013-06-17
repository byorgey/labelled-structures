module Zippy where

import           SpeciesTypes
import qualified Vec          as V

-- For labelled species, only things whose shape has no real content
-- are zippy, since we need to be able to match up the shapes AND the
-- labels.

class Zippy f where
  fzip :: f l -> f l -> f l

instance Zippy One where
  fzip o _ = o

instance Zippy X where
  fzip x _ = x

instance Zippy E where
  fzip x _ = x

instance Zippy f => Zippy (Shape f) where
  fzip (Shape shA) (Shape shB) = Shape (fzip shA shB)

zipS :: Zippy f => Sp f l a -> Sp f l b -> Sp f l (a,b)
zipS = zipWithS (,)

zipWithS :: Zippy f => (a -> b -> c) -> Sp f l a -> Sp f l b -> Sp f l c
zipWithS f (Struct shA as) (Struct shB bs) = Struct (fzip shA shB) (V.zipWith f as bs)