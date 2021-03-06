{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

------------------------------------------
-- The point of this module is to show that Traversable implies
-- Functor f => f # List.

module Data.Species.Traversal where

import           Control.Monad.Supply
import           Control.Monad.Writer
import qualified Data.Foldable        as F
import qualified Data.Traversable     as T
import qualified Data.MultiSet        as MS

import           Data.Species.Elim
import           Data.Species.List
import           Data.Species.Shape
import           Data.Species.Shuffle (forgetShape)
import           Data.Species.Types
import qualified Data.Storage         as S
import qualified Data.Set.Abstract    as Set

-- can get a L-structure from just Foldable
fromFold :: (F.Foldable f, S.Storage s) => f a -> Sp' L s a
fromFold f = fromList $ F.foldr (:) [] f

-- useful utility routine for below
replace :: a -> WriterT [a] (Supply l) l
replace a = do
  l <- supply
  tell [a]
  return l

-- so of course, it can be done from Traversable too:
toL :: (T.Traversable f, S.Storage s) => f a -> Sp' L s a
toL = fromList . execWriter . T.traverse rep'
  where
    rep' :: a -> Writer [a] ()
    rep' a = do tell [a]; return ()

fromTrav :: (T.Traversable f, S.Storage s) => f a -> Sp' (f # L) s a
fromTrav fa = case fromFold fa of
                SpEx sp@(Struct l v) ->
                  SpEx (Struct (CProd fl l) v)
                  where fl = fst . evalSupply m $ toList sp
                        m = runWriterT . T.traverse replace $ fa

toList :: (Eq l, S.Storage s) => Sp L s l a -> [l]
toList (Struct shp _) = case elimList [] (:) of Elim f -> f shp id

-- All of these are valid:
instance (Eq l, S.Storage s) => F.Foldable (Sp L s l) where
  foldr f b s =
    elim (elimList b f) s

instance (Eq l, S.Storage s) => F.Foldable (Sp (f # L) s l) where
  foldr f b (Struct (CProd _ f2) elts) =
    elim (elimList b f) (Struct f2 elts)

instance F.Foldable (Sp' (f # L) s) where
  foldr f b (SpEx (Struct (CProd _ f2) elts)) =
    elim (elimList b f) (Struct f2 elts)

-- Actually, in Haskell, all species are Foldable:
instance (Set.Enumerable l, Eq l, S.Storage s) => F.Foldable (Sp f s l) where
  foldr f b sp = elim k (forgetShape sp)
    where k = elimE $ \s -> MS.fold f b $ Set.smap snd s
-- The above is 'wrong' in the sense that it should restrict f to be
-- associative-commutative.  Otherwise we can observe the order in which
-- things are fed to MS.fold, and then create a list from that.  That is
-- what fromFold above shows.  

{-

Basic idea: get the 'L l' structure, traverse that, and use
the resulting f [l] to decode what should be there.

And fundamentally this is false, as there is no 'left to right'
in g, not matter what the super-imposed L-structure says.

instance T.Traversable (Sp' (g # L)) where
  -- traverse :: Applicative f => (a -> f b) -> t a -> f (t b)
  --  where t = Sp' (g # L)
  traverse f l = case l of
                   SpEx (Struct (CProd f1 l1) v) ->
                     let sp = Struct l1 v in
                     let lt = T.traverse f (toList sp) in
-}
