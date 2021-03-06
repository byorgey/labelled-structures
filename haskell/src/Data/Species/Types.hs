{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE EmptyDataDecls             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}

module Data.Species.Types
    ( -- * Labelled structures

      Sp(..), shape, elts

      -- * Relabelling and reshaping

    , relabelI, relabel
    , reshapeI, reshape

      -- * Existentially quantified structures

    , Sp'(..), withSp

      -- * Introduction forms
      -- ** Unit
    , one, one'
      -- ** Singleton
    , x, x'
      -- ** Bags
    , e, e', empty, econs
      -- ** Element (Underlying(
    , u
      -- ** Sum
    , inl, inr, inl', inr'
      -- ** Product
    , prod, prod'
      -- ** Cartesian product
    , cprodL, cprodR, decompL, decompR, projL, projR, editL, editR
      -- ** Differentiation
    , d
      -- ** Pointing
    , p
      -- ** Partition
    , part
      -- ** Composition
    , compA, compAP, compJ, compJ', compJ''
      -- ** Cardinality restriction
    -- , sized
    )
    where

import           Control.Arrow (first, second)
import           Control.Lens (makeLenses, iso, view, from, over, mapped, (%~))
import           Data.Proxy
import           Data.Type.Equality

import           Data.Iso
import           Data.BFunctor
import           Data.Fin
import           Data.Finite
import           Data.Functor ((<$>))
import           Data.Species.Shape
import           Data.Storage
import           Data.Subset
import           Data.Type.List
import           Data.Type.Nat
import qualified Data.Vec          as V
import qualified Data.Set.Abstract as S

------------------------------------------------------------
-- Labelled structures

-- | A species is a labelled shape paired with a map from labels to data
--   values.  Since label types are required to be constructively
--   finite, that is, come with an isomorphism to @'Fin' n@ for some n, we
--   can represent the map as a length-@n@ vector.
data Sp (f :: * -> *) (s :: * -> * -> *) (l :: *) (a :: *) = Struct { _shape ::  f l, _elts :: s l a }

makeLenses ''Sp

------------------------------------------------------------
--  Relabelling/functoriality

-- | Structures can be relabelled; /i.e./ isomorphisms between label
--   sets induce isomorphisms between labelled structures.
relabelI :: (BFunctor f, Storage s, HasSize l1, HasSize l2, Eq l1, Eq l2)
         => (l1 <-> l2) -> (Sp f s l1 a <-> Sp f s l2 a)
relabelI i =
  case isoPresSize i of
    Refl -> iso (\(Struct s es) -> Struct (view (bmap i       ) s) (reindex i        es))
                (\(Struct s es) -> Struct (view (bmap (from i)) s) (reindex (from i) es))

-- | A version of 'relabelI' which returns a function instead of an
--   isomorphism, which is sometimes more convenient.
relabel :: (BFunctor f, Storage s, HasSize l1, HasSize l2, Eq l1, Eq l2)
        => (l1 <-> l2) -> Sp f s l1 a -> Sp f s l2 a
relabel = view . relabelI

instance Functor (s l) => Functor (Sp f s l) where
  fmap = over (elts . mapped)

-- | We can also do a 'mapWithKey', called imap for vectors:
lmap :: Storage s => (l -> a -> b) -> Sp f s l a -> Sp f s l b
lmap f (Struct s es) = Struct s (skmap f es)
------------------------------------------------------------
--  Reshaping

-- | Structures can also be /reshaped/: isomorphisms between species
--   induce isomorphisms between labelled structures.
reshapeI :: Eq l => (f <--> g) -> (Sp f s l a <-> Sp g s l a)
reshapeI i = liftIso shape shape i

-- | A version of 'reshapeI' which returns a function instead of an
--   isomorphism, which is sometimes more convenient.
reshape :: Eq l => (f --> g) -> Sp f s l a -> Sp g s l a
reshape r = over shape r

------------------------------------------------------------
--  Existentially labelled structures

-- | Labelled structures whose label type has been existentially
--   hidden.  Note that we need to package up an @Eq@ constraint on the
--   labels, otherwise we can't really do anything with them and we
--   might as well just not have them at all.
data Sp' f s a where
  SpEx :: (Eq l, Storage s) => Sp f s l a -> Sp' f s a

withSp :: (forall l. Sp f s l a -> Sp g s l b) -> Sp' f s a -> Sp' g s b
withSp q sp' = case sp' of SpEx sp -> SpEx (q sp)

-- instance Functor (Sp' f s) where
--   fmap f = withSp (fmap f)

-- Or we can package up an Ord constraint and get L-species
-- structures.

data LSp' f s a where
  LSpEx :: Ord l => Sp f s l a -> LSp' f s a

-- One -------------------------------------------

one :: Storage s => Sp One s (Fin Z) a
one = Struct one_ emptyStorage

one' :: Storage s => Sp' One s a
one' = SpEx one

-- X ---------------------------------------------

x :: Storage s => a -> Sp X s (Fin (S Z)) a
x a = Struct x_ (allocate finite_Fin (const a))

x' :: Storage s => a -> Sp' X s a
x' = SpEx . x

-- E ---------------------------------------------

e :: Storage s => Finite l -> (l -> a) -> Sp E s l a
e fin f = Struct (e_ (S.enumerate fin)) (allocate fin f)

-- it is also useful to have the empty bag, as well as 
-- one-element union
empty :: Storage s => Sp E s (Fin Z) a
empty = Struct (e_ S.emptySet) emptyStorage

econs :: (Storage s) => a -> Sp E s l a -> Sp E s (Either (Fin (S Z)) l) a
econs x (Struct (E s) stor) = 
  Struct (E (S.union (S.enumerate finite_Fin) s)) 
         (append (allocate finite_Fin (const x)) stor id)

-- probably could forgo the Vector by using snatToInt
e' :: Storage s => [a] -> Sp' E s a
e' as = case V.fromList as of
          (V.SomeVec v) -> natty (V.size v) $
                           SpEx (Struct (e_ (S.enumerate finite_Fin)) 
                                (initialize (V.index v)))

-- u ---------------------------------------------

-- Note how this is essentially the Store Comonad.
u :: Storage s => Finite l -> (l -> a) -> l -> Sp U s l a
u fin f x = Struct (u_ x) (allocate fin f)

-- No u' since u depends very closely on the labels

-- Sum -------------------------------------------

inl :: Sp f s l a -> Sp (f + g) s l a
inl = shape %~ inl_

inl' :: Sp' f s a -> Sp' (f + g) s a
inl' = withSp inl

inr :: Sp g s l a -> Sp (f + g) s l a
inr = shape %~ inr_

inr' :: Sp' g s a -> Sp' (f + g) s a
inr' = withSp inr

-- Product ---------------------------------------

prod :: (Storage s, Eq l1, Eq l2)
     => Sp f s l1 a -> Sp g s l2 a -> Sp (f * g) s (Either l1 l2) a
prod (Struct sf esf) (Struct sg esg) =
    Struct (prod_ sf sg) (append esf esg id)

prod' :: Sp' f s a -> Sp' g s a -> Sp' (f * g) s a
prod' (SpEx f) (SpEx g) = SpEx (prod f g)

-- Cartesian product -----------------------------

-- | Superimpose a new shape atop an existing structure, with the
--   structure on the left.
cprodL :: Sp f s l a -> g l -> Sp (f # g) s l a
cprodL (Struct sf es) sg = Struct (cprod_ sf sg) es

-- | Superimpose a new shape atop an existing structure, with the
--   structure on the right.
cprodR :: f l -> Sp g s l a -> Sp (f # g) s l a
cprodR sf (Struct sg es) = Struct (cprod_ sf sg) es

-- | Decompose a Cartesian product structure.  Inverse to `cprodL`.
decompL :: Sp (f # g) s l a -> (Sp f s l a, g l)
decompL (Struct (CProd fl gl) es) = (Struct fl es, gl)

-- | Decompose a Cartesian product structure.  Inverse to `cprodR`.
decompR :: Sp (f # g) s l a -> (f l, Sp g s l a)
decompR (Struct (CProd fl gl) es) = (fl, Struct gl es)

-- | Project out the left structure from a Cartesian product.
projL ::  Sp (f # g) s l a -> Sp f s l a
projL = fst . decompL

-- | Project out the right structure from a Cartesian product.
projR ::  Sp (f # g) s l a -> Sp g s l a
projR = snd . decompR

-- | Apply a function to the left-hand structure of a Cartesian
-- product.
editL :: (Sp f s l a -> Sp f s l b) -> (Sp (f # g) s l a -> Sp (f # g) s l b)
editL f = uncurry cprodL . first f . decompL

-- | Apply a function to the right-hand structure of a Cartesian
-- product.
editR :: (Sp g s l a -> Sp g s l b) -> (Sp (f # g) s l a -> Sp (f # g) s l b)
editR f = uncurry cprodR . second f . decompR

-- Differentiation -------------------------------

d :: (Storage s, HasSize l, Eq l) => Sp f s (Maybe l) a -> (a, Sp (D f) s l a)
d (Struct s es)
  = (index es Nothing, Struct (d_ s) (reindex subsetMaybe es))

-- No d' operation since it really does depend on the labels

-- Pointing --------------------------------------

p :: l -> Sp f s l a -> Sp (P f) s l a
p l (Struct s es) = Struct (p_ l s) es

-- No p' operation---it again depends on the labels

-- Partition   -----------------------------------

part :: (Storage s, Eq l1, Eq l2)
  => Finite l1 -> Finite l2
  -> (l1 -> a) -> (l2 -> a) -> (Either l1 l2 <-> l) -> Sp (E * E) s l a
part finl1 finl2 f g i = 
  Struct (part_ (S.enumerate finl1) (S.enumerate finl2) i) 
         (append (allocate finl1 f) (allocate finl2 g) i)

-- It is not clear that we can create a part' because this witnesses a subset
-- relation on labels, which seems difficult to abstract

-- Composition -----------------------------------

-- | 'compA' can be seen as a generalized version of the 'Applicative'
--   method '<*>'. Unlike 'compJ', there is no dependent variant of 'compA':
--   we only get to provide a single @g@-structure which is copied into
--   all the locations of the @f@-structure, so all the label types must
--   be the same; they cannot depend on the labels of the @f@-structure.
compA :: (Eq l1, Eq l2, HasSize l1, HasSize l2, Functor (s l1), Functor (s l2))
      => Sp f s l1 (a -> b) -> Sp g s l2 a -> Sp (Comp f g) s (l1,l2) b
compA spf spg = compJ ((<$> spg) <$> spf)

-- | A variant of 'compA', interdefinable with it.
compAP :: (Eq l1, Eq l2, HasSize l1, HasSize l2, Functor (s l1), Functor (s l2))
       => Sp f s l1 a -> Sp g s l2 b -> Sp (Comp f g) s (l1,l2) (a,b)
compAP spf spg = compA (fmap (,) spf) spg

-- | 'compJ' and 'compJ'' are like generalized versions of the 'Monad'
--   function 'join'.
--
--   'compJ' is a restricted form of composition where the substructures
--   are constrained to all have the same label type.

-- XXX todo: reimplement with Storage
compJ :: forall s f l1 g l2 a. (Eq l1, Eq l2, HasSize l1, HasSize l2)
      => Sp f s l1 (Sp g s l2 a) -> Sp (Comp f g) s (l1,l2) a
compJ = undefined
-- compJ (Struct f_ es finl1@(F isol1))
--     = case mapRep l1Size (Proxy :: Proxy g) (Proxy :: Proxy l2) of
--         Refl ->
--           allRep l1Size (Proxy :: Proxy Eq) (Proxy :: Proxy l2) $
--           Struct (Comp finl1 f_ (lpRep l1Size (Proxy :: Proxy l2)) gShps' pf)
--                  (V.concat gElts) finl1l2
--   where
--     l1Size                 = size finl1
--     (gShps, gElts, finPfs) = V.unzip3 (fmap unSp es)
--     gShps'                 = V.toHVec gShps
--     unSp (Struct sh es' f) = (sh, es', f)
--     pf                     :: Sum (Replicate (Size l1) l2) <-> (l1, l2)
--     pf                     = sumRepIso finl1
--     finl1l2 :: Finite (l1,l2)
--     finl1l2 = finConv (liftIso _1 _1 isol1) (V.finite_cat finPfs)

-- | 'compJ'' is a fully generalized version of 'join'.
--
--   Ideally the type of 'compJ'' would be a dependent version of the
--   type of 'compJ', where @l2@ can depend on @l1@.  Indeed, I expect
--   that in a true dependently typed language we can write that type
--   directly.  However, we can't express that in Haskell, so instead
--   we use existential quantification.
compJ' :: forall f s l g a. (Eq l) => Sp f s l (Sp' g s a) -> Sp' (Comp f g) s a
compJ' = undefined

-- XXX todo: reimplement with Storage
-- compJ' (Struct f_ es finl)
--   = case unzipSpSp' es of
--       UZSS ls gShps gElts finPfs ->
--         SpEx (Struct
--                (Comp finl f_ ls gShps id)
--                (V.hconcat (Proxy :: Proxy g) ls gElts)
--                (V.finite_hcat ls finPfs)
--              )

  -- If you squint really hard, you can see that the implementations
  -- of compJ and compJ' are structurally identical, but with a bunch
  -- of extra machinery thrown in to convince the typechecker, in
  -- fact, different machinery in each case: in the case of compJ, we
  -- have to do some work to replicate the second label type and show
  -- that iterated sum is the same as a product.  In the case of
  -- compJ', we have to work to maintain existentially-quantified
  -- heterogeneous lists of types and carefully preserve knowledge
  -- about which types are equal.

-- | For convenience, a variant of 'compJ'' which takes an
--   existentially labelled structure as input.
compJ'' :: forall f g s a. Sp' f s (Sp' g s a) -> Sp' (Comp f g) s a
compJ'' sp' =
  case sp' of
    SpEx sp -> compJ' sp

-- A data structure to represent an "unzipped" Sp(Sp')-thing: a vector
-- of g-structures paired with a vector of element vectors, with the
-- list of label types existentially hidden.
data UnzippedSpSp' n g a where
  UZSS :: (Eq (Sum ls), HasSize (Sum ls), All Eq ls)
       => LProxy n ls    -- We need an LProxy so the typechecker can
                         -- actually infer the label types (the only
                         -- other occurrences of ls are buried inside
                         -- type functions which we know are injective
                         -- but GHC doesn't) and to drive recursion
                         -- over the vectors.
       -> V.HVec n (Map g ls)           -- vector of g-structures
       -> V.HVec n (V.VecsOfSize ls a)  -- vector of element vectors
       -> V.HVec n (Map Finite ls)
       -> UnzippedSpSp' n g a

-- unzipSpSp' :: V.Vec n (Sp' g s a) -> UnzippedSpSp' n g a
-- unzipSpSp' V.VNil = UZSS LNil V.HNil V.HNil V.HNil
-- unzipSpSp' (V.VCons (SpEx (Struct (gl :: g l) v finl)) sps) =
--   case unzipSpSp' sps of
--     UZSS prox gls evs finPfs
--       -> UZSS (LCons (Proxy :: Proxy l) prox) (V.HCons gl gls) (V.HCons v evs) (V.HCons finl finPfs)

-- Functor composition ---------------------------

-- XXX todo

-- Cardinality restriction -----------------------

sized :: Finite l -> Sp f s l a -> Sp (OfSize (Size l) f) s l a
sized finl (Struct s es) = Struct (sized_ finl s) es

