{-# LANGUAGE DeriveDataTypeable, DeriveGeneric #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) Edward Kmett 2013
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
--------------------------------------------------------------------
module Data.Approximate.Mass
  ( Mass(..)
  , (|?), (&?), (^?)
  ) where

import Control.Applicative
import Control.Comonad
import Data.Data
import Data.Default
import Data.Foldable
import Data.Functor.Apply
import Data.Pointed
import Data.Traversable
import Data.Semigroup
import Generics.Deriving
import Numeric.Log

-- | A quantity with a lower-bound on its probability mass. This represents
-- a 'probable value' as a 'Monad' that you can use to calculate progressively
-- less likely consequences.
--
-- /NB:/ These probabilities are all stored in the log domain. This enables us
-- to retain accuracy despite very long multiplication chains. We never add
-- these probabilities so the additional overhead of working in the log domain
-- is never incurred, except on transitioning in and out.
--
-- This is most useful for discrete types, such as
-- small 'Integral' instances or a 'Bounded' 'Enum' like
-- 'Bool'.
--
-- Also note that @('&?')@ and @('|?')@ are able to use knowledge about the
-- function to get better precision on their results than naively using
-- @'liftA2' ('&&')@
data Mass a = Mass {-# UNPACK #-} !(Log Double) a
  deriving (Eq,Ord,Show,Read,Typeable,Data,Generic)

instance Functor Mass where
  fmap f (Mass p a) = Mass p (f a)
  {-# INLINE fmap #-}

instance Foldable Mass where
  foldMap f (Mass _ a) = f a
  {-# INLINE foldMap #-}

instance Traversable Mass where
  traverse f (Mass p a) = Mass p <$> f a
  {-# INLINE traverse #-}

instance Apply Mass where
  (<.>) = (<*>)
  {-# INLINE (<.>) #-}

instance Pointed Mass where
  point = Mass 1
  {-# INLINE point #-}

instance Default a => Default (Mass a) where
  def = Mass 1 def
  {-# INLINE def #-}

instance Applicative Mass where
  pure = Mass 1
  {-# INLINE pure #-}
  Mass p f <*> Mass q a = Mass (p * q) (f a)
  {-# INLINE (<*>) #-}

instance Monoid a => Monoid (Mass a) where
  mempty = Mass 1 mempty
  {-# INLINE mempty #-}
  mappend (Mass p a) (Mass q b) = Mass (p * q) (mappend a b)
  {-# INLINE mappend #-}

instance Semigroup a => Semigroup (Mass a) where
  Mass p a <> Mass q b = Mass (p * q) (a <> b)
  {-# INLINE (<>) #-}

instance Monad Mass where
  return = Mass 1
  {-# INLINE return #-}
  Mass p a >>= f = case f a of
    Mass q b -> Mass (p * q) b
  {-# INLINE (>>=) #-}

instance Comonad Mass where
  extract (Mass _ a) = a
  {-# INLINE extract #-}
  duplicate (Mass n a) = Mass n (Mass n a)
  {-# INLINE duplicate #-}
  extend f w@(Mass n _) = Mass n (f w)
  {-# INLINE extend #-}

instance ComonadApply Mass where
  (<@>)  = (<*>)
  {-# INLINE (<@>) #-}

infixl 6 ^?
infixr 3 &?
infixr 2 |?

-- | Calculate the logical @and@ of two booleans with confidence lower bounds.
(&?) :: Mass Bool -> Mass Bool -> Mass Bool
Mass p False &? Mass q False = Mass (max p q) False
Mass p False &? Mass _ True  = Mass p False
Mass _ True  &? Mass q False = Mass q False
Mass p True  &? Mass q True  = Mass (p * q) True
{-# INLINE (&?) #-}

-- | Calculate the logical @or@ of two booleans with confidence lower bounds.
(|?) :: Mass Bool -> Mass Bool -> Mass Bool
Mass p False |? Mass q False = Mass (p * q) False
Mass _ False |? Mass q True  = Mass q True
Mass p True  |? Mass _ False = Mass p True
Mass p True  |? Mass q True  = Mass (max p q) True
{-# INLINE (|?) #-}

-- | Calculate the exclusive @or@ of two booleans with confidence lower bounds.
(^?) :: Mass Bool -> Mass Bool -> Mass Bool
Mass p a ^? Mass q b = Mass (p * q) (xor a b) where
  xor True  True  = False
  xor False True  = True
  xor True  False = True
  xor False False = False
  {-# INLINE xor #-}
{-# INLINE (^?) #-}
