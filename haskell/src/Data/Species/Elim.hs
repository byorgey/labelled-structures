{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveFunctor   #-}
{-# LANGUAGE GADTs           #-}
{-# LANGUAGE RankNTypes      #-}
{-# LANGUAGE TypeOperators   #-}

-- | This module defines /eliminators/ for labelled structures.
--
--   An eliminator for labelled structures should be able to look at
--   the labelling.  However, it should not actually care about the
--   labels; that is, it should be indifferent to relabeling.
--   Fortunately, we can actually enforce this in Haskell via
--   parametricity.  We specify that an eliminator must work for /any/
--   label type which is an instance of 'Eq'.  (If we were to use
--   'Ord' instead of 'Eq', we would get eliminators for L-species
--   instead; if we used no constraint at all, @Elim f a b@ would be
--   isomorphic to @f a -> b@, that is, a usual eliminator for
--   (non-labeled) @f@-structures.)
--
--   Note that the difference between @Elim f a b@ and @f a -> b@ really
--   only matters for structures with sharing, /e.g./ cartesian product.

module Data.Species.Elim
    ( -- * Eliminators

      Elim(..)
    , mapElimSrc
    , mapElimShape

      -- * Running eliminators

    , elim
    , elim'

      -- * Combinators for building eliminators

    , elimZero
    , elimOne
    , elimX
    , elimSum
    , elimProd
    , elimComp

    )
    where

import           Control.Lens

import           Data.Fin (Fin(..))
import           Data.Finite (Finite(..), toFin)
import           Data.Species.Shape
import           Data.Species.Types
import           Data.Type.List
import qualified Data.Vec           as V

-- | The type of eliminators for labelled structures.  A value of type
--   @Elim f a r@ is an eliminator for labelled @f@-structures with
--   data of type @a@, which yields a value of type @r@.
--
--   @Elim@ is a covariant functor in its final argument (witnessed by
--   the @Functor@ instance) and contravariant in its first two,
--   witnessed by 'mapElimSrc' and 'mapElimShape'.
newtype Elim f a r = Elim (forall l. Eq l => f l -> (l -> a) -> r)
  deriving Functor

-- | Convert an eliminator for @a@-valued structures into one for
--   @b@-valued structures, by specifying a map from @b@ to @a@.
mapElimSrc :: (b -> a) -> Elim f a r -> Elim f b r
mapElimSrc f (Elim el) = Elim $ \s m -> el s (f . m)

-- | Convert an eliminator for @f@-structures into an eliminator for
--   @g@-structures, by specifying a parametric mapping from
--   @g@-structures to @f@-structures.
mapElimShape :: (forall l. g l -> f l) -> Elim f a r -> Elim g a r
mapElimShape q (Elim el) = Elim $ \s m -> el (q s) m

-- Running eliminators

-- | Run an eliminator.
elim :: (Eq l) => Elim f a b -> Sp f l a -> b
elim (Elim el) (Struct shp es (F finl)) = el shp (V.index es . view (from finl))

-- | Run an eliminator over existentially quantified structures.
elim' :: Elim f a b -> Sp' f a -> b
elim' el (SpEx s) = elim el s

-- Combinators for building eliminators

-- | The standard eliminator for 'Zero'.
elimZero :: Elim Zero a r
elimZero = Elim (\z _ -> absurdZ z)

-- | Create an eliminator for 'One' by specifying a return value.
elimOne :: r -> Elim One a r
elimOne r = Elim (\_ _ -> r)
  -- arguably we should force the shape + proof contained therein

-- | Create an eliminator for 'X' by specifying a mapping from data
-- values to return values.
elimX :: (a -> r) -> Elim X a r
elimX f = Elim (\(X i) m -> f (m (view i FZ)))

-- | Create an eliminator for @(f+g)@-structures out of individual
-- eliminators for @f@ and @g@.
elimSum :: Elim f a r -> Elim g a r -> Elim (f+g) a r
elimSum (Elim f) (Elim g) = Elim $ \shp m ->
  case shp of
    Inl fShp -> f fShp m
    Inr gShp -> g gShp m

-- | Create an eliminator for @(f*g)@-structures from a curried
--   eliminator.
elimProd :: Elim f a (Elim g a r) -> Elim (f*g) a r
elimProd (Elim f) = Elim $ \(Prod fShp gShp pf) m ->
  let mEither  = m . view pf
      (mf, mg) = (mEither . Left, mEither . Right)
  in
    case f fShp mf of
      Elim g -> g gShp mg

-- | Create an eliminator for @(Comp f g)@-structures containing @a@'s
--   from a way to eliminate @g@-structures containing @a@'s to some
--   intermediate type @x@, and then @f@-structures containing @x@'s
--   to the final result type @r@.
elimComp :: Elim f x r -> Elim g a x -> Elim (Comp f g) a r
elimComp (Elim ef) (Elim eg)
  = Elim $ \((Comp finl1 fl1 lp gs pf)) m ->
      ef fl1 $ \l1 ->
        case hlookup (toFin finl1 l1) gs lp of
          HLResult gli inj -> eg gli (m . view pf . inj)

data HLResult g ls where
  HLResult :: Eq l => g l -> (l -> Sum ls) -> HLResult g ls

hlookup :: All Eq ls => Fin n -> V.HVec n (Map g ls) -> LProxy n ls -> HLResult g ls
hlookup FZ     (V.HCons gl _) (LCons _ _ ) = HLResult gl Left
hlookup (FS f) (V.HCons _  h) (LCons _ ls) =
  case hlookup f h ls of
    HLResult gl s -> HLResult gl (Right . s)
