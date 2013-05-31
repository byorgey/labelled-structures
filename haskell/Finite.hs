{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Finite where

import BFunctor
import Control.Lens
import Data.Void
import Equality
import Nat
import Proxy

import Unsafe.Coerce (unsafeCoerce)

class Finite l where
  type Size l :: Nat
  size        :: Proxy l -> SNat (Size l)
  finite      :: Fin (Size l) <-> l

instance Natural n => Finite (Fin n) where
  type Size (Fin n) = n
  size _ = toSNat
  finite = id

instance Finite Void where
  type Size Void = Z
  size _ = SZ
  finite = undefined

instance Finite () where
  type Size () = S Z
  size _ = SS SZ
  finite = iso (const ()) (const FZ)

instance Finite a => Finite (Maybe a) where
  type Size (Maybe a) = S (Size a)
  size _ = SS (size (Proxy :: Proxy a))
  finite = iso toM fromM
    where
      toM :: Fin (S (Size a)) -> Maybe a
      toM FZ         = Nothing
      toM (FS n)     = Just $ view finite n

      fromM :: Maybe a -> Fin (S (Size a))
      fromM Nothing  = FZ
      fromM (Just l) = FS (view (from finite) l)

instance Finite Bool where
  type Size (Bool) = S (S Z)
  size _ = SS (SS SZ)
  finite = iso (\s -> case s of FZ -> False; FS FZ -> True)
               (\b -> case b of False -> FZ; True -> FS FZ)

instance (Finite a, Finite b) => Finite (Either a b) where
  type Size (Either a b) = Plus (Size a) (Size b)
  size _ = plus (size (Proxy :: Proxy a)) (size (Proxy :: Proxy b))
  finite = undefined -- XXX todo

instance (Finite a, Finite b) => Finite (a,b) where
  type Size (a,b) = Times (Size a) (Size b)
  size _ = times (size (Proxy :: Proxy a)) (size (Proxy :: Proxy b))
  finite = undefined -- XXX todo

------------------------------------------------------------
-- Miscellaneous proofs about size

isoPresSize :: forall l1 l2. (Finite l1, Finite l2)
            => (l1 <-> l2) -> (Size l1 == Size l2)
isoPresSize _
  | snatEq s1 s2 = unsafeCoerce Refl
  | otherwise = error $ "isoPresSize: " ++ show s1 ++ " /= " ++ show s2
  where s1 = size (Proxy :: Proxy l1)
        s2 = size (Proxy :: Proxy l2)

  -- Can we actually implement this in Haskell?  I don't think so.
