{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}

------------------------------------------
-- The point of this module is to show that Traversable is the same as
-- Functor f => f # List.

module Traversal where

import SpeciesTypes
import qualified Data.Traversable as T
import qualified Data.Foldable as F
import Control.Applicative
import qualified Nat as N
import Finite
import qualified Vec as V

import Control.Monad.Writer
import Control.Monad.Supply

-- Use this orphan instance until
-- https://github.com/ghulette/monad-supply/pull/3 is merged and
-- released
instance Applicative (Supply s) where
  pure  = return
  (<*>) = ap

fromFold :: F.Foldable f => f a -> Sp' L a
fromFold f = fromList l
  where l = F.foldr (:) [] f

replace :: a -> WriterT [(a,N.Nat)] (Supply N.Nat) N.Nat
replace a = do
  l <- supply
  tell [(a,l)]
  return l

toL :: T.Traversable f => f a -> Sp' L a
toL = fromList . execWriter . T.traverse rep'
  where
    rep' :: a -> Writer [a] ()
    rep' a = do tell [a]; return () 

fromTrav :: T.Traversable f => f a -> Sp' (f # L) a
fromTrav fa = 
    case toL fa of
      SpEx (Struct sh v) -> SpEx (Struct (Shape (CProd undefined (_shapeVal sh))) v)
{-
fromTrav :: T.Traversable f => f a -> Sp' (f # L) a
fromTrav = mkSp' . T.traverse replace
  where
    mkSp' :: WriterT [a] (Supply N.Nat) (f N.Nat) -> Sp' (f # L) a
    mkSp' m =
      let nats = map N.intToNat [0..] in
      --  (fl, as) :: (f N.Nat, [a])
      let (fl, as) = flip evalSupply nats . runWriterT $ m
      in SpEx (Struct (Shape (CProd fl undefined)) undefined)

        -- convert all Ints to Fin n for some n, convert as to vector,
        -- pair up with L shape
-}

-- All of these are valid:
instance Finite l => F.Foldable (Sp L l) where
  foldr f b (Struct (Shape f2) elts) =
    elim (elimList b f) (Struct (Shape f2) elts)

instance Finite l => F.Foldable (Sp (f # L) l) where
  foldr f b (Struct (Shape (CProd _ f2)) elts) =
    elim (elimList b f) (Struct (Shape f2) elts)

instance F.Foldable (Sp' (f # L)) where
  foldr f b (SpEx (Struct (Shape (CProd _ f2)) elts)) =
    elim (elimList b f) (Struct (Shape f2) elts)
