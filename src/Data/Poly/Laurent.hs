-- |
-- Module:      Data.Poly.Laurent
-- Copyright:   (c) 2020 Andrew Lelechenko
-- Licence:     BSD3
-- Maintainer:  Andrew Lelechenko <andrew.lelechenko@gmail.com>
--
-- <https://en.wikipedia.org/wiki/Laurent_polynomial Laurent polynomials>.
--

{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PatternSynonyms            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE ViewPatterns               #-}

module Data.Poly.Laurent
  ( Laurent
  , VLaurent
  , ULaurent
  , unLaurent
  , toLaurent
  , leading
  , monomial
  , scale
  , pattern X
  , (^-)
  , eval
  , subst
  , deriv
  , LaurentOverField(..)
  ) where

import Prelude hiding (quotRem, quot, rem, gcd)
import Control.Arrow (first)
import Control.DeepSeq (NFData(..))
import Data.Euclidean (GcdDomain(..), Euclidean(..), Field)
import Data.List (intersperse)
import Data.Semiring (Semiring(..), Ring())
import qualified Data.Semiring as Semiring
import qualified Data.Vector as V
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Unboxed as U

import Data.Poly.Internal.Dense (Poly(..))
import qualified Data.Poly.Internal.Dense as Dense
import Data.Poly.Internal.Dense.Field ()
import Data.Poly.Internal.Dense.GcdDomain ()
import Data.Poly.Internal.PolyOverField

-- | <https://en.wikipedia.org/wiki/Laurent_polynomial Laurent polynomials>
-- of one variable with coefficients from @a@,
-- backed by a 'G.Vector' @v@ (boxed, unboxed, storable, etc.).
--
-- Use pattern 'X' and operator '^-' for construction:
--
-- >>> (X + 1) + (X^-1 - 1) :: VLaurent Integer
-- 1 * X + 0 + 1 * X^-1
-- >>> (X + 1) * (1 - X^-1) :: ULaurent Int
-- 1 * X + 0 + (-1) * X^-1
--
-- Polynomials are stored normalized, without leading
-- and trailing
-- zero coefficients, so 0 * X + 1 + 0 * X^-1 equals to 1.
--
-- 'Ord' instance does not make much sense mathematically,
-- it is defined only for the sake of 'Data.Set.Set', 'Data.Map.Map', etc.
--
data Laurent v a = Laurent !Int !(Poly v a)
  deriving (Eq, Ord)

-- | Deconstruct a 'Laurent' polynomial into an offset (largest possible)
-- and a regular polynomial.
--
-- >>> unLaurent (2 * X + 1 :: ULaurent Int)
-- (0,2 * X + 1)
-- >>> unLaurent (1 + 2 * X^-1 :: ULaurent Int)
-- (-1,1 * X + 2)
-- >>> unLaurent (2 * X^2 + X :: ULaurent Int)
-- (1,2 * X + 1)
-- >>> unLaurent (0 :: ULaurent Int)
-- (0,0)
unLaurent :: Laurent v a -> (Int, Poly v a)
unLaurent (Laurent off poly) = (off, poly)

-- | Construct 'Laurent' polynomial from an offset and a regular polynomial.
-- One can imagine it as 'Data.Poly.scale'', but allowing negative offsets.
--
-- >>> toLaurent 2 (2 * Data.Poly.X + 1) :: ULaurent Int
-- 2 * X^3 + 1 * X^2
-- >>> toLaurent (-2) (2 * Data.Poly.X + 1) :: ULaurent Int
-- 2 * X^-1 + 1 * X^-2
toLaurent
  :: (Eq a, Semiring a, G.Vector v a)
  => Int
  -> Poly v a
  -> Laurent v a
toLaurent off (Poly xs) = go 0
  where
    go k
      | k >= G.length xs
      = Laurent 0 zero
      | G.unsafeIndex xs k == zero
      = go (k + 1)
      | otherwise
      = Laurent (off + k) (Poly (G.unsafeDrop k xs))
{-# INLINE toLaurent #-}

toLaurentNum
  :: (Eq a, Num a, G.Vector v a)
  => Int
  -> Poly v a
  -> Laurent v a
toLaurentNum off (Poly xs) = go 0
  where
    go k
      | k >= G.length xs
      = Laurent 0 0
      | G.unsafeIndex xs k == 0
      = go (k + 1)
      | otherwise
      = Laurent (off + k) (Poly (G.unsafeDrop k xs))
{-# INLINE toLaurentNum #-}

instance NFData (v a) => NFData (Laurent v a) where
  rnf (Laurent off poly) = rnf off `seq` rnf poly

instance (Show a, G.Vector v a) => Show (Laurent v a) where
  showsPrec d (Laurent off poly)
    | G.null (unPoly poly)
      = showString "0"
    | otherwise
      = showParen (d > 0)
      $ foldl (.) id
      $ intersperse (showString " + ")
      $ G.ifoldl (\acc i c -> showCoeff (i + off) c : acc) []
      $ unPoly poly
    where
      showCoeff 0 c = showsPrec 7 c
      showCoeff 1 c = showsPrec 7 c . showString " * X"
      showCoeff i c = showsPrec 7 c . showString (" * X^" ++ show i)

-- | Laurent polynomials backed by boxed vectors.
type VLaurent = Laurent V.Vector

-- | Laurent polynomials backed by unboxed vectors.
type ULaurent = Laurent U.Vector

-- | Return a leading power and coefficient of a non-zero polynomial.
--
-- >>> leading ((2 * X + 1) * (2 * X^2 - 1) :: ULaurent Int)
-- Just (3,4)
-- >>> leading (0 :: ULaurent Int)
-- Nothing
leading :: G.Vector v a => Laurent v a -> Maybe (Int, a)
leading (Laurent off poly) = first ((+ off) . fromIntegral) <$> Dense.leading poly

-- | Note that 'abs' = 'id' and 'signum' = 'const' 1.
instance (Eq a, Num a, G.Vector v a) => Num (Laurent v a) where
  Laurent off1 poly1 * Laurent off2 poly2 = toLaurentNum (off1 + off2) (poly1 * poly2)
  Laurent off1 poly1 + Laurent off2 poly2 = case off1 `compare` off2 of
    LT -> toLaurentNum off1 (poly1 + Dense.scale (fromIntegral $ off2 - off1) 1 poly2)
    EQ -> toLaurentNum off1 (poly1 + poly2)
    GT -> toLaurentNum off2 (Dense.scale (fromIntegral $ off1 - off2) 1 poly1 + poly2)
  Laurent off1 poly1 - Laurent off2 poly2 = case off1 `compare` off2 of
    LT -> toLaurentNum off1 (poly1 - Dense.scale (fromIntegral $ off2 - off1) 1 poly2)
    EQ -> toLaurentNum off1 (poly1 - poly2)
    GT -> toLaurentNum off2 (Dense.scale (fromIntegral $ off1 - off2) 1 poly1 - poly2)
  negate (Laurent off poly) = Laurent off (negate poly)
  abs = id
  signum = const 1
  fromInteger n = Laurent 0 (fromInteger n)
  {-# INLINE (+) #-}
  {-# INLINE (-) #-}
  {-# INLINE negate #-}
  {-# INLINE fromInteger #-}
  {-# INLINE (*) #-}

instance (Eq a, Semiring a, G.Vector v a) => Semiring (Laurent v a) where
  zero = Laurent 0 zero
  one  = Laurent 0 one
  Laurent off1 poly1 `times` Laurent off2 poly2 =
    toLaurent (off1 + off2) (poly1 `times` poly2)
  Laurent off1 poly1 `plus` Laurent off2 poly2 = case off1 `compare` off2 of
    LT -> toLaurent off1 (poly1 `plus` Dense.scale' (fromIntegral $ off2 - off1) one poly2)
    EQ -> toLaurent off1 (poly1 `plus` poly2)
    GT -> toLaurent off2 (Dense.scale' (fromIntegral $ off1 - off2) one poly1 `plus` poly2)
  fromNatural n = Laurent 0 (fromNatural n)
  {-# INLINE zero #-}
  {-# INLINE one #-}
  {-# INLINE plus #-}
  {-# INLINE times #-}
  {-# INLINE fromNatural #-}

instance (Eq a, Ring a, G.Vector v a) => Ring (Laurent v a) where
  negate (Laurent off poly) = Laurent off (Semiring.negate poly)

-- | Create a monomial from a power and a coefficient.
monomial :: (Eq a, Semiring a, G.Vector v a) => Int -> a -> Laurent v a
monomial p c
  | c == zero = Laurent 0 zero
  | otherwise = Laurent p (Dense.monomial' 0 c)
{-# INLINE monomial #-}

-- | Multiply a polynomial by a monomial, expressed as a power and a coefficient.
--
-- >>> scale 2 3 (X^2 + 1) :: ULaurent Int
-- 3 * X^4 + 0 * X^3 + 3 * X^2 + 0 * X + 0
scale :: (Eq a, Semiring a, G.Vector v a) => Int -> a -> Laurent v a -> Laurent v a
scale yp yc (Laurent off poly) = toLaurent (off + yp) (Dense.scale' 0 yc poly)

-- | Evaluate at a given point.
--
-- >>> eval (X^2 + 1 :: ULaurent Int) 3
-- 10
eval :: (Field a, G.Vector v a) => Laurent v a -> a -> a
eval (Laurent off poly) x = Dense.eval' poly x `times`
  (if off >= 0 then x Semiring.^ off else quot one x Semiring.^ (- off))
{-# INLINE eval #-}

-- | Substitute another polynomial instead of 'Data.Poly.X'.
--
-- >>> subst (X^2 + 1 :: UPoly Int) (X + 1 :: ULaurent Int)
-- 1 * X^2 + 2 * X + 2
subst :: (Eq a, Semiring a, G.Vector v a, G.Vector w a) => Poly v a -> Laurent w a -> Laurent w a
subst = Dense.substitute' (scale 0)
{-# INLINE subst #-}

-- | Take a derivative.
--
-- >>> deriv (X^3 + 3 * X) :: ULaurent Int
-- 3 * X^2 + 0 * X + 3
deriv :: (Eq a, Ring a, G.Vector v a) => Laurent v a -> Laurent v a
deriv (Laurent off (Poly xs)) =
  toLaurent (off - 1) $ Dense.toPoly' $ G.imap (times . Semiring.fromIntegral . (+ off)) xs
{-# INLINE deriv #-}

-- | Create an identity polynomial.
pattern X :: (Eq a, Semiring a, G.Vector v a, Eq (v a)) => Laurent v a
pattern X <- ((==) var -> True)
  where X = var

var :: forall a v. (Eq a, Semiring a, G.Vector v a, Eq (v a)) => Laurent v a
var
  | (one :: a) == zero = Laurent 0 zero
  | otherwise          = Laurent 1 one
{-# INLINE var #-}

-- | This operator can be applied only to 'X',
-- but is instrumental to express Laurent polynomials in mathematical fashion:
--
-- >>> X + 2 + 3 * X^-1 :: ULaurent Int
-- 1 * X + 2 + 3 * X^(-1)
(^-)
  :: (Eq a, Semiring a, G.Vector v a, Eq (v a))
  => Laurent v a
  -> Int
  -> Laurent v a
X^-n = monomial (negate n) one
_^-_ = error "(^-) can be applied only to X"

-- | Consider using 'LaurentOverField' wrapper,
-- which provides a much faster implementation of
-- 'Data.Euclidean.gcd' for polynomials over 'Field'.
instance (Eq a, Ring a, GcdDomain a, Eq (v a), G.Vector v a) => GcdDomain (Laurent v a) where
  divide (Laurent off1 poly1) (Laurent off2 poly2) =
    toLaurent (off1 - off2) <$> divide poly1 poly2
  {-# INLINE divide #-}

  gcd (Laurent _ poly1) (Laurent _ poly2) =
    toLaurent 0 (gcd poly1 poly2)
  {-# INLINE gcd #-}

-- | Wrapper for Laurent polynomials over 'Field',
-- providing a faster 'GcdDomain' instance.
newtype LaurentOverField laurent = LaurentOverField { unLaurentOverField :: laurent }
  deriving (Eq, NFData, Num, Ord, Ring, Semiring, Show)

instance (Eq a, Eq (v a), Field a, G.Vector v a) => GcdDomain (LaurentOverField (Laurent v a)) where
  divide (LaurentOverField (Laurent off1 poly1)) (LaurentOverField (Laurent off2 poly2)) =
    LaurentOverField . toLaurent (off1 - off2) . unPolyOverField <$> divide (PolyOverField poly1) (PolyOverField poly2)

  gcd (LaurentOverField (Laurent _ poly1)) (LaurentOverField (Laurent _ poly2)) =
    LaurentOverField (toLaurent 0 (unPolyOverField (gcd (PolyOverField poly1) (PolyOverField poly2))))
  {-# INLINE gcd #-}
