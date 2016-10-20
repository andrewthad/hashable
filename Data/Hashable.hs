{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Trustworthy #-}
#endif

------------------------------------------------------------------------
-- |
-- Module      :  Data.Hashable
-- Copyright   :  (c) Milan Straka 2010
--                (c) Johan Tibell 2011
--                (c) Bryan O'Sullivan 2011, 2012
-- License     :  BSD-style
-- Maintainer  :  johan.tibell@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- This module defines a class, 'Hashable', for types that can be
-- converted to a hash value.  This class exists for the benefit of
-- hashing-based data structures.  The module provides instances for
-- most standard types.  Efficient instances for other types can be
-- generated automatically and effortlessly using the generics support
-- in GHC 7.2 and above.
--
-- The easiest way to get started is to use the 'hash' function. Here
-- is an example session with @ghci@.
--
-- > ghci> import Data.Hashable
-- > ghci> hash "foo"
-- > 60853164

module Data.Hashable
    (
      -- * Hashing and security
      -- $security

      -- * Computing hash values
      Hashable(..)

      -- * Creating new instances
      -- | There are two ways to create new instances: by deriving
      -- instances automatically using GHC's generic programming
      -- support or by writing instances manually.

      -- ** Generic instances
      -- $generics

      -- *** Understanding a compiler error
      -- $generic_err

      -- ** Writing instances by hand
      -- $blocks

      -- *** Hashing contructors with multiple fields
      -- $multiple-fields

      -- *** Hashing types with multiple constructors
      -- $multiple-ctors

    , hashUsing
    , hashPtr
    , hashPtrWithSalt
#if defined(__GLASGOW_HASKELL__)
    , hashByteArray
    , hashByteArrayWithSalt
#endif
    -- * Caching hashes
    , Hashed
    , hashed
    , unhashed
    ) where

import Data.String (IsString(..))
import Data.Typeable (Typeable)
import Data.Hashable.Class

#if !(MIN_VERSION_base(4,8,0))
import Data.Foldable (Foldable(foldr))
#endif

#if MIN_VERSION_base(4,9,0)
import Data.Functor.Classes (Eq1(..),Ord1(..),Show1(..))
#endif

#ifdef GENERICS
import Data.Hashable.Generic ()
#endif

-- $security
-- #security#
--
-- Applications that use hash-based data structures to store input
-- from untrusted users can be susceptible to \"hash DoS\", a class of
-- denial-of-service attack that uses deliberately chosen colliding
-- inputs to force an application into unexpectedly behaving with
-- quadratic time complexity.
--
-- At this time, the string hashing functions used in this library are
-- susceptible to such attacks and users are recommended to either use
-- a 'Data.Map' to store keys derived from untrusted input or to use a
-- hash function (e.g. SipHash) that's resistant to such attacks. A
-- future version of this library might ship with such hash functions.

-- $generics
--
-- Beginning with GHC 7.2, the recommended way to make instances of
-- 'Hashable' for most types is to use the compiler's support for
-- automatically generating default instances.
--
-- > {-# LANGUAGE DeriveGeneric #-}
-- >
-- > import GHC.Generics (Generic)
-- > import Data.Hashable
-- >
-- > data Foo a = Foo a String
-- >              deriving (Eq, Generic)
-- >
-- > instance Hashable a => Hashable (Foo a)
-- >
-- > data Colour = Red | Green | Blue
-- >               deriving Generic
-- >
-- > instance Hashable Colour
--
-- If you omit a body for the instance declaration, GHC will generate
-- a default instance that correctly and efficiently hashes every
-- constructor and parameter.

-- $generic_err
--
-- Suppose you intend to use the generic machinery to automatically
-- generate a 'Hashable' instance.
--
-- > data Oops = Oops
-- >      -- forgot to add "deriving Generic" here!
-- >
-- > instance Hashable Oops
--
-- And imagine that, as in the example above, you forget to add a
-- \"@deriving 'Generic'@\" clause to your data type. At compile time,
-- you will get an error message from GHC that begins roughly as
-- follows:
--
-- > No instance for (GHashable (Rep Oops))
--
-- This error can be confusing, as 'GHashable' is not exported (it is
-- an internal typeclass used by this library's generics machinery).
-- The correct fix is simply to add the missing \"@deriving
-- 'Generic'@\".

-- $blocks
--
-- To maintain high quality hashes, new 'Hashable' instances should be
-- built using existing 'Hashable' instances, combinators, and hash
-- functions.
--
-- The functions below can be used when creating new instances of
-- 'Hashable'.  For example, for many string-like types the
-- 'hashWithSalt' method can be defined in terms of either
-- 'hashPtrWithSalt' or 'hashByteArrayWithSalt'.  Here's how you could
-- implement an instance for the 'B.ByteString' data type, from the
-- @bytestring@ package:
--
-- > import qualified Data.ByteString as B
-- > import qualified Data.ByteString.Internal as B
-- > import qualified Data.ByteString.Unsafe as B
-- > import Data.Hashable
-- > import Foreign.Ptr (castPtr)
-- >
-- > instance Hashable B.ByteString where
-- >     hashWithSalt salt bs = B.inlinePerformIO $
-- >                            B.unsafeUseAsCStringLen bs $ \(p, len) ->
-- >                            hashPtrWithSalt p (fromIntegral len) salt

-- $multiple-fields
--
-- Hash constructors with multiple fields by chaining 'hashWithSalt':
--
-- > data Date = Date Int Int Int
-- >
-- > instance Hashable Date where
-- >     hashWithSalt s (Date yr mo dy) =
-- >         s `hashWithSalt`
-- >         yr `hashWithSalt`
-- >         mo `hashWithSalt` dy
--
-- If you need to chain hashes together, use 'hashWithSalt' and follow
-- this recipe:
--
-- > combineTwo h1 h2 = h1 `hashWithSalt` h2

-- $multiple-ctors
--
-- For a type with several value constructors, there are a few
-- possible approaches to writing a 'Hashable' instance.
--
-- If the type is an instance of 'Enum', the easiest path is to
-- convert it to an 'Int', and use the existing 'Hashable' instance
-- for 'Int'.
--
-- > data Color = Red | Green | Blue
-- >              deriving Enum
-- >
-- > instance Hashable Color where
-- >     hashWithSalt = hashUsing fromEnum
--
-- If the type's constructors accept parameters, it is important to
-- distinguish the constructors. To distinguish the constructors, add
-- a different integer to the hash computation of each constructor:
--
-- > data Time = Days Int
-- >           | Weeks Int
-- >           | Months Int
-- >
-- > instance Hashable Time where
-- >     hashWithSalt s (Days n)   = s `hashWithSalt`
-- >                                 (0::Int) `hashWithSalt` n
-- >     hashWithSalt s (Weeks n)  = s `hashWithSalt`
-- >                                 (1::Int) `hashWithSalt` n
-- >     hashWithSalt s (Months n) = s `hashWithSalt`
-- >                                 (2::Int) `hashWithSalt` n

-- | A hashable value along with the result of the 'hash' function.
data Hashed a = Hashed a {-# UNPACK #-} !Int
  deriving (Typeable)

-- | Wrap a hashable value, caching the 'hash' function result.
hashed :: Hashable a => a -> Hashed a
hashed a = Hashed a (hash a)

-- | Unwrap hashed value.
unhashed :: Hashed a -> a
unhashed (Hashed a _) = a

-- | Uses precomputed hash to detect inequality faster
instance Eq a => Eq (Hashed a) where
  Hashed a ha == Hashed b hb = ha == hb && a == b

instance Ord a => Ord (Hashed a) where
  Hashed a _ `compare` Hashed b _ = a `compare` b

instance Show a => Show (Hashed a) where
  showsPrec d (Hashed a _) = showsUnaryWith showsPrec "hashed" d a

instance Hashable a => Hashable (Hashed a) where
  hashWithSalt = defaultHashWithSalt
  hash (Hashed _ h) = h

-- This instance is a little unsettling. It is unusal for
-- 'liftHashWithSalt' to ignore its first argument when a
-- value is actually available for it to work on.
instance Hashable1 Hashed where
  liftHashWithSalt _ s (Hashed _ h) = defaultHashWithSalt s h

instance (IsString a, Hashable a) => IsString (Hashed a) where
  fromString s = let r = fromString s in Hashed r (hash r)

instance Foldable Hashed where
  foldr f acc (Hashed a _) = f a acc

-- instances for @Data.Functor.Classes@ higher rank typeclasses
-- in base-4.9 and onward.
#if MIN_VERSION_base(4,9,0)
instance Eq1 Hashed where
  liftEq f (Hashed a ha) (Hashed b hb) = ha == hb && f a b

instance Ord1 Hashed where
  liftCompare f (Hashed a _) (Hashed b _) = f a b

instance Show1 Hashed where
  liftShowsPrec sp _ d (Hashed a _) = showsUnaryWith sp "hashed" d a
#endif

-- This function is copied from Data.Functor.Classes, which does
-- not export it.
showsUnaryWith :: (Int -> a -> ShowS) -> String -> Int -> a -> ShowS
showsUnaryWith sp name d x = showParen (d > 10) $
    showString name . showChar ' ' . sp 11 x


